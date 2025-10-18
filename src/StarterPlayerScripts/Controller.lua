--!strict
-- Cliente: Corrección anti-flicker en exhaust.
-- - Gating local: mientras RunExhaust==true jamás intenta reproducir anim Run ni enviar nuevas peticiones.
-- - Reenvía sólo 1 vez tras terminar exhaust si la tecla sigue activa y condiciones de movimiento se cumplen.
-- - FOV cae al instante al entrar en exhaust.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RunKeyEvent: RemoteEvent = Remotes:WaitForChild("RunKeyState")
local AnimationHandler = require(ReplicatedStorage.Assets.Modules:WaitForChild("AnimationHandler"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- CONFIG
local RUN_KEY = Enum.KeyCode.LeftControl
local RUN_MODE = "Hold" :: "Hold" | "Toggle"
local REQUIRE_FORWARD_ONLY = false
local FORWARD_DOT_MIN = 0.55
local RUN_ENTER_SPEED = 11
local RUN_EXIT_SPEED  = 8
local MIN_ANIM_HOLD = 0.25
local BLOCK_ATTRS = { "IsPunching", "IsDashing", "IsStunned" }
local BLOCK_STATES = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
}

local BASE_FOV = 70
local RUN_FOV  = 80
local FOV_RISE_TIME = 0.25
local FOV_FALL_TIME = 0.32
local USE_KEY_FOR_FOV = true

local LOCOMOTION_ANIMS = { Idle="Idle", Walk="Walk", Run="Run" }

-- Estado
local runKeyLogicalActive = false
local humanoid: Humanoid?
local lastLocomotion: "Idle"|"Walk"|"Run" = "Idle"
local lastChangeTime = 0
local fovBlend = 0
local exhaustedLocal = false      -- snapshot para gating
local runKeySentState: boolean? = nil
local resendArmedAfterExhaust = false

-- Helpers
local function easeOutQuad(x: number) return 1 - (1 - x)*(1 - x) end
local function anyBlockingAction(char: Model?): boolean
	if not char then return false end
	for _, a in ipairs(BLOCK_ATTRS) do
		if char:GetAttribute(a) == true then return true end
	end
	return false
end
local function isBlockedByState(): boolean
	if not humanoid then return false end
	return BLOCK_STATES[humanoid:GetState()] == true
end

local function forwardAllowed(): boolean
	if not humanoid then return false end
	if not REQUIRE_FORWARD_ONLY then return true end
	local dir = humanoid.MoveDirection
	if dir.Magnitude < 0.05 then return false end
	local root = humanoid.RootPart
	if not root then return false end
	dir = dir.Unit
	local f = root.CFrame.LookVector
	local dot = f.X*dir.X + f.Z*dir.Z
	return dot >= FORWARD_DOT_MIN
end

local function fireRunKeyState(force: boolean?)
	if runKeyLogicalActive == runKeySentState and not force then return end
	RunKeyEvent:FireServer(runKeyLogicalActive)
	runKeySentState = runKeyLogicalActive
	if player.Character then
		player.Character:SetAttribute("ClientRunKeyActive", runKeyLogicalActive)
	end
end

-- Input
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == RUN_KEY then
		if RUN_MODE == "Hold" then
			runKeyLogicalActive = true
		else
			runKeyLogicalActive = not runKeyLogicalActive
		end
		-- Si estamos exhaust, no enviar spam, marcamos intento para luego
		if player.Character and player.Character:GetAttribute("RunExhaust") == true then
			resendArmedAfterExhaust = true
		else
			fireRunKeyState(true)
		end
		lastChangeTime = 0
	end
end)

UserInputService.InputEnded:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == RUN_KEY and RUN_MODE == "Hold" then
		runKeyLogicalActive = false
		fireRunKeyState(true)
		lastChangeTime = 0
		if lastLocomotion == "Run" and humanoid then
			local sp = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
			lastLocomotion = (sp > 1) and "Walk" or "Idle"
			AnimationHandler.playChannel(player.Character :: Model, "Locomotion", LOCOMOTION_ANIMS[lastLocomotion], 0.15)
		end
	end
end)

-- Anim
local function playLocomotion(state: "Idle"|"Walk"|"Run")
	if state == lastLocomotion then return end
	local now = os.clock()
	if now - lastChangeTime < MIN_ANIM_HOLD then return end
	lastChangeTime = now
	lastLocomotion = state
	AnimationHandler.playChannel(player.Character :: Model, "Locomotion", LOCOMOTION_ANIMS[state], 0.15)
end

local function evaluateLocomotion()
	local char = player.Character
	if not char or not humanoid then return end
	if anyBlockingAction(char) or isBlockedByState() then return end

	local serverRunning = char:GetAttribute("IsRunning") == true
	local exhausted = char:GetAttribute("RunExhaust") == true
	exhaustedLocal = exhausted

	-- Al entrar en exhaust: cortar run inmediatamente a Walk/Idle
	if exhausted and lastLocomotion == "Run" then
		lastChangeTime = 0
		local sp = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
		playLocomotion((sp > 1) and "Walk" or "Idle")
	end

	local moveDir = humanoid.MoveDirection
	local speed = (humanoid.RootPart and (humanoid.RootPart.AssemblyLinearVelocity * Vector3.new(1,0,1)).Magnitude)
		or (moveDir.Magnitude * humanoid.WalkSpeed)

	if serverRunning and runKeyLogicalActive and not exhausted then
		playLocomotion("Run")
		return
	end

	if speed <= 1 or moveDir.Magnitude < 0.05 then
		playLocomotion("Idle")
	else
		if lastLocomotion ~= "Run" then
			if runKeyLogicalActive and not exhausted and speed >= RUN_ENTER_SPEED and forwardAllowed() then
				playLocomotion("Run")
			else
				playLocomotion("Walk")
			end
		else
			if not runKeyLogicalActive or exhausted or speed <= RUN_EXIT_SPEED or not forwardAllowed() then
				playLocomotion("Walk")
			else
				playLocomotion("Run")
			end
		end
	end
end

-- FOV
local function updateFOV(dt: number)
	local char = player.Character
	local serverRunning = char and char:GetAttribute("IsRunning") == true
	local exhausted = char and char:GetAttribute("RunExhaust") == true
	local want = 0
	if serverRunning and not exhausted then
		if (not USE_KEY_FOR_FOV) or runKeyLogicalActive then
			want = 1
		end
	end
	local target = want
	local time = (target > fovBlend) and FOV_RISE_TIME or FOV_FALL_TIME
	if time <= 0 then
		fovBlend = target
	else
		local alpha = math.clamp(dt / time, 0, 1)
		fovBlend = fovBlend + (target - fovBlend) * alpha
	end
	camera.FieldOfView = BASE_FOV + (RUN_FOV - BASE_FOV) * easeOutQuad(fovBlend)
end

-- Rebind y listeners
local moveConn: RBXScriptConnection?
local staminaConn: RBXScriptConnection?
local runAttrConn: RBXScriptConnection?
local exhaustConn: RBXScriptConnection?
local stateConn: RBXScriptConnection?

local function bindCharacter(char: Model)
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	lastLocomotion = "Idle"
	lastChangeTime = 0
	AnimationHandler.playChannel(char, "Locomotion", LOCOMOTION_ANIMS.Idle, 0.15)

	if moveConn then moveConn:Disconnect() end
	moveConn = humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		-- Sólo reenvía si no exhaust
		if runKeyLogicalActive and not exhaustedLocal then fireRunKeyState() end
	end)

	if staminaConn then staminaConn:Disconnect() end
	staminaConn = char:GetAttributeChangedSignal("Stamina"):Connect(function()
		if runKeyLogicalActive and not exhaustedLocal then fireRunKeyState() end
	end)

	if runAttrConn then runAttrConn:Disconnect() end
	runAttrConn = char:GetAttributeChangedSignal("IsRunning"):Connect(function()
		if char:GetAttribute("IsRunning") ~= true and lastLocomotion == "Run" then
			lastChangeTime = 0
			local sp = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
			playLocomotion((sp > 1) and "Walk" or "Idle")
		end
	end)

	if exhaustConn then exhaustConn:Disconnect() end
	exhaustConn = char:GetAttributeChangedSignal("RunExhaust"):Connect(function()
		local ex = char:GetAttribute("RunExhaust") == true
		exhaustedLocal = ex
		if ex then
			-- cortar visual de inmediato
			lastChangeTime = 0
			if lastLocomotion == "Run" then
				local sp = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
				playLocomotion((sp > 1) and "Walk" or "Idle")
			end
			-- armar reenvío cuando salga de exhaust
			resendArmedAfterExhaust = true
		else
			-- exhaust liberado
			if resendArmedAfterExhaust and runKeyLogicalActive then
				resendArmedAfterExhaust = false
				fireRunKeyState(true)
			end
		end
	end)

	if stateConn then stateConn:Disconnect() end
	stateConn = humanoid.StateChanged:Connect(function(_, newState)
		if not BLOCK_STATES[newState] then
			lastChangeTime = 0
		end
	end)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

RunService.RenderStepped:Connect(function(dt)
	evaluateLocomotion()
	updateFOV(dt)
end)
