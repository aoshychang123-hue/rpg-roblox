--!strict
-- Client: NPC "XP" Dialogue (Typewriter + Secret + Quest "More XP")
-- - First time Yes gives free XP (never again). Next times, offers the repeatable "More XP" mission.
-- - If mission is ready: Yes claims reward.
-- - If mission is active: Yes reminds the objective.
-- - When accepting the mission, the NPC finishes speaking (typewriter) BEFORE closing; then a "Go" button appears to close.
-- - Buttons are centered, compact, and appear only after the typewriter finishes.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local function cam(): Camera return workspace.CurrentCamera end

local Remotes = RS:WaitForChild("Remotes")
local NPCXPRequest = Remotes:WaitForChild("NPCXPRequest") :: RemoteFunction

-- Mission remotes (optional but expected for quest)
local MissionRequest = Remotes:FindFirstChild("MissionRequest") :: RemoteFunction?
local MissionStatus  = Remotes:FindFirstChild("MissionStatus")  :: RemoteFunction?
local MissionClaim   = Remotes:FindFirstChild("MissionClaim")   :: RemoteFunction?

-- Optional input lock from server
local NPCDialogState: RemoteEvent? = Remotes:FindFirstChild("NPCDialogState") :: RemoteEvent?

local MISSION_ID = "BanditIdea"
local MISSION_TARGET_NAME = "Bandit"

-- Input lock
local ACTION_NAME = "Dialog_BlockAllInputs"
local locked = false

local Controls = (function()
	local pm = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
	local mod = require(pm)
	return mod:GetControls()
end)()

local function setCharAttr(v: boolean)
	local ch = player.Character
	if ch then ch:SetAttribute("IsInDialog", v) end
end

local function sinkAllInputs(_, _)
	return Enum.ContextActionResult.Sink
end

local function lockInputs()
	if locked then return end
	locked = true
	Controls:Disable()
	ContextActionService:BindActionAtPriority(ACTION_NAME, sinkAllInputs, false, 3000)
	setCharAttr(true)
end

local function unlockInputs()
	if not locked then return end
	locked = false
	ContextActionService:UnbindAction(ACTION_NAME)
	Controls:Enable()
	setCharAttr(false)
end

_G.DialogInputLock = {
	Lock = lockInputs,
	Unlock = unlockInputs,
	IsLocked = function() return locked end,
}

if NPCDialogState then
	NPCDialogState.OnClientEvent:Connect(function(state: boolean)
		if state then lockInputs() else unlockInputs() end
	end)
end

player.CharacterAdded:Connect(function(ch) ch:SetAttribute("IsInDialog", locked) end)

-- UI
type UIRefs = {
	Screen: ScreenGui,
	Root: Frame,
	Msg: TextLabel,
	Row: Frame,
	BtnYes: TextButton,
	BtnNo: TextButton,
	BtnSecret: TextButton,
	BtnMore: TextButton,
	BtnGo: TextButton,
	Dim: Frame,
}

local function styleButton(b: TextButton)
	b.AutoButtonColor = true
	b.Size = UDim2.new(0, 92, 0, 28)
	b.Font = Enum.Font.GothamSemibold
	b.TextSize = 13
	b.TextColor3 = Color3.fromRGB(255,255,255)
	b.BackgroundTransparency = 1
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = Color3.fromRGB(40,44,52); s.Transparency = 1; s.Parent = b
	local scale = Instance.new("UIScale"); scale.Scale = 0.94; scale.Parent = b
end

local function buildUI(): UIRefs
	local screen = Instance.new("ScreenGui")
	screen.Name = "NPC_XP_Dialog"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.fromRGB(0,0,0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1,1)
	dim.Parent = screen

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -110)
	root.Size = UDim2.new(0, 480, 0, 154)
	root.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	root.BackgroundTransparency = 0.2
	root.BorderSizePixel = 0
	root.Parent = screen
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = root
		local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = Color3.fromRGB(40,44,52); s.Transparency = 0.4; s.Parent = root
		local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12); pad.PaddingTop = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10); pad.Parent = root
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 20)
	title.Font = Enum.Font.GothamSemibold
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(230,235,255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "XP"
	title.Parent = root

	local msg = Instance.new("TextLabel")
	msg.Name = "Msg"
	msg.BackgroundTransparency = 1
	msg.Size = UDim2.new(1, 0, 0, 72)
	msg.Position = UDim2.fromOffset(0, 26)
	msg.Font = Enum.Font.Gotham
	msg.TextWrapped = true
	msg.TextSize = 16
	msg.TextColor3 = Color3.fromRGB(220,230,245)
	msg.TextXAlignment = Enum.TextXAlignment.Left
	msg.TextYAlignment = Enum.TextYAlignment.Top
	msg.Text = ""
	msg.Parent = root

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -8)
	row.Size = UDim2.new(1, -8, 0, 32)
	row.BackgroundTransparency = 1
	row.Parent = root

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.Parent = row

	-- Order: More XP, Yes, No, ???
	local btnMore = Instance.new("TextButton"); btnMore.Text = "More XP"; btnMore.BackgroundColor3 = Color3.fromRGB(90, 140, 255); btnMore.LayoutOrder = 1; btnMore.Parent = row
	styleButton(btnMore)

	local btnYes = Instance.new("TextButton"); btnYes.Text = "Yes"; btnYes.BackgroundColor3 = Color3.fromRGB(60, 200, 110); btnYes.LayoutOrder = 2; btnYes.Parent = row
	styleButton(btnYes)

	local btnNo = Instance.new("TextButton"); btnNo.Text = "No"; btnNo.BackgroundColor3 = Color3.fromRGB(200, 80, 80); btnNo.LayoutOrder = 3; btnNo.Parent = row
	styleButton(btnNo)

	local btnSecret = Instance.new("TextButton"); btnSecret.Text = "???"; btnSecret.BackgroundColor3 = Color3.fromRGB(100, 104, 120); btnSecret.LayoutOrder = 4; btnSecret.Parent = row
	styleButton(btnSecret)

	local btnGo = Instance.new("TextButton")
	btnGo.Text = "Go"
	btnGo.Visible = false
	btnGo.BackgroundColor3 = Color3.fromRGB(60, 200, 110)
	btnGo.LayoutOrder = 5
	btnGo.Parent = row
	styleButton(btnGo)

	TweenService:Create(dim, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.35 }):Play()

	return { Screen = screen, Root = root, Msg = msg, Row = row, BtnYes = btnYes, BtnNo = btnNo, BtnSecret = btnSecret, BtnMore = btnMore, BtnGo = btnGo, Dim = dim }
end

local function tweenButtonAppear(b: TextButton)
	local s = b:FindFirstChildOfClass("UIStroke")
	local sc = b:FindFirstChildOfClass("UIScale")
	b.BackgroundTransparency = 1
	b.TextTransparency = 1
	if sc then sc.Scale = 0.9 end
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(b, ti, { BackgroundTransparency = 0.2, TextTransparency = 0 }):Play()
	if s then TweenService:Create(s, ti, { Transparency = 0.4 }):Play() end
	if sc then TweenService:Create(sc, ti, { Scale = 1.0 }):Play() end
end

local function tweenButtonDisappear(b: TextButton)
	local s = b:FindFirstChildOfClass("UIStroke")
	local sc = b:FindFirstChildOfClass("UIScale")
	local ti = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(b, ti, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	if s then TweenService:Create(s, ti, { Transparency = 1 }):Play() end
	if sc then TweenService:Create(sc, ti, { Scale = 0.96 }):Play() end
end

local function setButtonsVisible(ui: UIRefs, show: boolean, which: {TextButton}?)
	local buttons = which or { ui.BtnMore, ui.BtnYes, ui.BtnNo, ui.BtnSecret }
	for _, b in ipairs(buttons) do
		b.Active = show
		b.AutoButtonColor = show
		if show then tweenButtonAppear(b) else tweenButtonDisappear(b) end
	end
end

-- Camera helpers
type PrevCam = { type: Enum.CameraType, subject: any, cf: CFrame, fov: number }
local camGuardConn: RBXScriptConnection? = nil

local function focusOnNPC(npc: Model): PrevCam?
	local head = npc:FindFirstChild("Head") :: BasePart?
	local playerHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not head or not playerHRP then return nil end

	local c = cam()
	local prev: PrevCam = { type = c.CameraType, subject = c.CameraSubject, cf = c.CFrame, fov = c.FieldOfView }

	c.CameraType = Enum.CameraType.Scriptable
	c.CameraSubject = nil

	if camGuardConn then camGuardConn:Disconnect() end
	camGuardConn = RunService.RenderStepped:Connect(function()
		local cc = cam()
		if cc.CameraType ~= Enum.CameraType.Scriptable then
			cc.CameraType = Enum.CameraType.Scriptable
			cc.CameraSubject = nil
		end
	end)

	local lookAt = head.Position + Vector3.new(0, 0.7, 0)
	local dirToPlayer = (playerHRP.Position - head.Position)
	local forward = Vector3.new(dirToPlayer.X, 0, dirToPlayer.Z)
	forward = (forward.Magnitude > 0) and forward.Unit or head.CFrame.LookVector
	local camPos = lookAt + forward * 4 + Vector3.new(0, 0.2, 0)
	local target = CFrame.lookAt(camPos, lookAt)

	c.CFrame = target
	c.FieldOfView = 50
	TweenService:Create(c, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target, FieldOfView = 50 }):Play()

	return prev
end

local function restoreCamera(prev: PrevCam?)
	local c = cam()
	local subject: Instance? = prev and prev.subject or nil
	if (not subject) or (typeof(subject) == "Instance" and subject.Parent == nil) then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		subject = hum
	end
	local targetFov = (prev and prev.fov) or 70
	local targetCF = prev and prev.cf

	if targetCF then
		local tw = TweenService:Create(c, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = targetCF, FieldOfView = targetFov
		})
		tw.Completed:Connect(function()
			if camGuardConn then camGuardConn:Disconnect() end
			c.CameraType = Enum.CameraType.Custom
			if subject then c.CameraSubject = subject end
		end)
		tw:Play()
	else
		if camGuardConn then camGuardConn:Disconnect() end
		c.CameraType = Enum.CameraType.Custom
		if subject then c.CameraSubject = subject end
		c.FieldOfView = targetFov
	end
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if camGuardConn then camGuardConn:Disconnect() end
end)

-- Typewriter (blocking)
local typeToken = 0
local function typewriteBlocking(label: TextLabel, text: string, cps: number?)
	typeToken += 1
	local my = typeToken
	label.Text = ""
	local speed = cps or 48
	local dt = 1 / math.max(8, speed)
	for i = 1, #text do
		if my ~= typeToken then return end
		label.Text = string.sub(text, 1, i)
		local ch = string.sub(text, i, i)
		local extra = (ch == "." or ch == "!" or ch == "?") and 0.06 or (ch == "," and 0.03 or 0)
		task.wait(dt + extra)
	end
end

-- Mission helpers
local function missionSupported(): boolean
	return MissionRequest ~= nil and MissionStatus ~= nil and MissionClaim ~= nil
end

local function queryMission(): string
	if not missionSupported() then return "none" end
	local ok, res = pcall(function()
		return (MissionStatus :: RemoteFunction):InvokeServer({ missionId = MISSION_ID })
	end)
	if not ok or not res then return "none" end
	return res.state or "none"
end

local function hasFreeXPLocal(): boolean
	return player:GetAttribute("FreeXPGiven") == true
end
local function setFreeXPLocal(v: boolean)
	player:SetAttribute("FreeXPGiven", v)
end

-- NPC lookup
local function findNPCXP(): Model?
	local nf = workspace:FindFirstChild("NPC")
	if not nf then return nil end
	local m = nf:FindFirstChild("XP")
	return (m and m:IsA("Model")) and m or nil
end

local function isPromptFromNPCXP(prompt: ProximityPrompt): boolean
	local obj: Instance? = prompt
	while obj and obj ~= workspace do
		if obj.Name == "XP" and obj:IsA("Model") and obj.Parent == (workspace:FindFirstChild("NPC")) then
			return true
		end
		obj = obj.Parent
	end
	return false
end

-- Dialog
local busy = false
local function startDialog()
	if busy then return end
	local npc = findNPCXP()
	if not npc then return end

	busy = true
	lockInputs()
	local prevCam = focusOnNPC(npc)

	local ui = buildUI()
	ui.Screen.Parent = player:WaitForChild("PlayerGui")

	-- Initial line by mission state
	local st = queryMission()
	local initial = "Do you want some XP?"
	if st == "ready" then
		initial = "You're back! Do you want to claim your reward?"
	elseif st == "active" then
		initial = string.format("Objective: defeat the %s and come back to claim.", MISSION_TARGET_NAME)
	end

	setButtonsVisible(ui, false)
	typewriteBlocking(ui.Msg, initial)
	setButtonsVisible(ui, true)

	local finished = false
	local distanceStop = false
	local diedConn: RBXScriptConnection?

	local function finish()
		if finished then return end
		finished = true
		distanceStop = true

		if diedConn then diedConn:Disconnect() end

		typeToken += 1
		restoreCamera(prevCam)
		unlockInputs()

		setButtonsVisible(ui, false, { ui.BtnMore, ui.BtnYes, ui.BtnNo, ui.BtnSecret, ui.BtnGo })

		local ti = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(ui.Dim, ti, { BackgroundTransparency = 1 }):Play()
		for _, d in ipairs(ui.Root:GetDescendants()) do
			if d:IsA("UIStroke") then
				TweenService:Create(d, ti, { Transparency = 1 }):Play()
			elseif d:IsA("TextLabel") or d:IsA("TextButton") then
				TweenService:Create(d, ti, { TextTransparency = 1 }):Play()
			end
		end
		local f = TweenService:Create(ui.Root, ti, { BackgroundTransparency = 1 })
		f.Completed:Connect(function()
			if ui.Screen then ui.Screen:Destroy() end
			busy = false
		end)
		f:Play()
	end

	-- Close if you die or walk away (lower frequency polling)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then diedConn = hum.Died:Connect(finish) end
	task.spawn(function()
		while not distanceStop do
			task.wait(0.12)
			if distanceStop then break end
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local npcHRP = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp or not npcHRP then finish() break end
			if (hrp.Position - npcHRP.Position).Magnitude > 30 then finish() break end
		end
	end)

	-- Anti-spam
	local clicked = false
	local function softLock(): boolean
		if clicked then
			typeToken += 1
			setButtonsVisible(ui, false)
			typewriteBlocking(ui.Msg, "Why are you spamming, buddy?")
			task.delay(0.9, finish)
			return true
		end
		clicked = true
		setButtonsVisible(ui, false)
		return false
	end
	local function unlockButtons(...)
		clicked = false
		local lst = table.pack(...)
		if lst.n > 0 then
			local buttons: {TextButton} = {}
			for i = 1, lst.n do buttons[i] = lst[i] end
			setButtonsVisible(ui, true, buttons)
		else
			setButtonsVisible(ui, true)
		end
	end

	-- Yes (mission-first logic)
	ui.BtnYes.MouseButton1Click:Connect(function()
		if softLock() then return end

		local state = queryMission()

		if state == "ready" and missionSupported() then
			typewriteBlocking(ui.Msg, "Claiming your reward...")
			local ok2, res2 = pcall(function()
				return (MissionClaim :: RemoteFunction):InvokeServer({ missionId = MISSION_ID })
			end)
			if ok2 and res2 and res2.ok then
				typewriteBlocking(ui.Msg, string.format("+%d XP! Level %d (%d/%d)", res2.rewardXP or 0, res2.level or 0, res2.xp or 0, res2.required or 0))
			else
				typewriteBlocking(ui.Msg, "Hmm... not now.")
			end
			task.delay(1.1, finish)
			return
		elseif state == "active" then
			typewriteBlocking(ui.Msg, string.format("Objective: defeat the %s and come back to claim.", MISSION_TARGET_NAME))
			task.delay(1.0, finish)
			return
		end

		-- No mission ready/active: try free XP once, else offer mission
		if hasFreeXPLocal() then
			typewriteBlocking(ui.Msg, "I can't give you more for free, but I have a mission for you. Do you want it?")
			ui.BtnYes.Text = "Accept"
			ui.BtnNo.Text = "Decline"
			unlockButtons(ui.BtnYes, ui.BtnNo)

			local conY: RBXScriptConnection?
			local conN: RBXScriptConnection?

			conY = ui.BtnYes.MouseButton1Click:Connect(function()
				if softLock() then return end
				if missionSupported() then
					pcall(function()
						(MissionRequest :: RemoteFunction):InvokeServer({ action = "accept", missionId = MISSION_ID })
					end)
				end
				typewriteBlocking(ui.Msg, "Mission accepted. Defeat the Bandit, then press 'Go'.")
				ui.BtnGo.Visible = true
				unlockButtons(ui.BtnGo)
				ui.BtnGo.MouseButton1Click:Connect(function()
					if softLock() then return end
					finish()
				end)
				if conY then conY:Disconnect() end
				if conN then conN:Disconnect() end
			end)

			conN = ui.BtnNo.MouseButton1Click:Connect(function()
				if softLock() then return end
				typewriteBlocking(ui.Msg, "Maybe later.")
				task.delay(0.9, finish)
				if conY then conY:Disconnect() end
				if conN then conN:Disconnect() end
			end)
			return
		end

		local ok, res = pcall(NPCXPRequest.InvokeServer, NPCXPRequest)
		if ok and res and res.ok == true then
			setFreeXPLocal(true)
			typewriteBlocking(ui.Msg, "Here you go...")
			task.delay(0.9, finish)
		else
			typewriteBlocking(ui.Msg, "I can't give you more for free, but I have a mission for you. Do you want it?")
			ui.BtnYes.Text = "Accept"
			ui.BtnNo.Text = "Decline"
			unlockButtons(ui.BtnYes, ui.BtnNo)

			local conY: RBXScriptConnection?
			local conN: RBXScriptConnection?

			conY = ui.BtnYes.MouseButton1Click:Connect(function()
				if softLock() then return end
				if missionSupported() then
					pcall(function()
						(MissionRequest :: RemoteFunction):InvokeServer({ action = "accept", missionId = MISSION_ID })
					end)
				end
				typewriteBlocking(ui.Msg, "Mission accepted. Defeat the Bandit, then press 'Go'.")
				ui.BtnGo.Visible = true
				unlockButtons(ui.BtnGo)
				ui.BtnGo.MouseButton1Click:Connect(function()
					if softLock() then return end
					finish()
				end)
				if conY then conY:Disconnect() end
				if conN then conN:Disconnect() end
			end)

			conN = ui.BtnNo.MouseButton1Click:Connect(function()
				if softLock() then return end
				typewriteBlocking(ui.Msg, "Maybe later.")
				task.delay(0.9, finish)
				if conY then conY:Disconnect() end
				if conN then conN:Disconnect() end
			end)
		end
	end)

	-- No
	ui.BtnNo.MouseButton1Click:Connect(function()
		if softLock() then return end
		typewriteBlocking(ui.Msg, "Oh... Boomer")
		task.delay(0.9, finish)
	end)

	-- Secret
	ui.BtnSecret.MouseButton1Click:Connect(function()
		if softLock() then return end
		typewriteBlocking(ui.Msg, "Kippy is The best animator")
		task.delay(1.0, finish)
	end)

	-- More XP direct flow
	ui.BtnMore.MouseButton1Click:Connect(function()
		if softLock() then return end
		if not missionSupported() then
			typewriteBlocking(ui.Msg, "Hmm... not available right now.")
			task.delay(0.9, finish)
			return
		end

		local state = queryMission()
		if state == "ready" then
			typewriteBlocking(ui.Msg, "Claiming your reward...")
			local ok2, res2 = pcall(function()
				return (MissionClaim :: RemoteFunction):InvokeServer({ missionId = MISSION_ID })
			end)
			if ok2 and res2 and res2.ok then
				typewriteBlocking(ui.Msg, string.format("+%d XP! Level %d (%d/%d)", res2.rewardXP or 0, res2.level or 0, res2.xp or 0, res2.required or 0))
			else
				typewriteBlocking(ui.Msg, "Hmm... not now.")
			end
			task.delay(1.1, finish)
			return
		elseif state == "active" then
			typewriteBlocking(ui.Msg, string.format("Objective: defeat the %s and come back to claim.", MISSION_TARGET_NAME))
			task.delay(1.0, finish)
			return
		end

		typewriteBlocking(ui.Msg, "I saw a bandit who stole my idea. Go finish him and come back to claim your reward. Do you accept?")
		ui.BtnYes.Text = "Accept"
		ui.BtnNo.Text = "Decline"
		unlockButtons(ui.BtnYes, ui.BtnNo)

		local conY: RBXScriptConnection?
		local conN: RBXScriptConnection?

		conY = ui.BtnYes.MouseButton1Click:Connect(function()
			if softLock() then return end
			pcall(function()
				(MissionRequest :: RemoteFunction):InvokeServer({ action = "accept", missionId = MISSION_ID })
			end)
			typewriteBlocking(ui.Msg, "Mission accepted. Defeat the Bandit, then press 'Go'.")
			ui.BtnGo.Visible = true
			unlockButtons(ui.BtnGo)
			ui.BtnGo.MouseButton1Click:Connect(function()
				if softLock() then return end
				finish()
			end)
			if conY then conY:Disconnect() end
			if conN then conN:Disconnect() end
		end)

		conN = ui.BtnNo.MouseButton1Click:Connect(function()
			if softLock() then return end
			typewriteBlocking(ui.Msg, "Maybe later.")
			task.delay(0.9, finish)
			if conY then conY:Disconnect() end
			if conN then conN:Disconnect() end
		end)
	end)
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, plr)
	if plr ~= player then return end
	if not isPromptFromNPCXP(prompt) then return end
	startDialog()
end)
