# CombatKit

A modular combat addon for World of Warcraft (Retail) with a small resource footprint. It bundles:

- **Loadout** (on by default): spec, talents and gear switched automatically by scenario: open world, delves, dungeons / M+, raids, arena, battlegrounds.
- **Stats**: live stats on a compact HUD.
- **Range**: distance to your target, focus and mouseover.
- **PvP** (beta): your arena teammates' defensive and burst cooldowns next to their party frames.
- **Extras**: a text on entering and leaving combat; right click disabled in combat.

Every module is a load-on-demand addon of its own: a disabled module is never loaded and uses no memory, not even its saved settings. No libraries, no texture or font files.

[繁體中文](README.zhTW.md)

## Install

From CurseForge, or take the zip of the latest [release](../../releases) and unpack it into `World of Warcraft/_retail_/Interface/AddOns`. It unpacks into several folders (`CombatKit`, `CombatKit_Loadout`, ...): each module is an addon of its own, which is how the game can leave it unloaded.

## Getting around

`/ck` opens the settings; so do the addon compartment at the minimap, the game's Options > AddOns list, and a right click on the HUD. There is a tab per module (Loadout, Stats, Range, PvP, Extras) and **Settings** at the right. The tab of a module that is off is dimmed and offers to switch it on. **Settings** has three pages: Modules, General (language, theme, window scale) and HUD.

Switching on works at once. Switching off stops the module at once; the memory of what was already loaded comes back with the next reload, because the game cannot unload code. The small features under Extras share one addon, which is only loaded while at least one of them is on. The settings window itself is loaded the first time you open it.

## The HUD

One small box that modules fill, Loadout first, Stats below:

```
[icon] Havoc              Ready
Talents                  M+ AoE
Gear                        PvE
-------------------------------
Crit                      23.4%
Haste                     18.0%
```

Right click: settings. Drag to move (unless locked), `Ctrl` + mouse wheel to resize. With nothing to show it is hidden. **Settings > HUD** hides it altogether and sets its scale, background opacity (down to none), border, font and anchor: the corner the box keeps while lines come and go, top left by default, so it grows down and to the right. Fonts: the game's own, plus whatever LibSharedMedia offers when another addon brought it along.

## Loadout

Open `/ck`. There are two entries, **PvE** and **PvP**. Pick a spec from the large icons at the top, then its talent loadout and equipment set underneath; a corner mark shows which specs are set up. That is the whole setup: whatever spec you are in decides which pair is used, so a battleground as DPS and a battleground as healer are simply two specs, each set up once. *Switch now* under the fields takes you there at once: the spec picked on the page, its talents and gear, wherever you are.

| | |
|---|---|
| **Split into scenarios** (on the PvE and PvP pages) | PvE becomes open world, delves, dungeons / M+, raids. PvP becomes arena (with Solo Shuffle) and battlegrounds / rated (with Blitz). A scenario has *Use the PvE settings* ticked until you untick it; its own settings then start as a copy. |
| **Switch spec automatically** (open world, delves) | Tick it and pick the spec from the large icons: that spec is switched to the moment you enter, and the talents and gear below are the ones set for it. In a group it never takes you out of the role the group gave you, and says so in chat; a group without assigned roles (friends, an NPC companion) changes nothing. |
| **Open world with War Mode uses PvP** (PvP page) | With War Mode on, the open world uses your PvP settings. |
| **Smart gear check** (Options, on by default) | Tells whether the gear you wear fits the scenario: *Switch to PvP gear* on screen in arena or a battleground when both trinkets are not PvP ones, *Switch to PvE gear* in a dungeon or raid when they are. It stays until your first combat there; open world and delves are not judged. A PvP trinket is one whose tooltip names the Gladiator set. |

With *Switch talents and gear automatically* on (Loadout tab > Options; off by default), talents and gear are applied **once** when you enter a scenario (logging in counts) and once when you change spec. What you change by hand afterwards is left alone: on the HUD the line splits in two, what you have now and, under an arrow, what will be applied; when the scenario wants another spec the first line names it. A left click switches. It waits out combat, your own casts and, for a spec change, running; a request the game dropped is asked again, and it tells you when it gives up. A cast you interrupt yourself is not asked again: it says so once, and the HUD shows what is still missing. While a keystone is running or a PvP match has started nothing can be changed, so it waits. On a queue pop nothing is switched: the HUD shows what the upcoming scenario wants, click it if you want it now.

These setups are saved per character; everything else in the kit is account-wide. A loadout or set that was deleted and recreated under the same name is found again by name. The **Debug** page simulates another scenario and, under Advanced, a queue pop, War Mode, a group role or a running key, so everything can be tried from a city; *Dry run* only says what would be switched.

Run one loadout switcher at a time: next to another addon that changes talents or gear on its own, the two will undo each other.

## Stats

Crit, haste, mastery, versatility by default; leech, avoidance, movement speed, primary stat, item level, armor, dodge, parry, block and gear durability can be added. Order and decimals are yours, and the HUD can use the English stat names whatever language the rest is in.

Since patch 12.0.5 the game hides your own stat values from addons in combat ("secret values"): an addon may not compute with them, but may hand them to the game to be formatted. So the stats keep updating in combat. The exceptions need arithmetic: movement speed and the flat part of versatility show the last readable value until combat ends.

## Range

A colour-coded number near your target and focus, and one that follows the cursor for your mouseover. Hostile units and friendly ones out of combat are measured with a ladder of items of known range; friendly units in combat with your own short-range spells. Font, update rate, which units, "hide at 5 yards or closer", and drag-to-place are on its page.

## PvP (beta)

Arena only. One row of icons per teammate, next to his party frame (DandersFrames, the frames FrameSort sorted, else the game's compact party frames; without any, a row you drag into place while *Unlock* is ticked): his personal defensives, for a healer or support the externals he can give, then his crowd control, then his burst cooldown (*Crowd control* and *Burst cooldowns* in the settings hide them). When FrameSort moves the frames, the rows follow. An icon goes dark and counts down when the ability is used, and glows while its buff is up. A "?" marks a use that two teammates of the same class could have made.

How it knows: since 12.1 an addon may not read other players' buffs in arena, but it may ask the game to draw them. The module keeps hidden aura frames, one filter per ability, and only learns whether the game drew something: yes or no, nothing else. A yes starts the estimate. A crowd control leaves nothing on the caster, so its debuff is looked for on the enemy arena units instead and credited the same way. The cooldown is the ability's, changed by the talents the teammate was inspected with (spec, talents and PvP talents; the talents the module knows about are listed in `Modules/PvP/Spells.lua`, the rest leave the base cooldown; `/ckpvp cd <spellID> <seconds>` sets one by hand). An external is credited to the teammate who could have cast it: your own casts, who was crowd controlled at the time and "it cannot be on the caster" settle it; when two still could have, both icons share the estimate and show "?". A teammate who arrives mid-round (or a reload) shows "?" until his first use. One missing read is not a new use, and an external seen again within its duration is the same use. The glow while a buff is up is drawn by the game itself, so it does not wait for a scan. Every read is checked against known answers and an always-empty control; a scan that straddled a roster change is discarded; when the client refuses the frames for a unit that unit reads unknown, when it refuses them for you or the checks keep failing, the module says so in chat and on its page and shows nothing rather than guess. A new round (Solo Shuffle) resets every cooldown. Settings: icon size, spacing, font size, max per row, side, offset, remaining time, highlight, *Show sample rows* to place them outside arena. `/ckpvp status`, `log` and `entries` show what it is doing. `/ckpvp solo` (or *Solo mode* on the page) makes you stand in for a teammate and your target for an enemy, here and now: use a defensive, an external on yourself or a crowd control and watch the icons, no arena or group needed. Beta: the cooldowns and talent IDs in `Modules/PvP/Spells.lua` want confirming.

## Extras

Small things that do not deserve an addon of their own. One with settings has a page; those that are only a switch share the **Misc** page.

- **Combat alert**: a text in the middle of the screen when combat starts and ends. Both texts, the font size and the position are yours, and it can float up as it fades; *Test* plays it.
- **Disable right click in combat**: while you are in combat and a unit is under the cursor, right click only turns the camera. Corpses count as units, so right click on them is held back too; left click (with the game's *interact on left click*) and the interact key still reach them. Ore, herbs, chests and doors are not units and are never affected. Back to normal when combat ends.

## Look and weight

Flat panels drawn by the addon itself, no Blizzard frame skin. Two themes, *Tide* (blue) and *Dusk* (violet), switchable in **Settings > General**; each is one table in `Skin.lua`, and another one is a table and a name. English and 繁體中文, switchable there too; more translations are welcome, every `Locales.lua` is a plain table.

## Development

`tests/run_tests.py` (Python with `lupa`) compiles every file, checks that no module can be loaded by the core's `.toc`, checks locale coverage and the release metadata, and runs the behaviour tests against WoW API stubs in both languages. `deploy.bat` copies the core and every folder under `Modules/` into the AddOns folder; the packager does the same through `.pkgmeta`. A `v*` tag releases: see `.github/workflows/release.yml`.

## License

MIT
