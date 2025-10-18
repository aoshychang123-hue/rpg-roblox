--!strict
-- MissionService: "More XP" quest for XP NPC (repeatable)
-- Flow:
--  - Player talks to XP NPC -> picks "More XP" -> Accept mission "BanditIdea"
--  - Kill workspace.NPC.Bandit (target)
--  - Come back to XP NPC -> Claim reward -> XP granted server-side
--
-- Remotes in ReplicatedStorage.Remotes:
--  - MissionRequest: RemoteFunction ({action="offer"|"accept", missionId})
--  - MissionStatus:  RemoteFunction ({missionId}) -> {state="none"|"active"|"ready"|"claimed"}
--  - MissionClaim:   RemoteFunction ({missionId}) -> {ok, rewardXP, level, xp, required}
--  - MissionProgress: RemoteEvent (server->client state changes)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RS = ReplicatedStorage
local RemotesFolder = RS:FindFirstChild("Remotes") or Instance.new("Folder", RS)
RemotesFolder.Name = "Remotes"

local MissionRequest = RemotesFolder:FindFirstChild("MissionRequest") :: RemoteFunction?
if not MissionRequest then
	MissionRequest = Instance.new("RemoteFunction")
	MissionRequest.Name = "MissionRequest"
	MissionRequest.Parent = RemotesFolder
end
local MissionStatus = RemotesFolder:FindFirstChild("MissionStatus") :: RemoteFunction?
if not MissionStatus then
	MissionStatus = Instance.new("RemoteFunction")
	MissionStatus.Name = "MissionStatus"
	MissionStatus.Parent = RemotesFolder
end
local MissionClaim = RemotesFolder:FindFirstChild("MissionClaim") :: RemoteFunction?
if not MissionClaim then
	MissionClaim = Instance.new("RemoteFunction")
	MissionClaim.Name = "MissionClaim"
	MissionClaim.Parent = RemotesFolder
end
local MissionProgress = RemotesFolder:FindFirstChild("MissionProgress") :: RemoteEvent?
if not MissionProgress then
	MissionProgress = Instance.new("RemoteEvent")
	MissionProgress.Name = "MissionProgress"
	MissionProgress.Parent = RemotesFolder
end

-- Config
type MissionCfg = {
	targetName: string,
	displayName: string,
	rewardXP: number,
	allowRepeat: boolean,
}

local Missions: {[string]: MissionCfg} = {
	BanditIdea = {
		targetName = "Bandit",
		displayName = "More XP: The Stolen Idea",
		rewardXP = 175,
		allowRepeat = true, -- repeatable
	},
}

-- Per-player state (in-memory)
type MissionState = "none" | "active" | "ready" | "claimed"
type PlayerState = { state: MissionState, startedAt: number, readyAt: number? }
local playerMissions: {[Player]: {[string]: PlayerState}} = {}

local function getState(plr: Player, missionId: string): PlayerState
	playerMissions[plr] = playerMissions[plr] or {}
	playerMissions[plr][missionId] = playerMissions[plr][missionId] or { state = "none", startedAt = 0 }
	return playerMissions[plr][missionId]
end

local function setState(plr: Player, missionId: string, newState: MissionState)
	local st = getState(plr, missionId)
	st.state = newState
	if newState == "active" then
		st.startedAt = os.clock()
	elseif newState == "ready" then
		st.readyAt = os.clock()
	end
	playerMissions[plr][missionId] = st
	plr:SetAttribute("Mission_" .. missionId, newState)
	MissionProgress:FireClient(plr, { missionId = missionId, state = newState })
end

-- Award XP to Character attributes
local function awardXP(plr: Player, amount: number): {ok: boolean, level: number, xp: number, req: number}
	local char = plr.Character
	if not char then
		return { ok = false, level = 0, xp = 0, req = 0 }
	end
	if char:GetAttribute("Level") == nil then char:SetAttribute("Level", 1) end
	if char:GetAttribute("XP") == nil then char:SetAttribute("XP", 0) end
	if char:GetAttribute("RequiredXP") == nil then char:SetAttribute("RequiredXP", 100) end

	local level = tonumber(char:GetAttribute("Level")) or 1
	local xp = tonumber(char:GetAttribute("XP")) or 0
	local req = math.max(1, tonumber(char:GetAttribute("RequiredXP")) or 100)

	xp += amount
	while xp >= req do
		xp -= req
		level += 1
		req = math.floor(req * 1.15 + 10)
	end

	char:SetAttribute("XP", xp)
	char:SetAttribute("Level", level)
	char:SetAttribute("RequiredXP", req)

	return { ok = true, level = level, xp = xp, req = req }
end

-- Helpers
local function findNearestLivingPlayer(pos: Vector3, maxDist: number): Player?
	local nearest: Player? = nil
	local best = maxDist
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - pos).Magnitude
			if d < best then best = d; nearest = plr end
		end
	end
	return nearest
end

local function extractKiller(humanoid: Humanoid): Player?
	local tagNames = { "creator", "LastHitBy", "Killer" }
	for _, n in ipairs(tagNames) do
		local obj = humanoid:FindFirstChild(n)
		if obj and obj:IsA("ObjectValue") then
			local val = obj.Value
			if val and typeof(val) == "Instance" then
				if val:IsA("Player") then
					return val
				elseif val:IsA("Model") then
					local owner = Players:GetPlayerFromCharacter(val)
					if owner then return owner end
				end
			end
		end
	end
	return nil
end

-- Bind a model as mission target
local function bindMissionTarget(model: Model, missionId: string)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp then return end
	model:SetAttribute("MissionTarget", missionId)

	hum.Died:Connect(function()
		local killer = extractKiller(hum) or findNearestLivingPlayer(hrp.Position, 25)
		if killer then
			local st = getState(killer, missionId)
			if st.state == "active" then
				setState(killer, missionId, "ready")
			end
		end
	end)
end

-- Watch for targets
local function tryBindExistingTargets()
	local folder = workspace:FindFirstChild("NPC")
	if not folder then return end
	for missionId, cfg in pairs(Missions) do
		local m = folder:FindFirstChild(cfg.targetName)
		if m and m:IsA("Model") then
			bindMissionTarget(m, missionId)
		end
	end
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "NPC" then
		task.defer(tryBindExistingTargets)
	end
end)
if workspace:FindFirstChild("NPC") then
	workspace.NPC.ChildAdded:Connect(function(inst)
		for missionId, cfg in pairs(Missions) do
			if inst:IsA("Model") and inst.Name == cfg.targetName then
				bindMissionTarget(inst, missionId)
			end
		end
	end)
end

-- Remotes
MissionStatus.OnServerInvoke = function(plr: Player, payload: any)
	local missionId = payload and payload.missionId or "BanditIdea"
	local st = getState(plr, missionId)
	return { state = st.state, missionId = missionId }
end

MissionRequest.OnServerInvoke = function(plr: Player, payload: any)
	local action = payload and payload.action or "offer"
	local missionId = payload and payload.missionId or "BanditIdea"
	local cfg = Missions[missionId]
	if not cfg then
		return { ok = false, err = "Unknown mission." }
	end

	local st = getState(plr, missionId)
	if action == "offer" then
		return { ok = true, missionId = missionId, target = cfg.targetName, rewardXP = cfg.rewardXP, state = st.state }
	elseif action == "accept" then
		if st.state == "none" or (st.state == "claimed" and cfg.allowRepeat) then
			setState(plr, missionId, "active")
			return { ok = true, state = "active", missionId = missionId, target = cfg.targetName }
		else
			return { ok = false, state = st.state, err = "Mission already in progress or completed." }
		end
	end

	return { ok = false, err = "Unsupported action." }
end

MissionClaim.OnServerInvoke = function(plr: Player, payload: any)
	local missionId = payload and payload.missionId or "BanditIdea"
	local cfg = Missions[missionId]
	if not cfg then
		return { ok = false, err = "Unknown mission." }
	end

	local st = getState(plr, missionId)
	if st.state ~= "ready" then
		return { ok = false, state = st.state, err = "Not ready to claim." }
	end

	local result = awardXP(plr, cfg.rewardXP)
	-- For repeatable missions: reset to none so it can be accepted again
	if cfg.allowRepeat then
		setState(plr, missionId, "none")
	else
		setState(plr, missionId, "claimed")
	end

	return { ok = result.ok, rewardXP = cfg.rewardXP, level = result.level, xp = result.xp, required = result.req }
end

-- Init
tryBindExistingTargets()

Players.PlayerRemoving:Connect(function(plr)
	playerMissions[plr] = nil
end)
