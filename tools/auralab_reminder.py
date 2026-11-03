"""What AuraLab's Reminder probe recorded in game, answered as the questions the Reminder module has.

    python tools/auralab_reminder.py                     # the newest AuraLab.lua under the WoW folder
    python tools/auralab_reminder.py path/to/AuraLab.lua

AuraLab (../AuraLab, a development addon) records, wherever its switch is on, a line
each time something the Reminder module relies on changed (AuraLabDB.reminder.lines),
and counts group members' casts by whether their spell read (AuraLabDB.reminder.casts).
Here that becomes:

  1. which chat event carries a feast's line
  2. whether a cauldron says anything in chat
  3. whether a group member's cast reads out of combat (dungeon, raid)
  4. how auras are handed out in dungeons, raids, keys, in and out of combat
  5. the weapon enchant APIs; 6. the stance bar against the aura API

followed by the lines themselves, newest last. Needs lupa (pip install lupa), as the tests do.
"""
import glob, os, re, sys
from collections import Counter, defaultdict

from lupa.lua51 import LuaRuntime

WOW = r"F:\World of Warcraft\_retail_"
FEASTS = {242272, 242744, 242273, 242745, 255845, 266985, 255846, 266996, 275264, 275267, 275265, 275268, 275266, 275269}
FLASK_CAULDRONS = {241318, 241319}
POTION_CAULDRONS = {241284, 241285}

# date time place combat tag text, as Reminder.lua writes them
LINE = re.compile(r"^(\S+ \S+) (\S+)\s+(no combat|combat)\s+(\S+)\s+(.*)$")


def saved_path():
    if len(sys.argv) > 1:
        return sys.argv[1]
    found = glob.glob(os.path.join(WOW, "WTF", "Account", "*", "SavedVariables", "AuraLab.lua"))
    if not found:
        raise SystemExit("no AuraLab.lua under %s: name the file" % WOW)
    return max(found, key=os.path.getmtime)


def read(path):
    lua = LuaRuntime(unpack_returned_tuples=True)
    with open(path, encoding="utf-8") as f:
        lua.execute(f.read())
    db = lua.eval("AuraLabDB")
    r = db["reminder"] if db is not None else None
    if r is None:
        return [], {}
    lines = [r["lines"][i] for i in range(1, len(r["lines"]) + 1)] if r["lines"] else []
    casts = {k: int(v) for k, v in (r["casts"] or {}).items()}
    return lines, casts


def parsed(lines):
    out = []
    for text in lines:
        m = LINE.match(text)
        if m:
            out.append({"when": m.group(1), "place": m.group(2), "combat": m.group(3), "tag": m.group(4), "text": m.group(5)})
    return out


def item_of(text):
    m = re.search(r"\b(2\d{5})\b", text)
    return int(m.group(1)) if m else None


def main():
    path = saved_path()
    lines, casts = read(path)
    rows = parsed(lines)
    print("%s: %d lines" % (path, len(rows)))
    if not rows and not casts:
        print("nothing recorded yet: AuraLab 0.14 or later, the switch on, then /reload or log out")
        return
    by = defaultdict(list)
    for r in rows:
        by[r["tag"]].append(r)

    print("\n1. the chat event that carries a feast's line")
    events = Counter(r["text"].split()[0] for r in by["chat"] if item_of(r["text"]) in FEASTS)
    print("   " + (", ".join("%s %d" % kv for kv in events.most_common()) if events else "no feast line seen yet"))

    print("\n2. does a cauldron say anything in chat")
    said = [r for r in by["chat"] if item_of(r["text"]) in FLASK_CAULDRONS | POTION_CAULDRONS]
    silent = [r for r in by["cast"] if r["text"].startswith("no chat line") and item_of(r["text"]) in FLASK_CAULDRONS | POTION_CAULDRONS]
    cast_seen = [r for r in by["cast"] if "->" in r["text"] and item_of(r["text"].split("->")[1]) in FLASK_CAULDRONS | POTION_CAULDRONS]
    if said:
        print("   yes: %d lines (%s)" % (len(said), ", ".join(sorted({r["text"].split()[0] for r in said}))))
    elif silent:
        print("   no: %d cauldron casts with no chat line after them" % len(silent))
    else:
        print("   not seen yet (%d cauldron casts read)" % len(cast_seen))

    print("\n3. group members' casts: does the spell read")
    table = defaultdict(Counter)
    for key, n in casts.items():
        kind, combat, state = [p.strip() for p in key.split(",")]
        table[(kind, combat)][state] += n
    for (kind, combat), c in sorted(table.items()):
        total = sum(c.values())
        print("   %-12s %-9s %5d casts: %s" % (kind, combat, total, ", ".join("%s %d" % kv for kv in sorted(c.items()))))
    if not table:
        print("   no group cast counted yet")

    print("\n4. auras by place, in and out of combat (the last line of each)")
    last = {}
    for r in by["aura"]:
        last[(r["place"], r["combat"])] = r
    for (place, combat), r in sorted(last.items()):
        print("   %-12s %-9s %s" % (place, combat, r["text"]))
    if not last:
        print("   no aura line yet")

    print("\n5. weapon enchant APIs (the last line)")
    print("   " + (by["enchant"][-1]["text"] if by["enchant"] else "no line yet"))
    print("   " + (by["api"][-1]["text"] if by["api"] else "no api line yet"))

    print("\n6. the stance bar against the aura API")
    seen = Counter(r["text"] for r in by["stance"] if "spell nil" not in r["text"] and "bar 0" not in r["text"])
    print("   " + ("; ".join("%s (x%d)" % kv for kv in seen.most_common(5)) if seen else "no stance seen yet"))

    print("\nchat and cast lines")
    for r in by["chat"] + by["cast"]:
        print("   %s %-12s %-9s %-5s %s" % (r["when"], r["place"], r["combat"], r["tag"], r["text"][:160]))


if __name__ == "__main__":
    main()
