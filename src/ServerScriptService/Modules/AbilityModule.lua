--!strict
-- AbilityModule (server): autoriza y ejecuta habilidades por tecla usando ConfigResolver/AbilitySets.
-- Soporta:
--  - AbilityUse (RemoteFunction): valida y arma meta (Animation, Cooldown).
--  - AbilityAction (RemoteEvent): maneja MarkerHit ("Hit").
--  - Timeline (VFX/Hitbox) programado desde server.
--  - CooldownEvent: "Ability:Z|X|C|V" al cliente.

local RS = game:GetService("ReplicatedStorage")

local Modules = RS.Assets:WaitForChild("Modules")
local ConfigResolver = require(Modules:WaitForChild("ConfigResolver"))
local AnimationHandler = require(Modules:WaitForChild("AnimationHandler"))
local HitboxHandler = require(Modules:WaitForChild("HitboxHandler"))

local Remotes = RS:WaitForChild("Remotes")
local AbilityUse: RemoteFunction = Remotes:WaitForChild("AbilityUse")
local AbilityAction: RemoteEvent = Remotes:WaitForChild("AbilityAction")
local Replicate: RemoteEvent = Remotes:WaitForChild("Replicate")
local CooldownEvent: RemoteEvent = Remotes:WaitForChild("CooldownEvent")

local AbilityModule = {}

-- Estado por Character
local activeTokens: { [Model]: { [string]: number } } = {} -- key -> expireTime
local cdUntil: { [Model]: { [string]: number } } = {}      -- key -> endTime

local function now() return os.clock() end

local function getChar(player: Player): Model?
	return player and player.Character or nil
end

local function getAbilityForKey(character: Model, key: string): any?
	local cfg = ConfigResolver.get(character)
	if not cfg or not cfg.Abilities then return nil end
	local ab = cfg.Abilities[key]
	return ab
end

local function putToken(character: Model, key: string, window: number)
	activeTokens[character] = activeTokens[character] or {}
	activeTokens[character][key] = now() + window
end

local function checkAndConsumeToken(character: Model, key: string): boolean
	local t = activeTokens[character] and activeTokens[character][key]
	if not t then return false end
	if now() <= t then
		activeTokens[character][key] = nil
		return true
	end
	activeTokens[character][key] = nil
	return false
end

local function onMarkerHit(character: Model, key: string, ab: any)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	local mh = ab.MarkerHit
	if not mh then return end

	-- Hitbox desde MarkerHit
	local hb = HitboxHandler.new({
		Attacker = character,
		Type = (mh.Dynamic and "Dynamic") or "Static",
		Duration = mh.Duration or 0.12,
		QueryHz = mh.QueryHz or 60,
		TeamFilter = "EnemiesOnly",
		Visuals = {
			Enabled = false,
			Size = mh.Size or Vector3.new(6, 5, 7),
			Offset = mh.Offset or CFrame.new(0, 0, -6),
		},
		MaxHits = mh.MaxHits or 5,
	})
	hb.HitInfo = mh.HitInfo
	hb:Fire()

	-- VFX opcional emit part
	if mh.EmitPart then
		local cframe = hrp.CFrame * (mh.EmitOffset or CFrame.new())
		Replicate:FireAllClients("AbilityVFX", {
			Character = character,
			Effect = "EmitPart",
			Params = {
				Template = tostring(mh.EmitPart),
				CFrame = cframe,
				Lifetime = mh.EmitLifetime or 5,
			},
		})
	end
end

local function scheduleTimeline(character: Model, ab: any)
	if not ab.Timeline then return end
	local baseStart = now()
	for _, ev in ipairs(ab.Timeline) do
		local t = tonumber(ev.t) or 0
		task.delay(math.max(0, t), function()
			if not character.Parent then return end
			if ev.type == "Hitbox" then
				local hb = HitboxHandler.new({
					Attacker = character,
					Type = (ev.Dynamic and "Dynamic") or "Static",
					Duration = ev.Duration or 0.1,
					QueryHz = ev.QueryHz or 60,
					TeamFilter = "EnemiesOnly",
					Visuals = {
						Enabled = false,
						Size = ev.Size or Vector3.new(6, 5, 7),
						Offset = ev.Offset or CFrame.new(),
					},
					MaxHits = ev.MaxHits or 999,
				})
				hb.HitInfo = ev.HitInfo
				hb:Fire()
			elseif ev.type == "VFX" then
				Replicate:FireAllClients("AbilityVFX", {
					Character = character,
					Effect = tostring(ev.Effect or ""),
					Params = ev.Params or {},
				})
			end
		end)
	end
end

-- Remote: AbilityUse
AbilityUse.OnServerInvoke = function(player: Player, key: string)
	if not player then return { Accepted = false } end
	local character = getChar(player)
	if not character or not character.Parent then return { Accepted = false } end

	if character:GetAttribute("IsRagdolled") or character:GetAttribute("IsStunned") then
		return { Accepted = false, Reason = "Busy" }
	end

	local k = string.upper(tostring(key or ""))
	if k ~= "Z" and k ~= "X" and k ~= "C" and k ~= "V" then
		return { Accepted = false }
	end

	local ab = getAbilityForKey(character, k)
	if not ab then
		return { Accepted = false, Reason = "NoAbility" }
	end

	-- Cooldown
	cdUntil[character] = cdUntil[character] or {}
	local nowt = now()
	local curCD = cdUntil[character][k] or 0
	if nowt < curCD then
		return { Accepted = false, Reason = "OnCooldown", CooldownLeft = curCD - nowt }
	end

	local cooldown = tonumber(ab.Cooldown) or 0.5
	cdUntil[character][k] = nowt + cooldown
	CooldownEvent:FireClient(player, "Ability:" .. k, cooldown)

	-- Replicar anim a terceros
	if ab.Animation then
		Replicate:FireAllClients("PlayAnimation", { Target = character, Animation = ab.Animation })
	end

	-- Event window (MarkerHit)
	if ab.EventWindow and ab.EventWindow > 0 then
		putToken(character, k, ab.EventWindow)
	end

	-- Schedule timeline (golpes/VFX programados)
	scheduleTimeline(character, ab)

	return { Accepted = true, Cooldown = cooldown, Animation = ab.Animation }
end

-- Remote: AbilityAction (Marker "Hit")
AbilityAction.OnServerEvent:Connect(function(player: Player, key: string, action: string)
	if not player then return end
	local character = getChar(player)
	if not character or not character.Parent then return end

	local k = string.upper(tostring(key or ""))
	if action ~= "Hit" or (k ~= "Z" and k ~= "X" and k ~= "C" and k ~= "V") then
		return
	end

	local ab = getAbilityForKey(character, k)
	if not ab or not ab.MarkerHit then return end

	if checkAndConsumeToken(character, k) then
		onMarkerHit(character, k, ab)
	end
end)

return AbilityModule
