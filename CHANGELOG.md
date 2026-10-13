# Changelog

Newest at the bottom: the release workflow publishes the last section with the file.

## 0.3.0 (2026-09-22)

First public release.

- **Loadout**: one PvE and one PvP setup per spec (talent loadout + equipment set), optionally split into open world, delves, dungeons / M+, raids, arena and battlegrounds. Applied once when you enter and once when you change spec; what you change by hand afterwards is left alone. Open world and delves can switch your spec as well.
- **Stats**: your stats as lines on the HUD, live in combat. Which ones, their order and decimals are yours; the HUD can use the English names in any language.
- **Range**: distance to your target, focus and mouseover as colour-coded numbers.
- **Extras**: a text when you enter and leave combat; right click disabled in combat, so turning the camera never switches your target.
- **The kit**: every module is a load-on-demand addon; a disabled module is never loaded. One HUD that the modules share, with its own scale, background opacity, border and font. Settings in tabs, reachable from `/ck`, the addon compartment and the game's AddOns options. English and 繁體中文, switchable in game. No libraries, no texture or font files.

## 0.3.1 (2026-09-26)

- Loadout: a *Switch now* button under the talent and gear fields switches to the spec picked on the page and applies what is shown, wherever you are.
- HUD: when talents or gear differ from the setup, the line splits in two: what you have now, and under an arrow, what will be applied. When the scenario wants another spec, the first line names it, and a click switches to it. "Battlegrounds" is short on the HUD.
- HUD: an anchor corner in Settings > HUD. The box keeps that corner while lines come and go; top left by default, so it grows down and to the right.
- Loadout: *Switch talents and gear automatically* is off on a fresh install.
- Loadout: a spec or talent change you interrupt is not asked again. It says so once and the HUD shows what is still missing; nothing is retried until the next entry, spec change or click.
- `/ck` only opens the settings now; `/ck apply`, `/ck debug` and `/ck reset` are gone. Apply from the HUD or the *Switch now* button, the debug page is in the Loadout tab, the HUD position is reset in Settings > HUD.

## 0.3.2 (2026-09-27)

- Settings: the list of pages on the left is as wide as its names need, and a tab with a single page has the whole width.
- Stats: the list of stats on the settings page sits at the right, clear of the *English on the HUD* label.
- Extras: the combat alert can float up as it fades (*Effect* on its page; off unless ticked).

## 0.3.3 (2026-09-28)

- Loadout: a smart gear check (Options, on by default). *Switch to PvP gear* on screen in arena or a battleground when both trinkets are not PvP ones, *Switch to PvE gear* in a dungeon or raid when they are, until the first combat there. Open world and delves are not judged; nothing while a key or a match runs.

## 0.3.4 (2026-10-10)

- Settings: a *Theme* in Settings > General. *Tide* is the blue it always had; *Dusk*, in violet, is new. The window and the HUD take the colours at once.

## 1.0.0 (2026-10-12)

- **PvP** (beta, off by default): your arena teammates' defensive cooldowns, externals, crowd control and burst cooldowns as icons next to their party frames (DandersFrames, FrameSort's sorted frames or the game's own; a loose row to drag when none is found). A cooldown starts when the buff the ability leaves is seen (a crowd control: its debuff on an enemy), through the game's own aura frames, and counts down the cooldown the teammate's inspected talents give it (a subset of talents is known; `/ckpvp cd` sets one by hand). An external is credited to the teammate who could have cast it: the player's own casts, who was crowd controlled and "it cannot be on the caster" settle it; still two: both icons share the estimate and show "?". A teammate who arrives mid-round shows "?" until a first use. Arena only; a new round resets everything. The glow while a buff is up is drawn by the game. When the client refuses the reads the module says so and shows nothing. Settings: icon size, spacing, font size, max per row, side, offset, remaining time, highlight, crowd control and burst cooldowns on or off, sample rows; `/ckpvp status | log | entries`, and `/ckpvp solo` to try the whole thing on yourself, anywhere, with no group.
- Settings: the modules are listed down the left of the window, Settings at the bottom; a module with several pages has them as tabs across the top of its page.

## 1.0.1 (2026-10-12)

- PvP: the sample rows (*Test icons*) show a teammate who is really there with his own class, spec and talents, and name him; a missing teammate's sample sits by your own party frame when you are in a group, instead of at its loose position, and the label says so (or says *not attached*).
- License: all rights reserved from this version on (fork and modify on GitHub as you like; ask about anything else). Earlier versions stay under the MIT license they were released with.

## 1.0.2 (2026-10-13)

- PvP: the module is removed. The other modules are unchanged.

## 1.1.0 (2026-10-13)

- **Party CD** (beta, off by default): your arena teammates' defensive cooldowns, the externals they put on each other, their burst cooldowns and the crowd control they land on the opponents (watched on arena1-3), as a row of icons per teammate, with a row for yourself. A cooldown starts the frame the buff the ability leaves is drawn by the game, and counts down the ability's base cooldown until the teammate's talents are known: each teammate is inspected on arrival and at every round start, and what their selected talents, PvP talents and specialization passives do to a watched ability's cooldown or charges is looked up in a table generated from the game's own data files (`tools/talentdata.py`, via wago.tools), which also gives every watched ability its base cooldown and charges; an ability their tree offers but they did not take, or that their specialization does not have, leaves the row. Inspect waits while you have the inspect window open. An external or a crowd control is credited to the teammate who could have cast it: your own casts (a trap or a totem that goes off later included), who is dead and what cannot be cast on oneself settle it; two who could have both show the estimate with a small "?". A teammate who arrives mid round, or a reload, shows "?" until a first use is seen. The PvP trinket leads every row, from the game's own cooldown data, with the icon of the medallion or the racial the teammate carries (it can be switched off). Settings > Party CD > Spells: a class picked at the top, its abilities by category (defensive, offensive cooldowns, crowd control), a box per category and per ability. Abilities with charges show the count; a second use during the first buff is counted when the buff's length gives it away. Every new round resets everything. Your own row doubles as a self-test: when your own buff does not show after your own cast, the rows dim and say so instead of showing everyone as ready. Rows hang on the party frames, or wherever you drag them (unlock in Settings > Party CD). Beside a frame a row runs away from it and its lines go down, up or sit centred; above or below one it starts at the left end, the right end or the middle. The detection is a new design, written from the game's own aura container API and measured in game; the idea of detecting a secret aura through what the game draws of it came from AsIntendedCDs.
