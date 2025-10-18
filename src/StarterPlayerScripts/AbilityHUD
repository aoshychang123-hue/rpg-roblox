--!strict
-- AbilityHUD actualizado: deshabilita teclas sin skill, muestra DisplayName desde AbilitySets/ConfigResolver
-- y resetea cooldowns locales al cambiar de arma (WeaponType|WeaponId|Moveset).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CooldownEvent: RemoteEvent = Remotes:WaitForChild("CooldownEvent")

local Modules = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Modules")
local ConfigResolver = require(Modules:WaitForChild("ConfigResolver"))

local player = Players.LocalPlayer

-- Paleta
local BLURPLE = Color3.fromRGB(88, 101, 242)
local BG_PANEL = Color3.fromRGB(16, 18, 22)
local CARD_BG = Color3.fromRGB(28, 31, 38)
local TEXT_PRIMARY = Color3.fromRGB(228, 232, 240)
local TEXT_DISABLED = Color3.fromRGB(120, 128, 140)
local BAR_BG = Color3.fromRGB(22, 25, 31)
local BAR_BG_DISABLED = Color3.fromRGB(18, 20, 25)

local ORDER = { "Z", "X", "C", "V" }

type SlotState = { endAt: number, duration: number }
local cdState: { [string]: SlotState } = {}

local gui: ScreenGui
local frame: Frame
local nameLabels: { [string]: TextLabel } = {}
local fills: { [string]: Frame } = {}
local rowFrames: { [string]: Frame } = {}

local charConns: { RBXScriptConnection } = {}
local hbConn: RBXScriptConnection?
local available: { [string]: boolean } = {}

-- Firma del perfil de arma actual para resetear cooldowns al cambiar
local lastSignature: string? = nil

-- Helpers
local function tween(obj: Instance, t: number, props: {}, easing: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local info = TweenInfo.new(t, easing or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(obj, info, props); tw:Play(); return tw
end

local function round(inst: GuiObject, px: number)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, px); c.Parent = inst
end

local function currentSignature(): string
	local ch = player.Character
	if not ch then return "NoChar" end
	local wt = tostring(ch:GetAttribute("WeaponType") or "Fists")
	local wid = tostring(ch:GetAttribute("WeaponId") or "")
	local mv = tostring(ch:GetAttribute("Moveset") or "MainCharacter")
	return wt .. "|" .. wid .. "|" .. mv
end

local function zeroAllFills()
	for _, key in ipairs(ORDER) do
		local fill = fills[key]
		if fill then fill.Size = UDim2.new(0, 0, 1, 0) end
	end
end

local function resetCooldownsIfProfileChanged()
	local sig = currentSignature()
	if sig ~= lastSignature then
		lastSignature = sig
		-- Limpia cooldowns locales y barras
		table.clear(cdState)
		zeroAllFills()
	end
end

local function readAvailabilityAndNames()
	local names: { [string]: string } = { Z = "Skill Z", X = "Skill X", C = "Skill C", V = "Skill V" }
	local ch = player.Character
	if not ch then
		for _, k in ipairs(ORDER) do available[k] = false end
		return names
	end

	-- Si cambia el perfil, resetea cooldowns
	resetCooldownsIfProfileChanged()

	local ok, cfg = pcall(function() return ConfigResolver.get(ch) end)
	if ok and cfg and cfg.Abilities then
		for _, k in ipairs(ORDER) do available[k] = false end
		for k, ab in pairs(cfg.Abilities) do
			local K = string.upper(tostring(k))
			if names[K] ~= nil and type(ab) == "table" then
				available[K] = true
				local label = ab.DisplayName or ab.Name
				if label and #tostring(label) > 0 then
					names[K] = tostring(label)
				end
			end
		end
	else
		for _, k in ipairs(ORDER) do available[k] = false end
	end
	return names
end

local function applyRowEnabled(key: string, enabled: boolean)
	local lbl = nameLabels[key]
	local row = rowFrames[key]
	local fill = fills[key]
	if not (lbl and row and fill) then return end
	lbl.TextColor3 = enabled and TEXT_PRIMARY or TEXT_DISABLED
	local barBG = row:FindFirstChild("BarBG") :: Frame?
	if barBG then barBG.BackgroundColor3 = enabled and BAR_BG or BAR_BG_DISABLED end
	if not enabled then
		fill.Size = UDim2.new(0, 0, 1, 0)
	end
end

-- UI
local function buildUI()
	gui = Instance.new("ScreenGui")
	gui.Name = "AbilityHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 2
	gui.Parent = player:WaitForChild("PlayerGui")

	frame = Instance.new("Frame")
	frame.Name = "AbilityColumn"
	frame.AnchorPoint = Vector2.new(1, 0.5)
	frame.Position = UDim2.new(1, -20, 0.52, 0)
	frame.Size = UDim2.new(0, 240, 0, 4 * 42 + 3 * 8 + 12)
	frame.BackgroundColor3 = BG_PANEL
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	round(frame, 10)

	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.new(1, -12, 1, -12)
	inner.Position = UDim2.new(0, 6, 0, 6)
	inner.Parent = frame

	for i, key in ipairs(ORDER) do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. key
		row.Size = UDim2.new(1, 0, 0, 42)
		row.Position = UDim2.new(0, 0, 0, (i - 1) * (42 + 8))
		row.BackgroundColor3 = CARD_BG
		row.BorderSizePixel = 0
		row.Parent = inner
		round(row, 8)
		rowFrames[key] = row

		local line = Instance.new("Frame")
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, 22)
		line.Position = UDim2.new(0, 0, 0, 3)
		line.Parent = row

		local keyChip = Instance.new("TextLabel")
		keyChip.Name = "Key"
		keyChip.Text = key
		keyChip.Font = Enum.Font.GothamBold
		keyChip.TextSize = 14
		keyChip.TextColor3 = Color3.fromRGB(245, 247, 255)
		keyChip.BackgroundColor3 = BLURPLE
		keyChip.Size = UDim2.new(0, 24, 0, 18)
		keyChip.Position = UDim2.new(0, 4, 0, 2)
		keyChip.BorderSizePixel = 0
		keyChip.Parent = line
		round(keyChip, 6)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "Name"
		nameLbl.Text = "Skill " .. key
		nameLbl.Font = Enum.Font.GothamSemibold
		nameLbl.TextSize = 14
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.TextColor3 = TEXT_PRIMARY
		nameLbl.BackgroundTransparency = 1
		nameLbl.Size = UDim2.new(1, -24 - 8 - 6, 1, 0)
		nameLbl.Position = UDim2.new(0, 24 + 8, 0, 0)
		nameLbl.Parent = line
		nameLabels[key] = nameLbl

		local barBG = Instance.new("Frame")
		barBG.Name = "BarBG"
		barBG.Size = UDim2.new(1, -8, 0, 6)
		barBG.Position = UDim2.new(0, 4, 1, -8)
		barBG.BackgroundColor3 = BAR_BG
		barBG.BorderSizePixel = 0
		barBG.Parent = row
		round(barBG, 4)

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = BLURPLE
		fill.BorderSizePixel = 0
		fill.Parent = barBG
		round(fill, 4)
		fills[key] = fill
	end

	frame.Visible = true
	frame.Position = UDim2.new(1, 40, 0.52, 0)
	tween(frame, 0.18, { Position = UDim2.new(1, -20, 0.52, 0) })
end

-- Update de barra por cooldown
local function ensureUpdater()
	if hbConn then return end
	hbConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, key in ipairs(ORDER) do
			local st = cdState[key]
			local fill = fills[key]
			if not available[key] then
				if fill and fill.Size.X.Scale ~= 0 then
					fill.Size = UDim2.new(0, 0, 1, 0)
				end
			elseif st and st.endAt and st.duration and st.duration > 0 then
				local remaining = math.max(0, st.endAt - now)
				local elapsed = math.clamp(st.duration - remaining, 0, st.duration)
				local frac = elapsed / st.duration
				if fill then fill.Size = UDim2.new(frac, 0, 1, 0) end
			else
				if fill and fill.Size.X.Scale ~= 0 then
					fill.Size = UDim2.new(0, 0, 1, 0)
				end
			end
		end
	end)
end

-- Remoto de cooldown
local function normalizeKey(name: any): string?
	if typeof(name) ~= "string" or #name == 0 then return nil end
	local k = name
	local i = string.find(k, ":", 1, true)
	if i then
		local prefix = string.sub(k, 1, i - 1)
		local rest = string.sub(k, i + 1)
		if string.lower(prefix) == "ability" then k = rest end
	end
	k = string.upper(k)
	if k == "Z" or k == "X" or k == "C" or k == "V" then return k end
	return nil
end

local function onCooldownEvent(name: any, duration: any)
	local key = normalizeKey(name); if not key then return end
	-- Evita aplicar cooldown si la tecla no existe para el arma actual
	if not available[key] then return end
	local dur = tonumber(duration) or 0; if dur <= 0 then return end
	cdState[key] = { endAt = os.clock() + dur, duration = dur }
	ensureUpdater()
end

-- HUD refresh
local function updateHUD()
	local names = readAvailabilityAndNames()
	for _, key in ipairs(ORDER) do
		local lbl = nameLabels[key]
		if lbl then lbl.Text = names[key] or ("Skill " .. key) end
		applyRowEnabled(key, available[key] == true)
	end
end

local function clearCharConns()
	for _, c in ipairs(charConns) do
		if c.Connected then c:Disconnect() end
	end
	table.clear(charConns)
end

local function bindCharacter(char: Model)
	clearCharConns()
	table.insert(charConns, char:GetAttributeChangedSignal("WeaponId"):Connect(updateHUD))
	table.insert(charConns, char:GetAttributeChangedSignal("WeaponType"):Connect(updateHUD))
	table.insert(charConns, char:GetAttributeChangedSignal("Moveset"):Connect(updateHUD))
	-- Primer estado
	task.delay(0.05, updateHUD)
end

-- Init
buildUI()
CooldownEvent.OnClientEvent:Connect(onCooldownEvent)
if player.Character then bindCharacter(player.Character) end
player.CharacterAdded:Connect(bindCharacter)
