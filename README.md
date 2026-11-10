# CombatKit

A modular combat addon for World of Warcraft (Retail) with a small resource footprint. It bundles:

- **Loadout** (on by default): spec, talents, PvP talents and gear switched automatically by scenario: open world, delves, dungeons / M+, raids, arena, battlegrounds.
- **Stats**: live stats on a compact HUD.
- **Range**: distance to your target, focus and mouseover.
- **Party CD** (beta): your arena teammates' defensives, burst cooldowns and crowd control as icons by their frames.
- **Reminder**: reminders of what is missing: flask, food, augment rune, weapon oil, healthstone, your class's buffs, and a feast or cauldron the group puts down.
- **Extras**: a text on entering and leaving combat; right click disabled in combat.

Every module is a load-on-demand addon of its own: a disabled module is never loaded and uses no memory, not even its saved settings. No texture files. It brings one font, Rethink Sans, for the numbers on the HUD, and LibSharedMedia, so other addons can use that font too.

[繁體中文](README.zhTW.md)

## Install

From CurseForge, or take the zip of the latest [release](../../releases) and unpack it into `World of Warcraft/_retail_/Interface/AddOns`. It unpacks into several folders (`CombatKit`, `CombatKit_Loadout`, ...): each module is an addon of its own, which is how the game can leave it unloaded.

## Getting around

`/ck` opens the settings; so do the addon compartment at the minimap, the game's Options > AddOns list, and a right click on the HUD. The modules (Loadout, Stats, Range, Party CD, Reminder, Extras) are listed down the left, **Settings** at the bottom; a module with several pages has them as tabs across the top of its page. The entry of a module that is off is dimmed and offers to switch it on. **Settings** has three pages: Modules, General (language, theme, window scale) and HUD.

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

Right click: settings. Drag to move (unless locked), `Ctrl` + mouse wheel to resize. With nothing to show it is hidden. **Settings > HUD** hides it altogether and sets its scale, background opacity (down to none), border, font and anchor: the corner the box keeps while lines come and go, top left by default, so it grows down and to the right. Fonts: the game's own, plus whatever other addons registered with LibSharedMedia.

## Loadout

Open `/ck`. There are two entries, **PvE** and **PvP**. Pick a spec from the large icons at the top, then its talent loadout and equipment set underneath; a corner mark shows which specs are set up. On the PvP pages a row between the two takes three **PvP talents**, drawn as in the game's talent window: pick each slot, or *Use current* to fill all three with the ones you have on. The game keeps PvP talents per spec, not per talent loadout, so a loadout switch alone never changes them; this row does. They are picked while you are in that spec (the game lists no other spec's, so another spec's are greyed out), and an empty slot is left as it is. A page opens on the spec it switches to, else on the one you are in. That is the whole setup: whatever spec you are in decides which pair is used, so a battleground as DPS and a battleground as healer are simply two specs, each set up once. *Apply* under the fields takes you there at once: the spec picked on the page, its talents and gear, wherever you are.

| | |
|---|---|
| **Use different settings per scenario** (on the PvE and PvP pages) | PvE becomes open world, delves, dungeons / M+, raids. PvP becomes arena (with Solo Shuffle) and battlegrounds / rated (with Blitz). A scenario has *Use the PvE settings* ticked until you untick it; its own settings then start as a copy. |
| **Switch spec automatically** (open world, delves) | Tick it and pick the spec from the large icons: that spec is switched to the moment you enter, and the talents and gear below are the ones set for it. In a group it never takes you out of the role the group gave you, and says so in chat; a group without assigned roles (friends, an NPC companion) changes nothing. |
| **Multiple setups** (PvP pages) | Up to three setups for the spec there, for example one per kind of team you meet. Tick it and pick 1, 2 or 3 next to it: the fields below show that setup, and it is the one used, until you pick another. Off, or ticked and never changed, the first is used. The HUD tooltip names the setup in use. |
| **Open world with War Mode uses PvP** (PvP page) | With War Mode on, the open world uses your PvP settings. |
| **Smart gear check** (Options, on by default) | Tells whether the gear you wear fits the scenario: *Switch to PvP gear* on screen in arena or a battleground when both trinkets are not PvP ones, *Switch to PvE gear* in a dungeon or raid when they are. It stays until your first combat there; open world and delves are not judged. A PvP trinket is one whose tooltip names the Gladiator set. |

With *Switch talents and gear automatically* on (Loadout tab > Options; off by default), talents and gear (and PvP talents, after the talent loadout) are applied **once** when you enter a scenario (logging in counts) and once when you change spec. What you change by hand afterwards is left alone: on the HUD the line splits in two, what you have now and, under an arrow, what will be applied; when the scenario wants another spec the first line names it. A left click switches. PvP talents have a line of their own where some are set: how many of them are on, *2/3*; which slot a talent sits in does not matter. It waits out combat, your own casts and, for a spec change, running; a request the game dropped is asked again, and it tells you when it gives up. A cast you interrupt yourself is not asked again: it says so once, and the HUD shows what is still missing. A loadout the game refuses for now (a talent that changes an ability's charges cannot be taken out while that ability recharges) is waited for: it gives the game's reason once, the HUD reads *Waiting for cooldown* with the ability it waits for under it, counting down (*Soul Immolation (0:15)*), and the loadout is asked for again once every charge of that ability is back, for up to three minutes (a click meanwhile changes nothing; entering another scenario or changing spec by hand drops the wait). While a keystone is running or a PvP match has started nothing can be changed, so it waits. On a queue pop nothing is switched: the HUD shows what the upcoming scenario wants, click it if you want it now.

These setups are saved per character; everything else in the kit is account-wide. A loadout or set that was deleted and recreated under the same name is found again by name. The **Debug** page simulates another scenario and, under Advanced, a queue pop, War Mode, a group role or a running key, so everything can be tried from a city; *Dry run* only says what would be switched.

Run one loadout switcher at a time: next to another addon that changes talents or gear on its own, the two will undo each other.

## Stats

Crit, haste, mastery, versatility by default; leech, avoidance, movement speed, primary stat, item level, armor, dodge, parry, block and gear durability can be added. Order and decimals are yours, and the HUD can use the English stat names whatever language the rest is in.

*Coloured stats* (off by default) gives each stat's name a colour of its own, and a value changes colour when its state says something: green-yellow to red as a secondary stat runs into diminishing returns (from 30% of bonus from rating), red when a debuff lowers your primary stat or armor, red when you are slowed and green when you move faster than a run. The numbers are in Rethink Sans, whose digits are all one width, so a number that changes does not shake its line; Arial Narrow, the HUD's own font or any LibSharedMedia font can be picked instead.

Since patch 12.0.5 the game hides your own stat values from addons in combat ("secret values"): an addon may not compute with them, but may hand them to the game to be formatted. So the stats keep updating in combat. The exceptions need arithmetic: movement speed and the flat part of versatility show the last readable value until combat ends. A value's colour is the one it had when it could last be read.

## Range

A colour-coded number near your target and focus, and one that follows the cursor for your mouseover. Hostile units and friendly ones out of combat are measured with a ladder of items of known range; friendly units in combat with your own short-range spells. Font, update rate, which units, "hide at 5 yards or closer", and drag-to-place are on its page.

## Party CD

In an arena, a row of icons per teammate (and one for yourself): their defensive cooldowns, the externals they put on each other, their burst cooldowns, the crowd control they land on the opponents, and their racial ability (Stoneform, War Stomp and the like, read from their race, at the end of the row). An icon is bright when the ability is ready, wears an animated border while its aura is up, one of the game's own (marching ants by default; *Highlight* on the display page offers thin ants or a band that runs round the edge), coloured by what the ability is for (green for a defensive, yellow for an immunity or a big external, red for a burst, violet for a crowd control on an opponent, blue for the rest), darkens with a cooldown swipe once used, and shows "?" when the module cannot know (a teammate who arrived mid round, a reload). Externals and crowd control are credited to the teammate who could have cast them, never to a teammate when you cast it yourself (a trap or a totem that goes off later included), nor to one who was stunned, feared or disoriented at the time; when two could have, both show the estimate with a small "?". The PvP trinket leads each row, from the game's own arena cooldown data. Each teammate is inspected on arrival and at every round start: what their selected talents, PvP talents and specialization passives do to a watched ability's cooldown or charges is looked up in a table generated from the game's data files, and an ability they could have taken but did not, or that their specialization does not have, leaves the row; until then a small dot marks the cooldown as the class's base. A new round resets everything. Settings > Party CD > Spells lists every class's abilities by what they are for (defensive, offensive cooldowns, crowd control, other), in the order they sit in a row, and under *Racial* the races'; a category's box switches all of it, each ability has its own. Abilities with a cooldown of a minute or more are ticked by default, except a few left for you to tick (the racial bursts, Mass Polymorph, Invoke Xuen, Tree of Life, Summon Doomguard).

How it knows: other players' auras are secret to addons in an arena. The game is asked to draw each watched buff (or, on an opponent, debuff) into an aura container slot of the module's own, and a Cooldown frame of the module's own, fed that slot's duration, shows and hides with the buff; that is the one bit the module reads, one frame behind the game, and nothing else. The design is new and was measured in game before it was written; the idea of detecting a secret aura through what the game draws of it came from AsIntendedCDs.

## Reminder

A row of icons, out of combat, in the scenarios you pick: one for each thing missing, its name above it, the time left inside when it is running out (under five minutes by default), and for a group buff how many near you lack it.

- **Your consumables** (PvE only; a healthstone in PvP too): a flask, food (any Well Fed; not while you are eating), an augment rune (only when you have one), oil, a stone or ammunition on each weapon, bows and guns included (not on a slot your class imbues itself; the icon and the click take what goes on that weapon), a healthstone (taken from a warlock in the group; a warlock's own is a class reminder). At the entrance, until the first pull; in a raid again whenever combat ends (a boss down, a buff run out); a ready check shows them anywhere. A Mythic+ run needs no second reminder: once the key runs nothing shows, so at a Mythic entrance a consumable that would not last a key run (35 minutes) is shown as running out.
- **Your class**: your group buff (Arcane Intellect, Battle Shout, Power Word: Fortitude, Mark of the Wild, Blessing of the Bronze, Skyfury), what you put on yourself (stance or form, shields, poisons, an aura, a weapon imbue or a rune, Grimoire of Sacrifice), a warlock's healthstone to make when there is none in the bags, your pet, and what you put on someone else in a group (Earth Shield, the beacons, Source of Magic, Symbiotic Relationship, Soulstone). Defensive Stance on Arms or Fury shows in red: time to leave it.
- **What the group puts down**: a feast or a flask cauldron. Its icon shows the moment someone puts one down and counts down while it stays (three and five minutes), until you have eaten or taken a flask; that is what everyone uses then, so your own food or flask reminder steps aside meanwhile. Seen in chat and from the cast of whoever puts it down.
- **Custom**: any spell ID, on you or on the group, missing or present, up to ten per class.

The settings have four pages: *Consumables* (yours, and the group's), *Your class* (each of your class's reminders on its own, under every spec or under the specs that have it, each with its icon; greyed when your spec or talents do not use it; and your own spell IDs), *Where* (a line per scenario, a column each for your consumables, your class reminders and the group's feasts and cauldrons; by default consumables in dungeons, raids and arenas, class reminders everywhere, the group's in dungeons, raids and battlegrounds) and *Display*. Flasks, food, runes and oils are for PvE: an arena or a battleground reminds of a healthstone only, and of no cauldron.

A click on an icon casts its spell or uses the flask, food, rune or oil from your bags (on the right weapon; a paladin's rite too); the right mouse button goes through, for the camera. It takes, per spec and PvE or PvP, the kind you used last (the flask by its buff, the oil by its enchant, the food by what you ate; a cauldron's fleeting flask first; a demon, a hunter's pet, a paladin's aura or rite, a shaman's shield by what you cast), and for a rogue a poison not on yet (the icon named for it), those of last time first, else what the guides recommend for the spec in PvE or PvP. Hold Alt over such an icon and the others show under it: click one to cast it, and the icon casts it from then on. Hovering an icon shows the spell or item, why it is up (the time left, how many in the group lack it) and what a click does. A weapon without a rune is told which one: yours of last time, else the guides'. The class page lists a hunter's or warlock's pet first (a warlock's Grimoire of Sacrifice with it), then what every spec has, then each spec with that spec's recommendation; a page of one group has no headings. Shaman imbues count on either hand, or as their buff. A rune of another setup of yours (your other spec, or this spec's PvP or PvE), still on, and in PvE a demon that is not a Felguard for Demonology with Summon Felguard, show in red. Where 12.1 hides auras from addons, each is asked for on its own: what the game hands back is there, what it will not say about is left alone rather than reported missing. The same can show as rows on the HUD, and a sound can mark a new one. Nothing shows in combat, while dead, in a running key or encounter. In a battleground they show before the start and once after each death, until the next fight, not whenever a fight ends. In a resting area (a capital city or an inn) only a death knight's runes show, since they are put on there. `/ckreminder` prints what the module sees, check by check.

A hunter's or warlock's pet low on health has a warning of its own, above the middle of the screen, in combat too: below 40% by default, the healing spell's icon with the text to its right, or the text alone, at a font size of your choice (ticked in the class page's pet section, its settings under it; dragged while unlocked). The pet's health is never read: the game hands it through a colour curve whose opacity is the icon's, so it works where 12.1 keeps the pet's health secret (arenas, raid encounters, keys), and for the same reason it has no sound. Not with Grimoire of Sacrifice.

## Extras

Small things that do not deserve an addon of their own. One with settings has a page; those that are only a switch share the **Misc** page.

- **Combat alert**: a text in the middle of the screen when combat starts and ends. Both texts, the font size and the position are yours, and it can float up as it fades; *Test* plays it.
- **Disable right click in combat**: while you are in combat and a unit is under the cursor, right click only turns the camera. Corpses count as units, so right click on them is held back too; left click (with the game's *interact on left click*) and the interact key still reach them. Ore, herbs, chests and doors are not units and are never affected. Back to normal when combat ends.

## Look and weight

Flat panels drawn by the addon itself, no Blizzard frame skin. Two themes, *Tide* (blue) and *Obsidian* (black-gold), switchable in **Settings > General**; each is one table in `Skin.lua`, and another one is a table and a name. English and 繁體中文, switchable there too; more translations are welcome, every `Locales.lua` is a plain table.

## Development

`tests/run_tests.py` (Python with `lupa`) compiles every file, checks that no module can be loaded by the core's `.toc`, checks locale coverage and the release metadata, and runs the behaviour tests against WoW API stubs in both languages. `deploy.bat` copies the core and every folder under `Modules/` into the AddOns folder; the packager does the same through `.pkgmeta`. A `v*` tag releases: see `.github/workflows/release.yml`. `tools/talentdata.py` regenerates `Modules/PartyCD/TalentData.lua` (base cooldowns, charges and the talents that change them) from the game's data files through wago.tools; run it after a patch and look over what it prints; the downloads are kept per build in `../wago-cache`.

## License

All rights reserved, see [LICENSE](LICENSE). Fork and modify on GitHub as you like; ask about anything else.
