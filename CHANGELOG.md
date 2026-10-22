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

## 1.1.1 (2026-10-14)

- **Party CD** (beta, off by default): your arena teammates' defensive cooldowns, the externals they put on each other, their burst cooldowns and the crowd control they land on the opponents (watched on arena1-3), as a row of icons per teammate, with a row for yourself. A cooldown starts the frame the buff the ability leaves is drawn by the game, and counts down the ability's base cooldown until the teammate's talents are known: each teammate is inspected on arrival and at every round start, and what their selected talents, PvP talents and specialization passives do to a watched ability's cooldown or charges is looked up in a table generated from the game's own data files (`tools/talentdata.py`, via wago.tools), which also gives every watched ability its base cooldown and charges; an ability their tree offers but they did not take, or that their specialization does not have, leaves the row. Inspect waits while you have the inspect window open. An external or a crowd control is credited to the teammate who could have cast it: your own casts (a trap or a totem that goes off later included), who is dead, who is stunned, feared or disoriented (the game's loss-of-control data) and what cannot be cast on oneself settle it; two who could have both show the estimate with a small "?". A teammate who arrives mid round, or a reload, shows "?" until a first use is seen. The PvP trinket leads every row, from the game's own cooldown data, with the icon of the medallion or the racial the teammate carries (it can be switched off). Settings > Party CD > Spells: a class picked at the top, its abilities by what they are for (defensive, offensive cooldowns, crowd control, other), a box per category and per ability, in the order they sit in a row, the categories down the left column and on into the right, other last; abilities with a cooldown of a minute or more are ticked by default, the shorter ones wait to be ticked. Abilities with charges show the count; a second use during the first buff is counted when the buff's length gives it away. Every new round resets everything. Your own row doubles as a self-test: when your own buff does not show after your own cast, the rows dim and say so instead of showing everyone as ready. Rows hang on the party frames, or wherever you drag them (unlock in Settings > Party CD). *Show sample rows* shows the rows out in the world as they would be in an arena: a teammate without a frame gets a stand-in box where their frame would be, sized and placed from DandersFrames' own party settings next to your frame (one on each side when its group grows from the centre), or the size of your frame below it; a round in progress switches the samples off. Beside a frame a row runs away from it and its lines go down, up or sit centred; above or below one it starts at the left end, the right end or the middle. The detection is a new design, written from the game's own aura container API and measured in game; the idea of detecting a secret aura through what the game draws of it came from AsIntendedCDs.
- Party CD: racial abilities. A teammate's race is read with the roster (no inspect needed) and their racial ability ends their row, after the class's: Stoneform, Fireblood, Shadowmeld, War Stomp, Quaking Palm, Haymaker, Bull Rush, and Blood Fury, Berserking and Ancestral Call (these three unticked by default). They are under *Racial* in the class picker of Settings > Party CD > Spells; the sample rows show your own.
- Party CD: while an ability's aura is up, its icon wears one of the game's own animated borders, tinted by what the ability is for (green defensive, red offensive, violet crowd control, blue other, yellow an immunity or a big external). *Highlight* in Settings > Party CD: marching ants (the default), thin ants, or a band that runs round the edge. If the game lacks the texture, the breathing border from before stands in.
- Party CD: cooldowns and talents from the game's data for 12.1.5; Ice Cold, now on Ice Block's button, counts as Ice Block.
- Party CD: more abilities, picked from the game's own data: Vanish, Smoke Bomb (counted only on the rogue who drops it: an enemy rogue's cloud gives your team the same aura), Death Pact, Breath of Sindragosa, Rain from Above, Dream Flight, Soul Rip, Shield Charge, Interpose, Vampiric Embrace, Execution Sentence, Convoke the Spirits; and, unticked by default, Mass Polymorph, Master's Call, Invoke Xuen, Tree of Life and Summon Doomguard. Devourer's The Hunt and Spectral Sight, Marksmanship's Intimidation and the other Intimidating Shout count as the ability they are a version of; a teammate who did not take that version's talent loses it from the row, and a restoration druid with Ancient of Lore loses Tree of Life.

## 1.1.2 (2026-10-14)

- Marked for 12.1.5 as well (Interface 120105), so the game no longer lists the addon as out of date.

## 1.2.0 (2026-10-22)

- Loadout: PvP talents. On the PvP pages (PvP, and arena and battlegrounds when split) a row between the talent loadout and the equipment set takes three PvP talents for the spec, as octagonal slots drawn like the game's talent window: pick each slot, or *Use current* fills all three with the ones you have on. The game keeps PvP talents per spec, not per talent loadout, so until now a loadout switch left them as they were. They are applied with the rest, after the talent loadout; a talent that is on already stays in its slot, and an empty slot is left alone. The HUD has a *PvP talents* line where some are set, counting how many are on (*2/3*). They are picked while you are in that spec: the game lists no other spec's, so another spec's slots are greyed out.
- Loadout: the tabs read *PvE* and *PvP* (were *PvE scenarios* and *PvP scenarios*); the talent loadout and equipment set fields are a third as long; the *Switch now* button is *Apply* (「套用」). Opening the settings, or another page, starts on the spec that page switches to, else on the one you are in, instead of the spec picked last.
- Loadout: *Multiple setups* on the PvP pages: up to three setups (loadout, PvP talents, gear set) for a spec, say one per kind of team you meet. Pick 1, 2 or 3 next to the box: the fields show that setup and it is the one used, the first unless you pick another. The HUD tooltip names the setup in use.
- Loadout: shorter labels: *Loadout*, *PvP*, *Gear set*; *Split into scenarios* reads *Use different settings per scenario*.
