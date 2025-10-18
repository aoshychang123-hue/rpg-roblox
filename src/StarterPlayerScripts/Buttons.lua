--!strict
-- MobileActions: circular Punch + Dash + Lock buttons (MOBILE-ONLY)
-- Uses the SAME remotes as PC:
--  - Punch -> Remotes.CombatEvent:FireServer("M1") or "Downslam" if airborne
--  - Dash  -> Remotes.DashGet:InvokeServer(direction: "Forward"|"Backward"|"Left"|"Right")
-- Direction on mobile dash:
--  - Uses the thumbstick (Controls:GetMoveVector or Humanoid.MoveDirection)
--  - Side dash when joystick left/right; backward dash when joystick backward;
--    forward dash when joystick forward OR no movement.
-- Mobile ShiftLock like PC:
--  - Single tap "Lock" = camera-relative movement + shoulder camera offset (PC-style shift lock feel)
--  - Double tap "Lock" = AimLock nearest player you're facing (shows rotating reticles); tap again to release
-- Cooldown dim per button using CooldownEvent ("M1"/"M1_Global" and "Dash"/"Ability:Dash")
-- Auto-places above PerfHUD and adapts to viewport size.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local player = Players.LocalPlayer
local RS = ReplicatedStorage
local Remotes = RS:WaitForChild("Remotes")
local CooldownEvent = Remotes:WaitForChild("CooldownEvent") :: RemoteEvent
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent
local DashGet = Remotes:WaitForChild("DashGet") :: RemoteFunction

-- Mobile only
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
if not isMobile then return end

-- Optional airborne helper (same module used on PC)
local Modules = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Modules")
local AirDetector = Modules and require(Modules:WaitForChild("AirDetector"))

-- Access PlayerModule Controls to read thumbstick movement vector (more responsive than MoveDirection)
local Controls = (function()
	local ok, value = pcall(function()
		local pm = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
		local mod = require(pm)
		return mod:GetControls()
	end)
	return ok and value or nil
end)()

-- Style
local COLORS = {
	Bg = Color3.fromRGB(20, 22, 28),
	Stroke = Color3.fromRGB(40, 44, 52),
	Label = Color3.fromRGB(235, 240, 255),
	Accent = Color3.fromRGB(90, 140, 255),
	Accent2 = Color3.fromRGB(60, 200, 110),
	Dim = Color3.fromRGB(120, 124, 135),
	Warn = Color3.fromRGB(220, 90, 90),
	Aim = Color3.fromRGB(255, 220, 120),
}

-- Metrics (responsive)
local M = {
	rightMargin = 18,
	bottomBase = 140,     -- fallback bottom if PerfHUD not found
	spacing = 12,         -- vertical spacing
	sideSpacing = 12,     -- horizontal spacing between bottom row buttons
	punchSize = 78,       -- bigger (primary)
	dashSize = 64,        -- secondary
	lockSize = 56,        -- small
	font = 14,
	fontSmall = 13,
}

local function computeMetrics()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local s = math.clamp(vp.Y / 720, 0.9, 1.2)
	M.punchSize = math.floor(math.clamp(78 * s, 64, 92))
	M.dashSize  = math.floor(math.clamp(64 * s, 56, 84))
	M.lockSize  = math.floor(math.clamp(56 * s, 48, 72))
	M.spacing   = math.floor(math.clamp(12 * s, 10, 16))
	M.sideSpacing = math.floor(math.clamp(12 * s, 8, 16))
	M.font      = math.floor(math.clamp(14 * s, 12, 18))
	M.fontSmall = math.max(12, M.font - 1)
end

-- UI root
local screen = Instance.new("ScreenGui")
screen.Name = "MobileActions"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

export type CircleButton = {
	Btn: TextButton,
	Label: TextLabel,
	Dim: Frame,
	CDText: TextLabel,
	CooldownUntil: number,
	UpdateConn: RBXScriptConnection?,
}

local function makeCircle(labelText: string, sizePx: number, accentColor: Color3): CircleButton
	local btn = Instance.new("TextButton")
	btn.Name = labelText .. "_Button"
	btn.AnchorPoint = Vector2.new(1, 1) -- bottom-right by default; can override for others
	btn.Size = UDim2.new(0, sizePx, 0, sizePx)
	btn.BackgroundColor3 = COLORS.Bg
	btn.BackgroundTransparency = 0.25
	btn.BorderSizePixel = 0
	btn.Text = ""

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = COLORS.Stroke
	stroke.Transparency = 0.4
	stroke.Parent = btn

	local ring = Instance.new("ImageLabel")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.Image = "rbxassetid://7072718362"
	ring.ImageColor3 = accentColor
	ring.ImageTransparency = 0.15
	ring.Parent = btn

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.BackgroundTransparency = 1
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale(0.5, 0.5)
	lbl.Size = UDim2.new(1, -10, 0, math.max(20, math.floor(sizePx * 0.36)))
	lbl.Font = Enum.Font.GothamSemibold
	lbl.Text = labelText
	lbl.TextSize = (#labelText > 5) and M.fontSmall or M.font
	lbl.TextColor3 = COLORS.Label
	lbl.TextWrapped = true
	lbl.Parent = btn

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Visible = false
	dim.AnchorPoint = Vector2.new(0.5, 0.5)
	dim.Position = UDim2.fromScale(0.5, 0.5)
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = COLORS.Dim
	dim.BackgroundTransparency = 0.35
	dim.BorderSizePixel = 0
	dim.Parent = btn
	local dimCorner = Instance.new("UICorner")
	dimCorner.CornerRadius = UDim.new(1, 0)
	dimCorner.Parent = dim

	local cdText = Instance.new("TextLabel")
	cdText.Name = "CD"
	cdText.AnchorPoint = Vector2.new(0.5, 0.5)
	cdText.Position = UDim2.fromScale(0.5, 0.5)
	cdText.BackgroundTransparency = 1
	cdText.Size = UDim2.new(1, -10, 0, math.max(18, math.floor(sizePx * 0.3)))
	cdText.Font = Enum.Font.GothamSemibold
	cdText.TextColor3 = Color3.fromRGB(250, 250, 250)
	cdText.TextSize = (#labelText > 5) and M.fontSmall or M.font
	cdText.Text = ""
	cdText.Parent = dim

	return {
		Btn = btn,
		Label = lbl,
		Dim = dim,
		CDText = cdText,
		CooldownUntil = 0,
		UpdateConn = nil,
	}
end

-- Instances
computeMetrics()
local punch = makeCircle("Punch", M.punchSize, COLORS.Accent)
local dash  = makeCircle("Dash",  M.dashSize,  COLORS.Accent2)
local lockB = makeCircle("Lock",  M.lockSize,  Color3.fromRGB(255, 200, 90)) -- golden ring

-- Place into ScreenGui
punch.Btn.Parent = screen
dash.Btn.Parent  = screen
lockB.Btn.Parent = screen

-- AimLock reticles:
-- - Center reticle (small rotating square)
-- - Target tag (BillboardGui above target's head with rotating square)
local reticleCenter = Instance.new("ImageLabel")
reticleCenter.Name = "AimReticleCenter"
reticleCenter.BackgroundTransparency = 1
reticleCenter.AnchorPoint = Vector2.new(0.5, 0.5)
reticleCenter.Position = UDim2.fromScale(0.5, 0.5)
reticleCenter.Size = UDim2.fromOffset(18, 18)
reticleCenter.Image = "rbxassetid://7188137259" -- simple square icon
reticleCenter.ImageColor3 = COLORS.Aim
reticleCenter.Visible = false
reticleCenter.Parent = screen

local targetBillboard: BillboardGui? = nil
local function attachTargetTag(hrp: BasePart)
	if targetBillboard then targetBillboard:Destroy() targetBillboard = nil end
	local bb = Instance.new("BillboardGui")
	bb.Name = "AimTargetTag"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(24, 24)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.Adornee = hrp
	bb.Parent = screen

	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = "rbxassetid://7188137259"
	img.ImageColor3 = COLORS.Aim
	img.Parent = bb

	targetBillboard = bb
	return img
end

-- Place above PerfHUD
local function placeButtons()
	local pg = player:FindFirstChild("PlayerGui")
	local rightMargin = M.rightMargin
	local baseBottom = M.bottomBase

	if pg then
		local perf = pg:FindFirstChild("PerfHUD")
		if perf and perf:IsA("ScreenGui") then
			local pr = perf:FindFirstChild("Root")
			if pr and pr:IsA("Frame") and pr.Visible then
				local bm = math.abs(pr.Position.Y.Offset)
				local rm = math.abs(pr.Position.X.Offset)
				rightMargin = rm > 0 and rm or rightMargin
				baseBottom = bm + pr.AbsoluteSize.Y + 8
			end
		end
	end

	-- Bottom-right row: [Lock] [Punch], Dash stacked above Punch
	punch.Btn.Position = UDim2.new(1, -rightMargin, 1, -baseBottom)
	dash.Btn.Position  = UDim2.new(1, -rightMargin - (M.punchSize - M.dashSize) - 6, 1, -baseBottom - M.punchSize - M.spacing)
	-- Lock to the left of Punch
	lockB.Btn.AnchorPoint = Vector2.new(1, 1)
	lockB.Btn.Position = UDim2.new(1, -rightMargin - M.punchSize - M.sideSpacing, 1, -baseBottom)
end

-- Cooldown overlay
local function startCooldownUI(circle: CircleButton, seconds: number)
	seconds = math.max(0, tonumber(seconds) or 0)
	if circle.UpdateConn then circle.UpdateConn:Disconnect(); circle.UpdateConn = nil end
	if seconds <= 0 then
		circle.Dim.Visible = false
		circle.CooldownUntil = 0
		return
	end
	circle.CooldownUntil = os.clock() + seconds
	circle.Dim.Visible = true
	circle.CDText.Text = tostring(math.max(1, math.floor(seconds)))

	circle.UpdateConn = RunService.RenderStepped:Connect(function()
		local left = circle.CooldownUntil - os.clock()
		if left <= 0 then
			circle.Dim.Visible = false
			circle.CDText.Text = ""
			if circle.UpdateConn then circle.UpdateConn:Disconnect(); circle.UpdateConn = nil end
			circle.CooldownUntil = 0
		else
			circle.CDText.Text = tostring(math.max(1, math.floor(left)))
		end
	end)
end

-- Listen to standard cooldowns
CooldownEvent.OnClientEvent:Connect(function(name: string, duration: number)
	if typeof(name) ~= "string" then return end
	-- Punch (M1)
	if name == "M1" or name == "M1_Global" then
		startCooldownUI(punch, duration)
	end
	-- Dash
	if name == "Dash" or name == "DASH" or name == "Ability:Dash" then
		startCooldownUI(dash, duration)
	end
end)

-- Helpers: Airborne detector
local detector: any = nil
local function ensureDetector(character: Model?)
	if AirDetector and character then
		detector = AirDetector.new(character)
	else
		detector = nil
	end
end

local function isAirborne(): boolean
	if detector and typeof(detector.IsAirborne) == "function" then
		return detector:IsAirborne()
	end
	-- Fallback
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return not hum or hum.FloorMaterial == Enum.Material.Air
end

-- Determine dash direction from the thumbstick (Controls) or MoveDirection
local function resolveDashDirection(): string
	local char = player.Character
	if not char then return "Forward" end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp then return "Forward" end

	-- Prefer Controls:GetMoveVector() for mobile thumbstick; fallback to MoveDirection
	local move: Vector3 = Vector3.zero
	if Controls and typeof(Controls.GetMoveVector) == "function" then
		move = Controls:GetMoveVector()
	end
	if move.Magnitude < 0.01 then
		move = hum.MoveDirection
	end
	if move.Magnitude < 0.05 then
		return "Forward" -- no movement -> forward dash
	end

	-- Project into HRP's local axes to decide side/back/forward
	local look = hrp.CFrame.LookVector
	local right = hrp.CFrame.RightVector
	local fwdDot = look:Dot(move.Unit)
	local rightDot = right:Dot(move.Unit)

	-- Strongest component picks direction
	if math.abs(fwdDot) >= math.abs(rightDot) then
		return (fwdDot >= 0) and "Forward" or "Backward"
	else
		return (rightDot >= 0) and "Right" or "Left"
	end
end

-- Fire actions using the SAME server remotes as PC
local localM1Lock = false
local function firePunch()
	if localM1Lock then return end
	localM1Lock = true
	-- airborne -> Downslam, else M1
	if isAirborne() then
		CombatEvent:FireServer("Downslam")
	else
		CombatEvent:FireServer("M1")
	end
	task.delay(0.25, function() localM1Lock = false end)
end

local globalDashLock = false
local function fireDash()
	if globalDashLock then return end
	globalDashLock = true
	task.delay(0.12, function() globalDashLock = false end)

	local direction = resolveDashDirection()
	local ok, res = pcall(function()
		return DashGet:InvokeServer(direction)
	end)
	if not ok or not res then return end

	if (typeof(res) == "table" and res.Accepted) or (typeof(res) == "boolean" and res) then
		TweenService:Create(dash.Btn, TweenInfo.new(0.06), { BackgroundTransparency = 0.35 }):Play()
		task.delay(0.10, function()
			TweenService:Create(dash.Btn, TweenInfo.new(0.08), { BackgroundTransparency = 0.25 }):Play()
		end)
	end
end

-- ShiftLock like PC: camera-relative movement and shoulder camera offset
local shiftLocked = false
local lastLockTap = 0
local doubleTapWindow = 0.35

local function setShiftLock(enabled: boolean)
	shiftLocked = enabled
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	-- Camera-relative rotation (PC-like)
	UserGameSettings.RotationType = enabled and Enum.RotationType.CameraRelative or Enum.RotationType.MovementRelative
	-- Shoulder offset for "over-the-shoulder" feel
	if hum then
		hum.CameraOffset = enabled and Vector3.new(0.8, 0, 0) or Vector3.new(0, 0, 0)
	end
	-- Visual feedback: ring color pulse
	local ring = lockB.Btn:FindFirstChild("Ring")
	if ring and ring:IsA("ImageLabel") then
		local targetColor = enabled and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(255, 200, 90)
		TweenService:Create(ring, TweenInfo.new(0.12), { ImageColor3 = targetColor }):Play()
	end
end

-- AimLock
local aimLockActive = false
local aimTarget: Model? = nil
local aimConn: RBXScriptConnection? = nil
local retConn: RBXScriptConnection? = nil

local function stopAimLock()
	aimLockActive = false
	aimTarget = nil
	if aimConn then aimConn:Disconnect(); aimConn = nil end
	if retConn then retConn:Disconnect(); retConn = nil end
	reticleCenter.Visible = false
	if targetBillboard then targetBillboard:Destroy(); targetBillboard = nil end
end

local function pickAimTarget(maxDist: number, maxAngleDeg: number): Model?
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local camPos = cam.CFrame.Position
	local look = cam.CFrame.LookVector

	local best: Model? = nil
	local bestScore = math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			local c = plr.Character
			local hrp = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			if c and hrp and hum and hum.Health > 0 then
				local to = hrp.Position - camPos
				local dist = to.Magnitude
				if dist <= maxDist then
					local ang = math.deg(math.acos(math.clamp(look:Dot(to.Unit), -1, 1)))
					if ang <= maxAngleDeg then
						local score = ang * 3 + dist * 0.05
						if score < bestScore then
							bestScore = score
							best = c
						end
					end
				end
			end
		end
	end
	return best
end

local function startAimLock()
	local cam = workspace.CurrentCamera
	if not cam then return end

	local target = pickAimTarget(100, 35) -- within 100 studs and ~35° cone
	if not target then
		TweenService:Create(lockB.Btn, TweenInfo.new(0.09), { BackgroundColor3 = COLORS.Warn, BackgroundTransparency = 0.15 }):Play()
		task.delay(0.15, function()
			TweenService:Create(lockB.Btn, TweenInfo.new(0.12), { BackgroundColor3 = COLORS.Bg, BackgroundTransparency = 0.25 }):Play()
		end)
		return
	end

	aimTarget = target
	aimLockActive = true
	reticleCenter.Visible = true

	-- Rotating center reticle and target tag
	local targetHRP = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tagImage: ImageLabel? = nil
	if targetHRP then
		local tagImg = attachTargetTag(targetHRP)
		tagImage = tagImg
	end

	local rot = 0
	if retConn then retConn:Disconnect() end
	retConn = RunService.RenderStepped:Connect(function(dt)
		rot = (rot + dt * 180) % 360
		reticleCenter.Rotation = rot
		if tagImage then tagImage.Rotation = -rot end
	end)

	-- Keep the camera looking at target each frame (without taking control of position)
	if aimConn then aimConn:Disconnect() end
	aimConn = RunService.RenderStepped:Connect(function()
		local c = aimTarget
		local camNow = workspace.CurrentCamera
		if not c or not camNow then stopAimLock(); return end
		local hrp = c:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = c:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then stopAimLock(); return end

		local pos = camNow.CFrame.Position
		local lookAt = hrp.Position + Vector3.new(0, 1.5, 0)
		camNow.CFrame = CFrame.new(pos, lookAt)
	end)
end

-- Button interactions
local function tapFeedback(btn: TextButton)
	TweenService:Create(btn, TweenInfo.new(0.06, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 0.35 }):Play()
	task.delay(0.10, function()
		TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 0.25 }):Play()
	end)
end

punch.Btn.MouseButton1Click:Connect(function()
	if punch.CooldownUntil > 0 then return end
	tapFeedback(punch.Btn)
	firePunch()
end)

dash.Btn.MouseButton1Click:Connect(function()
	if dash.CooldownUntil > 0 then return end
	tapFeedback(dash.Btn)
	fireDash()
end)

lockB.Btn.MouseButton1Click:Connect(function()
	-- Double tap detection
	local now = os.clock()
	if now - lastLockTap <= doubleTapWindow then
		-- Double tap -> AimLock toggle
		lastLockTap = 0
		if aimLockActive then
			stopAimLock()
		else
			startAimLock()
		end
	else
		-- Single tap -> ShiftLock toggle (PC-like)
		lastLockTap = now
		setShiftLock(not shiftLocked)
	end
end)

-- Responsive
local function applyResponsive()
	computeMetrics()
	-- Resize
	punch.Btn.Size = UDim2.new(0, M.punchSize, 0, M.punchSize)
	dash.Btn.Size  = UDim2.new(0, M.dashSize,  0, M.dashSize)
	lockB.Btn.Size = UDim2.new(0, M.lockSize,  0, M.lockSize)
	-- Update label sizes
	punch.Label.TextSize = (#punch.Label.Text > 5) and M.fontSmall or M.font
	dash.Label.TextSize  = (#dash.Label.Text  > 5) and M.fontSmall or M.font
	lockB.Label.TextSize = (#lockB.Label.Text > 5) and M.fontSmall or M.font
	-- Place
	placeButtons()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(function()
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsive)
			applyResponsive()
		end
	end)
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsive)
end

-- Character binds (for AirDetector and to clear locks on respawn)
player.CharacterAdded:Connect(function(char)
	ensureDetector(char)
	-- Reset locks on respawn
	setShiftLock(false)
	stopAimLock()
end)
if player.Character then ensureDetector(player.Character) end

-- Initial placement
applyResponsive()
RunService.Heartbeat:Wait()
placeButtons()
