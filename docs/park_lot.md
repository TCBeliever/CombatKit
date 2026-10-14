# Park lot

Things set aside on purpose: not forgotten, not being worked on now. Take one out when it is picked up.

## Party CD: to confirm in game

Each one is in Spells.lua as the game's data suggests; a check in game settles it.

| Ability | Class, spec | What to check | If it fails |
|---|---|---|---|
| Fiery Brand 204021 | Demon Hunter, Vengeance | the debuff on the opponent shows, as 207771 or 207744 | find the aura ID (AuraLab learn mode), or take it out |
| Guardian of the Forgotten Queen 228049 | Paladin, Protection (PvP talent) | an aura on the paladin after the cast | watch the ally's aura instead (Ally) |
| Healing Tide Totem 108280 | Shaman, Restoration | an aura on the shaman after the cast | take it out: a totem alone cannot be seen |
| Invoke Niuzao 132578 | Monk, Brewmaster | an aura on the monk after the cast | take it out |
| Invoke Yu'lon 322118 | Monk, Mistweaver | an aura on the monk after the cast | take it out |
| Time Stop 378441 | Evoker (PvP talent) | can be cast on oneself (the data says yes) | make it OtherAlly |
| Roar of Sacrifice 53480 | Hunter | can be put on the hunter (the data says yes) | make it OtherAlly |
| Stoneform 20594, Fireblood 265221 | Dwarf, Dark Iron Dwarf | a teammate's PvP trinket use puts them on a 30 s cooldown (they share category 1166 with it) | yes: on ARENA_COOLDOWNS_UPDATE showing a fresh trinket use, give a ready Stoneform / Fireblood 30 s; until measured they count their own 120 s |
| Vanish 1856 | Rogue | the 3 s buff on the rogue is 11327 (115193 is another Vanish of the same name, not watched) | find the aura ID (AuraLab learn mode) |
| Master's Call 1241871 | Hunter (Command Pet, cunning pet) | which buff shows: 54216 or 1224810 on the ally, 62305 on the hunter (the data names all three, nothing links them) | keep the one seen, drop the others |
| Tree of Life 33891 | Druid, Restoration | the form's aura (no duration of its own) shows in the aura container; shifting in and out during the 30 s counts as one use | watch the 30 s window 117679 instead (shared with other Incarnations? check) |
| Shield Charge 385952 | Warrior, Protection | the stun on the opponent is 385954 (the data names it, nothing links it to the cast) | find the aura ID (AuraLab learn mode) |
| Smoke Bomb 212182 | Rogue (PvP talent) | the cloud's aura 212183 shows on the rogue who dropped it; an enemy rogue's cloud over our rogue would count as a use (left as it is: rare) | if the rogue's own aura differs, watch that one |
| War Stomp 20549, Quaking Palm 107079, Haymaker 287712, Bull Rush 255723 | Tauren, Pandaren, Kul Tiran, Highmountain Tauren | the debuff shows on the opponent with these IDs | find the aura ID (AuraLab learn mode) |

## Party CD: the highlight, to look at in game

UI.lua draws the active highlight from the game's own textures (docs/PartyCD-next.md, A). In game: all three still load on 12.1 (a missing one falls back to the breathing strips, `/ckpartycd` shows nothing about it, look at the icon); the classic ants' 48 px cells line up (no seam, no jump at the loop); how many of the 30 cells the two atlases draw (an empty cell flashes) and their speed; violet and blue are visible on the ants; the size around the icon (ants 1.2x, atlases 1.4x) and whether the additive blend is too bright on a light icon.

## Party CD: later

The next round is written up in `docs/PartyCD-next.md`. Done, to see in game: the highlight (A), racial abilities (B), the generated files' dates (D). Waiting: the 24 additions `tools/candidates.py` proposes (C, Invoke Xuen among them; to be picked), the stand-in frames' sides with DandersFrames grown from the centre (D).
- Still not decided: Breath of Eons (Augmentation burst), Earth Elemental.
