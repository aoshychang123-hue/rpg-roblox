--!strict
-- WeaponMenu (compact UI with animated dropdown, selection dot, SFX, and clean empty details)
-- - Categories: All, Sword, Maze, Bow, Spear, Shield, Fists, Other
-- - Animated dropdown with overlay, selection dot, and shifted a bit to the right
-- - Search filter
-- - 1 weapon per category (client cleans; server normalizes)
-- - Smooth immediate UI refresh on equip/unequip
-- - Details panel shows nothing until a weapon is selected (no template)
-- - SFX for open/close, dropdown open/close/select, hover, click, equip/unequip

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ModulesRoot = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Modules")
local WeaponConfig = require(ModulesRoot:WaitForChild("WeaponConfig"))
local WeaponTypeResolver = require(ModulesRoot:WaitForChild("WeaponTypeResolver"))
local AbilitySets = require(ModulesRoot:WaitForChild("AbilitySets"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EquipWeaponRF: RemoteFunction = Remotes:WaitForChild("EquipWeapon")
local SyncHotbarEvent: RemoteEvent = Remotes:WaitForChild("SyncHotbar")

local player = Players.LocalPlayer
local MAX_SLOTS = 7

-- Palette
local BLURPLE = Color3.fromRGB(88, 101, 242)
local BG_COLOR = Color3.fromRGB(22, 24, 29)
local CARD_BG = Color3.fromRGB(30, 33, 41)
local CARD_BG_HOVER = Color3.fromRGB(40, 44, 54)
local STROKE = Color3.fromRGB(64, 72, 88)
local TEXT = Color3.fromRGB(226, 232, 240)
local TEXT_MUTED = Color3.fromRGB(150, 158, 172)
local TEXT_DARK = Color3.fromRGB(28, 28, 28)
local RATING_DOT_ON = Color3.fromRGB(255, 194, 58)
local RATING_DOT_OFF = Color3.fromRGB(70, 76, 88)

-- Assets
local GLOW_IMG = "rbxassetid://6238980196"
local CLOSE_ICON_IMG = "rbxassetid://13516615928"
local SEARCH_ICON_IMG = "rbxassetid://13516773321"
local CHEVRON_DOWN_ICON_IMG = "rbxassetid://13516773201"

-- SFX (replace the ids with yours if needed)
local SFX_IDS = {
	OPEN = "rbxassetid://138962746314476",
	CLOSE = "rbxassetid://138962746314476",
	DROPDOWN_OPEN = "rbxassetid://117008703469445",
	DROPDOWN_CLOSE = "rbxassetid://117008703469445",
	CATEGORY = "rbxassetid://0",
	HOVER = "rbxassetid://111470738698118",
	CLICK = "rbxassetid://132669402068612",
	EQUIP = "rbxassetid://107198978765151",
	UNEQUIP = "rbxassetid://138962746314476",
}

-- Layout
local FRAME_W, FRAME_H = 840, 480
local SHEET_MARGIN_X, SHEET_MARGIN_Y = 24, 16
local PADDING = 10
local HEADER_H = 40
local CONTROLS_H = 30
local CONTROLS_GAP = 8
local FOOTER_H = 20
local DETAILS_W = 240
local GRID_CARD_W, GRID_CARD_H = 64, 82
local GRID_GAP = 14

-- Dropdown shift (move a little to the right so it looks nicer)
local DROPDOWN_X_SHIFT = 16

-- State
local allWeapons: { [string]: any } = WeaponConfig
local hotbar: { [number]: string } = {}
local equipped: { [string]: boolean } = {}
local currentTab = "All"
local currentSearchQuery = ""

local gui: ScreenGui
local frame: Frame
local sheet: Frame
local gridScroll: ScrollingFrame
local footer: Frame

local dropdownOpen = false
local categoryDropdownButton: TextButton
local categoryDropdownList: Frame
local screenCover: TextButton

local open = false
local selectedIndex = 1
local selectedWeaponId: string? = nil
local gridCards: { [number]: Frame } = {}
local gridWeaponIds: { [number]: string } = {}

local details: Frame
local detailsRefs = {
	Icon = nil,
	Title = nil,
	SlotPill = nil,
	Desc = nil,
	Dmg = nil,
	SkillsList = nil,
	ActionBtn = nil,
	RatingDots = {} :: { Frame },
	EmptyMask = nil, -- covers panel when nothing selected
}

local CATEGORIES = { "All", "Sword", "Maze", "Bow", "Spear", "Shield", "Fists", "Other" }

-- Forward declarations for functions used before definitions
local function positionDropdown() end
local function updateDropdownSelectionVisual() end
local function openDropdownAnimated() end
local function closeDropdownAnimated() end
local function updateDetails(_wid: string?) end
local function setDetailsEmpty() end

-- SFX manager ------------------------------------------------------------------
local sfxFolder: Folder

local function ensureSfx()
	if sfxFolder and sfxFolder.Parent then return end
	sfxFolder = Instance.new("Folder")
	sfxFolder.Name = "SFX"
	sfxFolder.Parent = gui
	for name, id in pairs(SFX_IDS) do
		local snd = Instance.new("Sound")
		snd.Name = name
		snd.SoundId = id
		snd.Volume = (name == "HOVER") and 0.25 or 0.6
		snd.RollOffMode = Enum.RollOffMode.Linear
		snd.Parent = sfxFolder
	end
end

local function playSfx(name: string, pitch: number?)
	if not sfxFolder then ensureSfx() end
	local tpl = sfxFolder:FindFirstChild(name)
	if not tpl or not tpl:IsA("Sound") then return end
	local s = tpl:Clone()
	s.Parent = gui
	if pitch and pitch > 0 then s.PlaybackSpeed = pitch end
	s.Ended:Connect(function() s:Destroy() end)
	s:Play()
end

-- Utils -----------------------------------------------------------------------
local function tween(obj: Instance, t: number, props: {}, easing: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local info = TweenInfo.new(t, easing or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(obj, info, props)
	tw:Play()
	return tw
end

local function round(inst: GuiObject, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = inst
end

local function stroke(inst: GuiObject, color: Color3?, thickness: number?, trans: number?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 1.1
	s.Color = color or STROKE
	s.Transparency = trans or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function makeGlow(parent: GuiObject, sizeOffset: number?): ImageLabel
	local glow = Instance.new("ImageLabel")
	glow.Name, glow.BackgroundTransparency = "Glow", 1
	glow.Image, glow.ImageColor3, glow.ImageTransparency = GLOW_IMG, Color3.fromRGB(200, 200, 200), 0.85
	glow.ScaleType, glow.SliceCenter = Enum.ScaleType.Slice, Rect.new(50, 50, 450, 450)
	local off = sizeOffset or 10
	glow.Size, glow.Position, glow.ZIndex, glow.Parent = UDim2.new(1,off,1,off), UDim2.new(0.5,-off/2,0.5,-off/2), parent.ZIndex - 1, parent
	return glow
end

local function ensureFistsInSlot1()
	if not hotbar[1] or hotbar[1] == "" then
		hotbar[1] = "Fists"
		equipped["Fists"] = true
	end
end

local function getWeaponName(wid: string): string
	local cfg = allWeapons[wid]
	return (cfg and (cfg.Name or cfg.DisplayName)) or (wid == "Fists" and "Fists" or wid)
end

-- Group normalization ----------------------------------------------------------
local CANON: { [string]: string } = {
	Sword = "Sword", Espada = "Sword", sword = "Sword",
	Maze = "Maze", Mazo = "Maze", Mace = "Maze", Hammer = "Maze", hammer = "Maze", mace = "Maze", maze = "Maze",
	Bow = "Bow", Arco = "Bow", bow = "Bow",
	Spear = "Spear", Lanza = "Spear", spear = "Spear",
	Shield = "Shield", Escudo = "Shield", shield = "Shield",
	Fists = "Fists", ["Puños"] = "Fists", fists = "Fists",
}

local function fuzzyTypeToGroup(t: string?): string?
	if typeof(t) ~= "string" or #t == 0 then return nil end
	if CANON[t] then return CANON[t] end
	local l = string.lower(t)
	if string.find(l, "sword") or string.find(l, "espada") or string.find(l, "katana") or string.find(l, "greatsword") then
		return "Sword"
	end
	if string.find(l, "mazo") or string.find(l, "mace") or string.find(l, "maze") or string.find(l, "hammer") then
		return "Maze"
	end
	if string.find(l, "bow") or string.find(l, "arco") then
		return "Bow"
	end
	if string.find(l, "spear") or string.find(l, "lanza") or string.find(l, "polearm") then
		return "Spear"
	end
	if string.find(l, "shield") or string.find(l, "escudo") then
		return "Shield"
	end
	if string.find(l, "fist") or string.find(l, "puñ") then
		return "Fists"
	end
	return nil
end

local function getWeaponGroup(wid: string): string
	if wid == "Fists" then return "Fists" end
	local cfg = allWeapons[wid]
	if not cfg then return "Other" end
	local norm = WeaponTypeResolver.fromWeaponConfigType(cfg.Type)
	if norm and CANON[norm] then return CANON[norm] end
	local fuzzy = fuzzyTypeToGroup(cfg.Type)
	if fuzzy then return fuzzy end
	local byName = fuzzyTypeToGroup((cfg.DisplayName or cfg.Name))
	if byName then return byName end
	return "Other"
end

local function slotOfWeapon(wid: string): number?
	for i = 1, MAX_SLOTS do
		if hotbar[i] == wid then return i end
	end
	return nil
end

-- Filtering (category + search) -----------------------------------------------
local function getFilteredWeapons(): { string }
	local arr: { string } = {}
	local query = string.lower(currentSearchQuery or "")

	for wid, _ in pairs(allWeapons) do
		local weaponName = string.lower(getWeaponName(wid))
		if query == "" or string.find(weaponName, query, 1, true) then
			local group = getWeaponGroup(wid)
			if currentTab == "All" or currentTab == group or (currentTab == "Other" and group == "Other") then
				table.insert(arr, wid)
			end
		end
	end
	-- Fists visible in All/Fists if search matches
	if (currentTab == "All" or currentTab == "Fists")
		and (query == "" or string.find("fists", query, 1, true)) then
		if not table.find(arr, "Fists") then table.insert(arr, "Fists") end
	end

	table.sort(arr, function(a, b) return getWeaponName(a) < getWeaponName(b) end)
	return arr
end

-- One-per-category rule + visuals ---------------------------------------------
local function removeSameGroupFromHotbar(wid: string, keepSlot: number?)
	local grp = getWeaponGroup(wid)
	if grp == "Other" then return end
	for s = 1, MAX_SLOTS do
		if not (keepSlot and s == keepSlot) then
			local other = hotbar[s]
			if other and other ~= "" and other ~= wid then
				if getWeaponGroup(other) == grp then
					hotbar[s] = nil
					equipped[other] = false
				end
			end
		end
	end
end

local function refreshGridVisuals()
	for idx, card in ipairs(gridCards) do
		local wid = gridWeaponIds[idx]
		if card and wid then
			local border = card:FindFirstChildOfClass("UIStroke")
			local badge = card:FindFirstChild("SlotBadge")
			local bTxt = badge and badge:FindFirstChild("Txt")
			local inSlot = slotOfWeapon(wid)
			if border then
				border.Color = (inSlot or (selectedWeaponId == wid)) and BLURPLE or STROKE
				border.Thickness = (selectedWeaponId == wid) and 2.0 or (inSlot and 1.6 or 1.1)
			end
			if badge and bTxt and bTxt:IsA("TextLabel") and badge:IsA("Frame") then
				badge.Visible = inSlot ~= nil
				if inSlot then bTxt.Text = tostring(inSlot) end
			end
		end
	end
end

local function assignToSlot(wid: string, slot: number)
	if not wid or wid == "" then return end

	if wid == "Fists" then
		hotbar[1] = "Fists"
		for s = 2, MAX_SLOTS do if hotbar[s] == "Fists" then hotbar[s] = nil end end
		equipped["Fists"] = true
		EquipWeaponRF:InvokeServer("")
		SyncHotbarEvent:FireServer(hotbar)
		playSfx("EQUIP")
		refreshGridVisuals()
		updateDetails(selectedWeaponId)
		return
	end

	if slot == 1 then return end
	for s = 1, MAX_SLOTS do if hotbar[s] == wid then hotbar[s] = nil end end
	removeSameGroupFromHotbar(wid, slot)

	hotbar[slot] = wid
	equipped[wid] = true

	EquipWeaponRF:InvokeServer(wid)
	SyncHotbarEvent:FireServer(hotbar)

	playSfx("EQUIP")
	refreshGridVisuals()
	updateDetails(selectedWeaponId)
end

local function unequipWeapon(wid: string)
	for s = 1, MAX_SLOTS do
		if hotbar[s] == wid then hotbar[s] = nil end
	end
	equipped[wid] = false
	EquipWeaponRF:InvokeServer("")
	SyncHotbarEvent:FireServer(hotbar)
	playSfx("UNEQUIP")
	refreshGridVisuals()
	updateDetails(selectedWeaponId)
end

-- Stats / Details --------------------------------------------------------------
local function avgM1Damage(wid: string): number
	local cfg = allWeapons[wid]
	if not cfg or not cfg.M1_Combo then return 0 end
	local total, count = 0, 0
	for _, step in pairs(cfg.M1_Combo) do
		local hi = step and step.HitInfo
		if hi and typeof(hi.Damage) == "number" then
			total += hi.Damage
			count += 1
		end
	end
	return (count > 0) and (total / count) or 0
end

local function skillsForWeapon(wid: string): { string }
	local names: { string } = {}
	local grp = getWeaponGroup(wid)
	if AbilitySets.Groups and AbilitySets.Groups[grp] and AbilitySets.Groups[grp].Abilities then
		for key, ab in pairs(AbilitySets.Groups[grp].Abilities) do
			if typeof(ab) == "table" then
				table.insert(names, tostring(ab.DisplayName or ab.Name or key))
			end
		end
	end
	if AbilitySets.Weapons and AbilitySets.Weapons[wid] and AbilitySets.Weapons[wid].Abilities then
		names = {}
		for key, ab in pairs(AbilitySets.Weapons[wid].Abilities) do
			if typeof(ab) == "table" then
				table.insert(names, tostring(ab.DisplayName or ab.Name or key))
			end
		end
	end
	table.sort(names)
	return names
end

local function ratingForWeapon(wid: string): number
	local dmg = avgM1Damage(wid)
	local skills = #skillsForWeapon(wid)
	local dmgPoints = math.clamp(math.floor((dmg / 10) * 3 + 0.5), 0, 3)
	local skillPoints = math.clamp(math.floor((skills / 3) * 2 + 0.5), 0, 2)
	return math.clamp(dmgPoints + skillPoints, 1, 5)
end

-- Details Panel ----------------------------------------------------------------
local function updateRatingDots(rating: number)
	for i, dot in ipairs(detailsRefs.RatingDots) do
		dot.BackgroundColor3 = i <= rating and RATING_DOT_ON or RATING_DOT_OFF
	end
end

setDetailsEmpty = function()
	if not details then return end
	if detailsRefs.Icon and detailsRefs.Icon:IsA("ImageLabel") then detailsRefs.Icon.Image = "" end
	if detailsRefs.Title and detailsRefs.Title:IsA("TextLabel") then detailsRefs.Title.Text = "" end
	if detailsRefs.Desc and detailsRefs.Desc:IsA("TextLabel") then detailsRefs.Desc.Text = "" end
	if detailsRefs.Dmg and detailsRefs.Dmg:IsA("TextLabel") then detailsRefs.Dmg.Text = "" end
	if detailsRefs.ActionBtn and detailsRefs.ActionBtn:IsA("TextButton") then detailsRefs.ActionBtn.Visible = false end
	if detailsRefs.SlotPill and detailsRefs.SlotPill:IsA("TextLabel") then detailsRefs.SlotPill.Visible = false end
	if detailsRefs.SkillsList and detailsRefs.SkillsList:IsA("ScrollingFrame") then
		for _,c in ipairs(detailsRefs.SkillsList:GetChildren()) do
			if not (c:IsA("UIListLayout") or c:IsA("UIPadding")) then c:Destroy() end
		end
	end
	updateRatingDots(0)
	if detailsRefs.EmptyMask and detailsRefs.EmptyMask:IsA("Frame") then
		detailsRefs.EmptyMask.Visible = true
	end
end

updateDetails = function(wid: string?)
	if not wid then
		setDetailsEmpty()
		return
	end

	local cfg = allWeapons[wid]
	if detailsRefs.EmptyMask and detailsRefs.EmptyMask:IsA("Frame") then
		detailsRefs.EmptyMask.Visible = false
	end

	if detailsRefs.Icon and detailsRefs.Icon:IsA("ImageLabel") then
		detailsRefs.Icon.Image = (wid == "Fists" and "" or (cfg and (cfg.Image or "") or ""))
	end
	if detailsRefs.Title and detailsRefs.Title:IsA("TextLabel") then
		detailsRefs.Title.Text = getWeaponName(wid)
	end

	local inSlot = slotOfWeapon(wid)
	if detailsRefs.SlotPill and detailsRefs.SlotPill:IsA("TextLabel") then
		detailsRefs.SlotPill.Visible = inSlot ~= nil
		if inSlot then detailsRefs.SlotPill.Text = "Slot " .. tostring(inSlot) end
	end

	if detailsRefs.Desc and detailsRefs.Desc:IsA("TextLabel") then
		detailsRefs.Desc.Text = string.format("Type: %s • Avg. M1 Damage: %.1f\nA versatile weapon of its category.", getWeaponGroup(wid), avgM1Damage(wid))
	end
	if detailsRefs.Dmg and detailsRefs.Dmg:IsA("TextLabel") then
		detailsRefs.Dmg.Text = string.format("Avg. M1 Damage: %.1f", avgM1Damage(wid))
	end

	if detailsRefs.SkillsList and detailsRefs.SkillsList:IsA("ScrollingFrame") then
		for _,c in ipairs(detailsRefs.SkillsList:GetChildren()) do
			if not (c:IsA("UIListLayout") or c:IsA("UIPadding")) then c:Destroy() end
		end
		local skills = skillsForWeapon(wid)
		if #skills == 0 then
			local none = Instance.new("TextLabel")
			none.BackgroundTransparency = 1
			none.Text = "No assigned skills"
			none.TextColor3 = TEXT_MUTED
			none.Font = Enum.Font.Gotham
			none.TextSize = 10
			none.TextXAlignment = Enum.TextXAlignment.Left
			none.Size = UDim2.new(1,0,0,14)
			none.Parent = detailsRefs.SkillsList
		else
			for _, s in ipairs(skills) do
				local row = Instance.new("TextLabel")
				row.BackgroundTransparency = 1
				row.Text = "• " .. s
				row.TextColor3 = TEXT
				row.Font = Enum.Font.Gotham
				row.TextSize = 10
				row.TextXAlignment = Enum.TextXAlignment.Left
				row.Size = UDim2.new(1,0,0,14)
				row.Parent = detailsRefs.SkillsList
			end
		end
	end

	updateRatingDots(ratingForWeapon(wid))

	if detailsRefs.ActionBtn and detailsRefs.ActionBtn:IsA("TextButton") then
		detailsRefs.ActionBtn.Visible = true
		detailsRefs.ActionBtn.Text = (equipped[wid] and "Unequip") or "Equip"
		detailsRefs.ActionBtn.BackgroundColor3 = equipped[wid] and Color3.fromRGB(50, 56, 68) or BLURPLE
		detailsRefs.ActionBtn.TextColor3 = equipped[wid] and TEXT or TEXT_DARK
	end
end

local function buildDetailsPanel(parent: Instance)
	details = Instance.new("Frame")
	details.Name, details.BackgroundColor3 = "Details", CARD_BG
	details.Size = UDim2.new(0, DETAILS_W, 1, -(HEADER_H + CONTROLS_H + CONTROLS_GAP + FOOTER_H + 3*PADDING))
	details.Position = UDim2.new(1, -PADDING - DETAILS_W, 0, HEADER_H + CONTROLS_H + CONTROLS_GAP + PADDING)
	details.Parent = parent
	round(details, 10); stroke(details)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = UDim.new(0,8), UDim.new(0,8), UDim.new(0,8), UDim.new(0,8)
	pad.Parent = details

	-- Empty mask to hide template at first open
	local emptyMask = Instance.new("Frame")
	emptyMask.Name = "EmptyMask"
	emptyMask.BackgroundColor3 = CARD_BG
	emptyMask.BorderSizePixel = 0
	emptyMask.Size = UDim2.new(1,0,1,0)
	emptyMask.Visible = true
	emptyMask.ZIndex = 1
	emptyMask.Parent = details
	round(emptyMask, 10)
	detailsRefs.EmptyMask = emptyMask

	local icon = Instance.new("ImageLabel"); icon.Name, icon.BackgroundTransparency = "Icon", 1
	icon.Size, icon.Position, icon.Parent = UDim2.new(1, -16, 0, 80), UDim2.new(0, 8, 0, 8), details
	icon.ZIndex = 0
	round(icon, 8); detailsRefs.Icon = icon

	local title = Instance.new("TextLabel"); title.Name, title.BackgroundTransparency = "Title", 1
	title.Font, title.TextSize, title.TextColor3, title.TextXAlignment = Enum.Font.GothamBlack, 14, TEXT, Enum.TextXAlignment.Left
	title.Size, title.Position, title.Parent = UDim2.new(1,-70,0,20), UDim2.new(0,8,0,92), details; detailsRefs.Title = title

	local slotPill = Instance.new("TextLabel"); slotPill.Name, slotPill.Visible, slotPill.BackgroundColor3 = "SlotPill", false, BLURPLE
	slotPill.Font, slotPill.TextSize, slotPill.TextColor3 = Enum.Font.GothamBold, 10, TEXT_DARK
	slotPill.Size, slotPill.Position, slotPill.Parent = UDim2.new(0,52,0,18), UDim2.new(1,-60,0,92), details
	round(slotPill, 8); detailsRefs.SlotPill = slotPill

	local desc = Instance.new("TextLabel"); desc.Name, desc.BackgroundTransparency = "Desc", 1
	desc.Font, desc.TextSize, desc.TextColor3, desc.TextWrapped = Enum.Font.Gotham, 10, TEXT_MUTED, true
	desc.TextXAlignment, desc.TextYAlignment, desc.Size, desc.Position = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top, UDim2.new(1,-8,0,50), UDim2.new(0,8,0,120)
	desc.Parent = details; detailsRefs.Desc = desc

	local dmg = Instance.new("TextLabel"); dmg.Name, dmg.BackgroundTransparency = "Dmg", 1
	dmg.Font, dmg.TextSize, dmg.TextColor3, dmg.TextXAlignment = Enum.Font.GothamSemibold, 10, TEXT, Enum.TextXAlignment.Left
	dmg.Size, dmg.Position, dmg.Parent = UDim2.new(1,-8,0,14), UDim2.new(0,8,0,176), details; detailsRefs.Dmg = dmg

	local ratingBox = Instance.new("Frame"); ratingBox.Name, ratingBox.BackgroundTransparency = "RatingBox", 1
	ratingBox.Size, ratingBox.Position, ratingBox.Parent = UDim2.new(1,-8,0,12), UDim2.new(0,8,0,196), details
	local rLay = Instance.new("UIListLayout"); rLay.FillDirection, rLay.Padding = Enum.FillDirection.Horizontal, UDim.new(0,4)
	rLay.VerticalAlignment = Enum.VerticalAlignment.Center; rLay.Parent = ratingBox
	for _ = 1, 5 do
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = RATING_DOT_OFF
		dot.BorderSizePixel = 0
		dot.Size = UDim2.new(0, 7, 0, 7)
		dot.Parent = ratingBox
		round(dot, 3)
		table.insert(detailsRefs.RatingDots, dot)
	end

	local skillsHeader = Instance.new("TextLabel"); skillsHeader.Text, skillsHeader.BackgroundTransparency = "Skills", 1
	skillsHeader.Font, skillsHeader.TextSize, skillsHeader.TextColor3, skillsHeader.TextXAlignment = Enum.Font.GothamBold, 11, TEXT, Enum.TextXAlignment.Left
	skillsHeader.Size, skillsHeader.Position, skillsHeader.Parent = UDim2.new(1,-8,0,16), UDim2.new(0,8,0,214), details

	local skillsList = Instance.new("ScrollingFrame"); skillsList.Name, skillsList.BackgroundTransparency = "SkillsList", 1
	skillsList.Size, skillsList.Position = UDim2.new(1,-8,1,-270), UDim2.new(0,8,0,232)
	skillsList.BorderSizePixel, skillsList.ScrollBarThickness, skillsList.CanvasSize = 0, 4, UDim2.new()
	skillsList.Parent = details
	local v = Instance.new("UIListLayout"); v.FillDirection, v.Padding = Enum.FillDirection.Vertical, UDim.new(0,3); v.Parent = skillsList
	detailsRefs.SkillsList = skillsList

	local btn = Instance.new("TextButton"); btn.Name, btn.AutoButtonColor = "Action", false
	btn.Font, btn.TextSize, btn.Size, btn.Position = Enum.Font.GothamBold, 12, UDim2.new(1,-8,0,28), UDim2.new(0,8,1,-36)
	btn.BorderSizePixel, btn.Parent = 0, details; round(btn, 8); detailsRefs.ActionBtn = btn

	btn.MouseButton1Click:Connect(function()
		if not selectedWeaponId then return end
		playSfx("CLICK")
		if equipped[selectedWeaponId] then
			unequipWeapon(selectedWeaponId)
		else
			local free: number? = nil
			for s = 2, MAX_SLOTS do
				if not hotbar[s] or hotbar[s] == "" then free = s; break end
			end
			if not free then free = 2 end
			assignToSlot(selectedWeaponId, free)
		end
	end)

	-- start empty
	setDetailsEmpty()
end

-- Dropdown (animated and shifted to the right) --------------------------------
local function updateDropdownSelectionVisualImpl()
	for _, child in ipairs(categoryDropdownList:GetChildren()) do
		if child:IsA("TextButton") then
			local isSel = (child.Name == currentTab)
			local dot = child:FindFirstChild("Dot")
			if not dot then
				dot = Instance.new("Frame")
				dot.Name = "Dot"
				dot.AnchorPoint = Vector2.new(0, 0.5)
				dot.Position = UDim2.new(0, 8, 0.5, 0)
				dot.Size = UDim2.new(0, 8, 0, 8)
				dot.BorderSizePixel = 0
				dot.BackgroundColor3 = RATING_DOT_OFF
				dot.Parent = child
				round(dot, 4)
				local pad = child:FindFirstChildOfClass("UIPadding")
				if not pad then
					pad = Instance.new("UIPadding")
					pad.Parent = child
				end
				pad.PaddingLeft = UDim.new(0, 22)
			end
			if dot:IsA("Frame") then
				dot.BackgroundColor3 = isSel and BLURPLE or RATING_DOT_OFF
			end
		end
	end
end

local function positionDropdownImpl()
	local btnPos = categoryDropdownButton.AbsolutePosition
	local btnSize = categoryDropdownButton.AbsoluteSize
	local listW = btnSize.X
	local listH = (#CATEGORIES * 28) + 12
	categoryDropdownList.Size = UDim2.new(0, listW, 0, math.clamp(listH, 120, 240))
	-- shift to the right a bit so it doesn't look cramped
	categoryDropdownList.Position = UDim2.new(0, btnPos.X + DROPDOWN_X_SHIFT, 0, btnPos.Y + btnSize.Y + 4)
end

local function openDropdownAnimatedImpl()
	if dropdownOpen then return end
	dropdownOpen = true
	positionDropdownImpl()
	updateDropdownSelectionVisualImpl()
	categoryDropdownList.Visible = true
	categoryDropdownList.ClipsDescendants = true
	screenCover.Visible = true

	playSfx("DROPDOWN_OPEN", 1.05)

	-- vertical scale animation
	local targetH = categoryDropdownList.Size.Y.Offset
	categoryDropdownList.Size = UDim2.new(categoryDropdownList.Size.X.Scale, categoryDropdownList.Size.X.Offset, 0, 8)
	tween(categoryDropdownList, 0.14, { Size = UDim2.new(categoryDropdownList.Size.X.Scale, categoryDropdownList.Size.X.Offset, 0, targetH) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, child in ipairs(categoryDropdownList:GetChildren()) do
		if child:IsA("TextButton") then
			child.TextTransparency = 1
			tween(child, 0.12, { TextTransparency = 0 })
		end
	end
end

local function closeDropdownAnimatedImpl()
	if not dropdownOpen then return end
	dropdownOpen = false
	playSfx("DROPDOWN_CLOSE", 0.95)
	for _, child in ipairs(categoryDropdownList:GetChildren()) do
		if child:IsA("TextButton") then
			tween(child, 0.1, { TextTransparency = 1 })
		end
	end
	local tw = tween(categoryDropdownList, 0.12, { Size = UDim2.new(categoryDropdownList.Size.X.Scale, categoryDropdownList.Size.X.Offset, 0, 8) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tw.Completed:Connect(function()
		categoryDropdownList.Visible = false
		screenCover.Visible = false
	end)
end

-- Bind the forward-declared functions
positionDropdown = positionDropdownImpl
updateDropdownSelectionVisual = updateDropdownSelectionVisualImpl
openDropdownAnimated = openDropdownAnimatedImpl
closeDropdownAnimated = closeDropdownAnimatedImpl

-- Grid ------------------------------------------------------------------------
local function rebuildGrid()
	if not gridScroll then return end
	for _, c in ipairs(gridScroll:GetChildren()) do
		if not (c:IsA("UIGridLayout") or c:IsA("UIPadding")) then c:Destroy() end
	end
	table.clear(gridCards); table.clear(gridWeaponIds)

	local list = getFilteredWeapons()
	for i, wid in ipairs(list) do
		local cfg = allWeapons[wid]
		local card = Instance.new("Frame")
		card.Name, card.BackgroundColor3, card.Parent = "Card_" .. wid, CARD_BG, gridScroll
		card.Size = UDim2.new(0, GRID_CARD_W, 0, GRID_CARD_H)
		round(card, 8); local border = stroke(card); local glow = makeGlow(card, 8); glow.ImageTransparency = 1

		local img = Instance.new("ImageButton")
		img.Name, img.BackgroundTransparency, img.Size = "Icon", 1, UDim2.new(1, 0, 0, GRID_CARD_H - 22)
		img.Image = (wid == "Fists" and "" or (cfg and (cfg.Image or "")))
		img.Parent = card

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name, nameLbl.BackgroundTransparency = "Name", 1
		nameLbl.Position, nameLbl.Size = UDim2.new(0, 4, 1, -16), UDim2.new(1, -8, 0, 12)
		nameLbl.Font, nameLbl.TextSize, nameLbl.TextColor3 = Enum.Font.GothamSemibold, 10, TEXT
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Text = getWeaponName(wid)
		nameLbl.Parent = card

		local badge = Instance.new("Frame")
		badge.Name, badge.Visible, badge.AnchorPoint, badge.Position = "SlotBadge", false, Vector2.new(1, 0), UDim2.new(1,-4,0,4)
		badge.Size, badge.BackgroundColor3, badge.Parent = UDim2.new(0,16,0,12), BLURPLE, card
		round(badge, 6)
		local bTxt = Instance.new("TextLabel")
		bTxt.Name, bTxt.BackgroundTransparency, bTxt.Size = "Txt", 1, UDim2.new(1,0,1,0)
		bTxt.Font, bTxt.TextSize, bTxt.TextColor3, bTxt.Text = Enum.Font.GothamBold, 10, TEXT_DARK, ""
		bTxt.Parent = badge

		card.MouseEnter:Connect(function()
			tween(card, 0.1, { BackgroundColor3 = CARD_BG_HOVER })
			tween(glow, 0.1, { ImageTransparency = 0.85 })
			playSfx("HOVER", 1.05)
		end)
		card.MouseLeave:Connect(function()
			tween(card, 0.15, { BackgroundColor3 = CARD_BG })
			tween(glow, 0.15, { ImageTransparency = 1 })
		end)

		img.MouseButton1Click:Connect(function()
			selectedIndex = i
			selectedWeaponId = wid
			updateDetails(wid)
			refreshGridVisuals()
			playSfx("CLICK")
			if dropdownOpen then closeDropdownAnimated() end
		end)

		gridCards[i] = card
		gridWeaponIds[i] = wid

		local inSlot = slotOfWeapon(wid)
		badge.Visible = inSlot ~= nil
		if inSlot then bTxt.Text = tostring(inSlot) end
		border.Color, border.Thickness = (inSlot and BLURPLE or STROKE), (inSlot and 1.6 or 1.1)
	end

	-- Keep selection if possible; otherwise keep panel empty (no auto-select)
	if selectedWeaponId then
		local idx = table.find(gridWeaponIds, selectedWeaponId)
		if idx then selectedIndex = idx end
		updateDetails(selectedWeaponId)
	else
		setDetailsEmpty()
	end
	refreshGridVisuals()
end

-- UI Construction --------------------------------------------------------------
local function buildControlsRow(parent: Instance)
	local controlsRow = Instance.new("Frame")
	controlsRow.Name = "ControlsRow"
	controlsRow.BackgroundTransparency = 1
	controlsRow.Size = UDim2.new(1, -2*PADDING, 0, CONTROLS_H)
	controlsRow.Position = UDim2.new(0, PADDING, 0, HEADER_H + PADDING)
	controlsRow.Parent = parent

	-- Search
	local searchBox = Instance.new("TextBox")
	searchBox.Name, searchBox.BackgroundColor3 = "SearchBox", CARD_BG
	searchBox.Size, searchBox.Position = UDim2.new(0, 240, 1, 0), UDim2.new(0, 0, 0, 0)
	searchBox.Font, searchBox.TextSize = Enum.Font.Gotham, 12
	searchBox.TextColor3, searchBox.PlaceholderColor3 = TEXT, TEXT_MUTED
	searchBox.Text = ""
	searchBox.PlaceholderText = "Search weapons..."
	searchBox.ClearTextOnFocus = false
	searchBox.Parent = controlsRow
	round(searchBox, 8); stroke(searchBox)
	local searchPad = Instance.new("UIPadding"); searchPad.PaddingLeft = UDim.new(0,26); searchPad.Parent = searchBox
	local searchIcon = Instance.new("ImageLabel")
	searchIcon.BackgroundTransparency = 1; searchIcon.Image = SEARCH_ICON_IMG
	searchIcon.Size, searchIcon.Position = UDim2.new(0,14,0,14), UDim2.new(0,6,0.5,-7)
	searchIcon.ImageColor3 = TEXT_MUTED
	searchIcon.Parent = searchBox
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		currentSearchQuery = searchBox.Text or ""
		rebuildGrid()
	end)

	-- Dropdown button
	categoryDropdownButton = Instance.new("TextButton")
	categoryDropdownButton.Name = "CategoryDropdown"
	categoryDropdownButton.BackgroundColor3 = CARD_BG
	categoryDropdownButton.Size = UDim2.new(0, 160, 1, 0)
	categoryDropdownButton.Position = UDim2.new(0, 240 + CONTROLS_GAP, 0, 0)
	categoryDropdownButton.Font = Enum.Font.GothamBold
	categoryDropdownButton.Text = "Category: " .. currentTab
	categoryDropdownButton.TextColor3 = TEXT
	categoryDropdownButton.TextSize = 12
	categoryDropdownButton.AutoButtonColor = false
	categoryDropdownButton.Parent = controlsRow
	round(categoryDropdownButton, 8); stroke(categoryDropdownButton)

	local chevron = Instance.new("ImageLabel")
	chevron.Image = CHEVRON_DOWN_ICON_IMG
	chevron.BackgroundTransparency = 1
	chevron.Size = UDim2.new(0, 16, 0, 16)
	chevron.Position = UDim2.new(1, -20, 0.5, -8)
	chevron.Parent = categoryDropdownButton

	-- Dropdown list (ScreenGui)
	categoryDropdownList = Instance.new("Frame")
	categoryDropdownList.Name = "DropdownList"
	categoryDropdownList.BackgroundColor3 = CARD_BG
	categoryDropdownList.BorderSizePixel = 0
	categoryDropdownList.Visible = false
	categoryDropdownList.Active = true
	categoryDropdownList.ZIndex = 20
	categoryDropdownList.Parent = gui
	round(categoryDropdownList, 8); stroke(categoryDropdownList)

	local listLayout = Instance.new("UIListLayout"); listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, 2); listLayout.Parent = categoryDropdownList
	local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6); pad.Parent = categoryDropdownList

	for _, cat in ipairs(CATEGORIES) do
		local item = Instance.new("TextButton")
		item.Name = cat
		item.BackgroundColor3 = Color3.fromRGB(24,26,32)
		item.AutoButtonColor = false
		item.Size = UDim2.new(1, -12, 0, 24)
		item.Text = cat
		item.Font = Enum.Font.Gotham
		item.TextSize = 12
		item.TextColor3 = TEXT
		item.Parent = categoryDropdownList
		round(item, 6); stroke(item, STROKE, 1, 0.2)

		-- Selection dot
		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 8, 0.5, 0)
		dot.Size = UDim2.new(0, 8, 0, 8)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = RATING_DOT_OFF
		dot.Parent = item
		round(dot, 4)
		local itemPad = Instance.new("UIPadding"); itemPad.PaddingLeft = UDim.new(0, 22); itemPad.Parent = item

		item.MouseEnter:Connect(function()
			if item.Name ~= currentTab then tween(item, 0.08, { BackgroundColor3 = Color3.fromRGB(28, 30, 38) }) end
		end)
		item.MouseLeave:Connect(function()
			if item.Name ~= currentTab then tween(item, 0.12, { BackgroundColor3 = Color3.fromRGB(24, 26, 32) }) end
		end)
		item.MouseButton1Click:Connect(function()
			currentTab = item.Name
			categoryDropdownButton.Text = "Category: " .. currentTab
			updateDropdownSelectionVisual()
			playSfx("CATEGORY")
			closeDropdownAnimated()
			rebuildGrid()
		end)
	end

	categoryDropdownButton.MouseButton1Click:Connect(function()
		if dropdownOpen then closeDropdownAnimated() else openDropdownAnimated() end
	end)

	-- Reposition on window resize
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if dropdownOpen then positionDropdown() end
	end)
end

local function buildHeader(parent: Instance)
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -2*PADDING, 0, HEADER_H)
	header.Position = UDim2.new(0, PADDING, 0, PADDING)
	header.Parent = parent

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Text = "Armory"
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextColor3 = TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, -40, 1, 0)
	title.Parent = header

	local closeBtn = Instance.new("ImageButton")
	closeBtn.BackgroundTransparency = 1
	closeBtn.Image = CLOSE_ICON_IMG
	closeBtn.Size = UDim2.new(0, 24, 0, 24)
	closeBtn.Position = UDim2.new(1, -24, 0.5, -12)
	closeBtn.Parent = header
	closeBtn.MouseButton1Click:Connect(function()
		if open then
			closeDropdownAnimated()
			closeMenu()
		end
	end)
end

local function buildFooter(parent: Instance)
	footer = Instance.new("Frame")
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, -2*PADDING, 0, FOOTER_H)
	footer.Position = UDim2.new(0, PADDING, 1, -FOOTER_H - PADDING)
	footer.Parent = parent
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Text = "1–7: Assign to Slot • Click a card to select • Use Equip button to apply"
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextColor3 = TEXT_MUTED
	hint.Size = UDim2.new(1,0,1,0)
	hint.Parent = footer
end

local function buildGrid(parent: Instance)
	gridScroll = Instance.new("ScrollingFrame")
	gridScroll.Name, gridScroll.BackgroundTransparency = "Grid", 1
	gridScroll.ScrollBarThickness = 5
	gridScroll.Size = UDim2.new(1, -(DETAILS_W + 3*PADDING), 1, -(HEADER_H + CONTROLS_H + CONTROLS_GAP + FOOTER_H + 3*PADDING))
	gridScroll.Position = UDim2.new(0, PADDING, 0, HEADER_H + CONTROLS_H + CONTROLS_GAP + PADDING)
	gridScroll.Parent = parent

	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingLeft = UDim.new(0, 12)
	gridPadding.PaddingRight = UDim.new(0, 12)
	gridPadding.PaddingTop = UDim.new(0, 12)
	gridPadding.PaddingBottom = UDim.new(0, 12)
	gridPadding.Parent = gridScroll

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, GRID_CARD_W, 0, GRID_CARD_H)
	grid.CellPadding = UDim2.new(0, GRID_GAP, 0, GRID_GAP)
	grid.Parent = gridScroll
end

-- Controls / lifecycle ---------------------------------------------------------
local function assignCurrentToSlot(digit: number)
	if not selectedWeaponId then return end
	if digit == 1 then
		assignToSlot("Fists", 1)
	elseif selectedWeaponId ~= "Fists" then
		assignToSlot(selectedWeaponId, digit)
	end
end

local function onKey(input: InputObject, gpe: boolean)
	if gpe or not open then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if UserInputService:GetFocusedTextBox() then return end

	local digit = tonumber(input.KeyCode.Name:match("^%d$"))
	if digit and digit >= 1 and digit <= MAX_SLOTS then assignCurrentToSlot(digit); return end
end

function openMenu()
	if not gui or not frame then return end
	open = true
	gui.Enabled = true
	rebuildGrid()
	playSfx("OPEN")
	tween(frame, 0.25, { Position = UDim2.new(0.5, 0, 0, 16) }, Enum.EasingStyle.Back)
end

function closeMenu()
	if not gui or not frame then return end
	open = false
	closeDropdownAnimated()
	playSfx("CLOSE")
	local tw = tween(frame, 0.25, { Position = UDim2.new(0.5, 0, 0, -FRAME_H) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tw.Completed:Connect(function() if not open and gui then gui.Enabled = false end end)
end

SyncHotbarEvent.OnClientEvent:Connect(function(list: { [number]: string }?)
	if not list then return end
	hotbar = list
	table.clear(equipped)
	for _, wid in pairs(hotbar) do if wid and wid ~= "" then equipped[wid] = true end end
	ensureFistsInSlot1()
	if open then
		closeDropdownAnimated()
		rebuildGrid()
		updateDetails(selectedWeaponId)
	end
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if input.KeyCode == Enum.KeyCode.G and not gpe and not UserInputService:GetFocusedTextBox() then
		if open then closeMenu() else openMenu() end
		return
	end
	onKey(input, gpe)
end)

-- Init -------------------------------------------------------------------------
local function buildUI()
	gui = Instance.new("ScreenGui"); gui.Name, gui.ResetOnSpawn, gui.Enabled, gui.DisplayOrder = "WeaponMenuGUI", false, false, 3
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	ensureSfx()

	screenCover = Instance.new("TextButton")
	screenCover.Name = "ScreenCover"
	screenCover.Text = ""
	screenCover.AutoButtonColor = false
	screenCover.BackgroundTransparency = 1
	screenCover.Size = UDim2.new(1, 0, 1, 0)
	screenCover.ZIndex = 19
	screenCover.Visible = false
	screenCover.Parent = gui
	screenCover.MouseButton1Click:Connect(function()
		closeDropdownAnimated()
	end)

	frame = Instance.new("Frame"); frame.Name, frame.BackgroundTransparency = "Root", 1
	frame.AnchorPoint, frame.Size = Vector2.new(0.5, 0), UDim2.new(0, FRAME_W, 0, FRAME_H)
	frame.Position = UDim2.new(0.5, 0, 0, -FRAME_H - 20)
	frame.Parent = gui

	sheet = Instance.new("Frame"); sheet.Name, sheet.BackgroundColor3 = "Sheet", BG_COLOR
	sheet.AnchorPoint, sheet.Size, sheet.Position = Vector2.new(0.5,0), UDim2.new(1,-SHEET_MARGIN_X,1,-SHEET_MARGIN_Y), UDim2.new(0.5,0,0,0)
	sheet.ClipsDescendants = false
	sheet.Parent = frame; round(sheet, 14); stroke(sheet, STROKE, 1.2); makeGlow(sheet, 14)

	-- Build sections
	buildHeader(sheet)
	buildControlsRow(sheet)
	buildGrid(sheet)
	buildDetailsPanel(sheet)
	buildFooter(sheet)
end

buildUI()
ensureFistsInSlot1()
