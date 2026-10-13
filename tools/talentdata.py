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
written in Spells.lua, and every modifier it found. Each table is downloaded whole, once per build (a few requests, never one per
spell), and kept in F:/project/littles/wago-cache (../wago-cache
next to the repository; the WAGO_CACHE environment variable overrides it).
"""
import csv, io, json, os, re, sys, tempfile, urllib.parse, urllib.request
from collections import defaultdict
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPELLS = os.path.join(ROOT, "Modules", "PartyCD", "Spells.lua")
OUT = os.path.join(ROOT, "Modules", "PartyCD", "TalentData.lua")

COOLDOWN_OP = 11          # SpellModOp: cooldown (charged abilities included)
# the spell modifiers: by class mask (107, 108) or by spell label (219, 218); 379 and 380
# carry no cooldown change in 12.1
FLAT, PCT, FLAT_LABEL, PCT_LABEL, MAX_CHARGES = 107, 108, 219, 218, 411
CHARGE_RECOVERY = 453   # milliseconds added to a charge category's recharge (EffectMiscValue_0: the category)
CHARGE_RECOVERY_PCT = 454   # percent added to a charge category's recharge
CATEGORY_COOLDOWN = 341     # milliseconds added to a cooldown category's cooldown (EffectMiscValue_0)
UNDER_CONTROL = 0x8 | 0x20000 | 0x40000   # SpellMisc.Attributes_5: usable while stunned, feared, disoriented

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
        self.tables = {}   # table -> its rows
        self.index = {}    # (table, column) -> value -> rows

    def table(self, table):
        """every row of a table: downloaded whole once per build (one request), read once per run"""
        if table not in self.tables:
            path = os.path.join(self.cache, table + ".csv")
            if not os.path.exists(path) or os.path.getsize(path) == 0:
                url = "https://wago.tools/db2/%s/csv?%s" % (table, urllib.parse.urlencode({"build": self.build}))
                sys.stderr.write("  fetching %s (the whole table)\n" % table)
                data = fetch(url)   # fetched first: a failed request leaves no file behind
                with open(path + ".part", "wb") as f:
                    f.write(data)
                os.replace(path + ".part", path)
            with open(path, encoding="utf-8", newline="") as f:
                self.tables[table] = list(csv.DictReader(f))
        return self.tables[table]

    def rows(self, table, **filters):
        """the rows whose columns equal the filters, looked up in the whole table:
        no request per spell, an index per column built on first use"""
        rows = self.table(table)
        if not filters:
            return rows
        (col, value), *rest = sorted(filters.items())
        index = self.index.get((table, col))
        if index is None:
            index = defaultdict(list)
            for r in rows:
                index[r.get(col)].append(r)
            self.index[(table, col)] = index
        out = index.get(str(value), [])
        for col, value in rest:
            out = [r for r in out if r.get(col) == str(value)]
        return out

# ---------------------------------------------------------------------------
# What is watched
# ---------------------------------------------------------------------------

# the constructors of Spells.lua; every one takes the spell ID and the cooldown first
CONSTRUCTORS = "Caster|Ally|OtherAlly|Allies|Enemy|Enemies|EnemyLater"

def watched_defs():
    """(spellID, hand cooldown, hand charges, hand specs or None, comment) per entry of Spells.lua"""
    text = open(SPELLS, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"\b(?:%s)\((\d+),\s*(\d+)(.*?)\),?\s*--\s*(.*)" % CONSTRUCTORS, text):
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
    # SpellMisc.Attributes_5: usable while stunned (0x8), while feared (0x20000), while
    # disoriented (0x40000): a teammate under such a control may still have cast it
    under_control = {}
    for r in db.rows("SpellMisc"):
        if r["DifficultyID"] == "0":
            under_control[int(r["SpellID"])] = int(r["Attributes_5"] or 0)
    for sid, hand_cd, hand_charges, _, comment in watched:
        cd, charges, charge_cat, own, cooldown_cat = None, 1, None, 0, None
        for r in db.rows("SpellCooldowns", SpellID=sid):
            if r["DifficultyID"] == "0":
                cd = max(num(r["RecoveryTime"]), num(r["CategoryRecoveryTime"])) / 1000
                own = cd
        for r in db.rows("SpellCategories", SpellID=sid):
            if r["DifficultyID"] == "0" and r["ChargeCategory"] != "0":
                charge_cat = int(r["ChargeCategory"])
            if r["DifficultyID"] == "0" and r["Category"] not in ("", "0"):
                cooldown_cat = int(r["Category"])
        if charge_cat and charge_cat in categories:
            c = categories[charge_cat]
            charges = max(1, int(c["MaxCharges"]))   # a category without charges says 0
            cd = num(c["ChargeRecoveryTime"]) / 1000
        if cd is None or cd == 0:
            print("  !! %d %s: no cooldown in the data, keeping %d" % (sid, comment, hand_cd))
            cd = hand_cd
        # own: the spell's own cooldown; with a charge category the recharge is what counts
        base[sid] = {"cd": cd, "charges": charges, "chargeCategory": charge_cat, "cooldownCategory": cooldown_cat, "own": own,
                     "underControl": bool(under_control.get(sid, 0) & UNDER_CONTROL), "name": name(sid)}
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
                b = base[sid]
                def seconds(v):
                    # a flat change moves the spell's own cooldown, not a charge category's
                    # recharge: what is waited is the longer of the two (Storm of Steel takes
                    # Bladestorm's own 90 s away so its second charge can be used; the recharge
                    # stays 90 s). A percentage moves the recharge as well (Honed Reflexes).
                    if not b["chargeCategory"]:
                        return v / 1000
                    return max(b["own"] + v / 1000, b["cd"]) - max(b["own"], b["cd"])
                flat = seconds(value)
                if flat != value / 1000:
                    print("  .. %d %s -> %s: %g s on its own cooldown, %g s on the recharge" % (
                        source, name(source), b["name"], value / 1000, flat))
                put(source, sid, "sec", flat, {d: [seconds(v) for v in vs] for d, vs in ranks.items()})
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
    # a talent that gives a charge often shortens the recharge too (Defender's Aegis: a
    # second Shield Wall and 60 s off it), by the same category; a percentage the same way
    # (Cycle of Binding), and a cooldown category by milliseconds (Angel's Mercy)
    for r in db.rows("SpellEffect", EffectAura=CHARGE_RECOVERY_PCT):
        source = int(r["SpellID"])
        if not kind(source):
            continue
        cat = int(r["EffectMiscValue_0"])
        for sid, b in base.items():
            if b["chargeCategory"] == cat and "pct" not in mods[source][sid]:   # a 108 of the same talent says it already
                value = num(r["EffectBasePointsF"])
                put(source, sid, "pct", value, ranks_for(source, int(r["EffectIndex"]), value))
    for r in db.rows("SpellEffect", EffectAura=CATEGORY_COOLDOWN):
        source = int(r["SpellID"])
        if not kind(source):
            continue
        cat = int(r["EffectMiscValue_0"])
        for sid, b in base.items():
            if b["cooldownCategory"] == cat:
                value = num(r["EffectBasePointsF"])
                put(source, sid, "sec", value / 1000,
                    {d: [v / 1000 for v in vs] for d, vs in ranks_for(source, int(r["EffectIndex"]), value).items()})
    for r in db.rows("SpellEffect", EffectAura=CHARGE_RECOVERY):
        source = int(r["SpellID"])
        if not kind(source):
            continue
        cat = int(r["EffectMiscValue_0"])
        for sid, b in base.items():
            if b["chargeCategory"] == cat:
                value = num(r["EffectBasePointsF"])
                if "sec" in mods[source][sid]:
                    print("  !! %d %s: a cooldown and a recharge change on %s, adding them" % (source, name(source), b["name"]))
                    value += mods[source][sid]["sec"] * 1000
                put(source, sid, "sec", value / 1000,
                    {d: [v / 1000 for v in vs] for d, vs in ranks_for(source, int(r["EffectIndex"]), value).items()})

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
    print("\nspecializations whose talent tree shows the ability (TraitCond by spec set) against `specs` in Spells.lua:")
    for sid, (hand, tree), comment in tree_spec_audit(db, watched):
        print("  %d %s: tree %s, Spells.lua %s" % (sid, comment, sorted(tree), sorted(hand) if hand else "every spec"))
    # an external that cannot land on its caster: SpellMisc.Attributes_1 0x80000 (Blessing of
    # Sacrifice, Intervene); Spells.lua says it with OtherAlly
    text = open(SPELLS, encoding="utf-8").read()
    excludes = {int(r["SpellID"]) for r in db.rows("SpellMisc")
                if r["DifficultyID"] == "0" and int(r["Attributes_1"] or 0) & 0x80000}
    print("\nexternals whose data and Spells.lua disagree on landing on the caster (Attributes_1 0x80000 vs OtherAlly):")
    for m in re.finditer(r"\b(Ally|OtherAlly|Allies)\((\d+),", text):
        sid = int(m.group(2))
        if (m.group(1) == "OtherAlly") != (sid in excludes) and m.group(1) != "Allies":
            print("  %d %s: Spells.lua %s, data %s" % (sid, name(sid), m.group(1), "excludes the caster" if sid in excludes else "may be the caster"))
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

def tree_spec_audit(db, watched):
    """(spellID, (Spells.lua specs or None, tree specs), comment) for each watched talent whose
    nodes a spec-set condition limits to other specializations than Spells.lua says. A node
    with no such condition is in the class tree: every spec. Old trees (all loadout rows
    numbered under 500) are left out."""
    rows = defaultdict(list)
    for r in db.rows("TraitTreeLoadout"):
        rows[int(r["TraitTreeID"])].append(int(r["ID"]))
    spec_sets = defaultdict(set)
    for r in db.rows("SpecSetMember"):
        spec_sets[int(r["SpecSet"])].add(int(r["ChrSpecializationID"]))
    shown_by = {}   # condition -> spec set, for the "available" (0) and "visible" (1) conditions
    for r in db.rows("TraitCond"):
        if r["CondType"] in ("0", "1") and r["SpecSetID"] not in ("", "0"):
            shown_by[int(r["ID"])] = int(r["SpecSetID"])
    node_conds = defaultdict(set)
    for r in db.rows("TraitNodeXTraitCond"):
        node_conds[int(r["TraitNodeID"])].add(int(r["TraitCondID"]))
    group_conds = defaultdict(set)
    for r in db.rows("TraitNodeGroupXTraitCond"):
        group_conds[int(r["TraitNodeGroupID"])].add(int(r["TraitCondID"]))
    for r in db.rows("TraitNodeGroupXTraitNode"):
        node_conds[int(r["TraitNodeID"])] |= group_conds.get(int(r["TraitNodeGroupID"]), set())
    tree_of = {int(r["ID"]): int(r["TraitTreeID"]) for r in db.rows("TraitNode")}
    old = {t for t, ids in rows.items() if max(ids) < 500}
    entry_def = {int(r["ID"]): int(r["TraitDefinitionID"]) for r in db.rows("TraitNodeEntry")}
    def_nodes = defaultdict(set)
    for r in db.rows("TraitNodeXTraitNodeEntry"):
        e = int(r["TraitNodeEntryID"])
        if e in entry_def and tree_of.get(int(r["TraitNodeID"])) not in old:
            def_nodes[entry_def[e]].add(int(r["TraitNodeID"]))
    spell_nodes = defaultdict(set)
    for r in db.rows("TraitDefinition"):
        for v in (r["SpellID"], r["VisibleSpellID"]):
            if v not in ("", "0"):
                spell_nodes[int(v)] |= def_nodes.get(int(r["ID"]), set())
    out = []
    for sid, _, _, hand, comment in watched:
        nodes = spell_nodes.get(sid)
        if not nodes:
            continue   # not a talent: a class skill, a spec spell, a PvP talent or a pet's
        specs = set()
        for n in nodes:
            sets = [shown_by[c] for c in node_conds.get(n, ()) if c in shown_by]
            if not sets:
                specs = None   # a node of the class tree
                break
            for ss in sets:
                specs |= spec_sets[ss]
        if specs is None:
            if hand:
                out.append((sid, (hand, {"every spec"}), comment))
        elif specs != (hand or set()):
            out.append((sid, (hand, specs), comment))
    return out


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
    w("-- base: a watched ability's cooldown and charges, and underControl when it can be cast\n")
    w("-- under a stun, a fear or a disorient. mods: every talent, specialization\n")
    w("-- passive and PvP talent that changes one of them, with sec (seconds added, negative\n")
    w("-- for a shorter cooldown), pct (negative for a shorter cooldown) or charges; `ranks`\n")
    w("-- gives the value per rank by the talent's TraitDefinition when it has ranks. Only\n")
    w("-- what a teammate has selected is applied. spec: each specialization's passives.\n")
    w("ns.TalentData = {\n")
    w("\tbuild = %s,\n" % json.dumps(build))
    w("\tbase = {\n")
    for sid, _, _, _, _ in watched:
        b = base[sid]
        w("\t\t[%d] = { cd = %s, charges = %d%s },  -- %s\n" % (sid, lua_value(b["cd"]), b["charges"],
          ", underControl = true" if b["underControl"] else "", b["name"]))
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
