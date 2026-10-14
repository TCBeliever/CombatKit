"""List the abilities the Party CD module could watch, from the game's own data files
(DB2, as exported by wago.tools) and nothing else, and keep the reason each one is in
or out of Modules/PartyCD/Spells.lua.

    python tools/candidates.py                  # the build TalentData.lua was made from
    python tools/candidates.py 12.1.0.69933

Why: the module's list of abilities has to be derived from the game's data, not from
another addon's list. This tool is the record of that: every ability a class can have
in the build, the ones a mechanical filter keeps, and a hand-written decision with a
reason for each one it keeps (tools/candidates_decisions.tsv).

1. The universe, per class: the class skill line's abilities (SkillLineAbility), every
   spell a node of the live talent trees gives (class, spec and hero trees; a removed
   talent or one only in an old tree does not count, see talentdata.LiveTalents), the
   specializations' spells (SpecializationSpells), the PvP talents (PvpTalent), and
   what these teach (a learn-spell effect) or swap onto the button (an override aura).
   A spell only another spell triggers is not in it: it is that ability's effect.
2. The candidates: active (not passive), a cooldown of 20 seconds or more (its own,
   its category's, or its charges' recharge), and an aura it leaves on someone the
   module can look at: the caster, an ally, or an opponent (an apply-aura effect of
   the cast, or of a spell the cast triggers, one link down; when the data links the
   cast to no aura at all, because the server applies it by script, the aura spells of
   the same name in the class's spell family, marked "by name"). When a talent or a PvP
   talent puts another spell on the same button, that spell joins the base ability as
   one candidate, keyed by the base's spell ID, the way Spells.lua keys its entries.
   A specialization's own version (Vengeance's Metamorphosis) stays its own candidate.
3. The decisions: tools/candidates_decisions.tsv, by hand: spell ID, `in` or `out`,
   the reason. Every candidate needs a row.
4. The report: docs/PartyCD-candidates.md, generated: per class the candidates, then
   what Spells.lua has that the filter does not keep (and why), the candidates marked
   `in` that Spells.lua lacks, and the Spells.lua entries marked `out`.

Exits 1 when a candidate has no decision, so the file stays complete. The tables come
from talentdata.py's cache (../wago-cache/<build>, WAGO_CACHE overrides it); a table
missing there is downloaded whole, once.
"""
import os, re, sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from talentdata import DATE_MARK, DB2, ROOT, SPELLS, LiveTalents, num, write_dated   # noqa: E402
from auradata import APPLY_AURA, TRIGGERS, Data, read           # noqa: E402

DECISIONS = os.path.join(ROOT, "tools", "candidates_decisions.tsv")
REPORT = os.path.join(ROOT, "docs", "PartyCD-candidates.md")
TALENT_DATA = os.path.join(ROOT, "Modules", "PartyCD", "TalentData.lua")

MIN_COOLDOWN = 20   # seconds; shorter ones are rotation, not something a row should show

# the classes as Spells.lua names them, their skill line (SkillLine, CategoryID 7) and
# their specializations (ChrSpecialization IDs, as listed in the Spells.lua header)
CLASSES = [
    ("DEATHKNIGHT", "Death Knight", {250: "Blood", 251: "Frost", 252: "Unholy"}),
    ("DEMONHUNTER", "Demon Hunter", {577: "Havoc", 581: "Vengeance", 1480: "Devourer"}),
    ("DRUID", "Druid", {102: "Balance", 103: "Feral", 104: "Guardian", 105: "Restoration"}),
    ("EVOKER", "Evoker", {1467: "Devastation", 1468: "Preservation", 1473: "Augmentation"}),
    ("HUNTER", "Hunter", {253: "Beast Mastery", 254: "Marksmanship", 255: "Survival"}),
    ("MAGE", "Mage", {62: "Arcane", 63: "Fire", 64: "Frost"}),
    ("MONK", "Monk", {268: "Brewmaster", 269: "Windwalker", 270: "Mistweaver"}),
    ("PALADIN", "Paladin", {65: "Holy", 66: "Protection", 70: "Retribution"}),
    ("PRIEST", "Priest", {256: "Discipline", 257: "Holy", 258: "Shadow"}),
    ("ROGUE", "Rogue", {259: "Assassination", 260: "Outlaw", 261: "Subtlety"}),
    ("SHAMAN", "Shaman", {262: "Elemental", 263: "Enhancement", 264: "Restoration"}),
    ("WARLOCK", "Warlock", {265: "Affliction", 266: "Demonology", 267: "Destruction"}),
    ("WARRIOR", "Warrior", {71: "Arms", 72: "Fury", 73: "Protection"}),
]
CLASS_OF_SPEC = {s: token for token, _, specs in CLASSES for s in specs}

# the racial abilities, listed as one more "class": every race's own skill line ("Racial -
# Dwarf"), for the races its race mask names, by the token UnitRace gives them (ChrRaces)
RACIAL = "RACIAL"
RACIAL_LINE = re.compile(r"^Racial - ")

# SkillLineAbility.AcquireMethod: 2 and 4 are learned with the class. 3 marks a spell a
# talent gives, or a long-gone artifact's; a live one comes in through the talent trees.
LEARNED_WITH_CLASS = {"2", "4"}

# SpellMisc
PASSIVE = 0x40             # Attributes_0
NOT_ON_SELF = 0x80000      # Attributes_1: cannot be cast on oneself (Blessing of Sacrifice)

# SpellEffect.Effect
LEARN_SPELL = 36
LINKS = set(TRIGGERS) | {32}   # auradata's triggers, and 32: a missile that casts its spell where it lands
LATER = {27: "a persistent area", 28: "a summon", 50: "an object", 76: "an object", 104: "an object", 105: "an object",
         106: "an object", 107: "an object", 179: "an area trigger"}   # the aura comes from something left behind
OVERRIDE_BUTTON = 332      # SpellEffect.EffectAura: puts EffectBasePointsF on the button of the spell it masks

# ImplicitTarget, sorted by what they mean for where an aura lands
CASTER = {1}
ENEMY_ONE = {6, 53}
ENEMY_AREA = {2, 15, 16, 24, 28, 54, 104, 108, 109, 112, 115}
ALLY_ONE = {21, 35, 57}
ANY_ONE = {25}   # the cast's target, friend or foe: the cast's own targets tell which
ALLY_AREA = {3, 4, 20, 29, 30, 31, 33, 34, 37, 45, 56, 58, 59, 61, 90, 93}
AREA_AURA = {27: "enemies", 35: "allies", 65: "allies", 128: "allies", 129: "enemies"}   # Effect -> who

# SpellEffect.EffectAura: the ones worth naming in the report, so a reader sees what an
# aura does without looking it up. %s takes the effect's value where it says something.
AURA_WORDS = {3: "damage over time", 5: "incapacitate", 7: "fear", 8: "heal over time", 12: "stun",
              16: "stealth", 18: "invisibility", 26: "root", 27: "silence", 31: "speed %s%%",
              33: "slow %s%%", 36: "shapeshift", 39: "school immunity", 56: "transform",
              60: "pacify and silence", 67: "disarm", 69: "absorb", 77: "mechanic immunity",
              79: "damage done %s%%", 81: "damage split %s%%", 87: "damage taken %s%%", 129: "speed %s%%"}

JUNK_NAME = re.compile(r"\(OLD\)|\bDNT\b|^zz|UNUSED|\(Test\)", re.I)

# ---------------------------------------------------------------------------
# The data
# ---------------------------------------------------------------------------

NAME = "name"   # a landing found by the spell's name, not by a link in the data
MAX_BY_NAME = 4  # the report shows this many of those (a common name finds creatures' spells too)

class Game(Data):
    """auradata's Data (names, cooldowns, effects, triggers), plus the effect columns and
    the SpellMisc attributes this tool needs."""
    def __init__(self, db):
        super().__init__(db)
        self.castable = set()   # every spell of the universe, set once it is known
        self.detail = defaultdict(list)   # spell -> [(Effect, EffectAura, value, misc0, mask, trigger, t0, t1)]
        cols = ("SpellID", "DifficultyID", "Effect", "EffectAura", "EffectBasePointsF", "EffectMiscValue_0",
                "EffectSpellClassMask_0", "EffectSpellClassMask_1", "EffectSpellClassMask_2", "EffectSpellClassMask_3",
                "EffectTriggerSpell", "ImplicitTarget_0", "ImplicitTarget_1")
        for sid, diff, eff, aura, bp, m0, k0, k1, k2, k3, trig, t0, t1 in read(db, "SpellEffect", cols):
            if diff == "0":
                self.detail[int(sid)].append((int(eff), int(aura), num(bp), int(m0),
                                              (int(k0), int(k1), int(k2), int(k3)), int(trig), int(t0), int(t1)))
        self.attr0, self.attr1 = {}, {}
        for sid, diff, a0, a1 in read(db, "SpellMisc", ("SpellID", "DifficultyID", "Attributes_0", "Attributes_1")):
            if diff == "0":
                self.attr0[int(sid)], self.attr1[int(sid)] = int(a0 or 0), int(a1 or 0)
        self.mask = {}
        for sid, k0, k1, k2, k3 in read(db, "SpellClassOptions", ("SpellID", "SpellClassMask_0", "SpellClassMask_1",
                                                                  "SpellClassMask_2", "SpellClassMask_3")):
            self.mask[int(sid)] = (int(k0), int(k1), int(k2), int(k3))

    def passive(self, sid):
        return bool(self.attr0.get(sid, 0) & PASSIVE)

    def not_on_self(self, sid):
        return bool(self.attr1.get(sid, 0) & NOT_ON_SELF)

    def landings(self, sid):
        """[(auraID, who, via)]: the auras this cast puts on someone, its own (via None),
        those of a spell it triggers (one link down, via = that spell's ID), or, when
        neither gives one, those of a spell of the same name (via = NAME). who is caster,
        ally, allies, enemy or enemies, from the aura spell's own targets."""
        out = []
        # where the cast itself aims, for an aura spell that says only "the target"
        aimed = [landing(6, t0, t1) for _, _, _, _, _, _, t0, t1 in self.detail.get(sid, ())]
        aimed = next((w for w in aimed if w in ("enemy", "enemies", "ally", "allies")), "ally")
        def scan(spell, via):
            for eff, aura, _, _, _, trig, t0, t1 in self.detail.get(spell, ()):
                if eff in APPLY_AURA:
                    who = landing(eff, t0, t1)
                    who = aimed if who == "target" else who
                    if who and (spell, who, via) not in out:
                        out.append((spell, who, via))
        scan(sid, None)
        for trig in self.links(sid):
            scan(trig, trig)
        if not out:
            # Nothing in the data links the cast to its aura: its effects are dummies (or it
            # leaves an area behind) and the server applies the aura as a spell of the same
            # name (Storm Bolt's stun 132169, Rallying Cry's buff 97463). Take those, from the
            # same class's spell family, that are not an ability of their own.
            for other in self.same_name(sid):
                if other not in self.castable:
                    scan(other, NAME)
        return out

    def links(self, sid):
        """the spells this cast triggers, one link down"""
        return [trig for eff, _, _, _, _, trig, _, _ in self.detail.get(sid, ()) if eff in LINKS and trig and trig != sid]

    def leaves_behind(self, sid):
        """what the cast, or a spell it triggers, leaves on the ground or summons (a trap, a
        totem, an area), if anything"""
        return sorted({LATER[e[0]] for s in [sid] + self.links(sid) for e in self.detail.get(s, ()) if e[0] in LATER})

    def aura_words(self, aura):
        """what an aura does, in the few words AURA_WORDS has for its effects"""
        words = []
        for eff, a, value, _, _, _, _, _ in self.detail.get(aura, ()):
            if eff in APPLY_AURA and a in AURA_WORDS:
                w = AURA_WORDS[a]
                if "%s" in w:   # a value of 0 is set elsewhere (a talent, a script): say only what it is
                    w = w % ("%+g" % value) if value else w.split(" %s")[0]
                if w not in words:
                    words.append(w)
        return words

def landing(eff, t0, t1):
    """who an apply-aura effect lands on, from its targets: caster, ally, allies, enemy,
    enemies; None for a pet or anything else the module does not look at"""
    t = {t0, t1} - {0}
    if t & ENEMY_ONE: return "enemy"
    if t & ENEMY_AREA: return "enemies"
    if eff in AREA_AURA: return AREA_AURA[eff]
    if t & ALLY_AREA: return "allies"
    if t & ALLY_ONE: return "ally"
    if t & ANY_ONE: return "target"
    if not t or t <= CASTER | {18, 22, 32, 62}: return "caster"   # the caster, or around the caster's feet
    return None

# ---------------------------------------------------------------------------
# 1. The universe
# ---------------------------------------------------------------------------

class Universe:
    """Per class: spell -> the specializations that get it and where it comes from;
    plus the buttons a talent or a PvP talent swaps (variant -> base)."""
    def __init__(self, db, game):
        self.db, self.game = db, game
        self.spells = {token: {} for token, _, _ in CLASSES}
        self.spells[RACIAL] = {}
        self.races = defaultdict(set)   # a racial spell -> the races that have it
        self.variant = {}        # a talent's or PvP talent's spell -> the button it replaces
        self.spec_version = {}   # a specialization's own version -> the spell it replaces
        self.standalone = set()  # spells some source gives as a button of their own
        self.dropped = []        # (class, spell, why) for what the liveness rules took out
        all_specs = {token: set(specs) for token, _, specs in CLASSES}

        # the class skill line
        line_of = {}
        for r in db.rows("SkillLine"):
            if r["CategoryID"] == "7":
                line_of[r["DisplayName_lang"]] = r["ID"]
        for token, line_name, _ in CLASSES:
            for r in db.rows("SkillLineAbility", SkillLine=line_of[line_name]):
                if r["AcquireMethod"] in LEARNED_WITH_CLASS:
                    self.add(token, int(r["Spell"]), all_specs[token], "class")
                    self.standalone.add(int(r["Spell"]))

        # the specializations' spells
        for r in db.rows("SpecializationSpells"):
            spec, sid, over = int(r["SpecID"]), int(r["SpellID"]), int(r["OverridesSpellID"])
            if spec in CLASS_OF_SPEC:
                self.add(CLASS_OF_SPEC[spec], sid, {spec}, "spec")
                self.standalone.add(sid)
                if over:
                    self.spec_version[sid] = over

        # the talent trees: only nodes of live trees
        live = LiveTalents(db)
        for r in db.rows("TraitDefinition"):
            nodes = live.def_nodes.get(int(r["ID"]))
            if not nodes:
                continue   # a removed talent, or one only in an old tree
            token, specs = None, set()
            for n in nodes:
                tree_classes = {CLASS_OF_SPEC.get(s) for s in live.tree_specs.get(live.tree_of.get(n), ())} - {None}
                if len(tree_classes) != 1:
                    continue
                token = tree_classes.pop()
                specs |= all_specs[token] if live.node_specs[n] is None else live.node_specs[n]
            if not token:
                continue
            sid, visible, over = int(r["SpellID"] or 0), int(r["VisibleSpellID"] or 0), int(r["OverridesSpellID"] or 0)
            for s in (sid, visible, over):
                if s:
                    self.add(token, s, specs, "talent")
            if sid and over and sid != over:
                self.variant.setdefault(sid, over)
            elif sid:
                self.standalone.add(sid)
            self.follow(token, sid, specs, "talent")

        # the PvP talents
        for r in db.rows("PvpTalent"):
            spec = int(r["SpecID"])
            if spec not in CLASS_OF_SPEC:
                continue
            token = CLASS_OF_SPEC[spec]
            sid, bar, over = int(r["SpellID"]), int(r["ActionBarSpellID"]), int(r["OverridesSpellID"])
            for s in (sid, bar, over):
                if s:
                    self.add(token, s, {spec}, "PvP")
            for s in (sid, bar):
                if s and over and s != over:
                    self.variant.setdefault(s, over)
                elif s:
                    self.standalone.add(s)
            self.follow(token, sid, {spec}, "PvP")

        # the racial skill lines, each for the races its race mask names (two 32-bit words,
        # bit n for the race whose PlayableRaceBit is n)
        race_of_bit = {int(r["PlayableRaceBit"]): r["ClientFileString"] for r in db.rows("ChrRaces")
                       if int(r["PlayableRaceBit"] or -1) >= 0}
        def races(m0, m1):
            mask = (int(m0 or 0) & 0xFFFFFFFF) | ((int(m1 or 0) & 0xFFFFFFFF) << 32)
            if mask == 0xFFFFFFFFFFFFFFFF:
                return set()   # every race: not a race's own
            return {race for bit, race in race_of_bit.items() if mask >> bit & 1}
        racial_lines = {r["ID"] for r in db.rows("SkillLine") if RACIAL_LINE.match(r["DisplayName_lang"])}
        line_races = defaultdict(set)
        for r in db.rows("SkillRaceClassInfo"):
            if r["SkillID"] in racial_lines:
                line_races[r["SkillID"]] |= races(r["RaceMasks_0"], r["RaceMasks_1"])
        for line in sorted(racial_lines, key=int):
            for r in db.rows("SkillLineAbility", SkillLine=line):
                if r["AcquireMethod"] in LEARNED_WITH_CLASS:
                    sid = int(r["Spell"])
                    self.add(RACIAL, sid, set(), "race")
                    self.standalone.add(sid)
                    self.races[sid] |= races(r["RaceMasks_0"], r["RaceMasks_1"]) or line_races[line]

        self.drop_junk()

    def add(self, token, sid, specs, source):
        e = self.spells[token].setdefault(sid, {"specs": set(), "from": set()})
        e["specs"] |= specs
        e["from"].add(source)

    def follow(self, token, sid, specs, source):
        """what a talent or PvP talent teaches (a learn-spell effect) or swaps onto a button
        (an override aura, whose value is the new spell; the replaced one is named by its
        misc value, or picked by the class mask)"""
        g = self.game
        for eff, aura, value, misc0, mask, trig, _, _ in g.detail.get(sid, ()):
            if eff == LEARN_SPELL and trig:
                self.add(token, trig, specs, source)
            elif eff in APPLY_AURA and aura == OVERRIDE_BUTTON and value:
                new = int(value)
                self.add(token, new, specs, source)
                base = misc0 if misc0 in self.spells[token] else self.masked(token, sid, mask, new)
                if base and base != new:
                    self.variant.setdefault(new, base)

    def masked(self, token, source, mask, new):
        """the active spell of this class, other than the new one, whose class mask the
        effect's mask picks (only when it picks one)"""
        g = self.game
        fam = g.family.get(source, 0)
        hits = [s for s in self.spells[token] if s != new and g.family.get(s, 0) == fam and not g.passive(s)
                and any(a & b for a, b in zip(mask, g.mask.get(s, (0, 0, 0, 0))))]
        return hits[0] if len(hits) == 1 else None

    def drop_junk(self):
        for token, spells in self.spells.items():
            for sid in list(spells):
                name = self.game.name(sid)
                if name == "?" or JUNK_NAME.search(name):
                    self.dropped.append((token, sid, "no name in the data" if name == "?" else "named as unused"))
                    del spells[sid]

    def base_of(self, token, sid):
        """the button a spell is a version of, following talent and PvP talent swaps; a spell
        that some source also gives as a button of its own stays its own ability"""
        seen = {sid}
        while sid in self.variant and sid not in self.standalone and self.variant[sid] in self.spells[token]                 and self.variant[sid] not in seen:
            sid = self.variant[sid]
            seen.add(sid)
        return sid

# ---------------------------------------------------------------------------
# 2. The candidates
# ---------------------------------------------------------------------------

def why_not(game, uni, token, sid):
    """why the filter does not keep a spell (None when it does)"""
    if sid not in uni.spells[token]:
        return "not in the class's spells"
    if game.passive(sid):
        return "passive"
    cd, _ = game.cooldown(sid)
    if cd < MIN_COOLDOWN:
        return "cooldown %gs" % cd
    if not game.landings(sid):
        return "no aura from the cast or one trigger down"
    return None

class Candidate:
    def __init__(self, token, key):
        self.token, self.key = token, key
        self.members = []   # the other cast IDs on the same button
        self.specs = set()
        self.races = set()  # a racial ability's races
        self.sources = set()
        self.landings = []  # (aura, who, via, cast)

def candidates(game, uni):
    """{class: {key: Candidate}}"""
    out = {}
    for token, spells in uni.spells.items():
        groups = {}
        for sid in sorted(spells):
            if why_not(game, uni, token, sid):
                continue
            key = uni.base_of(token, sid)
            c = groups.setdefault(key, Candidate(token, key))
            if sid != key:
                c.members.append(sid)
        for key, c in groups.items():
            for sid in [key] + c.members:
                if sid in spells:
                    c.specs |= spells[sid]["specs"]
                    c.sources |= spells[sid]["from"]
                    c.races |= uni.races.get(sid, set())
                for aura, who, via in game.landings(sid):
                    if not any(a == aura and w == who for a, w, _, _ in c.landings):
                        c.landings.append((aura, who, via, sid))
        out[token] = groups
    return out

def suggest_seen(game, c):
    """the constructor the data points at, from the cast's own landings (all of them when
    it has none of its own). An aura on opponents as the cast lands, one or several, is
    `enemy` (it shows at the cast); one that comes from what the cast leaves behind is
    `enemies` for an area that stays (Solar Beam) or `enemyLater` for a trap or a totem.
    A cast aimed at an opponent is watched on the opponent even when it buffs the caster."""
    own = {who for _, who, via, cast in c.landings if via in (None, NAME) and cast == c.key} or           {who for _, who, _, _ in c.landings}
    friendly = own & {"caster", "ally", "allies"}
    hostile = own & {"enemy", "enemies"}
    if "enemy" in own or (hostile and not friendly):
        later = game.leaves_behind(c.key)
        if not later:
            return "enemy"
        return "enemyLater" if set(later) & {"a summon", "an object"} else "enemies"
    if "allies" in own:
        return "allies"
    if "ally" in own:
        return "otherAlly" if game.not_on_self(c.key) else "ally"
    return "caster"

# ---------------------------------------------------------------------------
# Spells.lua and the decisions
# ---------------------------------------------------------------------------

CONSTRUCTORS = {"Caster": "caster", "Ally": "ally", "OtherAlly": "otherAlly", "Allies": "allies",
                "Enemy": "enemy", "Enemies": "enemies", "EnemyLater": "enemyLater"}

def listed():
    """[(class, spellID, seen, casts, auras, comment)] per entry of Spells.lua"""
    out, token = [], None
    for line in open(SPELLS, encoding="utf-8"):
        m = re.match(r"\t([A-Z]+) = \{", line)
        if m:
            token = m.group(1)
            continue
        if re.match(r"ns\.RACIALS = \{", line):
            token = RACIAL
            continue
        # a racial entry closes its race's braces too: ") },  -- name"
        m = re.search(r"\b(%s)\((\d+),(.*?)\)(?:\s*\})?,?\s*--\s*(.*)" % "|".join(CONSTRUCTORS), line)
        if m and token:
            extra = m.group(3)
            casts = re.search(r"casts\s*=\s*\{([\d,\s]+)\}", extra)
            many = re.search(r"auras\s*=\s*\{([\d,\s]+)\}", extra)
            one = re.search(r"\baura\s*=\s*(\d+)", extra)
            sid = int(m.group(2))
            auras = [int(x) for x in many.group(1).split(",")] if many else [int(one.group(1))] if one else [sid]
            out.append((token, sid, CONSTRUCTORS[m.group(1)],
                        [int(x) for x in casts.group(1).split(",")] if casts else [], auras, m.group(4).strip()))
    return out

def decisions():
    """{spellID: (in/out, reason)} from the hand-kept file; # starts a comment"""
    out = {}
    if not os.path.exists(DECISIONS):
        return out
    for n, line in enumerate(open(DECISIONS, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3 or parts[1] not in ("in", "out") or not parts[0].strip().isdigit():
            raise SystemExit("%s:%d: want spellID<TAB>in|out<TAB>reason, got %r" % (DECISIONS, n, line))
        sid = int(parts[0])
        if sid in out:
            raise SystemExit("%s:%d: %d decided twice" % (DECISIONS, n, sid))
        out[sid] = (parts[1], parts[2].strip())
    return out

def default_build():
    m = re.search(r'build\s*=\s*"([\d.]+)"', open(TALENT_DATA, encoding="utf-8").read())
    if not m:
        raise SystemExit("no build in TalentData.lua: name one")
    return m.group(1)

# ---------------------------------------------------------------------------
# 4. The report
# ---------------------------------------------------------------------------

def fmt_cd(game, sid):
    cd, charges = game.cooldown(sid)
    return "%gs%s" % (cd, " x%d" % charges if charges > 1 else "")

def fmt_specs(token, specs, races=()):
    if token == RACIAL:
        return ", ".join(sorted(races)) or "?"
    names = dict(next(s for t, _, s in CLASSES if t == token))
    if specs >= set(names):
        return "all"
    return ", ".join(names[s] for s in sorted(specs) if s in names)

def diagnose(game, uni, token, entry):
    """why a Spells.lua entry is not a candidate key or member, in plain words"""
    _, sid, seen, casts, auras, _ = entry
    reason = why_not(game, uni, token, sid)
    if reason == "not in the class's spells":
        lines = {r["SkillLine"] for r in uni.db.rows("SkillLineAbility", Spell=sid)}
        pets = sorted(r["DisplayName_lang"] for r in uni.db.rows("SkillLine") if r["ID"] in lines)
        if pets:
            return "a pet's or a guardian's ability (skill line %s): the module sees it on the opponent, the class's data does not give it" % ", ".join(pets)
        if not game.family.get(sid, 0):
            return "not a class spell: a pet's or a guardian's ability (no class spell family)"
        for t, spells in uni.spells.items():
            if sid in spells:
                return "listed under %s in the data" % t
        dropped = [w for t, s, w in uni.dropped if s == sid]
        if dropped:
            return "dropped by the liveness rules: " + dropped[0]
        return "no class skill, live talent node, specialization spell or PvP talent gives it"
    if reason and reason.startswith("no aura"):
        deep, via = game.auras_of(sid)
        hits = [a for a in auras if a in deep]
        if hits:
            return "its aura %s comes more than one trigger down" % ", ".join(map(str, hits))
        left = game.leaves_behind(sid)
        if left:
            return "no aura of its own: the aura comes from %s it leaves (%s), which the tool does not follow" % (
                " / ".join(left), ", ".join(map(str, auras)))
        return "no aura from the cast in the data (%s: not linked to it, a server script)" % ", ".join(map(str, auras))
    return reason

def cell(s):
    return str(s).replace("|", "\\|")

def write_report(build, game, uni, cands, decided, entries):
    out = []
    w = out.append
    total = sum(len(s) for s in uni.spells.values())
    n_cand = sum(len(g) for g in cands.values())
    n_in = sum(1 for g in cands.values() for k in g if decided.get(k, ("",))[0] == "in")
    n_out = sum(1 for g in cands.values() for k in g if decided.get(k, ("",))[0] == "out")
    w("# Party CD: candidates from the game's data")
    w("")
    w("> Generated by `tools/candidates.py` from the game's data files (DB2, via wago.tools), build %s, on %s." % (build, DATE_MARK))
    w("> Do not edit: change `tools/candidates_decisions.tsv` (the decisions) and run `python tools/candidates.py` again.")
    w("")
    w("Every ability below comes from the game's own tables only: the class skill line, the live talent trees,")
    w("the specializations' spells and the PvP talents (the universe), kept when it is active, has a cooldown of")
    w("%d s or more and leaves an aura the module can see on the caster, an ally or an opponent (the cast's own" % MIN_COOLDOWN)
    w("apply-aura effects, or those of a spell it triggers, one link down; when the data links the cast to no aura,")
    w("the aura spells of the same name in the class's spell family). A talent's or PvP talent's spell on the same")
    w("button is listed under the base ability (`casts`). The decision and its reason are written by hand.")
    w("Racial abilities come from each race's own skill line (\"Racial - Dwarf\"), for the races its race mask")
    w("names, and are listed last under *Racial*, the races in place of the specializations.")
    w("")
    w("Universe: %d spells. Candidates: %d (in %d, out %d, undecided %d)." % (total, n_cand, n_in, n_out, n_cand - n_in - n_out))
    w("")
    w("Columns: *Auras* lists each aura ID and where it lands (caster, ally, allies, enemy, enemies): `<- X` when")
    w("cast X triggers it, `[X]` when X (a version on the same button) applies it, `by name of X` when nothing in")
    w("the data links X to an aura and the aura is the spell of the same name the server applies (Storm Bolt's")
    w("stun); then what the aura does, where the data says so. *Seen* is the constructor the data points at.")
    w("*Listed* says whether Spells.lua has it: as an entry (with its constructor when that differs from *Seen*),")
    w("or under one as a cast or an aura.")
    w("")
    listed_ids = {}   # (class, spell) -> how Spells.lua has it
    for e in entries:
        for s in e[4]:
            listed_ids.setdefault((e[0], s), "aura of %d" % e[1])
        for s in e[3]:
            listed_ids[(e[0], s)] = "cast of %d" % e[1]
    listed_seen = {}
    for e in entries:
        listed_ids[(e[0], e[1])] = "yes"
        listed_seen[(e[0], e[1])] = e[2]
    for token in [t for t, _, _ in CLASSES] + [RACIAL]:
        groups = cands[token]
        w("## %s" % token.capitalize() if token not in ("DEATHKNIGHT", "DEMONHUNTER") else
          "## %s" % {"DEATHKNIGHT": "Death Knight", "DEMONHUNTER": "Demon Hunter"}[token])
        w("")
        w("| ID | Name | Cooldown | %s | Auras | Seen | Listed | Decision | Reason |" % ("Races" if token == RACIAL else "Specs"))
        w("|---|---|---|---|---|---|---|---|---|")
        for key in sorted(groups, key=lambda k: (decided.get(k, ("~",))[0], game.name(k), k)):
            c = groups[key]
            name = game.name(key)
            if c.members:
                name += " (casts " + ", ".join("%d %s" % (m, game.name(m)) for m in c.members) + ")"
            if key in uni.spec_version:
                name += " (a specialization's version of %d)" % uni.spec_version[key]
            auras, by_name = [], 0
            for aura, who, via, cast in c.landings:
                if via == NAME:
                    by_name += 1
                    if by_name > MAX_BY_NAME:
                        continue
                words = game.aura_words(aura)
                how = ("" if cast == c.key else " [%d]" % cast) if via is None else \
                      " by name of %d" % cast if via == NAME else " <- %d" % cast
                auras.append("%d %s%s%s" % (aura, who, how, (" (" + ", ".join(words) + ")") if words else ""))
            if by_name > MAX_BY_NAME:
                auras.append("and %d more by name" % (by_name - MAX_BY_NAME))
            cd = fmt_cd(game, key) + "".join("; %d: %s" % (m, fmt_cd(game, m)) for m in c.members
                                             if fmt_cd(game, m) != fmt_cd(game, key))
            hit = next((s for s in [key] + c.members if (token, s) in listed_ids), None)
            is_listed = listed_ids[(token, hit)] if hit else ""
            seen = suggest_seen(game, c)
            if is_listed == "yes" and listed_seen[(token, hit)] != seen:
                is_listed = "yes, as %s" % listed_seen[(token, hit)]
            if is_listed.startswith("yes") and hit != key:
                is_listed += " (entry %d)" % hit
            d, reason = decided.get(key, ("**undecided**", ""))
            w("| %d | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                key, cell(name), cd, fmt_specs(token, c.specs, c.races), "<br>".join(cell(a) for a in auras),
                seen, is_listed, d, cell(reason)))
        w("")

    member_of = {}
    for token, groups in cands.items():
        for key, c in groups.items():
            for s in [key] + c.members:
                member_of[(token, s)] = key
    w("## (a) In Spells.lua, not among the candidates")
    w("")
    w("Why the mechanical filter does not keep them. These stay in Spells.lua on the hand's judgement; the")
    w("filter's blind spots are named so they can be checked.")
    w("")
    a_list = []
    for e in entries:
        token, sid = e[0], e[1]
        if (token, sid) in member_of:
            key = member_of[(token, sid)]
            if key != sid:
                a_list.append("- %d %s (%s): the data folds it under %d %s, a talent or PvP talent on the same button" % (
                    sid, game.name(sid), token, key, game.name(key)))
            continue
        a_list.append("- %d %s (%s): %s" % (sid, game.name(sid), token, diagnose(game, uni, token, e)))
    out.extend(a_list or ["- none"])
    w("")
    w("## (b) Candidates marked `in` that Spells.lua lacks (proposed additions)")
    w("")
    b_list = []
    for token, groups in cands.items():
        for key, c in sorted(groups.items()):
            if decided.get(key, ("",))[0] == "in" and not any((token, s) in listed_ids for s in [key] + c.members):
                b_list.append("- %d %s (%s, %s, %s): %s" % (key, game.name(key), token, fmt_cd(game, key),
                                                             suggest_seen(game, c), decided[key][1]))
    out.extend(b_list or ["- none"])
    w("")
    w("## (c) Spells.lua entries marked `out` (proposed removals)")
    w("")
    c_list = []
    for e in entries:
        key = member_of.get((e[0], e[1]))
        if key is not None and decided.get(key, ("",))[0] == "out":
            c_list.append("- %d %s (%s): %s" % (e[1], game.name(e[1]), e[0], decided[key][1]))
    out.extend(c_list or ["- none"])
    w("")
    wrote = write_dated(REPORT, "\n".join(out))
    return a_list, b_list, c_list, wrote

# ---------------------------------------------------------------------------

def main():
    build = sys.argv[1] if len(sys.argv) > 1 else default_build()
    db = DB2(build)
    game = Game(db)
    uni = Universe(db, game)
    game.castable = {sid for spells in uni.spells.values() for sid in spells}
    cands = candidates(game, uni)
    decided = decisions()
    entries = listed()
    a_list, b_list, c_list, wrote = write_report(build, game, uni, cands, decided, entries)

    keys = {k for g in cands.values() for k in g}
    undecided = sorted(k for k in keys if k not in decided)
    stale = sorted(k for k in decided if k not in keys)
    print("build %s: universe %d, candidates %d, decided %d" % (
        build, sum(len(s) for s in uni.spells.values()), len(keys), len(keys) - len(undecided)))
    print("(a) %d listed, not candidates; (b) %d proposed additions; (c) %d proposed removals" % (
        len(a_list), len(b_list), len(c_list)))
    for sid in stale:
        print("  .. decision for %d %s, which is not a candidate (stale row)" % (sid, game.name(sid)))
    if wrote:
        print("wrote %s" % REPORT)
    if undecided:
        for sid in undecided:
            print("  !! no decision for %d %s" % (sid, game.name(sid)))
        sys.exit(1)

if __name__ == "__main__":
    main()
