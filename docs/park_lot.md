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

## Party CD: later

- `tools/candidates.py`: list candidates from the game's data only (cooldown, an aura on some unit, given by a class skill, talent, spec spell or PvP talent), and keep in Spells.lua the reason each one is in or out (docs/PartyCD-classification.md, section 6).
- Six candidates not decided: Stoneform, Shadowmeld, Fireblood (racials: does the PvP trinket share their cooldown?), Breath of Eons (Augmentation burst), Invoke Xuen (Windwalker burst), Earth Elemental.
