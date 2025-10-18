--!strict
-- CLIENT DASH + BLOQUEO + replicación de anims de terceros
-- Incluye enganche de markers de Mazo_X para terceros (Emit1, BeamActive, Hit, end)
-- Optimizaciones: consolidación de helpers, comentarios, y estructura clara. Sin alterar lógica.
-- MEJORA: Al iniciar cualquier dash, elimina cualquier velocidad previa y asegura VectorVelocity limpia antes de aplicar dash (mitiga flings y undimiento).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Player = Players.LocalPlayer

local ModulesRoot = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Modules")
local AnimationHandler = require(ModulesRoot:WaitForChild("AnimationHandler"))
local MovesetConfig = require(ModulesRoot:WaitForChild("MovesetConfig"))
local ClientVFXModule = require(ModulesRoot:WaitForChild("ClientVFXModule"))
local AirDetector = require(ModulesRoot:WaitForChild("AirDetector"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Replicate = Remotes:WaitForChild("Replicate")
local CombatEvent = Remotes:WaitForChild("CombatEvent")
local DashGet = Remotes:WaitForChild("DashGet")

local ReplicatedFunctions: {[string]: (any) -> ()} = {}

-- Ventana de gracia para permitir M1 inmediatamente tras parar un front/back dash por hit o stop
local dashStopGraceUntil = 0

-- Helpers de bloqueo de salto
local activeJumpLockToken = 0
local function unlockJump(humanoid: Humanoid?)
	if not humanoid or not humanoid.Parent then return end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	humanoid.Jump = false
	local savedPower = humanoid:GetAttribute("SavedJumpPower")
	local savedHeight = humanoid:GetAttribute("SavedJumpHeight")
	if typeof(savedPower) == "number" then
		humanoid.JumpPower = savedPower
		humanoid:SetAttribute("SavedJumpPower", nil)
	end
	if typeof(savedHeight) == "number" then
		humanoid.JumpHeight = savedHeight
		humanoid:SetAttribute("SavedJumpHeight", nil)
	end
end

local function lockJump(humanoid: Humanoid?, duration: number)
	if not humanoid or not humanoid.Parent then return end
	if humanoid:GetAttribute("SavedJumpPower") == nil then
		humanoid:SetAttribute("SavedJumpPower", humanoid.JumpPower)
	end
	if humanoid:GetAttribute("SavedJumpHeight") == nil then
		humanoid:SetAttribute("SavedJumpHeight", humanoid.JumpHeight)
	end
	humanoid.Jump = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	activeJumpLockToken += 1
	local myToken = activeJumpLockToken
	task.delay(duration, function()
		if myToken == activeJumpLockToken then
			unlockJump(humanoid)
		end
	end)
end

-- Enganche markers Mazo_X para terceros
local function attachMazo1XMarkers(track: AnimationTrack, character: Model)
	if not track or not character then return end
	local c1 = track:GetMarkerReachedSignal("Emit1"):Connect(function()
		ClientVFXModule.MazoX_emit1(character)
	end)
	local c2 = track:GetMarkerReachedSignal("BeamActive"):Connect(function()
		ClientVFXModule.MazoX_beamActive(character)
	end)
	local c3 = track:GetMarkerReachedSignal("Hit"):Connect(function()
		ClientVFXModule.MazoX_hit(character)
	end)
	local function cleanup()
		ClientVFXModule.MazoX_end(character)
		for _, c in ipairs({c1,c2,c3}) do if c then c:Disconnect() end end
	end
	track:GetMarkerReachedSignal("end"):Connect(cleanup)
	track:GetMarkerReachedSignal("End"):Connect(cleanup)
	track.Stopped:Connect(cleanup)
end

function ReplicatedFunctions.PlayAnimation(params)
	local targetCharacter = params and params.Target
	local animName = params and params.Animation
	if targetCharacter and animName and targetCharacter ~= Player.Character then
		local track = AnimationHandler.play(targetCharacter, animName)
		if track and animName == "Mazo_X" then
			attachMazo1XMarkers(track, targetCharacter)
		end
	end
end

function ReplicatedFunctions.DashStop(params)
	local character = params and params.Character or Player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	for _, obj in ipairs(hrp:GetChildren()) do
		if obj:IsA("LinearVelocity") and obj.Name == "DashVelocity" then obj:Destroy() end
		if obj:IsA("NumberValue") and obj.Name == "DashSpeed" then obj:Destroy() end
	end
	hrp.AssemblyLinearVelocity = Vector3.new(0, math.min(hrp.AssemblyLinearVelocity.Y, 0), 0)
	character:SetAttribute("IsDashing", false)
	dashStopGraceUntil = os.clock() + 0.18
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	unlockJump(humanoid)
end

-- ray helpers
local function raycastAhead(hrp: BasePart, dir: Vector3, dist: number, exclude: Instance): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { exclude, workspace:FindFirstChild("Debris"), workspace:FindFirstChild("Effects") }
	params.IgnoreWater = true
	return workspace:Raycast(hrp.Position, dir * dist, params)
end

local function rayDown(hrp: BasePart, exclude: Instance): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { exclude, workspace:FindFirstChild("Debris"), workspace:FindFirstChild("Effects") }
	params.IgnoreWater = true
	return workspace:Raycast(hrp.Position, Vector3.new(0, -12, 0), params)
end

local function isGrounded(hrp: BasePart, humanoid: Humanoid): boolean
	local res = rayDown(hrp, hrp.Parent)
	if not res then return false end
	local distFeet = (hrp.Position.Y - res.Position.Y) - humanoid.HipHeight
	return distFeet <= 0.35
end

function ReplicatedFunctions.DashCharacter(params)
	local character = params and params.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	local dashType = params.Type :: string
	local isAir = params.IsAir == true
	local startSpeed: number, duration: number, easingStyle: Enum.EasingStyle

	-- Contador de air dash
	local airDashCount = params.AirDashCount
	if airDashCount == nil then
		airDashCount = character:GetAttribute("AirDashCount") or 1
	end

	-- MEJORA: Elimina cualquier velocidad previa ANTES de aplicar el dash
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	hrp.Velocity = Vector3.new(0, 0, 0)
	-- También limpia cualquier RotVelocity para evitar flings residuales
	pcall(function() hrp.RotVelocity = Vector3.zero end)

	if isAir then
		startSpeed = 250; duration = 0.55; easingStyle = Enum.EasingStyle.Quad
		local movesetName = (character:GetAttribute("Moveset") or "MainCharacter") :: string
		local config = MovesetConfig[movesetName]
		if config and config.DashesAir then
			if dashType == "Forward" and (airDashCount :: number) >= 2 and config.DashesAir.DoubleForward then
				AnimationHandler.play(character, config.DashesAir.DoubleForward)
			else
				local animKey = config.DashesAir[dashType] and dashType or "Forward"
				if config.DashesAir[animKey] then
					AnimationHandler.play(character, config.DashesAir[animKey])
				end
			end
		end
	else
		if dashType == "Forward" then
			startSpeed = 160; duration = 0.62; easingStyle = Enum.EasingStyle.Quad
		elseif dashType == "Backward" then
			startSpeed = 130; duration = 0.85; easingStyle = Enum.EasingStyle.Sine
		elseif dashType == "Left" or dashType == "Right" then
			startSpeed = 180; duration = 0.48; easingStyle = Enum.EasingStyle.Quad
		else
			startSpeed = 110; duration = 0.7; easingStyle = Enum.EasingStyle.Sine
		end

		local movesetName = (character:GetAttribute("Moveset") or "MainCharacter") :: string
		local config = MovesetConfig[movesetName]
		if config and config.Dashes and config.Dashes[dashType] then
			AnimationHandler.play(character, config.Dashes[dashType])
		end
	end

	-- Limpieza exhaustiva antes de crear dashForce
	for _, obj in ipairs(hrp:GetChildren()) do
		if obj:IsA("BodyVelocity") or obj:IsA("LinearVelocity") or obj.Name == "DashSpeed" or obj.Name == "DashVelocity" then
			obj:Destroy()
		end
	end

	lockJump(humanoid, duration)

	local attachment = hrp:FindFirstChildOfClass("Attachment") or Instance.new("Attachment", hrp)
	local dashForce = Instance.new("LinearVelocity")
	dashForce.Name = "DashVelocity"
	dashForce.MaxForce = math.huge
	dashForce.Attachment0 = attachment
	dashForce.Parent = hrp

	local speed = Instance.new("NumberValue")
	speed.Name = "DashSpeed"
	speed.Value = startSpeed
	speed.Parent = dashForce

	-- MEJORA: Asegura que VectorVelocity sea 0 antes de aplicar la dirección (por si queda residual)
	dashForce.VectorVelocity = Vector3.zero

	local HARD_WALL_DOT = -0.55
	local STOP_DIST_MIN = 2.2
	local con: RBXScriptConnection?
	con = RunService.RenderStepped:Connect(function()
		if not dashForce.Parent or not speed or not hrp.Parent then
			if con then con:Disconnect() con = nil end
			return
		end

		local cf = hrp.CFrame
		local look = cf.LookVector
		local right = cf.RightVector
		local dir: Vector3

		if dashType == "Forward" then dir = look
		elseif dashType == "Backward" then dir = -look
		elseif dashType == "Left" then dir = -right
		elseif dashType == "Right" then dir = right
		else if con then con:Disconnect() con = nil end return end

		if isAir then
			local mv = humanoid.MoveDirection
			if mv.Magnitude > 0.001 then dir = mv.Unit end
		end

		local speedVal = speed.Value
		local probeDist = math.clamp(speedVal * 0.035, STOP_DIST_MIN, 12)
		local hit = raycastAhead(hrp, dir, probeDist, character)

		local vy = hrp.AssemblyLinearVelocity.Y
		if isAir then
			local downHit = rayDown(hrp, hrp.Parent)
			if downHit then
				local distFeet = (hrp.Position.Y - downHit.Position.Y) - humanoid.HipHeight
				if distFeet <= 0.35 and vy < 0 then
					vy = 0
				else
					vy = math.clamp(vy, -20, 10)
				end
			else
				vy = math.clamp(vy, -20, 10)
			end
		else
			if isGrounded(hrp, humanoid) and vy > 2 then vy = 0 end
			vy = math.clamp(vy, -18, 10)
		end

		if hit then
			local n = hit.Normal
			local facingDot = dir:Dot(n)
			local dist = (hit.Position - hrp.Position).Magnitude

			if facingDot < HARD_WALL_DOT and dist <= STOP_DIST_MIN then
				if con then con:Disconnect() con = nil end
				dashForce:Destroy()
				speed:Destroy()
				hrp.AssemblyLinearVelocity = Vector3.new(0, math.min(vy, 0), 0)
				character:SetAttribute("IsDashing", false)
				if not isAir and (dashType == "Left" or dashType == "Right") then
					character:SetAttribute("LastSideDashEnded", os.clock())
				end
				return
			end

			if dist < 4 then
				speed.Value = math.max(speed.Value * 0.5, 40)
			else
				speed.Value = math.max(speed.Value * 0.8, isAir and 120 or 105)
			end

			local proj = dir - n * math.max(0, dir:Dot(n))
			if proj.Magnitude > 0.001 then dir = proj.Unit end
		end

		local horiz = dir * speed.Value
		dashForce.VectorVelocity = Vector3.new(horiz.X, vy, horiz.Z)
	end)

	local tween = TweenService:Create(speed, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 0 })
	tween:Play()

	Debris:AddItem(dashForce, duration + 0.12)
	task.delay(duration + 0.12, function()
		if con then con:Disconnect() con = nil end
		if speed then speed:Destroy() end
		if not isAir and (dashType == "Left" or dashType == "Right") then
			character:SetAttribute("LastSideDashEnded", os.clock())
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		unlockJump(hum)
	end)

	if not isAir then
		task.spawn(ClientVFXModule.createRockTrail, character, duration)
	end
end

-- Dispatcher Replicate
Replicate.OnClientEvent:Connect(function(name, params)
	local fn = ReplicatedFunctions[name]
	if fn then pcall(fn, params) end
end)

-- ==========================================
-- Input local (dash, M1, block, doble salto)
-- ==========================================
local DOUBLE_TAP_TIME = 0.25
local DEFAULT_M1_COOLDOWN = 0.39
local CHAIN_WINDOW = 0

local keybinds = {
	[Enum.KeyCode.W] = "Forward",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.S] = "Backward",
	[Enum.KeyCode.D] = "Right",
}

local detector: any = nil
local lastTap: {[string]: number} = {}
local qIsHeld = false
local directionalDashUsedWithQ = false
local isMouseDown = false
local isAttacking = false
local localM1OnCD = false

local isBlockHeld = false
local blockStartTrack: AnimationTrack?
local blockIdleTrack: AnimationTrack?

local function playLocalBlockAnims(character: Model)
	local movesetName = (character:GetAttribute("Moveset") or "MainCharacter") :: string
	local config = MovesetConfig[movesetName]
	local blockCfg = config and config.Block
	if not blockCfg then return end

	if blockCfg.Start then
		blockStartTrack = AnimationHandler.play(character, blockCfg.Start)
	end

	local delayDur = (blockCfg.StartDuration and tonumber(blockCfg.StartDuration)) or 0.22
	task.delay(delayDur, function()
		if not isBlockHeld then return end
		if blockCfg.Idle then
			blockIdleTrack = AnimationHandler.play(character, blockCfg.Idle)
			if blockIdleTrack then blockIdleTrack.Looped = true end
		end
	end)
end

local function stopLocalBlockAnims()
	if blockStartTrack then
		pcall(function() blockStartTrack:Stop(0.05) end)
		blockStartTrack = nil
	end
	if blockIdleTrack then
		pcall(function() blockIdleTrack:Stop(0.08) end)
		blockIdleTrack = nil
	end
end

local canSideDash = true
local canFrontDash = true
local canAirDash = true
local globalDashLock = false
local localDashCooldowns = { Front = false, Side = false, Air = false }

local function setLocalDashLock(kind: "Front" | "Side" | "Air", duration: number?)
	if kind == "Front" then
		localDashCooldowns.Front = true
		task.delay(duration or 0.55, function() localDashCooldowns.Front = false end)
	elseif kind == "Side" then
		localDashCooldowns.Side = true
		task.delay(duration or 0.9, function() localDashCooldowns.Side = false end)
	elseif kind == "Air" then
		localDashCooldowns.Air = true
		task.delay(0.25, function() localDashCooldowns.Air = false end)
	end
end

local function now() return os.clock() end

local function tryDash(direction: string): boolean
	local character = Player.Character
	if not character or not detector then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	if character:GetAttribute("IsRagdolled") or character:GetAttribute("IsStunned") then return false end
	if character:GetAttribute("IsDashing") then return false end

	if detector:IsAirborne() then
		local airCount = (character:GetAttribute("AirDashCount") or 0) :: number
		local hasDoubleJumped = character:GetAttribute("HasDoubleJumped") == true
		if hasDoubleJumped and airCount >= 1 and direction ~= "Forward" then
			return false
		end
	end

	local isInAir = detector:IsAirborne()
	local isSide = (direction == "Left" or direction == "Right")

	if isInAir then
		if not canAirDash or localDashCooldowns.Air then return false end
	else
		if isSide then
			if not canSideDash or localDashCooldowns.Side then return false end
		else
			local allowChain = false
			if direction == "Forward" then
				local lastSideEnded = character:GetAttribute("LastSideDashEnded")
				if typeof(lastSideEnded) == "number" and (now() - lastSideEnded) <= CHAIN_WINDOW then
					allowChain = true
				end
			end
			if (not canFrontDash or localDashCooldowns.Front) and not allowChain then
				return false
			end
		end
	end

	if globalDashLock then return false end
	globalDashLock = true
	task.delay(0.12, function() globalDashLock = false end)

	local ok, serverMeta = pcall(function()
		return DashGet:InvokeServer(direction)
	end)
	if not ok or not serverMeta then
		return false
	end

	local accepted = false
	local duration = 0.7
	if typeof(serverMeta) == "table" then
		accepted = serverMeta.Accepted == true
		duration = serverMeta.Duration or duration
	elseif typeof(serverMeta) == "boolean" then
		accepted = serverMeta
	end
	if not accepted then return false end

	character:SetAttribute("IsDashing", true)
	task.delay(duration, function()
		if character and character.Parent then
			character:SetAttribute("IsDashing", false)
			if not isInAir and isSide then
				character:SetAttribute("LastSideDashEnded", now())
			end
		end
	end)

	if isInAir then
		setLocalDashLock("Air", 0.25)
	else
		if isSide then
			setLocalDashLock("Side", 0.9)
		else
			setLocalDashLock("Front", 0.9)
		end
	end

	if isInAir then
		canAirDash = false
		task.delay(0.2, function() canAirDash = true end)
	else
		if isSide then
			canSideDash = false
			task.delay(1.0, function() canSideDash = true end)
		else
			canFrontDash = false
			task.delay(3.0, function() canFrontDash = true end)
		end
	end

	return true
end

local function performDoubleJump()
	local character = Player.Character
	if not character then return end
	if character:GetAttribute("IsRagdolled") then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local movesetName = (character:GetAttribute("Moveset") or "MainCharacter") :: string
	local config = MovesetConfig[movesetName]
	if not (config and config.Jump and config.Jump.DoubleJumpAnim) then return end

	local animTrack = AnimationHandler.play(character, config.Jump.DoubleJumpAnim)
	if animTrack then
		local connection: RBXScriptConnection?
		connection = animTrack:GetMarkerReachedSignal("Jump"):Connect(function()
			if connection then connection:Disconnect() connection = nil end
			local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then return end

			local attachment = hrp:FindFirstChildOfClass("Attachment") or Instance.new("Attachment", hrp)
			local doubleJumpVelocity = Instance.new("LinearVelocity")
			doubleJumpVelocity.MaxForce = math.huge
			doubleJumpVelocity.VectorVelocity = Vector3.new(0, 45, 0)
			doubleJumpVelocity.Attachment0 = attachment
			doubleJumpVelocity.Parent = hrp
			Debris:AddItem(doubleJumpVelocity, 0.15)
		end)
	end

	CombatEvent:FireServer("DoubleJump")
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	local character = Player.Character
	if not character or not detector then return end
	if character:GetAttribute("IsRagdolled") then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if input.KeyCode == Enum.KeyCode.Space then
		if character:GetAttribute("IsDashing") then
			humanoid.Jump = false
			return
		end
		if detector:IsAirborne() and not character:GetAttribute("HasDoubleJumped") and not character:GetAttribute("IsDashing") then
			performDoubleJump()
		end
	end

	-- M1 gating
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isMouseDown = true
		if isAttacking then return end
		isAttacking = true

		task.spawn(function()
			while isMouseDown do
				local char = Player.Character
				if char and detector and not (char:GetAttribute("IsStunned") or char:GetAttribute("IsBlocking")) then
					local blockByDash = false
					local isDash = char:GetAttribute("IsDashing")
					if isDash then
						local dir = char:GetAttribute("LastDashDirection")
						local inGrace = os.clock() <= dashStopGraceUntil
						blockByDash = (dir ~= "Left" and dir ~= "Right") and (not inGrace)
					else
						if dashStopGraceUntil < os.clock() then
							dashStopGraceUntil = 0
						end
					end

					if not blockByDash and not localM1OnCD then
						localM1OnCD = true
						if detector:IsAirborne() then
							CombatEvent:FireServer("Downslam")
						else
							CombatEvent:FireServer("M1")
						end
						task.delay(DEFAULT_M1_COOLDOWN, function() localM1OnCD = false end)
					end
				end
				RunService.RenderStepped:Wait()
			end
			isAttacking = false
		end)
		return
	end

	-- Q mantenida: dash direccional
	if input.KeyCode == Enum.KeyCode.Q then
		qIsHeld = true
		directionalDashUsedWithQ = false
		for key, dir in pairs(keybinds) do
			if UserInputService:IsKeyDown(key) then
				directionalDashUsedWithQ = true
				tryDash(dir)
				return
			end
		end
		return
	end

	-- Doble tap direccional
	local directionKey = keybinds[input.KeyCode]
	if directionKey then
		if qIsHeld then
			directionalDashUsedWithQ = true
			tryDash(directionKey)
			return
		end
		local nowTick = tick()
		if lastTap[directionKey] and (nowTick - lastTap[directionKey] < DOUBLE_TAP_TIME) then
			tryDash(directionKey)
			lastTap[directionKey] = nil
		else
			lastTap[directionKey] = nowTick
		end
	end

	-- Block: reproducir animaciones locales y notificar al server
	if input.KeyCode == Enum.KeyCode.F then
		isBlockHeld = true
		if character then
			playLocalBlockAnims(character)
		end
		CombatEvent:FireServer("Block", { State = true })
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isMouseDown = false
	end

	if input.KeyCode == Enum.KeyCode.Q then
		qIsHeld = false
		if not directionalDashUsedWithQ then
			tryDash("Forward")
		end
	end

	local direction = keybinds[input.KeyCode]
	if direction then
		local tapAtRelease = lastTap[direction]
		if tapAtRelease then
			task.delay(DOUBLE_TAP_TIME, function()
				if lastTap and lastTap[direction] == tapAtRelease then
					lastTap[direction] = nil
				end
			end)
		end
	end

	if input.KeyCode == Enum.KeyCode.F then
		isBlockHeld = false
		stopLocalBlockAnims()
		CombatEvent:FireServer("Block", { State = false })
	end
end

local function onCharacterAdded(character: Model)
	detector = AirDetector.new(character)
end

Player.CharacterAdded:Connect(onCharacterAdded)
if Player.Character then onCharacterAdded(Player.Character) end

UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)
