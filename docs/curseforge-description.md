**Combat helpers, one switch each.**

[繁體中文說明](https://github.com/TCBeliever/CombatKit/blob/main/README.zhTW.md)

## Why CombatKit

- **One kit instead of five addons.** Loadout switching, a stats HUD, range numbers, a combat alert, a right click guard: one settings window, one look, one HUD.
- **What is off is never loaded.** Every module is a load-on-demand addon of its own. Switch it off and the game does not read its code, its frames or even its saved settings. The settings window is loaded the first time you open it.
- **Light.** No libraries, no texture or font files. Flat panels drawn by the addon itself.
- **Set up in a minute.** Loadout needs two choices per spec. Everything else is a tick box.
- **English and 繁體中文**, switchable in game.

## What's inside

### Loadout (on by default)

Talents and gear that follow where you are.

- Two entries, **PvE** and **PvP**. For each spec pick a talent loadout and an equipment set. Whatever spec you are in decides which pair is used, so healing a battleground and doing damage in one are simply two specs, each set up once.
- **Split into scenarios** when you want more: open world, delves, dungeons / M+, raids, arena, battlegrounds / rated. A scenario uses its group's settings until you give it its own.
- **Switch spec automatically** for open world and delves. In a group it never takes you out of the role the group gave you.
- **Open world with War Mode uses PvP**, if you like.
- Applied **once** when you enter and once when you change spec. What you change by hand afterwards is left alone: the HUD line turns amber, and a click applies the setup again.
- Waits out combat, your casts and, for a spec change, running. Nothing is touched while a keystone or a PvP match is running. On a queue pop the HUD shows what the upcoming scenario wants; nothing switches until you click.

### Stats

Your stats as lines on the HUD, **live in combat**: crit, haste, mastery, versatility, leech, avoidance, movement speed (skyriding included), your primary stat, item level, armor, dodge, parry, block, gear durability. You choose which, their order and the decimals. The HUD can use the English names whatever language the game is in.

### Range

A colour-coded number near your target and focus, and one at the cursor for your mouseover. Works in combat, for friendly and hostile units. Font, update rate, which units, "hide at 5 yards or closer", drag to place.

### Extras

- **Combat alert**: a text in the middle of the screen when combat starts and ends. Your texts, your size, your position.
- **Disable right click in combat**: while you are in combat and a unit is under the cursor, right click only turns the camera, so you never switch target by accident. Left click and the interact key are untouched; ore, herbs and chests are never affected.

## Quick start

1. `/ck` opens the settings. So do the addon compartment at the minimap and the game's Options > AddOns list.
2. **Loadout** tab: pick a spec from the large icons, then its talent loadout and equipment set. Do the same under PvP.
3. Switch on what else you want: a dimmed tab is a module that is off, and its page has the switch.
4. Drag the HUD where you want it; `Ctrl` + mouse wheel resizes it. **Settings > HUD** has its background opacity, border and font.

## FAQ

- **I switched a module off and the memory is still used.** It has stopped, but the game cannot unload code: a reload frees it, and the Modules page offers one.
- **Movement speed and part of versatility stop updating in combat.** Since patch 12.0.5 the game hides your own stat values from addons in combat. CombatKit hands them to the game to be formatted, which keeps most stats live; values that need arithmetic show the last readable number until combat ends.
- **It did not switch my spec.** In a dungeon, raid or PvP group it will not take you out of the role the group gave you; chat says so.
- **It changes my talents back.** It does not: it applies once per entry. If another addon switches talents or gear on its own as well, run only one of them.
- **Fonts.** The game's own; with any addon that brings LibSharedMedia installed, every font registered there is offered too.

## Links

- [Full documentation](https://github.com/TCBeliever/CombatKit#readme)
- [Bug reports and ideas](https://github.com/TCBeliever/CombatKit/issues), or the comments here. Include the Lua error text if there is one.
- Translations welcome: English and 繁體中文 so far.
