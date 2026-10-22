# CombatKit

A modular combat addon for World of Warcraft (Retail) with a small resource footprint. It bundles:

- **Loadout** (on by default): spec, talents, PvP talents and gear switched automatically by scenario: open world, delves, dungeons / M+, raids, arena, battlegrounds.
- **Stats**: live stats on a compact HUD.
- **Range**: distance to your target, focus and mouseover.
- **Party CD** (beta): your arena teammates' defensives, burst cooldowns and crowd control as icons by their frames.
- **Extras**: a text on entering and leaving combat; right click disabled in combat.

Every module is a load-on-demand addon of its own: a disabled module is never loaded and uses no memory, not even its saved settings. No libraries, no texture or font files.

[繁體中文](README.zhTW.md)

## Install

From CurseForge, or take the zip of the latest [release](../../releases) and unpack it into `World of Warcraft/_retail_/Interface/AddOns`. It unpacks into several folders (`CombatKit`, `CombatKit_Loadout`, ...): each module is an addon of its own, which is how the game can leave it unloaded.

## Getting around

`/ck` opens the settings; so do the addon compartment at the minimap, the game's Options > AddOns list, and a right click on the HUD. The modules (Loadout, Stats, Range, Party CD, Extras) are listed down the left, **Settings** at the bottom; a module with several pages has them as tabs across the top of its page. The entry of a module that is off is dimmed and offers to switch it on. **Settings** has three pages: Modules, General (language, theme, window scale) and HUD.

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

Open `/ck`. There are two entries, **PvE** and **PvP**. Pick a spec from the large icons at the top, then its talent loadout and equipment set underneath; a corner mark shows which specs are set up. On the PvP pages a row between the two takes three **PvP talents**, drawn as in the game's talent window: pick each slot, or *Use current* to fill all three with the ones you have on. The game keeps PvP talents per spec, not per talent loadout, so a loadout switch alone never changes them; this row does. They are picked while you are in that spec (the game lists no other spec's, so another spec's are greyed out), and an empty slot is left as it is. A page opens on the spec it switches to, else on the one you are in. That is the whole setup: whatever spec you are in decides which pair is used, so a battleground as DPS and a battleground as healer are simply two specs, each set up once. *Apply* under the fields takes you there at once: the spec picked on the page, its talents and gear, wherever you are.

| | |
|---|---|
| **Use different settings per scenario** (on the PvE and PvP pages) | PvE becomes open world, delves, dungeons / M+, raids. PvP becomes arena (with Solo Shuffle) and battlegrounds / rated (with Blitz). A scenario has *Use the PvE settings* ticked until you untick it; its own settings then start as a copy. |
| **Switch spec automatically** (open world, delves) | Tick it and pick the spec from the large icons: that spec is switched to the moment you enter, and the talents and gear below are the ones set for it. In a group it never takes you out of the role the group gave you, and says so in chat; a group without assigned roles (friends, an NPC companion) changes nothing. |
| **Multiple setups** (PvP pages) | Up to three setups for the spec there, for example one per kind of team you meet. Tick it and pick 1, 2 or 3 next to it: the fields below show that setup, and it is the one used, until you pick another. Off, or ticked and never changed, the first is used. The HUD tooltip names the setup in use. |
| **Open world with War Mode uses PvP** (PvP page) | With War Mode on, the open world uses your PvP settings. |
| **Smart gear check** (Options, on by default) | Tells whether the gear you wear fits the scenario: *Switch to PvP gear* on screen in arena or a battleground when both trinkets are not PvP ones, *Switch to PvE gear* in a dungeon or raid when they are. It stays until your first combat there; open world and delves are not judged. A PvP trinket is one whose tooltip names the Gladiator set. |

With *Switch talents and gear automatically* on (Loadout tab > Options; off by default), talents and gear (and PvP talents, after the talent loadout) are applied **once** when you enter a scenario (logging in counts) and once when you change spec. What you change by hand afterwards is left alone: on the HUD the line splits in two, what you have now and, under an arrow, what will be applied; when the scenario wants another spec the first line names it. A left click switches. PvP talents have a line of their own where some are set: how many of them are on, *2/3*; which slot a talent sits in does not matter. It waits out combat, your own casts and, for a spec change, running; a request the game dropped is asked again, and it tells you when it gives up. A cast you interrupt yourself is not asked again: it says so once, and the HUD shows what is still missing. While a keystone is running or a PvP match has started nothing can be changed, so it waits. On a queue pop nothing is switched: the HUD shows what the upcoming scenario wants, click it if you want it now.

These setups are saved per character; everything else in the kit is account-wide. A loadout or set that was deleted and recreated under the same name is found again by name. The **Debug** page simulates another scenario and, under Advanced, a queue pop, War Mode, a group role or a running key, so everything can be tried from a city; *Dry run* only says what would be switched.

Run one loadout switcher at a time: next to another addon that changes talents or gear on its own, the two will undo each other.

## Stats

Crit, haste, mastery, versatility by default; leech, avoidance, movement speed, primary stat, item level, armor, dodge, parry, block and gear durability can be added. Order and decimals are yours, and the HUD can use the English stat names whatever language the rest is in.

Since patch 12.0.5 the game hides your own stat values from addons in combat ("secret values"): an addon may not compute with them, but may hand them to the game to be formatted. So the stats keep updating in combat. The exceptions need arithmetic: movement speed and the flat part of versatility show the last readable value until combat ends.

## Range

A colour-coded number near your target and focus, and one that follows the cursor for your mouseover. Hostile units and friendly ones out of combat are measured with a ladder of items of known range; friendly units in combat with your own short-range spells. Font, update rate, which units, "hide at 5 yards or closer", and drag-to-place are on its page.

## Party CD

In an arena, a row of icons per teammate (and one for yourself): their defensive cooldowns, the externals they put on each other, their burst cooldowns, the crowd control they land on the opponents, and their racial ability (Stoneform, War Stomp and the like, read from their race, at the end of the row). An icon is bright when the ability is ready, wears an animated border while its aura is up, one of the game's own (marching ants by default; *Highlight* on the display page offers thin ants or a band that runs round the edge), coloured by what the ability is for (green for a defensive, yellow for an immunity or a big external, red for a burst, violet for a crowd control on an opponent, blue for the rest), darkens with a cooldown swipe once used, and shows "?" when the module cannot know (a teammate who arrived mid round, a reload). Externals and crowd control are credited to the teammate who could have cast them, never to a teammate when you cast it yourself (a trap or a totem that goes off later included), nor to one who was stunned, feared or disoriented at the time; when two could have, both show the estimate with a small "?". The PvP trinket leads each row, from the game's own arena cooldown data. Each teammate is inspected on arrival and at every round start: what their selected talents, PvP talents and specialization passives do to a watched ability's cooldown or charges is looked up in a table generated from the game's data files, and an ability they could have taken but did not, or that their specialization does not have, leaves the row; until then a small dot marks the cooldown as the class's base. A new round resets everything. Settings > Party CD > Spells lists every class's abilities by what they are for (defensive, offensive cooldowns, crowd control, other), in the order they sit in a row, and under *Racial* the races'; a category's box switches all of it, each ability has its own. Abilities with a cooldown of a minute or more are ticked by default, except a few left for you to tick (the racial bursts, Mass Polymorph, Invoke Xuen, Tree of Life, Summon Doomguard).

How it knows: other players' auras are secret to addons in an arena. The game is asked to draw each watched buff (or, on an opponent, debuff) into an aura container slot of the module's own, and a Cooldown frame of the module's own, fed that slot's duration, shows and hides with the buff; that is the one bit the module reads, one frame behind the game, and nothing else. The design is new and was measured in game before it was written; the idea of detecting a secret aura through what the game draws of it came from AsIntendedCDs.

## Extras

Small things that do not deserve an addon of their own. One with settings has a page; those that are only a switch share the **Misc** page.

- **Combat alert**: a text in the middle of the screen when combat starts and ends. Both texts, the font size and the position are yours, and it can float up as it fades; *Test* plays it.
- **Disable right click in combat**: while you are in combat and a unit is under the cursor, right click only turns the camera. Corpses count as units, so right click on them is held back too; left click (with the game's *interact on left click*) and the interact key still reach them. Ore, herbs, chests and doors are not units and are never affected. Back to normal when combat ends.

## Look and weight

Flat panels drawn by the addon itself, no Blizzard frame skin. Two themes, *Tide* (blue) and *Dusk* (violet), switchable in **Settings > General**; each is one table in `Skin.lua`, and another one is a table and a name. English and 繁體中文, switchable there too; more translations are welcome, every `Locales.lua` is a plain table.

## Development

`tests/run_tests.py` (Python with `lupa`) compiles every file, checks that no module can be loaded by the core's `.toc`, checks locale coverage and the release metadata, and runs the behaviour tests against WoW API stubs in both languages. `deploy.bat` copies the core and every folder under `Modules/` into the AddOns folder; the packager does the same through `.pkgmeta`. A `v*` tag releases: see `.github/workflows/release.yml`. `tools/talentdata.py` regenerates `Modules/PartyCD/TalentData.lua` (base cooldowns, charges and the talents that change them) from the game's data files through wago.tools; run it after a patch and look over what it prints; the downloads are kept per build in `../wago-cache`.

## License

All rights reserved, see [LICENSE](LICENSE). Fork and modify on GitHub as you like; ask about anything else.
