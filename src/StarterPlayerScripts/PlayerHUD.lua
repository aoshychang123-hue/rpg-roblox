--!strict
-- PlayerFaceHUD completo y funcional
-- - Vida circular con relleno lineal recortado por el círculo (NO radial, NO cambia tamaño el círculo).
--   El fill avanza de izquierda→derecha (o de abajo→arriba) dentro del disco circular usando UIGradient.Transparency.
-- - Stamina y XP en panel derecho. Stamina usa SOLO naranja/amarillo/rojo (sin verde) + overlay de EXHAUST con parpadeo y tiempo restante.
-- - Animaciones suaves por frame (suavizado exponencial), sin tweens “duros” que parpadeen.
-- - Solo LEE atributos/estado. No inicializa valores en Player/Character.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Dirección del fill de vida dentro del círculo:
-- "Horizontal" (izq→der) o "Vertical" (abajo→arriba)
local ORIENTATION: "Horizontal" | "Vertical" = "Horizontal"

-- Paleta
local COLORS = {
	Bg = Color3.fromRGB(20, 22, 28),
	PanelStroke = Color3.fromRGB(40, 44, 52),
	AvatarBg = Color3.fromRGB(24, 26, 32),

	HPBack = Color3.fromRGB(30, 34, 42),
	HP_GREEN = Color3.fromRGB(60, 200, 110),   -- ≥ 66%
	HP_YELLOW = Color3.fromRGB(255, 210, 60),  -- ≥ 33%
	HP_RED = Color3.fromRGB(230, 60, 60),      -- < 33%

	TextMain = Color3.fromRGB(220, 230, 245),
	TextSub = Color3.fromRGB(200, 208, 220),

	XPBack = Color3.fromRGB(30, 34, 42),
	XP1 = Color3.fromRGB(180, 120, 255),
	XP2 = Color3.fromRGB(120, 80, 255),
	Star = Color3.fromRGB(255, 255, 255),

	-- Stamina (sin verde)
	StaminaBack = Color3.fromRGB(28, 26, 20),
	StaminaHigh = Color3.fromRGB(255, 168, 40), -- naranja (≥ 66%)
	StaminaMid  = Color3.fromRGB(255, 210, 60), -- amarillo (≥ 33%)
	StaminaLow  = Color3.fromRGB(230, 60, 60),  -- rojo (< 33%)

	ExhaustOverlay = Color3.fromRGB(58, 40, 36),
	ExhaustFill = Color3.fromRGB(230, 100, 70),
	ExhaustText = Color3.fromRGB(255, 240, 230),

	Pulse = Color3.fromRGB(88, 101, 242),
}

-- Geometría
local GEOM = {
	RootWidth = 340, RootHeight = 128,

	AvatarSize = 84,     -- diámetro avatar
	HPCircle  = 96,      -- diámetro círculo vida (fijo)
	HPHole    = 86,      -- agujero interior (para ver avatar)

	PanelCorner = 12,
	Pad = 10,
	TitleH = 18,
	HPTextGap = 18,

	StaminaBarHeight = 10,
	XPBarHeight = 8,
	BarsGap = 8,
}

local DEFAULT_STAR_IMAGE = "rbxassetid://131981569450984"

-- Función de suavizado exponencial por frame
local function smoothStep(current: number, target: number, lambda: number, dt: number): number
	if current == target then return current end
	local alpha = 1 - math.exp(-lambda * math.max(dt, 0))
	return current + (target - current) * alpha
end

-- Mapas de color
local function hpColorFromFrac(frac: number): Color3
	if frac >= 0.66 then return COLORS.HP_GREEN
	elseif frac >= 0.33 then return COLORS.HP_YELLOW
	else return COLORS.HP_RED end
end

local function staminaColorByFrac(frac: number): Color3
	if frac >= 0.66 then return COLORS.StaminaHigh
	elseif frac >= 0.33 then return COLORS.StaminaMid
	else return COLORS.StaminaLow end
end

-- Helpers
local function getHumanoid(character: Model?): Humanoid?
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getHeadshot(userId: number): string
	local ok, url, ready = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok and ready and url then return url end
	return "rbxassetid://0"
end

-- Raíz GUI
local screen = Instance.new("ScreenGui")
screen.Name = "PlayerFaceHUD"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0, 1)
root.Position = UDim2.new(0, 16, 1, -16)
root.Size = UDim2.new(0, GEOM.RootWidth, 0, GEOM.RootHeight)
root.BackgroundTransparency = 1
root.Parent = screen

-- Responsive
local uiScale = Instance.new("UIScale")
uiScale.Parent = root
local function applyResponsive()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local scale = math.clamp(vp.Y / 720, 0.8, 1.35)
	if UserInputService.TouchEnabled then scale *= 1.05 end
	uiScale.Scale = scale
	local margin = math.floor(math.clamp(vp.X * 0.012, 10, 28))
	root.Position = UDim2.new(0, margin, 1, -margin)
end
applyResponsive()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(function()
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsive)
			applyResponsive()
		end
	end)
end)

-- IZQUIERDA: Avatar + Círculo HP (relleno lineal dentro del círculo)
local avatarGroup = Instance.new("Frame")
avatarGroup.Name = "AvatarGroup"
avatarGroup.BackgroundTransparency = 1
avatarGroup.Size = UDim2.new(0, GEOM.HPCircle, 0, GEOM.HPCircle)
avatarGroup.Position = UDim2.new(0, 0, 0.5, 0)
avatarGroup.AnchorPoint = Vector2.new(0, 0.5)
avatarGroup.Parent = root

-- Disco de fondo gris
local hpBackDisc = Instance.new("Frame")
hpBackDisc.Name = "HPBackDisc"
hpBackDisc.Size = UDim2.fromScale(1, 1)
hpBackDisc.BackgroundColor3 = COLORS.HPBack
hpBackDisc.BorderSizePixel = 0
hpBackDisc.Parent = avatarGroup
local backCorner = Instance.new("UICorner")
backCorner.CornerRadius = UDim.new(1, 0)
backCorner.Parent = hpBackDisc

-- Fill circular (se recorta linealmente con UIGradient.Transparency)
local hpCircleFill = Instance.new("Frame")
hpCircleFill.Name = "HPCircleFill"
hpCircleFill.Size = UDim2.fromScale(1, 1)
hpCircleFill.BackgroundColor3 = COLORS.HP_GREEN
hpCircleFill.BorderSizePixel = 0
hpCircleFill.ZIndex = 2
hpCircleFill.Parent = avatarGroup
local hpFillCorner = Instance.new("UICorner")
hpFillCorner.CornerRadius = UDim.new(1, 0)
hpFillCorner.Parent = hpCircleFill

local hpGrad = Instance.new("UIGradient")
-- 0 = izq→der (horizontal). 90 = abajo→arriba (vertical)
hpGrad.Rotation = (ORIENTATION == "Horizontal") and 0 or 90
hpGrad.Parent = hpCircleFill

-- Agujero interior (anillo) para ver el avatar
local hpInnerHole = Instance.new("Frame")
hpInnerHole.Name = "HPInnerHole"
hpInnerHole.AnchorPoint = Vector2.new(0.5, 0.5)
hpInnerHole.Position = UDim2.fromScale(0.5, 0.5)
hpInnerHole.Size = UDim2.new(0, GEOM.HPHole, 0, GEOM.HPHole)
hpInnerHole.BackgroundColor3 = COLORS.AvatarBg
hpInnerHole.BorderSizePixel = 0
hpInnerHole.ZIndex = 3
hpInnerHole.Parent = avatarGroup
local holeCorner = Instance.new("UICorner")
holeCorner.CornerRadius = UDim.new(1, 0)
holeCorner.Parent = hpInnerHole

-- Avatar
local avatarWrap = Instance.new("Frame")
avatarWrap.Name = "AvatarWrap"
avatarWrap.AnchorPoint = Vector2.new(0.5, 0.5)
avatarWrap.Position = UDim2.fromScale(0.5, 0.5)
avatarWrap.Size = UDim2.new(0, GEOM.AvatarSize, 0, GEOM.AvatarSize)
avatarWrap.BackgroundTransparency = 1
avatarWrap.BorderSizePixel = 0
avatarWrap.ZIndex = 4
avatarWrap.Parent = avatarGroup
local avatarStroke = Instance.new("UIStroke")
avatarStroke.Color = COLORS.PanelStroke
avatarStroke.Transparency = 0.35
avatarStroke.Thickness = 1
avatarStroke.Parent = avatarWrap
local avatarCorner = Instance.new("UICorner")
avatarCorner.CornerRadius = UDim.new(1, 0)
avatarCorner.Parent = avatarWrap

local avatarImg = Instance.new("ImageLabel")
avatarImg.Name = "Avatar"
avatarImg.AnchorPoint = Vector2.new(0.5, 0.5)
avatarImg.Position = UDim2.fromScale(0.5, 0.5)
avatarImg.Size = UDim2.new(1, -6, 1, -6)
avatarImg.BackgroundTransparency = 1
avatarImg.Image = getHeadshot(player.UserId)
avatarImg.ZIndex = 5
avatarImg.Parent = avatarWrap
local avatarImgCorner = Instance.new("UICorner")
avatarImgCorner.CornerRadius = UDim.new(1, 0)
avatarImgCorner.Parent = avatarImg

-- Pulso sutil del avatar
local avatarPulse = Instance.new("UIStroke")
avatarPulse.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
avatarPulse.Color = COLORS.Pulse
avatarPulse.Thickness = 2
avatarPulse.Transparency = 1
avatarPulse.Parent = avatarWrap

-- DERECHA: Panel con Stamina + XP
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Position = UDim2.new(0, GEOM.HPCircle + GEOM.Pad, 0, 6)
panel.Size = UDim2.new(1, -(GEOM.HPCircle + GEOM.Pad), 1, -12)
panel.BackgroundColor3 = COLORS.Bg
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Parent = root
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, GEOM.PanelCorner)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.PanelStroke
panelStroke.Transparency = 0.4
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamSemibold
title.TextSize = 14
title.TextColor3 = COLORS.TextMain
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = player.DisplayName
title.Position = UDim2.new(0, GEOM.Pad, 0, 6)
title.Size = UDim2.new(1, -GEOM.Pad*2, 0, GEOM.TitleH)
title.Parent = panel

local hpText = Instance.new("TextLabel")
hpText.Name = "HPText"
hpText.BackgroundTransparency = 1
hpText.Font = Enum.Font.Gotham
hpText.TextSize = 13
hpText.TextColor3 = COLORS.TextSub
hpText.TextXAlignment = Enum.TextXAlignment.Left
hpText.Text = "0 / 0 (0%)"
hpText.Position = UDim2.new(0, GEOM.Pad, 0, 6 + GEOM.TitleH)
hpText.Size = UDim2.new(1, -GEOM.Pad*2, 0, GEOM.HPTextGap)
hpText.Parent = panel

-- Stamina
local staminaBack = Instance.new("Frame")
staminaBack.Name = "StaminaBack"
staminaBack.BackgroundColor3 = COLORS.StaminaBack
staminaBack.BorderSizePixel = 0
staminaBack.Position = UDim2.new(0, GEOM.Pad, 0, 6 + GEOM.TitleH + GEOM.HPTextGap)
staminaBack.Size = UDim2.new(1, -GEOM.Pad*2, 0, GEOM.StaminaBarHeight)
staminaBack.Parent = panel
local staminaCorner = Instance.new("UICorner")
staminaCorner.CornerRadius = UDim.new(0, math.floor(GEOM.StaminaBarHeight/2))
staminaCorner.Parent = staminaBack

local staminaFill = Instance.new("Frame")
staminaFill.Name = "StaminaFill"
staminaFill.BackgroundColor3 = COLORS.StaminaHigh -- naranja (alto)
staminaFill.BorderSizePixel = 0
staminaFill.AnchorPoint = Vector2.new(0, 0.5)
staminaFill.Position = UDim2.fromScale(0, 0.5)
staminaFill.Size = UDim2.fromScale(0, 1)
staminaFill.Parent = staminaBack
local staminaFillCorner = Instance.new("UICorner")
staminaFillCorner.CornerRadius = staminaCorner.CornerRadius
staminaFillCorner.Parent = staminaFill

-- Exhaust overlay (stamina)
local exhaustOverlay = Instance.new("Frame")
exhaustOverlay.Name = "ExhaustOverlay"
exhaustOverlay.BackgroundColor3 = COLORS.ExhaustOverlay
exhaustOverlay.BorderSizePixel = 0
exhaustOverlay.Visible = false
exhaustOverlay.Size = UDim2.fromScale(1, 1)
exhaustOverlay.Parent = staminaBack
local exhaustCorner = Instance.new("UICorner")
exhaustCorner.CornerRadius = staminaCorner.CornerRadius
exhaustCorner.Parent = exhaustOverlay

local exhaustFill = Instance.new("Frame")
exhaustFill.Name = "ExhaustFill"
exhaustFill.BackgroundColor3 = COLORS.ExhaustFill
exhaustFill.BorderSizePixel = 0
exhaustFill.AnchorPoint = Vector2.new(1, 0.5)
exhaustFill.Position = UDim2.fromScale(1, 0.5)
exhaustFill.Size = UDim2.fromScale(1, 1) -- decrece 1→0 durante cooldown
exhaustFill.Parent = exhaustOverlay
local exhaustFillCorner = Instance.new("UICorner")
exhaustFillCorner.CornerRadius = staminaCorner.CornerRadius
exhaustFillCorner.Parent = exhaustFill

local exhaustLabel = Instance.new("TextLabel")
exhaustLabel.Name = "ExhaustLabel"
exhaustLabel.BackgroundTransparency = 1
exhaustLabel.Size = UDim2.fromScale(1, 1)
exhaustLabel.Font = Enum.Font.GothamBold
exhaustLabel.TextSize = 11
exhaustLabel.TextColor3 = COLORS.ExhaustText
exhaustLabel.TextStrokeTransparency = 0.6
exhaustLabel.Text = ""
exhaustLabel.Parent = exhaustOverlay

-- XP
local xpBack = Instance.new("Frame")
xpBack.Name = "XPBack"
xpBack.BackgroundColor3 = COLORS.XPBack
xpBack.BorderSizePixel = 0
xpBack.Position = UDim2.new(0, GEOM.Pad, 0, 6 + GEOM.TitleH + GEOM.HPTextGap + GEOM.StaminaBarHeight + GEOM.BarsGap)
xpBack.Size = UDim2.new(1, -GEOM.Pad*2, 0, GEOM.XPBarHeight)
xpBack.Parent = panel
local xpCorner = Instance.new("UICorner")
xpCorner.CornerRadius = UDim.new(0, math.floor(GEOM.XPBarHeight/2))
xpCorner.Parent = xpBack

local xpFill = Instance.new("Frame")
xpFill.Name = "XPFill"
xpFill.BackgroundColor3 = COLORS.XP1
xpFill.BorderSizePixel = 0
xpFill.AnchorPoint = Vector2.new(0, 0.5)
xpFill.Position = UDim2.fromScale(0, 0.5)
xpFill.Size = UDim2.fromScale(0, 1)
xpFill.Parent = xpBack
local xpFillCorner = Instance.new("UICorner")
xpFillCorner.CornerRadius = xpCorner.CornerRadius
xpFillCorner.Parent = xpFill
local xpGrad = Instance.new("UIGradient")
xpGrad.Color = ColorSequence.new(COLORS.XP1, COLORS.XP2)
xpGrad.Parent = xpFill

local star = Instance.new("ImageLabel")
star.Name = "XPStar"
star.BackgroundTransparency = 1
star.Image = DEFAULT_STAR_IMAGE
star.ImageColor3 = COLORS.Star
star.AnchorPoint = Vector2.new(0.5, 0.5)
star.Size = UDim2.new(0, 16, 0, 16)
star.Position = UDim2.fromScale(0, 0.5)
star.Parent = xpBack

local lvlText = Instance.new("TextLabel")
lvlText.Name = "LevelText"
lvlText.BackgroundTransparency = 1
lvlText.Font = Enum.Font.GothamSemibold
lvlText.TextSize = 12
lvlText.TextColor3 = COLORS.TextMain
lvlText.TextXAlignment = Enum.TextXAlignment.Left
lvlText.Size = UDim2.new(0, 60, 0, 16)
lvlText.AnchorPoint = Vector2.new(0, 0.5)
lvlText.Position = UDim2.fromScale(0, 0.5)
lvlText.Parent = xpBack

-- Estado y suavizado
local humanoid: Humanoid? = nil

local targetHPFrac = 1
local currentHPFrac = 1

local targetStamFrac = 1
local currentStamFrac = 1

local targetXPFrac = 0
local currentXPFrac = 0

-- Lambdas (más alto = respuesta más rápida)
local LAMBDA_HP = 10
local LAMBDA_STAM = 12
local LAMBDA_XP = 8
local LAMBDA_STAM_COLOR = 10

-- Lecturas de estado
local function readHPTargets()
	if not humanoid then targetHPFrac = 0; return end
	targetHPFrac = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
end

local function readStaminaTargets()
	local ch = player.Character
	local s = tonumber(ch and ch:GetAttribute("Stamina")) or tonumber(player:GetAttribute("Stamina")) or 0
	local ms = tonumber(ch and ch:GetAttribute("MaxStamina")) or tonumber(player:GetAttribute("MaxStamina")) or 100
	if ms < 1 then ms = 1 end
	targetStamFrac = math.clamp(s / ms, 0, 1)
end

local function readXPTargets()
	local ch = player.Character
	local req = tonumber(ch and ch:GetAttribute("RequiredXP")) or tonumber(player:GetAttribute("RequiredXP")) or 100
	local xp  = tonumber(ch and ch:GetAttribute("XP")) or tonumber(player:GetAttribute("XP")) or 0
	if req < 1 then req = 1 end
	targetXPFrac = math.clamp(xp / req, 0, 1)
end

-- HP visual: aplica gradiente de transparencia según currentHPFrac
local function applyHPVisual()
	local f = currentHPFrac
	local eps = 0.0001
	hpGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(f, 0),
		NumberSequenceKeypoint.new(math.min(1, f + eps), 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	hpCircleFill.BackgroundColor3 = hpColorFromFrac(f)
	if humanoid then
		local cur = math.floor(humanoid.Health + 0.5)
		local maxH = math.max(1, math.floor(humanoid.MaxHealth + 0.5))
		hpText.Text = ("%d / %d (%.0f%%)"):format(cur, maxH, f * 100)
	end
end

-- Stamina visual: tamaño y color suavizados
local function applyStaminaVisual(dt: number)
	-- Tamaño
	currentStamFrac = smoothStep(currentStamFrac, targetStamFrac, LAMBDA_STAM, dt)
	staminaFill.Size = UDim2.fromScale(currentStamFrac, 1)
	-- Color
	local targetColor = staminaColorByFrac(currentStamFrac)
	local cur = staminaFill.BackgroundColor3
	local newColor = Color3.new(
		smoothStep(cur.R, targetColor.R, LAMBDA_STAM_COLOR, dt),
		smoothStep(cur.G, targetColor.G, LAMBDA_STAM_COLOR, dt),
		smoothStep(cur.B, targetColor.B, LAMBDA_STAM_COLOR, dt)
	)
	staminaFill.BackgroundColor3 = newColor
end

local function placeStarAtFrac(frac: number)
	local w = xpBack.AbsoluteSize.X
	local targetX = math.max(8, math.min(w - 8, w * math.clamp(frac, 0, 1)))
	star.Position = UDim2.new(0, targetX, 0.5, 0)
	local level = tonumber(player.Character and player.Character:GetAttribute("Level")) or tonumber(player:GetAttribute("Level")) or 1
	lvlText.Text = ("Lv %d"):format(level)
	local lvlX = math.min(w - 56, targetX + 10)
	lvlText.Position = UDim2.new(0, lvlX, 0.5, 0)
end

local function applyXPVisual(dt: number)
	currentXPFrac = smoothStep(currentXPFrac, targetXPFrac, LAMBDA_XP, dt)
	xpFill.Size = UDim2.fromScale(currentXPFrac, 1)
	placeStarAtFrac(currentXPFrac)
end

-- Exhaust UI (stamina)
local exhaustBlinkConn: RBXScriptConnection? = nil
local lastBlinkActive = false
local exhaustSpanCached: number? = nil

local function setExhaustBlink(active: boolean)
	if active == lastBlinkActive then return end
	lastBlinkActive = active
	if exhaustBlinkConn then exhaustBlinkConn:Disconnect(); exhaustBlinkConn = nil end
	if active then
		exhaustBlinkConn = RunService.Heartbeat:Connect(function()
			local t = os.clock() * 4.0
			local pulse = 0.5 + 0.5 * math.sin(t)
			exhaustOverlay.BackgroundTransparency = 0.25 + 0.25 * pulse
			exhaustLabel.TextTransparency = 0.1 + 0.8 * (1 - pulse)
		end)
	else
		exhaustOverlay.BackgroundTransparency = 0
		exhaustLabel.TextTransparency = 0
	end
end

local function updateExhaustUI()
	local ch = player.Character
	if not ch then return end
	local exhausted = ch:GetAttribute("RunExhaust") == true
	local keyActive = ch:GetAttribute("ClientRunKeyActive") == true
	local untilTime = (ch:GetAttribute("RunExhaustUntil") :: any) :: number

	exhaustOverlay.Visible = exhausted
	staminaFill.Visible = not exhausted

	if exhausted and untilTime then
		local remaining = math.max(0, untilTime - os.clock())
		exhaustLabel.Text = ("EXHAUST %.1fs"):format(remaining)
		if not exhaustSpanCached then
			exhaustSpanCached = math.max(remaining, 0.001)
		end
		local prog = math.clamp(remaining / (exhaustSpanCached :: number), 0, 1)
		exhaustFill.Size = UDim2.fromScale(prog, 1)
	else
		exhaustSpanCached = nil
	end

	setExhaustBlink(exhausted and keyActive)
end

-- Conexiones y binding
local hpConn: RBXScriptConnection? = nil
local hpMaxConn: RBXScriptConnection? = nil
local xpConns: {RBXScriptConnection} = {}
local staminaConns: {RBXScriptConnection} = {}

local function clearConns()
	if hpConn then hpConn:Disconnect(); hpConn=nil end
	if hpMaxConn then hpMaxConn:Disconnect(); hpMaxConn=nil end
	for _,c in ipairs(xpConns) do if c then c:Disconnect() end end
	for _,c in ipairs(staminaConns) do if c then c:Disconnect() end end
	xpConns = {}; staminaConns = {}
	if exhaustBlinkConn then exhaustBlinkConn:Disconnect(); exhaustBlinkConn=nil end
end

local function bindCharacter(character: Model?)
	clearConns()
	avatarImg.Image = getHeadshot(player.UserId)

	humanoid = getHumanoid(character)
	if humanoid then
		readHPTargets()
		currentHPFrac = targetHPFrac
		applyHPVisual()

		hpConn = humanoid.HealthChanged:Connect(function()
			readHPTargets()
		end)
		hpMaxConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			readHPTargets()
		end)
	else
		currentHPFrac, targetHPFrac = 0, 0
		applyHPVisual()
		hpText.Text = "0 / 0 (0%)"
	end

	-- Suscripciones attrs
	if character then
		table.insert(xpConns, character:GetAttributeChangedSignal("Level"):Connect(readXPTargets))
		table.insert(xpConns, character:GetAttributeChangedSignal("XP"):Connect(readXPTargets))
		table.insert(xpConns, character:GetAttributeChangedSignal("RequiredXP"):Connect(readXPTargets))

		table.insert(staminaConns, character:GetAttributeChangedSignal("Stamina"):Connect(readStaminaTargets))
		table.insert(staminaConns, character:GetAttributeChangedSignal("MaxStamina"):Connect(readStaminaTargets))
		table.insert(staminaConns, character:GetAttributeChangedSignal("RunExhaust"):Connect(updateExhaustUI))
		table.insert(staminaConns, character:GetAttributeChangedSignal("RunExhaustUntil"):Connect(updateExhaustUI))
		table.insert(staminaConns, character:GetAttributeChangedSignal("ClientRunKeyActive"):Connect(updateExhaustUI))
	end

	-- Inicial
	readXPTargets(); currentXPFrac = targetXPFrac; applyXPVisual(0.016)
	readStaminaTargets(); currentStamFrac = targetStamFrac; staminaFill.Size = UDim2.fromScale(currentStamFrac, 1); staminaFill.BackgroundColor3 = staminaColorByFrac(currentStamFrac)
	updateExhaustUI()
end

bindCharacter(player.Character)
player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(function() bindCharacter(nil) end)

-- Recolocar star al cambiar tamaño
local function onResize()
	task.defer(function()
		placeStarAtFrac(currentXPFrac)
	end)
end
xpBack:GetPropertyChangedSignal("AbsoluteSize"):Connect(onResize)
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(onResize)

-- Loop de animación suave
RunService.RenderStepped:Connect(function(dt)
	-- HP
	currentHPFrac = smoothStep(currentHPFrac, targetHPFrac, LAMBDA_HP, dt)
	applyHPVisual()

	-- Stamina
	applyStaminaVisual(dt)

	-- XP
	applyXPVisual(dt)
end)

-- Pulso del borde del avatar (sutil)
RunService.Heartbeat:Connect(function()
	local t = os.clock() * 1.6
	avatarPulse.Thickness = 1.4 + 0.4 * math.sin(t)
end)
