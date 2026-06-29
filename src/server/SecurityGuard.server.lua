-- ============================================================================
-- SECURITY GUARD (anti-backdoor) — auto-removes injected/"infected" scripts from this game's own place.
--
-- HOW IT WORKS (and its honest limits):
--   * At runtime you CANNOT read Script.Source (Roblox blocks it), so this can't scan code text. Instead it uses
--     the fact that ALL of this game's real scripts exist at SERVER START (they're Rojo-synced into the place).
--     1) INSERTION GUARD: after a short grace period it snapshots every legit script, then watches the protected
--        services. ANY Script/LocalScript/ModuleScript inserted at runtime into those areas is treated as an
--        injection and destroyed. (This game never creates scripts at runtime, so there are no false positives.)
--     2) SIGNATURE SWEEP: removes instances whose NAME matches known-backdoor signatures.
--   * It deliberately IGNORES anything inside a player (Character/Backpack/PlayerGui/PlayerScripts) and an allow
--     list (e.g. the character "Animate" script), so legitimate runtime scripts are never touched.
--   * STRONGEST protection is still: keep the place under version control (Rojo) so the saved file stays clean,
--     and don't enable untrusted Studio plugins (that's how most backdoors get inserted in the first place).
-- ============================================================================

local Players = game:GetService("Players")

-- =========================== EASY-EDIT CONFIG ===============================
local CONFIG = {
	graceSeconds   = 5,    -- wait this long after start (let every legit script load) before arming the guard
	sweepEvery     = 30,   -- re-sweep the protected services this often (catches anything the event missed)
	removeInserted = true, -- destroy script-class instances inserted at runtime into protected areas (main defense)
	-- instance NAMES (lower-cased substring match) that flag a known backdoor/exploit -> removed on sight:
	signatureNames = { "backdoor", "infected", "malware", "trojan", "exploit", "synapse", "remotespy", "lagswitch", "antiskid", "nightmare", "ic3w0lf", "wutev", "nemesis vip" },
	-- legitimate scripts that DO appear at runtime and must NEVER be removed:
	allowNames     = { ["Animate"] = true, ["Health"] = true, ["Sound"] = true, ["Respawn"] = true, ["ControlScript"] = true, ["CameraScript"] = true, ["PlayerScriptsLoader"] = true, ["PlayerModule"] = true, ["RbxCharacterSounds"] = true },
	-- services to protect (these never legitimately gain scripts at runtime in this game):
	protectedServices = { "Workspace", "ServerScriptService", "ServerStorage", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPack", "StarterPlayer", "Lighting", "SoundService" },
}
-- ============================================================================

local removedCount = 0
_G.securityRemovedCount = function() return removedCount end

local function isScript(inst) return inst:IsA("LuaSourceContainer") end -- Script / LocalScript / ModuleScript

-- inside a player's own stuff (character incl. Animate, Backpack, PlayerGui, PlayerScripts, StarterGear)? -> leave it
local function inPlayerArea(inst)
	if inst:IsDescendantOf(Players) then return true end
	local anc = inst
	while anc and anc ~= game do
		if anc:IsA("Model") and Players:GetPlayerFromCharacter(anc) then return true end
		anc = anc.Parent
	end
	return false
end

local function nameLooksMalicious(inst)
	local n = string.lower(inst.Name)
	for _, sig in ipairs(CONFIG.signatureNames) do
		if string.find(n, sig, 1, true) then return sig end
	end
	return nil
end

local function removeThreat(inst, reason)
	local path = inst:GetFullName()
	local ok = pcall(function() inst:Destroy() end)
	if ok then
		removedCount = removedCount + 1
		warn(("[SecurityGuard] REMOVED threat (%s): %s [%s]"):format(reason, path, inst.ClassName))
	end
end

local services = {}
for _, name in ipairs(CONFIG.protectedServices) do
	local ok, svc = pcall(function() return game:GetService(name) end)
	if ok and svc then services[#services + 1] = svc end
end

-- one pass over every protected service: remove signature-named instances + (when armed) unknown injected scripts
local function sweep(snapshot)
	for _, svc in ipairs(services) do
		for _, d in ipairs(svc:GetDescendants()) do
			if not inPlayerArea(d) and d ~= script then
				local sig = nameLooksMalicious(d)
				if sig then
					removeThreat(d, "signature name '" .. sig .. "'")
				elseif snapshot and isScript(d) and not snapshot[d] and not CONFIG.allowNames[d.Name] then
					if CONFIG.removeInserted then removeThreat(d, "runtime-inserted script") end
				end
			end
		end
	end
end

task.spawn(function()
	-- pass 0: immediate signature scan (kills obviously-named threats even before the snapshot is built)
	sweep(nil)

	task.wait(CONFIG.graceSeconds) -- let ALL legitimate scripts finish loading

	-- snapshot every legit script that exists now; anything script-shaped added LATER is an injection
	local snapshot = {}
	for _, svc in ipairs(services) do
		for _, d in ipairs(svc:GetDescendants()) do
			if isScript(d) then snapshot[d] = true end
		end
	end
	local count = 0; for _ in pairs(snapshot) do count = count + 1 end
	print(("[SecurityGuard] armed -> %d legit scripts snapshotted across %d protected services."):format(count, #services))

	-- LIVE insertion guard: a script-class instance appearing at runtime in a protected area = injection
	for _, svc in ipairs(services) do
		svc.DescendantAdded:Connect(function(inst)
			task.defer(function() -- let it fully parent first
				if not (inst and inst.Parent) or inst == script then return end
				if inPlayerArea(inst) then return end
				local sig = nameLooksMalicious(inst)
				if sig then removeThreat(inst, "signature name '" .. sig .. "'"); return end
				if isScript(inst) and not snapshot[inst] and not CONFIG.allowNames[inst.Name] then
					if CONFIG.removeInserted then removeThreat(inst, "runtime-inserted script") end
				end
			end)
		end)
	end

	-- periodic re-sweep backstop
	while true do
		task.wait(CONFIG.sweepEvery)
		sweep(snapshot)
	end
end)

-- TEST: lando5485 can type "/scan" to run an immediate sweep + see the removal count.
Players.PlayerAdded:Connect(function(p)
	p.Chatted:Connect(function(msg)
		if p.Name == "lando5485" and string.lower((msg:gsub("%s+", ""))) == "/scan" then
			sweep(nil)
			print("[SecurityGuard] manual /scan done -> total removed so far: " .. removedCount)
		end
	end)
end)

print("[SecurityGuard] active (insertion guard + signature sweep; arms in " .. CONFIG.graceSeconds .. "s).")
