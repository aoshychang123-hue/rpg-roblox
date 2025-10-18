--!strict
-- CombatModule: combate base con soporte de:
-- - Bloqueo con equip/des-equip visual del escudo (Left Arm) y hotfix de equip robusto.
-- - M1 combo, Downslam y DoubleJump.
-- - Overrides por arma (animaciones e hitboxes) vía ConfigResolver.
-- - Replicación de animaciones para otros clientes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage.Assets:WaitForChild("Modules")
local HitboxHandler = require(Modules:WaitForChild("HitboxHandler"))
local AnimationHandler = require(Modules:WaitForChild("AnimationHandler"))
local ConfigResolver = require(Modules:WaitForChild("ConfigResolver"))
local MovesetConfig = require(Modules:WaitForChild("MovesetConfig"))
local EquipUtil = require(Modules:WaitForChild("EquipUtil"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Replicate = Remotes:WaitForChild("Replicate")
local CooldownEvent = Remotes:WaitForChild("CooldownEvent")

local CombatModule = {}

-- Ajustes
local M1_COMBO_TIMEOUT = 1.5

-- Utilidades comunes
local function now(): number
	return os.clock()
end

local function isInAirServer(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not hrp then return false end

	-- Si FloorMaterial no es Air, está en suelo
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return false
	end

	-- Confirmar distancia al suelo con raycast
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local res = workspace:Raycast(hrp.Position, Vector3.new(0, -12, 0), params)
	if not res then return true end
	local distFeet = (hrp.Position.Y - res.Position.Y) - humanoid.HipHeight
	return distFeet > 0.6
end

local function manageM1Combo(character: Model): number
	local lastAttackTime = (character:GetAttribute("LastM1Time") or 0) :: number
	local currentCombo = (character:GetAttribute("M1_Combo") or 0) :: number
	if (os.clock() - lastAttackTime) > M1_COMBO_TIMEOUT or currentCombo >= 6 then
		currentCombo = 0
	end
	currentCombo += 1
	character:SetAttribute("M1_Combo", currentCombo)
	character:SetAttribute("LastM1Time", os.clock())
	return currentCombo
end

local function performDownslam(character: Model, config: any)
	-- Usa el Downslam del config resuelto si no se pasa explícito
	local data = (config and config.Downslam) or (ConfigResolver.get(character).Downslam)
	if not data then return end

	local track = AnimationHandler.play(character, data.Animation)
	if not track then return end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end

	task.spawn(function()
		-- Esperar a que realmente entre en aire
		repeat RunService.Heartbeat:Wait() until humanoid.FloorMaterial == Enum.Material.Air or not character.Parent
		if not character or not character.Parent then return end

		-- Hitbox del impacto en el suelo
		local hb = HitboxHandler.new({
			Attacker = character,
			Duration = 0.05,
			Type = "Static",
			Shape = "Box",
			TeamFilter = "EnemiesOnly",
			Visuals = {
				Enabled = true,
				Size = Vector3.new(12, 1, 12),
				WorldCFrame = CFrame.new(root.Position),
				Color = Color3.fromRGB(255, 255, 0),
				Material = Enum.Material.Neon,
				Transparency = 0.6,
			},
			HitInfo = data.HitInfo,
		})
		hb:Fire()

		-- VFX de impacto y viento
		Replicate:FireAllClients("AbilityVFX", {
			Character = character,
			Effect = "Webo",
			Params = {
				Character = character,
				OriginCF = CFrame.new(root.Position),
				-- Tamaño general del anillo (elipse X/Z si quieres afinar luego)
				Radius = 5.5,
				-- Dos anillos, con separación radial en studs
				Rings = 2,
				RingGap = 1.2,             -- separación entre anillos (studs)
				-- Espaciado angular entre piezas (grados) -> controla cuántas piezas por anillo
				AngularSpacingDeg = 24,    -- 360/24 = 15 piezas por anillo aprox
				-- Piezas con más “cuerpo” (no tan flacas) y poca “salida” (profundidad)
				PartWidth = 1.4,           -- grosor X de cada pieza
				PartDepth = 0.38,          -- altura visual y fondo de la pieza (Y/Z)
				-- Tilt bajo para que no sobresalgan mucho
				MinRockTilt = 4,
				MaxRockTilt = 10,
				-- Rocas/humo secundarios (opcional)
				MinFlyingRocks = 2,
				MaxFlyingRocks = 4,
				MinFlyingRockSize = 0.6,
				MaxFlyingRockSize = 1.2,
			},
		})
	end)
end

local function isDashM1Allowed(character: Model): boolean
	if not character:GetAttribute("IsDashing") then return true end
	local dir = character:GetAttribute("LastDashDirection")
	if dir == "Left" or dir == "Right" then return true end
	local grace = tonumber(character:GetAttribute("DashStopGraceUntil")) or 0
	return os.clock() <= grace
end

local function replicatePlay(character: Model, animName: string?)
	if not animName or animName == "" then return end
	Replicate:FireAllClients("PlayAnimation", { Target = character, Animation = animName })
end

-- M1 principal con overrides por arma (anim + hitbox)
local function performM1(player: Player, character: Model, config: any?)
	if not player or not character or not character.Parent then return end
	if character:GetAttribute("IsRagdolled") or character:GetAttribute("M1_OnGlobalCD") then return end
	if not isDashM1Allowed(character) then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local cfg = config or ConfigResolver.get(character)

	character:SetAttribute("IsPunching", true)
	local step = manageM1Combo(character)
	CooldownEvent:FireClient(player, "M1", 0.4)

	local strength = (character:GetAttribute("Strength") or 10) :: number
	local data = cfg and cfg.M1_Combo and cfg.M1_Combo[step]
	if not data then
		character:SetAttribute("IsPunching", false)
		return
	end

	local track = AnimationHandler.play(character, data.Animation)
	if not track then
		character:SetAttribute("IsPunching", false)
		return
	end

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	-- Permitir overrides de tamaño/offset/hz vía data.Hitbox
	local hbOpts = data.Hitbox
	local hb = HitboxHandler.new({
		Attacker = character,
		Duration = (hbOpts and hbOpts.Duration) or 0.12,
		Type = (hbOpts and hbOpts.Type) or "Dynamic",
		Shape = "Box",
		QueryHz = (hbOpts and hbOpts.QueryHz) or 60,
		TeamFilter = "EnemiesOnly",
		Visuals = {
			Enabled = (hbOpts and hbOpts.Visuals and hbOpts.Visuals.Enabled) or true,
			Size = (hbOpts and hbOpts.Size) or Vector3.new(5, 5, 5),
			Offset = (hbOpts and hbOpts.Offset) or CFrame.new(0, 0, -3),
			Color = (hbOpts and hbOpts.Visuals and hbOpts.Visuals.Color) or Color3.fromRGB(255, 50, 50),
			Transparency = (hbOpts and hbOpts.Visuals and hbOpts.Visuals.Transparency) or 0.7,
			Material = (hbOpts and hbOpts.Visuals and hbOpts.Visuals.Material) or Enum.Material.Neon,
		},
	})

	-- Copiar y ajustar HitInfo
	local hitInfoCopy = {}
	for k, v in pairs(data.HitInfo or {}) do hitInfoCopy[k] = v end
	hitInfoCopy.Damage = (hitInfoCopy.Damage or 5) + (strength * 0.1)
	local baseKB = hitInfoCopy.KnockbackForce or 18
	hitInfoCopy.KnockbackForce = baseKB + step * 2
	hitInfoCopy.VerticalKnockbackForce = hitInfoCopy.VerticalKnockbackForce or 6
	hitInfoCopy.MirrorAttacker = true

	if step == 6 then
		hitInfoCopy.KnockbackForce = math.max(hitInfoCopy.KnockbackForce or 0, 26)
		hitInfoCopy.VerticalKnockbackForce = math.max(hitInfoCopy.VerticalKnockbackForce or 0, 10)
		hitInfoCopy.RagdollDuration = hitInfoCopy.RagdollDuration or 1.5
	end
	hb.HitInfo = hitInfoCopy

	local hitConnection: RBXScriptConnection?
	hitConnection = track:GetMarkerReachedSignal("Hit"):Connect(function()
		if hitConnection then hitConnection:Disconnect() hitConnection = nil end
		hb:Fire()
	end)

	local restored = false
	local function restore()
		if restored then return end
		restored = true
		if humanoid then humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
		if character then
			character:SetAttribute("IsPunching", false)
			if character:GetAttribute("M1_Queued") then
				character:SetAttribute("M1_Queued", false)
				task.defer(performM1, player, character, cfg)
			end
		end
	end
	track.Stopped:Once(restore)
	task.delay(math.max(track.Length * 0.8, 0.05), restore)

	if step == 6 then
		character:SetAttribute("M1_OnGlobalCD", true)
		CooldownEvent:FireClient(player, "M1_Global", 2.5)
		task.delay(2.5, function()
			if character then character:SetAttribute("M1_OnGlobalCD", false) end
		end)
	end
end

-- Estado de equip visual del escudo y watcher de bloqueo
local equippedShield: {[Model]: any} = {}
local blockConn: {[Model]: RBXScriptConnection} = {}
local DEBUG_EQUIP = false
local function dprint(...)
	if DEBUG_EQUIP then print("[CombatModule][BlockEquip]", ...) end
end
local function dwarn(...)
	if DEBUG_EQUIP then warn("[CombatModule][BlockEquip]", ...) end
end

function CombatModule.attachBlockVisualWatcher(character: Model)
	-- Limpia watcher previo
	if blockConn[character] then
		blockConn[character]:Disconnect()
		blockConn[character] = nil
	end

	local function ensureShieldEquipped()
		-- Si hay registro pero el modelo ya no existe, se considera no equipado
		local eq = equippedShield[character]
		local equippedAlive = (eq and eq.model and eq.model.Parent == character)
		if equippedAlive then
			return
		end

		-- Config: toma ShieldModel si existe, si no "Shield1"
		local movesetName = (character:GetAttribute("Moveset") or "MainCharacter") :: string
		local cfg = MovesetConfig[movesetName]
		local blockCfg = cfg and cfg.Block
		local shieldModel = (blockCfg and blockCfg.ShieldModel) or "Shield1"

		dprint("Equipando escudo", shieldModel, "para", character.Name)
		local ok, res = pcall(function()
			return EquipUtil.AttachToLeftArm({
				Character = character,
				ModelPath = shieldModel,
			})
		end)
		if not ok then
			dwarn("EquipUtil.AttachToLeftArm falló:", res)
			return
		end
		if not res or not res.model then
			dwarn("AttachToLeftArm no devolvió modelo (nil).")
			return
		end
		equippedShield[character] = res
		dprint("Escudo equipado:", res.model:GetFullName())
	end

	local function ensureShieldRemoved()
		local eq = equippedShield[character]
		if eq then
			dprint("Removiendo escudo de", character.Name)
			if eq.destroy then
				pcall(eq.destroy)
			elseif eq.model and eq.model.Parent then
				pcall(function() eq.model:Destroy() end)
			end
			equippedShield[character] = nil
		end
	end

	blockConn[character] = character:GetAttributeChangedSignal("IsBlocking"):Connect(function()
		local isBlocking = character:GetAttribute("IsBlocking") == true

		-- Animaciones de red para otros jugadores (el local las hace el cliente)
		local movesetName = (character:GetAttribute("Moveset") or "MainCharacter") :: string
		local cfg = MovesetConfig[movesetName]
		local blockCfg = cfg and cfg.Block
		local startName = blockCfg and blockCfg.Start
		local idleName = blockCfg and blockCfg.Idle
		local startDuration = (blockCfg and tonumber(blockCfg.StartDuration)) or 0.22

		if isBlocking then
			replicatePlay(character, startName)
			-- Intentar equipar inmediatamente
			ensureShieldEquipped()
			-- Luego pasar a Idle si sigue bloqueando
			task.delay(startDuration, function()
				if character.Parent and character:GetAttribute("IsBlocking") == true then
					replicatePlay(character, idleName)
					-- Doble verificación por si el equip falló la primera vez
					ensureShieldEquipped()
				end
			end)
		else
			ensureShieldRemoved()
		end
	end)

	-- Estado inicial: si ya estaba bloqueando cuando enchufamos el watcher, equipa ahora
	if character:GetAttribute("IsBlocking") == true then
		dprint("Estado inicial: IsBlocking=true, equipando escudo")
		ensureShieldEquipped()
	end

	-- Limpieza cuando el character se destruye
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			ensureShieldRemoved()
			if blockConn[character] then
				blockConn[character]:Disconnect()
				blockConn[character] = nil
			end
		end
	end)
end

-- Entrada principal de combate (acciones desde Remote)
function CombatModule.handleCombat(player: Player, action: string, params: any)
	if not player then return end
	local character = player.Character
	if not character or not character.Parent then return end
	if character:GetAttribute("IsRagdolled") then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Resolver config (moveset + arma activa)
	local config = ConfigResolver.get(character)

	if action == "Block" then
		local want = params and params.State
		if want then
			-- Cooldown de ruptura por espalda activa
			local brokenUntil = tonumber(character:GetAttribute("BlockBrokenUntil")) or 0
			if now() < brokenUntil then return end
			-- No bloquear si está haciendo otras acciones críticas
			if character:GetAttribute("IsPunching") or character:GetAttribute("IsDashing") or character:GetAttribute("IsStunned") then return end
			character:SetAttribute("IsBlocking", true)
		else
			character:SetAttribute("IsBlocking", false)
		end
		return
	end

	if action == "M1" then
		if character:GetAttribute("M1_OnGlobalCD") then return end
		if character:GetAttribute("IsPunching") then
			local currentCombo = (character:GetAttribute("M1_Combo") or 0) :: number
			if currentCombo < 6 then
				character:SetAttribute("M1_Queued", true)
			end
			return
		end
		performM1(player, character, config)
		return
	end

	if action == "Downslam" then
		if character:GetAttribute("IsPunching") then return end
		if not isInAirServer(character) then return end
		character:SetAttribute("IsPunching", true)
		performDownslam(character, config)
		task.delay(1.2, function()
			if character then character:SetAttribute("IsPunching", false) end
		end)
		return
	end

	if action == "DoubleJump" then
		if not character:GetAttribute("IsInAir") or character:GetAttribute("HasDoubleJumped") then return end
		character:SetAttribute("HasDoubleJumped", true)
		return
	end
end

function CombatModule.handleBlock(player: Player, isBlocking: boolean)
	CombatModule.handleCombat(player, "Block", { State = isBlocking })
end

return CombatModule
