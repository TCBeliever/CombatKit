"""Offline checks for CombatKit: python tests/run_tests.py  (needs `pip install lupa`).

1. every Lua file listed in a .toc compiles (Lua 5.1)
2. structure: the promise "a module that is off costs nothing" holds
3. release metadata, locale coverage, line endings, no Blizzard frame skin
4. behaviour tests against WoW API stubs, in both languages
"""
import re
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CORE = "CombatKit"
TESTS = ["test_kit.lua", "test_logic.lua", "test_apply.lua", "test_ui.lua", "test_stats.lua", "test_range.lua", "test_misc.lua"]

ok = True


def fail(msg):
    global ok
    ok = False
    print(msg)


# ---------------------------------------------------------------- addons and their files
tocs = [ROOT / f"{CORE}.toc"] + sorted((ROOT / "Modules").glob("*/*.toc"))
addons = {}   # name -> {"dir":, "files": [Path], "meta": {}}
for toc in tocs:
    meta, files = {}, []
    for line in toc.read_text(encoding="utf-8").splitlines():
        m = re.match(r"##\s*([\w-]+):\s*(.*)", line)
        if m:
            meta[m.group(1)] = m.group(2).strip()
        elif line.strip() and not line.startswith("#"):
            files.append(toc.parent / line.strip().replace("\\", "/"))
    addons[toc.stem] = {"dir": toc.parent, "files": files, "meta": meta}

# 1. syntax
lua = LuaRuntime(unpack_returned_tuples=True)
compile_file = lua.eval("function(p) local f, err = loadfile(p); return f ~= nil, err end")
for name, addon in addons.items():
    for f in addon["files"]:
        if not f.exists():
            fail(f"{name}.toc lists a missing file: {f.relative_to(ROOT)}")
            continue
        res = compile_file(str(f).replace("\\", "/"))
        good, err = res if isinstance(res, tuple) else (res, None)
        if not good:
            fail(f"syntax {f.relative_to(ROOT)}: {err}")
listed = {f.resolve() for a in addons.values() for f in a["files"]}
for f in list(ROOT.glob("*.lua")) + list((ROOT / "Modules").rglob("*.lua")):
    if f.resolve() not in listed:
        fail(f"not listed in any .toc: {f.relative_to(ROOT)}")
print(f"syntax: {sum(len(a['files']) for a in addons.values())} files in {len(addons)} addons")

# 2. structure: off = not loaded
for f in addons[CORE]["files"]:
    if "Modules" in f.relative_to(ROOT).parts:
        fail(f"the core .toc loads a module file: {f.relative_to(ROOT)}")
    src = f.read_text(encoding="utf-8")
    for m in re.finditer(r"modules\.(\w+)", src):
        fail(f"the core reaches into a module ({m.group(0)}) in {f.name}")
for name, addon in addons.items():
    if name == CORE:
        continue
    meta = addon["meta"]
    if meta.get("LoadOnDemand") != "1":
        fail(f"{name}.toc: LoadOnDemand must be 1")
    if meta.get("RequiredDeps") != CORE:
        fail(f"{name}.toc: RequiredDeps must be {CORE}")
    if addon["dir"].name != name.split("_", 1)[1]:
        fail(f"{name}.toc is not in Modules/{name.split('_', 1)[1]}")

# 2b. release metadata: one version everywhere, and the changelog ends with it (the release
# workflow publishes the last section of CHANGELOG.md and refuses a tag that does not match)
versions = {name: a["meta"].get("Version") for name, a in addons.items()}
if len(set(versions.values())) != 1:
    fail(f"the .toc files disagree about the version: {versions}")
interfaces = {a["meta"].get("Interface") for a in addons.values()}
if len(interfaces) != 1:
    fail(f"the .toc files disagree about the Interface: {interfaces}")
sections = re.findall(r"^## (\S+)", (ROOT / "CHANGELOG.md").read_text(encoding="utf-8"), re.M)
if not sections or sections[-1] != versions[CORE]:
    fail(f"CHANGELOG.md must end with the section for {versions[CORE]} (it ends with {sections[-1] if sections else 'nothing'})")
notes = addons[CORE]["meta"].get("Notes", "")
if len(notes) > 256:
    fail(f"the toc Notes double as the CurseForge summary, which takes 256 characters: {len(notes)}")

# 3a. line endings
for f in list(ROOT.glob("*.*")) + list((ROOT / "Modules").rglob("*.*")):
    if f.suffix in (".lua", ".toc", ".md") and b"\r\n" in f.read_bytes():
        fail(f"CRLF in {f.relative_to(ROOT)}")

# 3b. locale coverage: every key the code uses has a zhTW entry; symbolic keys also need English
en_keys, zh_keys, used, prefixes = set(), set(), set(), set()
code_files = []
for addon in addons.values():
    for f in addon["files"]:
        src = f.read_text(encoding="utf-8")
        if f.name == "Locales.lua":
            current = None
            for line in src.splitlines():
                m = re.match(r'\w+\.AddLocale\("(\w+)"', line)
                if m:
                    current = m.group(1)
                elif line.startswith("})"):
                    current = None
                else:
                    k = re.match(r'\s*\["([^"]+)"\]\s*=', line)
                    if k and current:
                        (en_keys if current == "enUS" else zh_keys).add(k.group(1))
            used |= set(re.findall(r'\bkey = "([A-Za-z_]+)"', src))
        else:
            code_files.append((f, src))

key_re = re.compile(r'L\["([^"]+)"\]')
prefix_re = re.compile(r'"([A-Z_]+_)"\s*\.\.')
helper_res = [
    re.compile(r'\), "([^"]+)"\)'),                                   # CK.Bind(widget, "key")
    re.compile(r'Field\(\w+, "([^"]+)"'),
    re.compile(r'Toggle\("([^"]+)"(?:, "([^"]+)")?(?:, "([^"]+)")?'),
    re.compile(r'Skin\.Tooltip\([\w.]+, "([^"]+)"(?:, "([^"]+)"\))?'),
    re.compile(r'\bStep\("([^"]+)"'),                                  # local page helpers
    re.compile(r'\bText\("([^"]+)", "\w+", -?\d'),
]
literal_re = re.compile(r'"([^"\n]*)"')   # * not +: an empty "" has to be consumed as one literal
for f, src in code_files:
    used |= set(key_re.findall(src))
    prefixes |= set(prefix_re.findall(src))
    for rx in helper_res:
        for m in rx.finditer(src):
            for g in m.groups():
                # a locale key starts with a capital (or is symbolic); "warmode", "GameFont..." are not keys
                if g and g[0].isupper() and not g.endswith("_") and not g.startswith("GameFont"):
                    used.add(g)
# a key can also reach L[] through a table or a condition: any literal that is a known key counts as used
known = en_keys | zh_keys
for f, src in code_files:
    used |= {lit for lit in literal_re.findall(src) if lit in known}
SAME_IN_EVERY_LOCALE = {"GROUP_pve", "GROUP_pvp"}
for k in sorted(used):
    if k not in zh_keys and k not in SAME_IN_EVERY_LOCALE:
        fail(f"no zhTW for: {k}")
    if re.match(r"[A-Z]+_", k) and k not in en_keys:
        fail(f"symbolic key without English: {k}")
for k in sorted((zh_keys | en_keys) - used):
    if not any(k.startswith(pre) for pre in prefixes):
        fail(f"locale entry never used: {k}")

# 3c. no Blizzard skin: templates and border art are gone (BackdropTemplate is the API, not a look)
banned = ["UIPanelButtonTemplate", "UICheckButtonTemplate", "UIRadioButtonTemplate", "UIPanelCloseButton",
          "UIPanelScrollFrameTemplate", "UI-DialogBox", "UI-Tooltip-Border", "ChatFrameBackground",
          "UI-QuestTitleHighlight", "Arrow-Down-Up", "ReadyCheck-"]
for f, src in code_files:
    for b in banned:
        if b in src:
            fail(f"Blizzard skin asset in {f.relative_to(ROOT)}: {b}")

# 4. behaviour, in both languages
for loc in ("enUS", "zhTW"):
    for test in TESTS:
        if not (HERE / test).exists():
            continue
        lua = LuaRuntime(unpack_returned_tuples=True)
        g = lua.globals()
        g.ROOT = str(ROOT).replace("\\", "/")
        g.HERE = str(HERE).replace("\\", "/")
        g.LOCALE = loc
        failed = lua.execute((HERE / test).read_text(encoding="utf-8"))
        ok = ok and failed == 0

sys.exit(0 if ok else 1)
