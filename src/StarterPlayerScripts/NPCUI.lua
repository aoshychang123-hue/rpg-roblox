--!strict
-- NPC Control UI (NPC+) responsive (PC + Mobile) with tabs: NPC | Config
-- - Toggle button aligned with the left edge of PlayerFaceHUD (avatar/health UI), with responsive sizing.
-- - Panel opens to the right of the button, widths/heights adapt to any screen size/orientation.
-- - NPC Tab: selector + actions (Toggle PVP, Toggle Dash, Toggle Move, Reset TP). Excludes "XP".
-- - Config Tab: client-only toggles (Hitbox visuals visibility, Combat HUD visibility, PerfHUD visibility).
-- - Scrollable content on NPC tab.
-- - Positions are anchored relative to PlayerFaceHUD if present; falls back to bottom-left margins otherwise.
-- - All texts in English.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")
local ControlNPC = Remotes:WaitForChild("ControlNPC") :: RemoteEvent

-- Style
local BG = Color3.fromRGB(20, 22, 28)
local STROKE = Color3.fromRGB(40, 44, 52)
local TXT = Color3.fromRGB(220, 230, 245)
local ACCENT = Color3.fromRGB(90, 140, 255)
local OK = Color3.fromRGB(60, 200, 110)
local OFF = Color3.fromRGB(100, 104, 120)

-- Base positioning (will be scaled responsively)
local POS = {
	spaceAboveLife = 8,   -- gap above PlayerFaceHUD
	leftInset = 0,        -- aligned with left border of PlayerFaceHUD
	panelGap = 8,         -- horizontal gap between button and panel
	-- Fallback if PlayerFaceHUD is missing
	fallbackLeft = 16,
	fallbackBottom = 170,
}

-- Responsive metrics (computed from viewport)
local currentScale = 1
local METRICS = {
	btn = 44,
	panelW = 280,
	openH = 220,
	scrollbar = 6,
}

local function computeMetrics()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	-- Scale based mainly on height; light boost on touch
	local scale = math.clamp(vp.Y / 720, 0.85, 1.35)
	if isMobile then scale = scale * 1.05 end
	currentScale = scale

	-- Button size (in px before applying UIScale)
	local btn = math.floor(math.clamp(vp.Y * 0.07, 44, isMobile and 72 or 56))
	-- Panel width as portion of width
	local panelW = math.floor(math.clamp(vp.X * (isMobile and 0.45 or 0.35), 260, 420))
	-- Open height as portion of height
	local openH = math.floor(math.clamp(vp.Y * (isMobile and 0.32 or 0.28), 200, 380))
	-- Scrollbar thickness
	local scrollbar = isMobile and 10 or 6

	METRICS.btn = btn
	METRICS.panelW = panelW
	METRICS.openH = openH
	METRICS.scrollbar = scrollbar
end

-- GUI root
local screen = Instance.new("ScreenGui")
screen.Name = "NPCControlUI"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

-- Root container with UIScale (we'll divide offset positions by currentScale)
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = screen

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = root

-- Toggle button (icon) - bottom-left anchored
local toggleBtn = Instance.new("ImageButton")
toggleBtn.Name = "Toggle"
toggleBtn.AnchorPoint = Vector2.new(0, 1) -- bottom-left
toggleBtn.Size = UDim2.new(0, METRICS.btn, 0, METRICS.btn)
toggleBtn.BackgroundColor3 = BG
toggleBtn.BackgroundTransparency = 0.35
toggleBtn.BorderSizePixel = 0
toggleBtn.Image = "rbxassetid://131981569450984" -- your icon here
toggleBtn.ImageTransparency = 0
toggleBtn.Parent = root
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = toggleBtn
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = STROKE; s.Transparency = 0.4; s.Parent = toggleBtn
end

-- Panel (opens to the right of the button)
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 1) -- bottom-left
panel.Size = UDim2.new(0, METRICS.panelW, 0, 0) -- start closed
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Visible = false
panel.Parent = root
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = STROKE; s.Transparency = 0.4; s.Parent = panel
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10); pad.PaddingTop=UDim.new(0,8); pad.PaddingBottom=UDim.new(0,8); pad.Parent = panel
end

-- Header (title + tabs)
local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 34)
header.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(0.5, -6, 1, 0)
title.Font = Enum.Font.GothamSemibold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = TXT
title.Text = "NPC+ Controller"
title.Parent = header

local tabs = Instance.new("Frame")
tabs.Name = "Tabs"
tabs.BackgroundTransparency = 1
tabs.AnchorPoint = Vector2.new(1, 0)
tabs.Position = UDim2.new(1, 0, 0, 0)
tabs.Size = UDim2.new(0.5, 0, 1, 0)
tabs.Parent = header

local tabsLayout = Instance.new("UIListLayout")
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
tabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabsLayout.Padding = UDim.new(0, 6)
tabsLayout.Parent = tabs

local function makeTabButton(text: string)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Size = UDim2.new(0, 74, 0, 24)
	b.Text = text
	b.Font = Enum.Font.GothamSemibold
	b.TextSize = 12
	b.TextColor3 = TXT
	b.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
	b.BackgroundTransparency = 0.2
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = STROKE; s.Transparency = 0.5; s.Parent = b
	b.Parent = tabs
	return b
end

local tabNPC = makeTabButton("NPC")
local tabCFG = makeTabButton("Config")

local function setActiveTabStyle(btn: TextButton, active: boolean)
	btn.BackgroundColor3 = active and ACCENT or Color3.fromRGB(30, 34, 42)
	btn.TextColor3 = active and Color3.fromRGB(255,255,255) or TXT
end

-- Tab containers
local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Position = UDim2.new(0, 0, 0, 36)
body.Size = UDim2.new(1, 0, 1, -38)
body.Parent = panel

-- NPC tab (scroll)
local npcContent = Instance.new("ScrollingFrame")
npcContent.Name = "NPC"
npcContent.BackgroundTransparency = 1
npcContent.Size = UDim2.new(1, 0, 1, 0)
npcContent.CanvasSize = UDim2.new(0, 0, 0, 0)
npcContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
npcContent.ScrollingDirection = Enum.ScrollingDirection.Y
npcContent.ScrollBarThickness = METRICS.scrollbar
npcContent.ScrollBarImageTransparency = 0.2
npcContent.Parent = body

local npcLayout = Instance.new("UIListLayout")
npcLayout.FillDirection = Enum.FillDirection.Vertical
npcLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
npcLayout.VerticalAlignment = Enum.VerticalAlignment.Top
npcLayout.Padding = UDim.new(0, 8)
npcLayout.Parent = npcContent

-- Config tab (no scroll needed for now)
local cfgContent = Instance.new("Frame")
cfgContent.Name = "Config"
cfgContent.BackgroundTransparency = 1
cfgContent.Visible = false
cfgContent.Size = UDim2.new(1, 0, 1, 0)
cfgContent.Parent = body

local cfgLayout = Instance.new("UIListLayout")
cfgLayout.FillDirection = Enum.FillDirection.Vertical
cfgLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
cfgLayout.VerticalAlignment = Enum.VerticalAlignment.Top
cfgLayout.Padding = UDim.new(0, 8)
cfgLayout.Parent = cfgContent

-- NPC selector (exclude "XP")
local npcRow = Instance.new("Frame")
npcRow.BackgroundTransparency = 1
npcRow.Size = UDim2.new(1, 0, 0, 26)
npcRow.Parent = npcContent

local npcName = Instance.new("TextLabel")
npcName.BackgroundTransparency = 1
npcName.Position = UDim2.new(0, 34, 0, 0)
npcName.Size = UDim2.new(1, -68, 1, 0)
npcName.Font = Enum.Font.Gotham
npcName.TextSize = 14
npcName.TextColor3 = TXT
npcName.TextXAlignment = Enum.TextXAlignment.Center
npcName.Text = "--"
npcName.Parent = npcRow

local prevBtn = Instance.new("TextButton")
prevBtn.Text = "<"
prevBtn.AutoButtonColor = true
prevBtn.Size = UDim2.new(0, 26, 1, 0)
prevBtn.Position = UDim2.new(0, 0, 0, 0)
prevBtn.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
prevBtn.TextColor3 = TXT
prevBtn.Font = Enum.Font.GothamSemibold
prevBtn.TextSize = 14
prevBtn.Parent = npcRow
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = prevBtn end

local nextBtn = Instance.new("TextButton")
nextBtn.Text = ">"
nextBtn.AutoButtonColor = true
nextBtn.Size = UDim2.new(0, 26, 1, 0)
nextBtn.AnchorPoint = Vector2.new(1, 0)
nextBtn.Position = UDim2.new(1, 0, 0, 0)
nextBtn.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
nextBtn.TextColor3 = TXT
nextBtn.Font = Enum.Font.GothamSemibold
nextBtn.TextSize = 14
nextBtn.Parent = npcRow
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = nextBtn end

local function makeButton(text: string)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.Size = UDim2.new(1, 0, 0, 28)
	b.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
	b.TextColor3 = TXT
	b.Font = Enum.Font.GothamSemibold
	b.TextSize = 14
	b.Text = text
	b.Parent = npcContent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
	return b
end

local btnPVP = makeButton("Toggle PVP")
local btnDash = makeButton("Toggle Dash")
local btnMove = makeButton("Toggle Move")
local btnReset = makeButton("Reset Position (TP)")

-- NPC list (exclude "XP")
local npcList: {Model} = {}
local selectedIdx = 1
local function refreshList()
	npcList = {}
	local folder = workspace:FindFirstChild("NPC")
	if folder then
		for _, inst in ipairs(folder:GetChildren()) do
			if inst:IsA("Model") and inst:FindFirstChild("Humanoid") and inst.Name ~= "XP" then
				table.insert(npcList, inst)
			end
		end
	end
	if #npcList == 0 then
		npcName.Text = "No NPCs"
	else
		if selectedIdx < 1 or selectedIdx > #npcList then selectedIdx = 1 end
		npcName.Text = npcList[selectedIdx].Name
	end
end
refreshList()

prevBtn.MouseButton1Click:Connect(function()
	if #npcList == 0 then return end
	selectedIdx -= 1
	if selectedIdx < 1 then selectedIdx = #npcList end
	npcName.Text = npcList[selectedIdx].Name
end)
nextBtn.MouseButton1Click:Connect(function()
	if #npcList == 0 then return end
	selectedIdx += 1
	if selectedIdx > #npcList then selectedIdx = 1 end
	npcName.Text = npcList[selectedIdx].Name
end)

local function send(action: string)
	if #npcList == 0 then return end
	local targetName = npcList[selectedIdx].Name
	ControlNPC:FireServer(targetName, action)
end

btnPVP.MouseButton1Click:Connect(function() send("TogglePVP") end)
btnDash.MouseButton1Click:Connect(function() send("ToggleDash") end)
btnMove.MouseButton1Click:Connect(function() send("ToggleMove") end)
btnReset.MouseButton1Click:Connect(function() send("ResetPosition") end)

-- =======================
-- Config tab: toggles (client-only)
-- =======================

local function makeToggleRow(labelText: string, initial: boolean, onChanged: (boolean)->())
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 28)
	row.Parent = cfgContent

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, -90, 1, 0)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 14
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = TXT
	lbl.Text = labelText
	lbl.Parent = row

	local sw = Instance.new("TextButton")
	sw.Name = "Switch"
	sw.AutoButtonColor = false
	sw.AnchorPoint = Vector2.new(1, 0.5)
	sw.Position = UDim2.new(1, 0, 0.5, 0)
	sw.Size = UDim2.new(0, 46, 0, 22)
	sw.Text = ""
	sw.BackgroundColor3 = initial and OK or OFF
	sw.Parent = row
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 11); c.Parent = sw
	end
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = initial and UDim2.new(1, -11, 0.5, 0) or UDim2.new(0, 11, 0.5, 0)
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.BackgroundColor3 = Color3.fromRGB(240,240,240)
	knob.Parent = sw
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 9); c.Parent = knob
		local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = STROKE; s.Transparency = 0.5; s.Parent = knob
	end

	local state = initial
	local function setState(v: boolean, animate: boolean)
		state = v
		local bg = v and OK or OFF
		if animate then
			TweenService:Create(sw, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = bg }):Play()
			local targetPos = v and UDim2.new(1, -11, 0.5, 0) or UDim2.new(0, 11, 0.5, 0)
			TweenService:Create(knob, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = targetPos }):Play()
		else
			sw.BackgroundColor3 = bg
			knob.Position = v and UDim2.new(1, -11, 0.5, 0) or UDim2.new(0, 11, 0.5, 0)
		end
		onChanged(state)
	end

	sw.MouseButton1Click:Connect(function()
		setState(not state, true)
	end)

	return {
		root = row,
		set = setState,
		get = function() return state end
	}
end

-- Helper: enable/disable a ScreenGui in PlayerGui by name
local function setScreenGuiEnabled(guiName: string, enabled: boolean)
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local gui = pg:FindFirstChild(guiName)
	if gui and gui:IsA("ScreenGui") then
		if gui.Enabled ~= enabled then
			gui.Enabled = enabled
		end
	end
end

-- Hitbox visibility toggle
local hitboxVisibility = true -- true = visible
local watcherConn: RBXScriptConnection? = nil

local function nameHasHitbox(s: string?): boolean
	if not s then return false end
	s = string.lower(s)
	return string.find(s, "hitbox") ~= nil
end

local function isHitboxDescendant(inst: Instance): boolean
	local obj: Instance? = inst
	while obj and obj ~= workspace do
		if nameHasHitbox(obj.Name) then return true end
		obj = obj.Parent
	end
	return false
end

local function applyOneHitboxVisibility(inst: Instance, visible: boolean)
	if inst:IsA("BasePart") then
		if isHitboxDescendant(inst) then
			(inst :: BasePart).LocalTransparencyModifier = visible and 0 or 1
		end
	elseif inst:IsA("Highlight") then
		if isHitboxDescendant(inst) then
			inst.Enabled = visible
		end
	elseif inst:IsA("SelectionBox") or inst:IsA("BoxHandleAdornment") or inst:IsA("SphereHandleAdornment") or inst:IsA("ConeHandleAdornment") or inst:IsA("CylinderHandleAdornment") then
		if isHitboxDescendant(inst) then
			pcall(function()
				(inst :: any).Visible = visible
			end)
			if inst:IsA("SelectionBox") then
				(inst :: SelectionBox).Transparency = visible and 0 or 1
			elseif inst:IsA("BoxHandleAdornment") then
				(inst :: BoxHandleAdornment).Transparency = visible and 0 or 1
			elseif inst:IsA("SphereHandleAdornment") then
				(inst :: SphereHandleAdornment).Transparency = visible and 0 or 1
			end
		end
	end
end

local function applyAllHitboxVisibility(visible: boolean)
	local folders: {Instance} = {}
	for _, fname in ipairs({ "Hitbox", "Hitboxes", "HitboxDebug" }) do
		local f = workspace:FindFirstChild(fname)
		if f then table.insert(folders, f) end
	end
	if #folders > 0 then
		for _, f in ipairs(folders) do
			for _, d in ipairs(f:GetDescendants()) do
				applyOneHitboxVisibility(d, visible)
			end
		end
	else
		for _, d in ipairs(workspace:GetDescendants()) do
			if isHitboxDescendant(d) then
				applyOneHitboxVisibility(d, visible)
			end
		end
	end
end

local function startWatcher()
	if watcherConn then watcherConn:Disconnect(); watcherConn = nil end
	watcherConn = workspace.DescendantAdded:Connect(function(inst)
		if not hitboxVisibility and isHitboxDescendant(inst) then
			applyOneHitboxVisibility(inst, false)
		end
	end)
end

startWatcher()

local hitboxToggle = makeToggleRow("Hitboxes visible (client)", hitboxVisibility, function(v)
	hitboxVisibility = v
	player:SetAttribute("ShowHitboxes", v)
	applyAllHitboxVisibility(v)
end)

-- Combat HUD visibility toggle
local defaultCombatHUDVisible = true
local function applyCombatHUDVisibility(visible: boolean)
	setScreenGuiEnabled("CombatHUD", visible)
end

do
	-- Prime from Player attribute or default
	local stored = player:GetAttribute("ShowCombatHUD")
	if typeof(stored) == "boolean" then
		defaultCombatHUDVisible = stored :: boolean
	end

	-- Create the toggle row
	local combatToggle = makeToggleRow("Combat HUD visible (client)", defaultCombatHUDVisible, function(v)
		player:SetAttribute("ShowCombatHUD", v)
		applyCombatHUDVisibility(v)
	end)

	-- Apply current state on startup and when CombatHUD spawns later
	applyCombatHUDVisibility(defaultCombatHUDVisible)

	local pg = player:FindFirstChild("PlayerGui")
	if pg then
		pg.ChildAdded:Connect(function(child)
			if child.Name == "CombatHUD" and child:IsA("ScreenGui") then
				applyCombatHUDVisibility(player:GetAttribute("ShowCombatHUD") ~= false)
			end
		end)
	end

	-- Listen to attribute changes to sync from elsewhere
	player.AttributeChanged:Connect(function(name)
		if name == "ShowCombatHUD" then
			local v = player:GetAttribute("ShowCombatHUD")
			if typeof(v) == "boolean" then
				combatToggle.set(v :: boolean, true)
				applyCombatHUDVisibility(v :: boolean)
			end
		elseif name == "ShowHitboxes" then
			local v = player:GetAttribute("ShowHitboxes")
			if typeof(v) == "boolean" then
				hitboxToggle.set(v :: boolean, true)
				applyAllHitboxVisibility(v :: boolean)
			end
		end
	end)
end

-- PerfHUD visibility toggle (By GekkoH • V.08)
local defaultPerfHUDVisible = true
local function applyPerfHUDVisibility(visible: boolean)
	setScreenGuiEnabled("PerfHUD", visible)
end

do
	-- Prime from Player attribute or default
	local stored = player:GetAttribute("ShowPerfHUD")
	if typeof(stored) == "boolean" then
		defaultPerfHUDVisible = stored :: boolean
	end

	local perfToggle = makeToggleRow("PerfHUD visible (client)", defaultPerfHUDVisible, function(v)
		player:SetAttribute("ShowPerfHUD", v)
		applyPerfHUDVisibility(v)
	end)

	-- Apply current state on startup and when PerfHUD spawns later
	applyPerfHUDVisibility(defaultPerfHUDVisible)

	local pg = player:FindFirstChild("PlayerGui")
	if pg then
		pg.ChildAdded:Connect(function(child)
			if child.Name == "PerfHUD" and child:IsA("ScreenGui") then
				applyPerfHUDVisibility(player:GetAttribute("ShowPerfHUD") ~= false)
			end
		end)
	end

	player.AttributeChanged:Connect(function(name)
		if name == "ShowPerfHUD" then
			local v = player:GetAttribute("ShowPerfHUD")
			if typeof(v) == "boolean" then
				perfToggle.set(v :: boolean, true)
				applyPerfHUDVisibility(v :: boolean)
			end
		end
	end)
end

-- If already stored preference for Hitboxes, load it
do
	local attr = player:GetAttribute("ShowHitboxes")
	if typeof(attr) == "boolean" then
		hitboxVisibility = attr
		hitboxToggle.set(hitboxVisibility, false)
		applyAllHitboxVisibility(hitboxVisibility)
	end
end

-- Tabs behavior
local function showTab(which: "NPC" | "Config")
	local npcActive = which == "NPC"
	npcContent.Visible = npcActive
	cfgContent.Visible = not npcActive
	setActiveTabStyle(tabNPC, npcActive)
	setActiveTabStyle(tabCFG, not npcActive)
end
showTab("NPC")
tabNPC.MouseButton1Click:Connect(function() showTab("NPC") end)
tabCFG.MouseButton1Click:Connect(function() showTab("Config") end)

-- Open/close (height responsive)
local open = false
local function setOpen(state: boolean)
	if open == state then return end
	open = state
	panel.Visible = true
	local targetH = state and METRICS.openH or 0
	TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, METRICS.panelW, 0, targetH)
	}):Play()
	if not state then
		task.delay(0.2, function()
			if not open then panel.Visible = false end
		end)
	end
end

toggleBtn.MouseButton1Click:Connect(function()
	setOpen(not open)
end)

-- Position relative to PlayerFaceHUD (divide offsets by currentScale because root is scaled)
local function placeAboveLifeUI()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end

	local lifeGui = pg:FindFirstChild("PlayerFaceHUD")
	local lifeRoot: Frame? = nil
	if lifeGui and lifeGui:IsA("ScreenGui") then
		lifeRoot = (lifeGui:FindFirstChild("Root") :: Frame?) or nil
	end

	if lifeRoot and lifeRoot:IsA("Frame") and lifeRoot.Visible then
		local lifePos = lifeRoot.AbsolutePosition
		local leftX = lifePos.X + POS.leftInset
		local aboveY = lifePos.Y - POS.spaceAboveLife

		-- Divide by scale because toggleBtn/panel live under a scaled root
		toggleBtn.Position = UDim2.fromOffset(math.floor(leftX / currentScale + 0.5), math.floor(aboveY / currentScale + 0.5))
		panel.Position = UDim2.fromOffset(
			math.floor((leftX + toggleBtn.Size.X.Offset + POS.panelGap) / currentScale + 0.5),
			math.floor(aboveY / currentScale + 0.5)
		)
	else
		-- Fallback bottom-left
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local x = POS.fallbackLeft
		local y = vp.Y - POS.fallbackBottom
		toggleBtn.Position = UDim2.fromOffset(math.floor(x / currentScale + 0.5), math.floor(y / currentScale + 0.5))
		panel.Position = UDim2.fromOffset(
			math.floor((x + toggleBtn.Size.X.Offset + POS.panelGap) / currentScale + 0.5),
			math.floor(y / currentScale + 0.5)
		)
	end
end

local function applyResponsive()
	computeMetrics()
	uiScale.Scale = currentScale
	-- Sizes
	toggleBtn.Size = UDim2.fromOffset(METRICS.btn, METRICS.btn)
	panel.Size = UDim2.new(0, METRICS.panelW, panel.Size.Y.Scale, panel.Size.Y.Offset)
	npcContent.ScrollBarThickness = METRICS.scrollbar
	-- Re-place after size/scale changes
	placeAboveLifeUI()
end

-- Hook PlayerFaceHUD signals for re-placement
local function hookLifeSignals()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local lifeGui = pg:FindFirstChild("PlayerFaceHUD")
	if lifeGui and lifeGui:IsA("ScreenGui") then
		local lifeRoot = lifeGui:FindFirstChild("Root")
		if lifeRoot and lifeRoot:IsA("Frame") then
			lifeRoot:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeAboveLifeUI)
			lifeRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeAboveLifeUI)
			lifeRoot:GetPropertyChangedSignal("Visible"):Connect(placeAboveLifeUI)
		end
	end
end

-- Viewport listeners
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(function()
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				applyResponsive()
			end)
			applyResponsive()
		end
	end)
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		applyResponsive()
	end)
end

-- Workspace NPC updates (exclude XP)
workspace.ChildAdded:Connect(function(child)
	if child.Name == "NPC" then task.defer(refreshList) end
end)
workspace.ChildRemoved:Connect(function(child)
	if child.Name == "NPC" then task.defer(refreshList) end
end)
if workspace:FindFirstChild("NPC") then
	workspace.NPC.ChildAdded:Connect(function(inst) if inst:IsA("Model") then task.defer(refreshList) end end)
	workspace.NPC.ChildRemoved:Connect(function(inst) if inst:IsA("Model") then task.defer(refreshList) end end)
end

-- Initial pass
applyResponsive()
placeAboveLifeUI()
hookLifeSignals()

-- Ensure final placement after one frame (anchors settled)
RunService.Heartbeat:Wait()
placeAboveLifeUI()
