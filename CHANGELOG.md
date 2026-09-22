# Changelog

Newest at the bottom: the release workflow publishes the last section with the file.

## 0.3.0 (2026-09-22)

First public release.

- **Loadout**: one PvE and one PvP setup per spec (talent loadout + equipment set), optionally split into open world, delves, dungeons / M+, raids, arena and battlegrounds. Applied once when you enter and once when you change spec; what you change by hand afterwards is left alone. Open world and delves can switch your spec as well.
- **Stats**: your stats as lines on the HUD, live in combat. Which ones, their order and decimals are yours; the HUD can use the English names in any language.
- **Range**: distance to your target, focus and mouseover as colour-coded numbers.
- **Extras**: a text when you enter and leave combat; right click disabled in combat, so turning the camera never switches your target.
- **The kit**: every module is a load-on-demand addon, so what is off is never loaded. One HUD that the modules share, with its own scale, background opacity, border and font. Settings in tabs, reachable from `/ck`, the addon compartment and the game's AddOns options. English and 繁體中文, switchable in game. No libraries, no texture or font files.
