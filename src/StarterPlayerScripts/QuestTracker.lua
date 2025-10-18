--!strict
-- QuestTracker: muestra "Kill Bandit 0/1" en la esquina superior izquierda al tener la misión activa.
-- - Cuando la misión queda lista (ready), cambia a 1/1 y se oculta suavemente.
-- - Reacciona a MissionProgress (server) y consulta el estado al iniciar sesión.
-- - Aparece/desaparece con tween.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")
local MissionStatus: RemoteFunction? = Remotes:FindFirstChild("MissionStatus") :: RemoteFunction?
local MissionProgress: RemoteEvent? = Remotes:FindFirstChild("MissionProgress") :: RemoteEvent?

local MISSION_ID = "BanditIdea"
local TARGET_NAME = "Bandit"

type Tracker = { Screen: ScreenGui, Root: Frame, Label: TextLabel }
local tracker: Tracker? = nil
local visibleState: "hidden" | "shown" | "done" = "hidden"

local function build(): Tracker
	local screen = Instance.new("ScreenGui")
	screen.Name = "QuestTracker"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false

	local inset = GuiService:GetGuiInset()
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromOffset(12, inset.Y + 10)
	root.Size = UDim2.fromOffset(220, 32)
	root.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = screen

	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = root
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = Color3.fromRGB(40, 44, 52); s.Transparency = 1; s.Parent = root

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamSemibold
	lbl.TextSize = 13
	lbl.TextColor3 = Color3.fromRGB(220, 230, 245)
	lbl.TextTransparency = 1
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Text = ("Kill %s 0/1"):format(TARGET_NAME)
	lbl.Position = UDim2.fromOffset(10, 0)
	lbl.Parent = root

	return { Screen = screen, Root = root, Label = lbl }
end

local function ensureShown(current: number)
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	if not tracker then
		tracker = build()
		tracker.Screen.Parent = pg
	end
	tracker.Label.Text = ("Kill %s %d/1"):format(TARGET_NAME, current)
	-- Aparecer
	local ti = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local stroke = tracker.Root:FindFirstChildOfClass("UIStroke")
	TweenService:Create(tracker.Root, ti, { BackgroundTransparency = 0.25 }):Play()
	if stroke then TweenService:Create(stroke, ti, { Transparency = 0.4 }):Play() end
	TweenService:Create(tracker.Label, ti, { TextTransparency = 0 }):Play()
	visibleState = "shown"
end

local function fadeOutAndDestroy()
	if not tracker then return end
	local ti = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local stroke = tracker.Root:FindFirstChildOfClass("UIStroke")
	TweenService:Create(tracker.Root, ti, { BackgroundTransparency = 1 }):Play()
	if stroke then TweenService:Create(stroke, ti, { Transparency = 1 }):Play() end
	TweenService:Create(tracker.Label, ti, { TextTransparency = 1 }):Play()
	task.delay(0.2, function()
		if tracker then
			local s = tracker.Screen
			tracker = nil
			visibleState = "hidden"
			if s then s:Destroy() end
		end
	end)
end

local function markDoneAndHide()
	if visibleState ~= "shown" or not tracker then return end
	visibleState = "done"
	tracker.Label.Text = ("Kill %s 1/1"):format(TARGET_NAME)
	tracker.Label.TextColor3 = Color3.fromRGB(100, 230, 140)
	task.delay(1.0, fadeOutAndDestroy)
end

-- Estado inicial
local function applyInitial()
	if not MissionStatus then return end
	local ok, res = pcall(function()
		return MissionStatus:InvokeServer({ missionId = MISSION_ID })
	end)
	if not ok or not res then return end
	local st = res.state
	if st == "active" then
		ensureShown(0)
	elseif st == "ready" then
		ensureShown(1)
		markDoneAndHide()
	end
end

-- Eventos
if MissionProgress then
	MissionProgress.OnClientEvent:Connect(function(payload)
		if not payload or payload.missionId ~= MISSION_ID then return end
		if payload.state == "active" then
			ensureShown(0)
		elseif payload.state == "ready" then
			ensureShown(1)
			markDoneAndHide()
		elseif payload.state == "claimed" then
			fadeOutAndDestroy()
		end
	end)
end

applyInitial()
