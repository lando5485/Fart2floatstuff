--======================================================================
-- NotifyCenterBoot  (StarterPlayerScripts)
--======================================================================
-- ⚠ THE FILE NAME MATTERS. This must NOT be called "NotifyCenter.client.luau": Rojo would then create a
-- LocalScript named "NotifyCenter" as a SIBLING of the ModuleScript "NotifyCenter", and the
-- `script.Parent:WaitForChild("NotifyCenter")` below could resolve to THIS SCRIPT instead of the module --
-- requiring a LocalScript, which errors. Roblox permits duplicate sibling names, so nothing would warn; it
-- would just fail on some boots and not others depending on which instance was found first.
--======================================================================
-- The banner itself now lives in NotifyCenter.luau, the MODULE next to this file -- ported from Space Realm,
-- re-themed to candy. This script is only the bridge that starts it and publishes the old global.
--
-- WHY A BRIDGE INSTEAD OF JUST DELETING THIS FILE
-- 24 scripts and ~75 call sites in this realm reach the banner through `_G.NotifyCenter` (every quest, the
-- crate client, gifting, rebirth, trades, VIP, the rival callout...). Rewriting all of them to `require` the
-- module would be a 75-site sweep with nothing to show for it, so the global stays. The module table is a
-- strict SUPERSET of what the old script published -- it had push / PRIORITY / isBusy, the module has those
-- plus pin, unpin, hold, release, pillSpot and isPinned -- so every existing caller keeps working unchanged
-- and new code can use the richer API.
--
-- WHAT THE OLD 285-LINE SCRIPT DID WORSE (all fixed by the port)
--   * ONE lane. Everything landed top-centre, so another player's news drew straight through your own
--     island-arrival banner. The module has HERO (yours) and SOCIAL (theirs, top-left pills) lanes.
--   * No PREEMPTION. A low-priority nudge already on screen kept the slot; a "WELCOME TO..." arriving behind
--     it just queued. The module demotes the lesser card back onto the queue instead of burying the bigger one.
--   * No PIN. There was no way to hold a standing instruction on screen while transient banners came and went.
--   * It hard-coded top-centre instead of reading PhoneHUD's shared banner spot, so it ignored the live
--     ResponsiveUI scale and drifted from every other banner on phones.
--
-- RECLAIM LOOP: this realm has a known stale-duplicate problem (Rojo only ever ADDS -- a baked-in copy of a
-- script keeps running beside the synced one). A stale copy of the OLD NotifyCenter would overwrite
-- _G.NotifyCenter with its own smaller table on load and quietly strip pin/unpin from everyone. The loop below
-- takes the global back if that happens, and says so, rather than failing silently.
--======================================================================

local NotifyCenter = require(script.Parent:WaitForChild("NotifyCenter"))

_G.NotifyCenter = NotifyCenter

task.spawn(function()
	for _ = 1, 20 do -- ~10s of cover; a stale duplicate loads within the first frames or not at all
		task.wait(0.5)
		if _G.NotifyCenter ~= NotifyCenter then
			_G.NotifyCenter = NotifyCenter
			warn("[NotifyCenter] a stale duplicate replaced _G.NotifyCenter -- reclaimed it. "
				.. "Delete the old baked-in NotifyCenter LocalScript in Studio to stop this.")
		end
	end
end)

print("[NotifyCenter] ready -- module port (HERO lane at PhoneHUD's shared banner spot + SOCIAL lane, "
	.. "priority preemption, pinned instructions). _G.NotifyCenter published for the realm's ~75 call sites.")
