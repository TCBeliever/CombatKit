"""Compare what AuraLab learned in game with the auras Modules/PartyCD/Spells.lua watches.

    python tools/auralab_check.py                     # finds AuraLab.lua under the WoW folder
    python tools/auralab_check.py path/to/AuraLab.lua

AuraLab (../AuraLab, a development addon) counts, for every cast of a watched ability
(its Targets.lua, from tools/auralab_targets.py) by the player or a teammate while auras
are not secret, which auras appeared 0.4 s later on the caster (self), on another member
of the group (ally) and on the caster's target (enemy). Here each watched ability gets a
verdict:

  confirmed   a listed aura came, where Spells.lua looks for it, in at least half of
              the casts and at least twice
  differs     no listed aura did, another one did: the data's guess was wrong
  no aura     cast at least twice and no aura came that often (lands later, a trap or
              a totem; or none at all)
  more casts  seen once: one cast proves nothing against chance
  not seen    never cast near the player yet

Needs lupa (pip install lupa), as the tests do.
"""
import glob, os, sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from candidates import listed   # noqa: E402

from lupa.lua51 import LuaRuntime

WOW = r"F:\World of Warcraft\_retail_"
MIN_CASTS = 2

# where Spells.lua looks for an ability's aura, as the lab names it
WHERE = {"caster": {"self"}, "ally": {"self", "ally"}, "otherAlly": {"ally"}, "allies": {"self", "ally"},
         "enemy": {"enemy"}, "enemies": {"enemy"}, "enemyLater": {"enemy"}}

def saved_path():
    if len(sys.argv) > 1:
        return sys.argv[1]
    found = glob.glob(os.path.join(WOW, "WTF", "Account", "*", "SavedVariables", "AuraLab.lua"))
    if not found:
        raise SystemExit("no AuraLab.lua under %s: name the file" % WOW)
    return max(found, key=os.path.getmtime)

def read_checks(path):
    lua = LuaRuntime(unpack_returned_tuples=True)
    with open(path, encoding="utf-8") as f:
        lua.execute(f.read())
    db = lua.eval("AuraLabDB")
    out = {}
    checks = db["checks"] if db is not None else None
    if checks is None:
        return out
    for key, c in checks.items():
        auras = {}
        for k, v in (c["auras"] or {}).items():
            where, aid = k.split(" ")
            auras[(where, int(aid))] = int(v)
        out[int(key)] = {"name": c["name"], "casts": int(c["casts"]), "mine": int(c["mine"] or 0), "auras": auras}
    return out

def main():
    path = saved_path()
    checks = read_checks(path)
    print("%s: %d abilities learned from" % (path, len(checks)))
    groups = defaultdict(list)
    for token, sid, seen, casts, auras, comment in listed():
        c = checks.get(sid)
        if not c:
            groups["not seen"].append("%d %s (%s)" % (sid, comment[:50], token))
            continue
        n, places = c["casts"], WHERE[seen]
        need = max(MIN_CASTS, (n + 1) // 2)
        listed_hits = [(a, w, k) for (w, a), k in c["auras"].items() if a in auras and w in places]
        good = [x for x in listed_hits if x[2] >= need]
        others = sorted(((k, w, a) for (w, a), k in c["auras"].items() if k >= need and not (a in auras and w in places)),
                        reverse=True)
        line = "%d %s (%s), %d casts (%d yours): " % (sid, comment[:50], token, n, c["mine"])
        if n < MIN_CASTS:
            groups["more casts"].append(line + ", ".join("%s %d x%d" % (w, a, k) for (w, a), k in c["auras"].items()))
        elif good:
            groups["confirmed"].append(line + ", ".join("%s %d x%d" % (w, a, k) for a, w, k in good))
        elif others:
            groups["differs"].append(line + "listed %s, seen %s" % (auras, ", ".join("%s %d x%d" % (w, a, k) for k, w, a in others[:4])))
        else:
            groups["no aura"].append(line + "listed %s%s" % (auras, " (lands later: not learnable at 0.4 s)" if seen == "enemyLater" else ""))
    for verdict in ("differs", "no aura", "confirmed", "more casts", "not seen"):
        rows = groups.get(verdict, [])
        print("\n%s: %d" % (verdict, len(rows)))
        if verdict != "not seen":
            for r in rows:
                print("  " + r)

if __name__ == "__main__":
    main()
