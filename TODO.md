# TODO

Things decided to be worth doing, not started yet.

## Extras: announce my focus marker (Mythic+)

Say once in party chat which raid marker my focus-kick macro uses, e.g. `My focus marker is {rt3}`, so the group can avoid using the same one.

Researched 2026-09-21, nothing built, nothing tested in game.

- **How others do it.** Mythic Dungeon Tools (its FocusMarker module, `Modules/FocusMarker.lua`, option "Announce my Focus Marker on ready check") and Stormseer's FocusMarker (GitHub) both announce on `READY_CHECK` with `C_ChatInfo.SendChatMessage(text, "PARTY")`. The marker is a user setting; nobody parses the player's macros. `{rt1}`..`{rt8}` works in every client language.
- **What 12.x forbids.** From the moment a keystone is inserted until the run is over, during encounters and during PvP matches, addons cannot send chat (`C_ChatInfo.InChatMessagingLockdown()`, restriction type `Enum.AddOnRestrictionType.Chat`). So "when the countdown starts" and "right after the key starts" are not possible. On zoning in is possible but early: the group may not be there yet, and it also fires in a Mythic dungeon without a key.
- **Plan.** A third feature in the Misc module ("Extras"), about 50 lines:
  - settings: the marker (1-8), the sentence;
  - trigger: `READY_CHECK`, in a party (not a raid), not in combat, not in chat lockdown (check the API exists; `pcall` the send);
  - once per group and instance: remember instance id + the sorted party GUIDs, announce again only when that changes;
  - reference guards in other addons: ClassReminders' `BuffRequests.lua` (lockdown check with fallback), Leatrix Plus ("Chat messages are restricted right now").
- **Open questions for the user.** Ready check only, or also "on entering the dungeon" as a second option? Default sentence in Chinese, English, or both?
- **To verify in game.** When exactly the chat restriction switches on relative to the keystone countdown, and whether a blocked send raises an error or fails silently. The CVars `addonChatRestrictionsForced` / `addonChallengeModeRestrictionsForced` simulate the restricted state.
