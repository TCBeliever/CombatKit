"""Generate Modules/PartyCD/TalentData.lua from the game's own data files (DB2), as
exported by wago.tools, for the abilities Modules/PartyCD/Spells.lua watches.

    python tools/talentdata.py            # the latest live build
    python tools/talentdata.py 12.1.0.69933

What it writes, per watched ability:
  base   its cooldown and charges as the client has them (SpellCooldowns,
         SpellCategory), so the hand-written values in Spells.lua are only a
         fallback;
  mods   every talent, specialization passive and PvP talent that changes that
         cooldown or its charges through a spell modifier aura; by rank, keyed
         by the talent's TraitDefinition, when the talent has ranks
         (TraitDefinitionEffectPoints -> CurvePoint). At run time only the
         selected ones are applied;
  spec   which of those spells each specialization has as a passive
         (SpecializationSpells).

The mechanism in the data: a modifier aura (EffectAura 107 flat / 108 percent,
or 379 / 380 which pick targets by spell label) carries the thing it changes
in EffectMiscValue_0 (the SpellModOp: 11 = cooldown) and picks the spells it
applies to by EffectSpellClassMask against the target's SpellClassOptions mask,
within the same spell family (SpellClassSet). Charges come as EffectAura 411
on the ability's charge category.

It also prints, for a human to look over: the base values that differ from
Spells.lua, the specializations the data gives an ability against the `specs`
written in Spells.lua, and every modifier it found. Downloads are cached per build in F:/project/littles/wago-cache (../wago-cache
next to the repository; the WAGO_CACHE environment variable overrides it).
"""
import csv, io, json, os, re, sys, tempfile, urllib.parse, urllib.request
from collections import defaultdict
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPELLS = os.path.join(ROOT, "Modules", "PartyCD", "Spells.lua")
OUT = os.path.join(ROOT, "Modules", "PartyCD", "TalentData.lua")

COOLDOWN_OP = 11          # SpellModOp: cooldown (charged abilities included)
FLAT, PCT, FLAT_LABEL, PCT_LABEL, MAX_CHARGES = 107, 108, 379, 380, 411

# ---------------------------------------------------------------------------
# wago.tools
# ---------------------------------------------------------------------------

def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "CombatKit talentdata (github.com/Venser)"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()

def latest_build():
    data = json.loads(fetch("https://wago.tools/api/builds"))
    for b in data["wow"]:
        if not b.get("is_bgdl"):
            return b["version"]
    raise SystemExit("no live build listed")

class DB2:
    def __init__(self, build):
        self.build = build
        self.cache = os.path.join(os.environ.get("WAGO_CACHE") or os.path.join(os.path.dirname(ROOT), "wago-cache"), build)
        os.makedirs(self.cache, exist_ok=True)

    def rows(self, table, **filters):
        q = {"build": self.build}
        for k, v in filters.items():
            q["filter[%s]" % k] = v
        key = table + ("_" + "_".join("%s=%s" % kv for kv in sorted(filters.items())) if filters else "") + ".csv"
        path = os.path.join(self.cache, key)
        if not os.path.exists(path):
            url = "https://wago.tools/db2/%s/csv?%s" % (table, urllib.parse.urlencode(q))
            sys.stderr.write("  fetching %s\n" % key)
            open(path, "wb").write(fetch(url))
        with open(path, encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        # wago's filter matches 498 and 4980 alike: keep the exact matches only
        for k, v in filters.items():
            rows = [r for r in rows if r.get(k) == str(v)]
        return rows

# ---------------------------------------------------------------------------
# What is watched
# ---------------------------------------------------------------------------

def watched_defs():
    """(spellID, hand cooldown, hand charges, hand specs or None, comment) per entry of Spells.lua"""
    text = open(SPELLS, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"(?:Self|External|Burst|CC)\((\d+),\s*(\d+)(.*?)\),?\s*--\s*(.*)", text):
        extra = m.group(3)
        charges = re.search(r"charges\s*=\s*(\d+)", extra)
        specs = re.search(r"specs\s*=\s*set\(([\d,\s]+)\)", extra)
        out.append((int(m.group(1)), int(m.group(2)), int(charges.group(1)) if charges else 1,
                    {int(s) for s in specs.group(1).split(",")} if specs else None, m.group(4).strip()))
    return out

# ---------------------------------------------------------------------------
# The data
# ---------------------------------------------------------------------------

def num(s, default=0):
    try:
        return float(s) if "." in s else int(s)
    except (TypeError, ValueError):
        return default

def main():
    build = sys.argv[1] if len(sys.argv) > 1 else latest_build()
    db = DB2(build)
    watched = watched_defs()
    print("build %s, %d watched abilities" % (build, len(watched)))

    class_options = {}
    for r in db.rows("SpellClassOptions"):
        class_options[int(r["SpellID"])] = (int(r["SpellClassSet"]), tuple(int(r["SpellClassMask_%d" % i]) for i in range(4)))
    labels = defaultdict(set)
    for r in db.rows("SpellLabel"):
        labels[int(r["SpellID"])].add(int(r["LabelID"]))
    names = {}
    def name(spell):
        if spell not in names:
            rows = db.rows("SpellName", ID=spell)
            names[spell] = rows[0]["Name_lang"] if rows else "?"
        return names[spell]

    # ---- base cooldown and charges
    base = {}
    categories = {int(r["ID"]): r for r in db.rows("SpellCategory")}
    print("\nbase values that differ from Spells.lua:")
    for sid, hand_cd, hand_charges, _, comment in watched:
        cd, charges, charge_cat = None, 1, None
        for r in db.rows("SpellCooldowns", SpellID=sid):
            if r["DifficultyID"] == "0":
                cd = max(num(r["RecoveryTime"]), num(r["CategoryRecoveryTime"])) / 1000
        for r in db.rows("SpellCategories", SpellID=sid):
            if r["DifficultyID"] == "0" and r["ChargeCategory"] != "0":
                charge_cat = int(r["ChargeCategory"])
        if charge_cat and charge_cat in categories:
            c = categories[charge_cat]
            charges = max(1, int(c["MaxCharges"]))   # a category without charges says 0
            cd = num(c["ChargeRecoveryTime"]) / 1000
        if cd is None or cd == 0:
            print("  !! %d %s: no cooldown in the data, keeping %d" % (sid, comment, hand_cd))
            cd = hand_cd
        base[sid] = {"cd": cd, "charges": charges, "chargeCategory": charge_cat, "name": name(sid)}
        if cd != hand_cd or charges != hand_charges:
            print("  %d %s: data cd=%g charges=%d, Spells.lua cd=%d charges=%d" % (sid, comment, cd, charges, hand_cd, hand_charges))

    # ---- who may be a source: talents, spec passives, PvP talents
    definitions = defaultdict(list)   # spell -> definition IDs
    for r in db.rows("TraitDefinition"):
        if r["SpellID"] not in ("", "0"):
            definitions[int(r["SpellID"])].append(int(r["ID"]))
    spec_spells = defaultdict(set)    # spell -> spec IDs (SpecializationSpells)
    for r in db.rows("SpecializationSpells"):
        spec_spells[int(r["SpellID"])].add(int(r["SpecID"]))
    pvp_talents = {int(r["SpellID"]) for r in db.rows("PvpTalent") if r["SpellID"] not in ("", "0")}
    def kind(source):
        if source in definitions: return "talent"
        if source in spec_spells: return "spec passive"
        if source in pvp_talents: return "pvp talent"
        return None

    # ---- rank curves, by definition
    curves = defaultdict(list)
    for r in db.rows("CurvePoint"):
        curves[int(r["CurveID"])].append((num(r["Pos_0"]), num(r["Pos_1"])))
    effect_points = defaultdict(dict)   # definition -> effect index -> (operation, curve)
    for r in db.rows("TraitDefinitionEffectPoints"):
        effect_points[int(r["TraitDefinitionID"])][int(r["EffectIndex"])] = (int(r["OperationType"]), int(r["CurveID"]))

    def ranks_for(source, effect_index, value):
        """{definitionID: [value at rank 1, 2, ...]} for the definitions of this talent that have a curve"""
        out = {}
        for defn in definitions.get(source, ()):
            pts = effect_points.get(defn, {}).get(effect_index)
            if not pts:
                continue
            op, curve = pts
            points = sorted(curves.get(curve, []))
            if not points:
                continue
            if op == 0:
                out[defn] = [v for _, v in points]
            elif op == 1:
                out[defn] = [value * v for _, v in points]
            else:
                print("  !! unknown curve operation %d on %d %s" % (op, source, name(source)))
        return out

    # ---- the modifiers that hit a watched ability
    mods = defaultdict(lambda: defaultdict(dict))   # source -> watched -> { sec | pct | charges, ranks }
    ops_seen = defaultdict(set)
    effects = []
    for aura in (FLAT, PCT, FLAT_LABEL, PCT_LABEL):
        effects += [(aura, r) for r in db.rows("SpellEffect", EffectAura=aura)]

    def put(source, sid, field, value, ranks):
        if not value and not ranks:
            return
        m = mods[source][sid]
        m[field] = value
        if ranks:
            m.setdefault("ranks", {})
            for defn, values in ranks.items():
                m["ranks"].setdefault(defn, {})[field] = values

    for aura, r in effects:
        source = int(r["SpellID"])
        if not kind(source):
            continue
        src = class_options.get(source)
        op = int(r["EffectMiscValue_0"])
        for sid, _, _, _, _ in watched:
            tgt = class_options.get(sid)
            if aura in (FLAT, PCT):
                if not src or not tgt or src[0] != tgt[0]:
                    continue
                mask = tuple(int(r["EffectSpellClassMask_%d" % i]) for i in range(4))
                if not any(a & b for a, b in zip(mask, tgt[1])):
                    continue
            elif int(r["EffectMiscValue_1"]) not in labels.get(sid, ()):
                continue
            ops_seen[op].add((source, sid))
            if op != COOLDOWN_OP:
                continue
            value = num(r["EffectBasePointsF"])
            ranks = ranks_for(source, int(r["EffectIndex"]), value)
            if aura in (FLAT, FLAT_LABEL):
                put(source, sid, "sec", value / 1000, {d: [v / 1000 for v in vs] for d, vs in ranks.items()})
            else:
                put(source, sid, "pct", value, ranks)
    for r in db.rows("SpellEffect", EffectAura=MAX_CHARGES):
        source = int(r["SpellID"])
        if not kind(source):
            continue
        cat = int(r["EffectMiscValue_0"])
        for sid, b in base.items():
            if b["chargeCategory"] == cat:
                value = num(r["EffectBasePointsF"])
                put(source, sid, "charges", value, ranks_for(source, int(r["EffectIndex"]), value))

    spec = defaultdict(list)
    for source in mods:
        for spec_id in spec_spells.get(source, ()):
            spec[spec_id].append(source)

    # ---- the audit
    print("\nspecializations the data gives an ability (SpecializationSpells) against `specs` in Spells.lua:")
    for sid, _, _, hand_specs, comment in watched:
        data_specs = spec_spells.get(sid)
        if data_specs and data_specs != (hand_specs or set()):
            print("  %d %s: data %s, Spells.lua %s" % (sid, comment, sorted(data_specs), sorted(hand_specs) if hand_specs else "every spec"))
    print("\nmodifier ops seen on the watched abilities from talents / passives / PvP talents (11 = cooldown, the rest ignored):")
    for op in sorted(ops_seen):
        srcs = sorted(ops_seen[op])
        print("  op %d: %d, e.g. %s" % (op, len(srcs), ", ".join("%s->%s" % (name(s), base[t]["name"]) for s, t in srcs[:3])))
    print("\nmodifiers:")
    for source in sorted(mods):
        for sid, m in sorted(mods[source].items()):
            fields = " ".join("%s=%s" % (k, v) for k, v in sorted(m.items()) if k != "ranks")
            ranks = m.get("ranks")
            print("  %-7d %-32s -> %-26s %s%s  [%s]" % (source, name(source), base[sid]["name"], fields,
                  (" ranks=" + str(ranks)) if ranks else "", kind(source)))

    write(build, watched, base, mods, spec, name, kind)
    print("\nwrote %s" % os.path.relpath(OUT, ROOT))

# ---------------------------------------------------------------------------
# The Lua
# ---------------------------------------------------------------------------

def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return "%g" % v
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_value(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join("[%d] = %s" % (k, lua_value(v[k])) for k in sorted(v)) + " }"
    if isinstance(v, str):
        return "%s = %s" % v
    raise TypeError(v)

def write(build, watched, base, mods, spec, name, kind):
    out = io.StringIO()
    w = out.write
    w("local ADDON, ns = ...\n\n")
    w("-- Generated by tools/talentdata.py from the game's data files (DB2, via wago.tools),\n")
    w("-- build %s, on %s. Do not edit: run the script again after a patch.\n" % (build, date.today().isoformat()))
    w("-- base: a watched ability's cooldown and charges. mods: every talent, specialization\n")
    w("-- passive and PvP talent that changes one of them, with sec (seconds added, negative\n")
    w("-- for a shorter cooldown), pct (negative for a shorter cooldown) or charges; `ranks`\n")
    w("-- gives the value per rank by the talent's TraitDefinition when it has ranks. Only\n")
    w("-- what a teammate has selected is applied. spec: each specialization's passives.\n")
    w("ns.TalentData = {\n")
    w("\tbuild = %s,\n" % json.dumps(build))
    w("\tbase = {\n")
    for sid, _, _, _, _ in watched:
        b = base[sid]
        w("\t\t[%d] = { cd = %s, charges = %d },  -- %s\n" % (sid, lua_value(b["cd"]), b["charges"], b["name"]))
    w("\t},\n\tmods = {\n")
    for source in sorted(mods):
        w("\t\t[%d] = {  -- %s (%s)\n" % (source, name(source), kind(source)))
        for sid, m in sorted(mods[source].items()):
            fields = []
            for k in ("sec", "pct", "charges"):
                if k in m:
                    fields.append("%s = %s" % (k, lua_value(m[k])))
            if "ranks" in m:
                parts = []
                for defn in sorted(m["ranks"]):
                    inner = ", ".join("%s = %s" % (k, lua_value(v)) for k, v in sorted(m["ranks"][defn].items()))
                    parts.append("[%d] = { %s }" % (defn, inner))
                fields.append("ranks = { %s }" % ", ".join(parts))
            w("\t\t\t[%d] = { %s },  -- %s\n" % (sid, ", ".join(fields), base[sid]["name"]))
        w("\t\t},\n")
    w("\t},\n\tspec = {\n")
    for spec_id in sorted(spec):
        w("\t\t[%d] = { %s },\n" % (spec_id, ", ".join(str(s) for s in sorted(spec[spec_id]))))
    w("\t},\n}\n")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(out.getvalue())

if __name__ == "__main__":
    main()
