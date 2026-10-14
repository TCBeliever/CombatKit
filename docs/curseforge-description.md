CombatKit is a modular combat addon with a small resource footprint. It bundles:

- **Loadout**: spec, talents and gear switched automatically by scenario: open world, delves, dungeons / M+, raids, arena, battlegrounds.
- **Stats**: live stats on a compact HUD.
- **Range**: distance to your target, focus and mouseover.
- **Party CD** (beta): your arena teammates' defensives, burst cooldowns and crowd control as icons by their party frames.
- **Extras**: a text on entering and leaving combat; right click disabled in combat.

Every module is a load-on-demand addon of its own: a disabled module is never loaded and uses no memory. No libraries, no texture or font files. Supports World of Warcraft Retail (Midnight). [繁體中文說明](https://github.com/TCBeliever/CombatKit/blob/main/README.zhTW.md)

**Loadout**

Switch spec, talents and gear automatically when you enter open world, delves, dungeons / M+, raids, arena or battlegrounds. One PvE and one PvP setup per spec, split further into scenarios if you want. With automatic switching on (off by default), applied once on entering and once on a spec change; what you change by hand afterwards is left alone. Open world and delves can switch your spec as well, and War Mode can use the PvP setup. A *Switch now* button applies any setup on demand. A smart gear check says on screen when to switch to PvP or PvE gear.

**Stats**

Crit, haste, mastery, versatility, leech, avoidance, movement speed, primary stat, item level, armor, dodge, parry, block and durability as lines on a compact HUD. Choose which to show, their order and the decimals. The lines keep updating in combat. English stat names can be used whatever the client language.

**Range**

Distance to your target and focus as colour-coded numbers, and one at the cursor for your mouseover. Works in combat, for friendly and hostile units. Font, update rate, which units to show, hide at melee range, drag to place.

**Party CD** (beta, off by default)

Arena only. A row of icons by each teammate's party frame (DandersFrames, FrameSort or the game's own; a row to drag where there is none): their defensive cooldowns, the externals they put on each other, their burst cooldowns, the crowd control they land on the opponents, and their racial ability. While an ability's aura is up its icon wears the game's own animated border, coloured by what the ability is for; once used it counts down the cooldown the teammate's inspected talents give it, and an ability they did not take leaves the row. The PvP trinket leads every row. An external or a crowd control is credited to whoever could have cast it; a teammate who arrives mid round shows "?" until a first use. The abilities are picked per class in the settings, those with a cooldown of a minute or more ticked by default.

How it knows: other players' auras are secret to addons in an arena. The module asks the game to draw each watched aura into a hidden frame of its own and reads only whether it is there. The idea of detecting a secret aura through what the game draws of it came from AsIntendedCDs; the design here is new.

**Extras**

Combat alert: a text in the middle of the screen when combat starts and ends, with your own texts, size and position, floating up if you like. Disable right click in combat: with a unit under the cursor, right click only turns the camera, so you never switch target by accident.

**HUD**

One box shared by Loadout and Stats. Drag to move, Ctrl + mouse wheel to resize; scale, background opacity, border and font are in the settings. Hidden when there is nothing to show.

**How to use**

`/ck` opens the settings; so do the addon compartment at the minimap and the game's Options > AddOns list. The modules are listed down the left, Settings at the bottom; a dimmed entry is a module that is off, and its page has the switch. Two colour themes (blue, violet) and two languages (English, 繁體中文), switchable in the settings.

**Support**

Bug reports and ideas: the comments here or [GitHub issues](https://github.com/TCBeliever/CombatKit/issues). Include the Lua error text if there is one. Full documentation on [GitHub](https://github.com/TCBeliever/CombatKit#readme). Translations welcome.
