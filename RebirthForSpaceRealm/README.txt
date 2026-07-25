REBIRTH SYSTEM -- copy for the SPACE REALM place (linked universe)
==================================================================

WHAT'S IN HERE
--------------
1. RebirthSystem.server.lua   -> put in ServerScriptService
2. RebirthClient.client.luau  -> put in StarterPlayer > StarterPlayerScripts
3. RebirthButton.client.luau  -> put in StarterPlayer > StarterPlayerScripts
   (the on-screen REBIRTH button. The MAIN place bakes this into its side-bar,
    but the Space Realm has no side-bar, so this standalone button is included.)

The RemoteEvent "RebirthEvent" is created automatically by the server script in
ReplicatedStorage -- you do NOT need to add it by hand.


HOW IT CONNECTS ACROSS THE UNIVERSE
-----------------------------------
DataStores are UNIVERSE-scoped (shared by every place in the same experience),
so this "just works" between the main place and the Space Realm -- same stores,
same data, no manual wiring:

  * "Rebirth_v1"                 -> rebirth COUNT + boosts persist everywhere.
  * "SpaceRealm_PlayerState_v1"  -> the "Space done?" check (highestPlanetReached >= 8).
  * "DinoRealm_PlayerState_v1"   -> the "Dino done?" check (dinoComplete == true).

A player's rebirth progress and their island/space/dino completion carry between
places automatically because both places read/write the SAME store keys.


REQUIREMENTS TO REBIRTH (checked server-side, fail-closed)
  * Reached Island 14   -> player attribute "HighestIsland" >= 14  (set by the MAIN place)
  * Completed Space Realm
  * Completed Dino Realm


IMPORTANT NOTES FOR THE SPACE REALM
-----------------------------------
* IN STUDIO the realm requirements auto-pass so you can test the button + HUD on a
  fresh test account. Live servers check the real per-realm saves.

* "HighestIsland" is a player ATTRIBUTE set by the MAIN place's PlayerStats. In the
  Space Realm that attribute is not set unless you replicate it, so on a LIVE Space
  Realm server the ISLANDS requirement reads as not-done. If you want players to
  rebirth FROM the Space Realm, either:
    (a) have them rebirth back in the MAIN place  (recommended -- a rebirth RESETS the
        island run, and the islands only exist in the main place), or
    (b) save HighestIsland into a shared DataStore and read it in this script too.

* resetRun() calls _G.rebirthResetHome (provided by the MAIN place's PlayerStats) to
  reset the island run + respawn on Bean Farm. The Space Realm has no islands, so that
  hook won't exist there -- the script falls back to resetting leaderstats + reloading
  the character. Practically: the real "reset" belongs in the main place; in the Space
  Realm this HUD is best used to VIEW rebirth status + boosts (and the boosts still
  apply because the Rebirths leaderstat + _G globals are set here too).

* LEADERSTATS: the server adds a "Rebirths" IntValue under each player's "leaderstats"
  folder. Make sure the Space Realm creates a "leaderstats" folder per player (most
  places do). The flight-speed boost is driven by that value on the client.


THE STACKING BOOST (per rebirth, kept forever)
  * +25% coins earned      (_G.rebirthMult -> read by the coin handler)
  * +3%  flight speed       (Rebirths leaderstat -> _G.rebirthSpeedMult on the client)
  * better rare-pet luck    (_G.rebirthLuck -> read by the pet rare-roll)
  If the Space Realm doesn't have coin/flight/pet systems that read those globals, the
  boosts simply won't do anything there -- they still apply in the main place.
