"""Check the auras Modules/PartyCD/Spells.lua watches against the game's own data
files (DB2, as exported by wago.tools), and look up abilities not watched yet.

    python tools/auradata.py                          # the latest live build
    python tools/auradata.py 12.1.0.69933
    python tools/auradata.py 12.1.0.69933 370960 363534 @more.txt

Extra arguments are spell IDs to look up as well (or @file: IDs anywhere in it).
Five whole tables are downloaded once per build (SpellEffect, SpellName,
SpellCooldowns, SpellCategories, SpellCategory; about 100 MB) into
talentdata.py's cache (../wago-cache/<build>); everything else is local.

For every spell, from SpellEffect:
  the auras it puts on someone itself (an apply-aura effect), and on whom;
  the spells it triggers (EffectTriggerSpell, followed three links down),
  and the auras those put on;
  when neither gives an aura: the spells of the same name that do, since the
  server often applies the effect as a separate spell (Storm Bolt's stun)
  that nothing in the data links to the cast;
  when the spell itself has no cooldown: the spells with one that trigger
  it (three links up), and those of the same name with one: the castable one
  (Freezing Trap's trap is not the trap you cast).
Then, for a watched ability: every aura ID in Spells.lua that the data does
not show as one of these, and every aura the data shows that Spells.lua does
not list. The report goes to stdout and to <cache>/auradata-report.md.
"""
import csv, os, re, sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from talentdata import DB2, SPELLS, fetch, latest_build, num   # noqa: E402

# SpellEffect.Effect: the ones that put an aura on someone, and the ones that cast another spell
APPLY_AURA = {6: "aura", 27: "area aura", 35: "party aura", 65: "raid aura", 119: "pet aura",
              128: "friendly area aura", 129: "enemy area aura", 143: "owner aura", 174: "aura on pet",
              202: "summons aura"}
TRIGGERS = {64: "triggers", 140: "forces", 141: "forces", 142: "triggers"}
# ImplicitTarget: whom
SELF = {1}
ENEMY = {6, 15, 16, 104, 108, 109, 112, 115}
ALLY = {20, 21, 25, 30, 31, 45, 56, 57, 90, 93}

def whom(t0, t1):
    t = {t0, t1} - {0}
    if t & ENEMY: return "enemy"
    if t & ALLY: return "ally"
    if t & SELF or not t: return "self"
    return "target " + "/".join(str(x) for x in sorted(t))

def watched():
    """(spellID, kind, aura IDs, comment) per entry of Spells.lua, the racial abilities included"""
    text = open(SPELLS, encoding="utf-8").read()
    out = []
    # a racial entry closes its race's braces too: ") },  -- name"
    for m in re.finditer(r"\b(Caster|Ally|OtherAlly|Allies|Enemy|Enemies|EnemyLater)\((\d+),\s*(\d+)(.*?)\)(?:\s*\})?,?\s*--\s*(.*)", text):
        sid, extra = int(m.group(2)), m.group(4)
        many = re.search(r"auras\s*=\s*\{([\d,\s]+)\}", extra)
        one = re.search(r"\baura\s*=\s*(\d+)", extra)
        auras = [int(x) for x in many.group(1).split(",")] if many else [int(one.group(1))] if one else [sid]
        kind = {"Caster": "self", "Ally": "ally", "OtherAlly": "ally", "Allies": "ally",
                "Enemy": "enemy", "Enemies": "enemy", "EnemyLater": "enemy"}[m.group(1)]
        out.append((sid, kind, auras, m.group(5).strip()))
    return out

def full_table(db, table):
    """the path of a whole table, downloaded once per build (one request)"""
    path = os.path.join(db.cache, table + ".csv")
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        url = "https://wago.tools/db2/%s/csv?build=%s" % (table, db.build)
        sys.stderr.write("  fetching %s (the whole table)\n" % table)
        data = fetch(url)
        with open(path + ".part", "wb") as f:
            f.write(data)
        os.replace(path + ".part", path)
    return path

def read(db, table, cols):
    """the rows of a whole table, only these columns, as tuples of ints (strings for a name)"""
    with open(full_table(db, table), encoding="utf-8", newline="") as f:
        r = csv.reader(f)
        head = next(r)
        idx = [head.index(c) for c in cols]
        for row in r:
            yield tuple(row[i] for i in idx)

class Data:
    """Everything looked up locally, from five whole tables (five requests per build)."""
    def __init__(self, db):
        self.db = db
        self.family = {}      # spell -> its class's spell family (0 for a creature's spell)
        for sid, fam in read(db, "SpellClassOptions", ("SpellID", "SpellClassSet")):
            self.family[int(sid)] = int(fam)
        self.names, self.byname = {}, defaultdict(list)
        for sid, n in read(db, "SpellName", ("ID", "Name_lang")):
            self.names[int(sid)] = n
            self.byname[n].append(int(sid))
        self._effects = defaultdict(list)   # spell -> [(Effect, TriggerSpell, ImplicitTarget_0, ImplicitTarget_1)]
        self._triggered_by = defaultdict(set)   # spell -> the spells whose effects trigger it
        for sid, diff, eff, trig, t0, t1 in read(db, "SpellEffect", ("SpellID", "DifficultyID", "Effect",
                                                                       "EffectTriggerSpell", "ImplicitTarget_0", "ImplicitTarget_1")):
            if diff == "0":
                self._effects[int(sid)].append((int(eff), int(trig), int(t0), int(t1)))
                if trig != "0" and trig != sid:
                    self._triggered_by[int(trig)].add(int(sid))
        self._recovery = defaultdict(float)
        for sid, diff, rec, cat in read(db, "SpellCooldowns", ("SpellID", "DifficultyID", "RecoveryTime", "CategoryRecoveryTime")):
            if diff == "0":
                self._recovery[int(sid)] = max(self._recovery[int(sid)], num(rec) / 1000, num(cat) / 1000)
        self._charge_cat = {}
        for sid, diff, cc in read(db, "SpellCategories", ("SpellID", "DifficultyID", "ChargeCategory")):
            if diff == "0" and cc != "0":
                self._charge_cat[int(sid)] = int(cc)
        self._category = {int(i): (int(m), num(t)) for i, m, t in read(db, "SpellCategory", ("ID", "MaxCharges", "ChargeRecoveryTime"))}

    def name(self, sid):
        return self.names.get(sid, "?")

    def effects(self, sid):
        return self._effects.get(sid, [])

    def cooldown(self, sid):
        """(seconds, charges): the spell's recovery, or its charges' when it has charges"""
        cd, charges = self._recovery.get(sid, 0), 1
        cat = self._category.get(self._charge_cat.get(sid))
        if cat and cat[0] > 0:
            charges, cd = cat[0], cat[1] / 1000
        return cd, charges

    def same_name(self, sid):
        """the other spells of this name in the same class's family (a creature's spells are left out)"""
        fam = self.family.get(sid, 0)
        if not fam:
            return []
        return [x for x in self.byname.get(self.name(sid), ()) if x != sid and self.family.get(x, 0) == fam]

    def is_variant(self, aura, sid):
        """an aura spell of the same class as the ability, that nothing in the data links to it
        (a talent's version, another look): plausible, and named here for a human to judge"""
        fam = self.family.get(sid, 0)
        return bool(fam) and self.family.get(aura, 0) == fam and any(e[0] in APPLY_AURA for e in self.effects(aura))

    DEPTH = 3   # a cast often reaches its aura through a missile and a hit spell or two

    def auras_of(self, sid):
        """{auraID: whom} that this spell puts on someone, itself or through what it triggers
        (up to DEPTH links down); `via` names the auras that came through a trigger"""
        out, via, seen, frontier = {}, {}, {sid}, [sid]
        for depth in range(self.DEPTH + 1):
            nxt = []
            for x in frontier:
                for eff, trig, t0, t1 in self.effects(x):
                    if eff in APPLY_AURA:
                        out.setdefault(x, whom(t0, t1))
                        if x != sid:
                            via[x] = sid
                    if trig and trig not in seen and depth < self.DEPTH:
                        seen.add(trig)
                        nxt.append(trig)
            frontier = nxt
        return out, via

    def cast_by(self, sid):
        """the spells of the same class with a cooldown that trigger this one (up to DEPTH links up)"""
        fam = self.family.get(sid, 0)
        src, frontier = set(), {sid}
        for _ in range(self.DEPTH):
            frontier = {s for x in frontier for s in self._triggered_by.get(x, ())} - src
            src |= frontier
        return sorted((s for s in src if self.cooldown(s)[0] >= 1 and (not fam or self.family.get(s, 0) == fam)),
                      key=lambda s: (self.cooldown(s)[0], s))

def look(d, sid, listed=None, kind=None):
    lines = []
    cd, charges = d.cooldown(sid)
    auras, via = d.auras_of(sid)
    lines.append("%d %s: cooldown %gs%s" % (sid, d.name(sid), cd, " x%d" % charges if charges > 1 else ""))
    for a, w in sorted(auras.items()):
        lines.append("    aura %d %s on %s%s" % (a, d.name(a), w, " (triggered)" if a in via else ""))
    found = set(auras)
    if not auras:
        others = {}
        for o in d.same_name(sid):
            a2, _ = d.auras_of(o)
            for a, w in a2.items():
                others.setdefault(a, w)
        if others:
            lines.append("    no aura of its own; spells of the same name that put one on:")
            for a, w in sorted(others.items()):
                lines.append("      %d on %s" % (a, w))
        else:
            lines.append("    no aura in the data, nor on a spell of the same name")
        found |= set(others)
    if cd == 0:
        casts = d.cast_by(sid)
        if casts:
            lines.append("    no cooldown of its own; cast through: " +
                         ", ".join("%d %s (%gs)" % (o, d.name(o), d.cooldown(o)[0]) for o in casts[:4]))
        castable = [o for o in d.same_name(sid) if d.cooldown(o)[0] > 0 and o not in casts]
        if castable:
            lines.append("    the same name with a cooldown: " +
                         ", ".join("%d (%gs)" % (o, d.cooldown(o)[0]) for o in castable))
    problems = []
    if listed is not None:
        for a in listed:
            if a in found:
                continue
            if d.is_variant(a, sid):
                lines.append("    listed aura %d %s: an aura of the same class, not linked to the cast (a talent's or another version)" % (a, d.name(a)))
            else:
                problems.append("listed aura %d %s is not one the data shows" % (a, d.name(a)))
        for a in sorted(found - set(listed)):
            problems.append("the data shows aura %d, not listed" % a)
        if kind:
            ws = {w for a, w in auras.items() if a in listed}
            if ws and kind not in ws and not (kind == "ally" and "self" in ws):
                problems.append("watched as %s, the data puts it on %s" % (kind, "/".join(sorted(ws))))
        if cd == 0:
            problems.append("no cooldown on this spell ID: it may not be the one that is cast")
    return lines, problems

def main():
    args = sys.argv[1:]
    build = args.pop(0) if args and re.match(r"^\d+\.\d+\.\d+\.\d+$", args[0]) else latest_build()
    extra = []
    for a in args:
        if a.startswith("@"):
            extra += [int(x) for x in re.findall(r"\b\d{2,8}\b", open(a[1:], encoding="utf-8").read())]
        else:
            extra += [int(x) for x in re.findall(r"\d+", a)]
    d = Data(DB2(build))
    report = ["# Aura check, build %s" % build, ""]

    entries = watched()
    sys.stderr.write("build %s: %d watched, %d to look up\n" % (build, len(entries), len(extra)))
    report += ["## Watched (Spells.lua)", "", "```"]
    flagged = []
    for sid, kind, auras, comment in entries:
        lines, problems = look(d, sid, auras, kind)
        report += lines
        if problems:
            report += ["    !! " + p for p in problems]
            flagged.append((sid, comment, problems))
    report += ["```", ""]

    if extra:
        known = {e[0] for e in entries}
        report += ["## Not watched yet", "", "```"]
        for sid in dict.fromkeys(extra):
            if sid in known:
                continue
            lines, _ = look(d, sid)
            report += lines
        report += ["```", ""]

    summary = ["## To look at", ""]
    for sid, comment, problems in flagged:
        summary.append("- %d %s: %s" % (sid, comment, "; ".join(problems)))
    report = report[:2] + summary + [""] + report[2:]
    path = os.path.join(d.db.cache, "auradata-report.md")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(report) + "\n")
    print("\n".join(summary))
    print("\nfull report: %s" % path)

if __name__ == "__main__":
    main()
