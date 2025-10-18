--!strict
-- HotbarUI (minimal + smooth, Discord blue)
-- - Sincronizada con WeaponMenu/WeaponManager:
--   - Al equipar desde el menú, auto-selecciona el slot del arma equipada.
--   - Al desequipar (equip ""), salta a Puños (slot 1) sin intervención del jugador.
--   - On SyncHotbarEvent, re-selecciona basado en WeaponId actual.
-- - Más pequeño, sin clipping en slot 7 (contenedor con márgenes y layout centrado)
-- - Selección suave: anima borde y glow rápido al cambiar de slot
-- - Teclado: fila numérica y keypad (1–7). 1 => Puños si están en slot 1; si no, selecciona slot 1
-- - Icono de Puños: placeholder FISTS_ICON = "rbxassetid://0" (cámbialo luego)
-- - Muestra icono y nombre del elemento seleccionado (WeaponConfig o ItemConfig opcional)
-- - Sin ToolTip, ignora input si estás escribiendo en un TextBox

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local WeaponConfig = require(ReplicatedStorage.Assets.Modules:WaitForChild("WeaponConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EquipWeaponRF: RemoteFunction = Remotes:WaitForChild("EquipWeapon")
local SyncHotbarEvent: RemoteEvent = Remotes:WaitForChild("SyncHotbar")

-- Opcional: soportar ítems no-arma
local okItems, ItemConfig = pcall(function()
	return require(ReplicatedStorage.Assets.Modules:WaitForChild("ItemConfig"))
end)

local player = Players.LocalPlayer
local MAX_SLOTS = 7

-- Paleta
local BLURPLE = Color3.fromRGB(88, 101, 242)
local BG_COLOR = Color3.fromRGB(16, 18, 22)
local SLOT_BG = Color3.fromRGB(28, 31, 38)
local STROKE = Color3.fromRGB(64, 72, 88)
local TEXT = Color3.fromRGB(220, 228, 240)

-- Assets UI
local GLOW_IMG = "rbxassetid://5028857075" -- 9-slice glow/shadow
local FISTS_ICON = "rbxassetid://73782670106599" -- placeholder que tú reemplazarás

-- Estado
local hotbar: { [number]: string } = {}
local selectedSlot = 1
local gui: ScreenGui?
local frame: Frame?
local slotsContainer: Frame?
local nameCaption: TextLabel?
local visible = true

-- Referencias por slot
local slotRefs: {
	[number]: {
		Button: ImageButton,
		Stroke: UIStroke,
		Glow: ImageLabel,
		Icon: ImageLabel,
	}
} = {}

-- Conexiones a character
local charConns: { RBXScriptConnection } = {}

-- Teclas: fila superior + keypad
local KEY_TO_INDEX: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,   [Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.Two] = 2,   [Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.Three] = 3, [Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.Four] = 4,  [Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.Five] = 5,  [Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.Six] = 6,   [Enum.KeyCode.KeypadSix] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.KeypadSeven] = 7,
}

-- Tweens helpers
local function tween(obj: Instance, t: number, props: {}, easing: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local info = TweenInfo.new(t, easing or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(obj, info, props); tw:Play(); return tw
end

local function roundStroke(inst: GuiObject, r: number?, stroke: boolean?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = inst
	if stroke then
		local s = Instance.new("UIStroke")
		s.Thickness = 1.4
		s.Color = STROKE
		s.Transparency = 0.2
		s.Parent = inst
	end
end

-- Resolución de nombre/imagen
local function itemNameFor(id: string?): string
	if not id or id == "" then return "" end
	if id == "Fists" then return "Fists" end
	local cfg = WeaponConfig[id]
	if cfg then return (cfg.Name or cfg.DisplayName or id) end
	if okItems and ItemConfig and ItemConfig[id] then
		local ic = ItemConfig[id]
		return (ic.Name or ic.DisplayName or id)
	end
	return id
end

local function itemImageFor(id: string?): string
	if not id or id == "" then return "" end
	if id == "Fists" then return FISTS_ICON end
	local cfg = WeaponConfig[id]
	if cfg and cfg.Image then return cfg.Image end
	if okItems and ItemConfig and ItemConfig[id] and ItemConfig[id].Image then
		return ItemConfig[id].Image
	end
	return ""
end

local function ensureFistsInSlot1()
	if not hotbar[1] or hotbar[1] == "" then
		hotbar[1] = "Fists"
	end
end

-- UI updates
local function updateCaption()
	if not nameCaption then return end
	local wid = hotbar[selectedSlot]
	-- Fade out then in para un cambio suave
	tween(nameCaption, 0.06, { TextTransparency = 1 })
	task.delay(0.06, function()
		if nameCaption then
			nameCaption.Text = itemNameFor(wid)
			tween(nameCaption, 0.08, { TextTransparency = 0 })
		end
	end)
end

local function applySelectionVisual(slot: number, isSelected: boolean)
	local refs = slotRefs[slot]
	if not refs then return end
	-- Borde: color y ligero grosor
	if refs.Stroke then
		tween(refs.Stroke, 0.08, {
			Color = isSelected and BLURPLE or STROKE,
			Thickness = isSelected and 1.8 or 1.4,
			Transparency = isSelected and 0 or 0.2,
		})
	end
	-- Glow rápido (aparece y desaparece)
	if refs.Glow then
		if isSelected then
			refs.Glow.Visible = true
			refs.Glow.ImageTransparency = 1
			tween(refs.Glow, 0.06, { ImageTransparency = 0.7 })
			task.delay(0.08, function()
				if refs.Glow then tween(refs.Glow, 0.08, { ImageTransparency = 1 }) end
			end)
		end
	end
end

local function refreshSlots()
	if not slotsContainer then return end
	for slot = 1, MAX_SLOTS do
		local refs = slotRefs[slot]
		if refs then
			local wid = hotbar[slot]
			if refs.Icon then
				refs.Icon.Image = itemImageFor(wid)
				refs.Icon.ImageColor3 = Color3.fromRGB(235, 235, 240)
			end
			-- asegurar estado de borde base (selection applied outside)
			if refs.Stroke and slot ~= selectedSlot then
				refs.Stroke.Color = STROKE
				refs.Stroke.Thickness = 1.4
				refs.Stroke.Transparency = 0.2
			end
		end
	end
end

local function setSelectedSlot(slot: number)
	if slot < 1 or slot > MAX_SLOTS then return end
	if not hotbar[slot] then return end

	-- Des-seleccionar anterior
	if slotRefs[selectedSlot] then
		applySelectionVisual(selectedSlot, false)
	end

	selectedSlot = slot
	applySelectionVisual(selectedSlot, true)
	updateCaption()
end

-- NUEVO: auto-selección por WeaponId (viene del servidor)
local function selectByWeaponId(weaponId: string?)
	-- Desequipado o vacío => saltar a Puños (slot 1)
	if not weaponId or weaponId == "" then
		ensureFistsInSlot1()
		setSelectedSlot(1)
		return
	end
	-- Buscar el slot donde esté ese weaponId
	for i = 1, MAX_SLOTS do
		if hotbar[i] == weaponId then
			setSelectedSlot(i)
			return
		end
	end
	-- Si no se encontró (aún no sincronizó), mantener selección actual pero refrescar caption
	updateCaption()
end

local function equipBySlot(slot: number)
	local weaponId = hotbar[slot]
	if not weaponId or weaponId == "" then return end
	setSelectedSlot(slot)

	if weaponId == "Fists" then
		EquipWeaponRF:InvokeServer("")
	else
		EquipWeaponRF:InvokeServer(weaponId)
	end
end

-- Construcción UI
local function createHotbarGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "HotbarGUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2
	gui.Parent = player:WaitForChild("PlayerGui")

	nameCaption = Instance.new("TextLabel")
	nameCaption.Name = "SelectedName"
	nameCaption.AnchorPoint = Vector2.new(0.5, 1)
	nameCaption.Position = UDim2.new(0.5, 0, 1, -78)
	nameCaption.Size = UDim2.new(0, 260, 0, 16)
	nameCaption.BackgroundTransparency = 1
	nameCaption.TextColor3 = TEXT
	nameCaption.Font = Enum.Font.GothamSemibold
	nameCaption.TextSize = 14
	nameCaption.Text = ""
	nameCaption.Parent = gui

	frame = Instance.new("Frame")
	frame.Name = "HotbarFrame"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, 80) -- fuera (abajo) para animación
	frame.Size = UDim2.new(0, 400, 0, 56) -- panel un poco más ancho para que slot 7 no toque la esquina
	frame.BackgroundColor3 = BG_COLOR
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	roundStroke(frame, 12, true)

	-- Contenedor interno para evitar clipping en esquinas
	slotsContainer = Instance.new("Frame")
	slotsContainer.Name = "Slots"
	slotsContainer.BackgroundTransparency = 1
	slotsContainer.Size = UDim2.new(1, -16, 1, -12) -- márgenes izquierda/derecha y arriba/abajo
	slotsContainer.Position = UDim2.new(0, 8, 0, 6)
	slotsContainer.Parent = frame

	local hLayout = Instance.new("UIListLayout")
	hLayout.FillDirection = Enum.FillDirection.Horizontal
	hLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hLayout.Padding = UDim.new(0, 8) -- separación entre slots
	hLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hLayout.Parent = slotsContainer

	for slot = 1, MAX_SLOTS do
		local btn = Instance.new("ImageButton")
		btn.Name = "Slot" .. slot
		btn.BackgroundTransparency = 1
		btn.Size = UDim2.new(0, 46, 0, 46)
		btn.Parent = slotsContainer

		-- Base
		local bg = Instance.new("Frame")
		bg.Name = "BG"
		bg.BackgroundColor3 = SLOT_BG
		bg.BorderSizePixel = 0
		bg.Size = UDim2.new(1, 0, 1, 0)
		bg.Parent = btn
		roundStroke(bg, 8, true)

		local stroke = bg:FindFirstChildOfClass("UIStroke") :: UIStroke?
		if not stroke then
			stroke = Instance.new("UIStroke")
			stroke.Thickness = 1.4
			stroke.Color = STROKE
			stroke.Transparency = 0.2
			stroke.Parent = bg
		end

		-- Glow de selección (rápido)
		local glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.BackgroundTransparency = 1
		glow.Image = GLOW_IMG
		glow.ImageColor3 = Color3.new(0, 0, 0) -- sombra
		glow.ImageTransparency = 1
		glow.ScaleType = Enum.ScaleType.Slice
		glow.SliceCenter = Rect.new(24, 24, 276, 276)
		glow.Size = UDim2.new(1, 18, 1, 18)
		glow.Position = UDim2.new(0.5, -9, 0.5, -9)
		glow.ZIndex = btn.ZIndex - 1
		glow.Visible = false
		glow.Parent = btn

		-- Icono (en máscara)
		local mask = Instance.new("Frame")
		mask.Name = "ImgMask"
		mask.BackgroundTransparency = 1
		mask.Size = UDim2.new(1, -8, 1, -8)
		mask.Position = UDim2.new(0, 4, 0, 4)
		mask.Parent = btn
		local maskCorner = Instance.new("UICorner")
		maskCorner.CornerRadius = UDim.new(0, 6)
		maskCorner.Parent = mask

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(1, 0, 1, 0)
		icon.Image = ""
		icon.Parent = mask

		-- Key
		local keyLbl = Instance.new("TextLabel")
		keyLbl.Name = "KeyLabel"
		keyLbl.Text = tostring(slot)
		keyLbl.Size = UDim2.new(0, 16, 0, 16)
		keyLbl.Position = UDim2.new(0, 3, 0, 3)
		keyLbl.BackgroundTransparency = 1
		keyLbl.TextColor3 = TEXT
		keyLbl.Font = Enum.Font.GothamBold
		keyLbl.TextSize = 11
		keyLbl.Parent = btn

		-- Click
		btn.MouseButton1Click:Connect(function()
			if hotbar[slot] then
				equipBySlot(slot)
				-- micro-bounce
				tween(btn, 0.06, { Size = UDim2.new(0, 50, 0, 50) })
				tween(btn, 0.08, { Size = UDim2.new(0, 46, 0, 46) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)

		slotRefs[slot] = {
			Button = btn,
			Stroke = stroke,
			Glow = glow,
			Icon = icon,
		}
	end

	-- Slide-in inicial
	tween(frame, 0.2, { Position = UDim2.new(0.5, 0, 1, -14) })
end

-- Sync desde servidor
local function syncHotbar(list: { [number]: string }?)
	if not list then return end
	for i = 1, MAX_SLOTS do
		hotbar[i] = list[i]
	end
	ensureFistsInSlot1()
	refreshSlots()

	-- Auto-seleccionar según WeaponId actual del Character
	local ch = player.Character
	local widAttr = ch and (ch:GetAttribute("WeaponId") :: any) or nil
	selectByWeaponId(typeof(widAttr) == "string" and widAttr or nil)
end

local function toggleHotbar()
	if not frame then return end
	if visible then
		visible = false
		tween(frame, 0.16, { Position = UDim2.new(0.5, 0, 1, 80) })
		if nameCaption then tween(nameCaption, 0.16, { TextTransparency = 1 }) end
	else
		visible = true
		tween(frame, 0.16, { Position = UDim2.new(0.5, 0, 1, -14) })
		if nameCaption then tween(nameCaption, 0.16, { TextTransparency = 0 }) end
	end
end

-- Input
local function handleInput(input: InputObject, gpe: boolean)
	if gpe then return end
	if UIS:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	local idx = KEY_TO_INDEX[input.KeyCode]
	if idx and idx >= 1 and idx <= MAX_SLOTS then
		if idx == 1 and hotbar[1] == "Fists" then
			equipBySlot(1)
		else
			if hotbar[idx] then equipBySlot(idx) else setSelectedSlot(idx) end
		end
		return
	end

	-- Toggle opcional con H
	if input.KeyCode == Enum.KeyCode.H then
		toggleHotbar()
	end
end

-- Character bind/unbind
local function clearCharConns()
	for _, c in ipairs(charConns) do
		if c.Connected then c:Disconnect() end
	end
	table.clear(charConns)
end

local function bindCharacter(char: Model)
	clearCharConns()
	-- Cuando el servidor cambia el arma equipada, mueve la selección al slot correspondiente
	table.insert(charConns, char:GetAttributeChangedSignal("WeaponId"):Connect(function()
		local v = char:GetAttribute("WeaponId")
		selectByWeaponId(typeof(v) == "string" and (v :: any) or nil)
	end))
	-- Primer alineamiento (por si ya viene equipada)
	task.delay(0.05, function()
		local v = char:GetAttribute("WeaponId")
		selectByWeaponId(typeof(v) == "string" and (v :: any) or nil)
	end)
end

-- Init
createHotbarGui()
ensureFistsInSlot1()
refreshSlots()
applySelectionVisual(selectedSlot, true)
updateCaption()

UIS.InputBegan:Connect(handleInput)
SyncHotbarEvent.OnClientEvent:Connect(syncHotbar)

if player.Character then bindCharacter(player.Character) end
player.CharacterAdded:Connect(bindCharacter)
