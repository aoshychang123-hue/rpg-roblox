--!strict
-- Dash: air dash sin daño; dash frontal sin knockback y stop on hit; hitbox frontal visible
-- CORREGIDO: Se arregla la forma de obtener y reproducir la animación de impacto del dash.
-- MEJORA: isAir calculado en el servidor (no confía en atributo del cliente). Bloqueo autoritativo de salto.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage.Assets:WaitForChild("Modules")

local DamageHandler = require(Modules:WaitForChild("DamageHandler"))
local StunHandler = require(Modules:WaitForChild("StunHandler"))
local HitboxHandler = require(Modules:WaitForChild("HitboxHandler"))
local AnimationHandler = require(Modules:WaitForChild("AnimationHandler"))
local MovesetConfig = require(Modules:WaitForChild("MovesetConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Replicate = Remotes:WaitForChild("Replicate")
local CooldownEvent = Remotes:WaitForChild("CooldownEvent")

local DashModule = {}

local DASH_DURATIONS = {Forward = 0.8, Backward = 0.9, Left = 0.7, Right = 0.7}
local DASH_DURATIONS_AIR = {Forward = 0.6, Backward = 0.6, Left = 0.5, Right = 0.5}
local AIR_DASH_WINDOW = 10

local function rayDown(origin: Vector3, excludeList: {Instance}): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList
	params.IgnoreWater = true
	return workspace:Raycast(origin, Vector3.new(0, -12, 0), params)
end

local function serverIsAir(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not hrp then return false end

	-- Si FloorMaterial no es Air, ya estás en el suelo
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return false
	end

	-- Raycast para confirmar distancia al suelo con HipHeight
	local exclude = { character }
	local dFolder = workspace:FindFirstChild("Debris"); if dFolder then table.insert(exclude, dFolder) end
	local eFolder = workspace:FindFirstChild("Effects"); if eFolder then table.insert(exclude, eFolder) end

	local rd = rayDown(hrp.Position, exclude)
	if not rd then return true end

	local groundDistFromFeet = (hrp.Position.Y - rd.Position.Y) - humanoid.HipHeight
	if groundDistFromFeet > 0.6 then
		return true
	end

	-- Si el estado es Freefall también lo consideramos aire
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
end

function DashModule.handleDashHit(player: Player, target: Model, direction: string, isAir: boolean)
	if not player or not player.Character then return end
	if not target or not target:FindFirstChildOfClass("Humanoid") then return end

	local character = player.Character
	if not character:GetAttribute("IsDashing") then return end

	-- CORRECCIÓN: Obtener el nombre de la animación de la forma correcta.
	local animName = MovesetConfig.MainCharacter.HitReactions.Dash
	if animName then
		-- Reproducir la animación de hit en el objetivo.
		AnimationHandler.play(target, animName)
	end

	local dashHitInfo = {
		Damage = (isAir and 0) or 12,
		StunDuration = (direction == "Forward" and not isAir) and 0.6 or 0.3,
		KnockbackForce = 0,
		IsDashHit = true,
		NoKnockback = true,
		NoRagdoll = true,
	}

	DamageHandler.applyDamage(character, target, dashHitInfo)

	if direction == "Forward" and not isAir then
		character:SetAttribute("IsDashing", false)

		-- Restaurar salto al parar por hit
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			hum.Jump = false
		end

		Replicate:FireClient(player, "DashStop", { Character = character })
	end
end

function DashModule.performDash(player: Player, direction: string)
	if not player or not player.Character then return false end
	local character = player.Character
	if character:GetAttribute("IsBlocking") or character:GetAttribute("IsStunned") or character:GetAttribute("IsRagdolled") or character:GetAttribute("IsDashing") then
		return false
	end

	-- isAir calculado de forma autoritativa en servidor (no confía en atributo del cliente)
	local isAir = serverIsAir(character)
	character:SetAttribute("LastDashDirection", direction)

	local abilityName: string?, cooldown: number?

	if isAir then
		if character:GetAttribute("AirDashOnCD") then return false end
		local current = (character:GetAttribute("AirDashCount") or 0) :: number
		if current >= 2 then return false end

		local hasDoubleJumped = character:GetAttribute("HasDoubleJumped") == true
		if current == 1 and hasDoubleJumped and direction ~= "Forward" then
			return false
		end

		current += 1
		character:SetAttribute("AirDashCount", current)
		if current == 1 then
			task.delay(AIR_DASH_WINDOW, function()
				if character and character.Parent and character:GetAttribute("AirDashCount") == 1 then
					character:SetAttribute("AirDashCount", 0)
				end
			end)
		elseif current == 2 then
			character:SetAttribute("AirDashOnCD", true)
			task.delay(2.5, function()
				if character and character.Parent then
					character:SetAttribute("AirDashOnCD", false)
				end
			end)
		end
		abilityName, cooldown = "AirDash", 1.2
	else
		-- Al detectar que está en suelo, opcionalmente resetea el contador de air-dash
		-- (esto evita que quede "pegado" a 1 si el jugador aterrizó)
		character:SetAttribute("AirDashCount", 0)

		if direction == "Left" or direction == "Right" then
			if character:GetAttribute("SideDashOnCD") then return false end
			character:SetAttribute("SideDashOnCD", true)
			task.delay(1.0, function() if character then character:SetAttribute("SideDashOnCD", false) end end)
			abilityName, cooldown = "SideDash", 1.0
		elseif direction == "Forward" or direction == "Backward" then
			if character:GetAttribute("FrontDashOnCD") then return false end
			character:SetAttribute("FrontDashOnCD", true)
			task.delay(3.0, function() if character then character:SetAttribute("FrontDashOnCD", false) end end)
			abilityName, cooldown = "ForwardDash", 3.0
		else
			return false
		end
	end

	local dashDuration = (isAir and DASH_DURATIONS_AIR[direction]) or DASH_DURATIONS[direction]
	if not dashDuration then return false end

	character:SetAttribute("IsDashing", true)

	-- Bloquear salto de forma autoritativa durante el dash
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid.Jump = false
	end

	task.delay(dashDuration, function()
		if character and character:GetAttribute("IsDashing") then
			character:SetAttribute("IsDashing", false)
			if not isAir and (direction == "Left" or direction == "Right") then
				character:SetAttribute("LastSideDashEnded", os.clock())
			end
		end
		-- Restaurar salto al terminar el dash
		if humanoid and humanoid.Parent then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			humanoid.Jump = false
		end
	end)

	if abilityName and cooldown then
		CooldownEvent:FireClient(player, abilityName, cooldown)
	end

	Replicate:FireAllClients("DashCharacter", {
		Type = direction,
		Character = character,
		IsAir = isAir,
		AirDashCount = character:GetAttribute("AirDashCount"),
	})

	if direction == "Forward" and not isAir then
		local hb = HitboxHandler.new({
			Attacker = character,
			Type = "Dynamic",
			Duration = math.max(dashDuration * 0.85, 0.15),
			QueryHz = 60,
			TeamFilter = "EnemiesOnly",
			Visuals = { Enabled = true, Size = (character:GetExtentsSize() + Vector3.new(3, 2, 6)), Offset = CFrame.new(0, 0, -3), Color = Color3.fromRGB(0, 180, 255), Transparency = 0.7, Material = Enum.Material.Neon },
			MaxHits = 1,
			DisableAutoDamage = true,
		})

		hb.onHit = function(attacker, target)
			DashModule.handleDashHit(player, target, direction, isAir)
			hb:Stop()
		end

		hb:Fire()
	end

	return { Accepted = true, Duration = dashDuration }
end

return DashModule
