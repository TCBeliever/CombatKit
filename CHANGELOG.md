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
