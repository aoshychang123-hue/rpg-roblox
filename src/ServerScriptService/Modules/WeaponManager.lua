--!strict
-- WeaponManager: equipar/desequipar armas + SyncHotbar
-- - Setea Character.Attribute("WeaponType") usando tags o Type de WeaponConfig.
-- - Normaliza hotbar: solo 1 arma por categoría (Sword/Bow/Maze/Spear/Shield/Fists).
-- - Slot 1 reservado para Fists.

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ModulesRS = RS.Assets:WaitForChild("Modules")
local WeaponConfig = require(ModulesRS:WaitForChild("WeaponConfig"))
local EquipUtil = require(ModulesRS:WaitForChild("EquipUtil"))
local WeaponTypeResolver = require(ModulesRS:WaitForChild("WeaponTypeResolver"))

local Remotes = RS:WaitForChild("Remotes")
local EquipWeaponRF: RemoteFunction = Remotes:FindFirstChild("EquipWeapon") :: RemoteFunction
if not EquipWeaponRF then
	EquipWeaponRF = Instance.new("RemoteFunction")
	EquipWeaponRF.Name = "EquipWeapon"
	EquipWeaponRF.Parent = Remotes
end

local SyncHotbarEvent: RemoteEvent = Remotes:FindFirstChild("SyncHotbar") :: RemoteEvent
if not SyncHotbarEvent then
	SyncHotbarEvent = Instance.new("RemoteEvent")
	SyncHotbarEvent.Name = "SyncHotbar"
	SyncHotbarEvent.Parent = Remotes
end

local MAX_SLOTS = 7

local WeaponManager = {}
local equipped: { [Model]: any } = {}
local hotbars: { [number]: { [number]: string } } = {} -- player.UserId -> { slot = weaponId }

local function destroyEquipped(character: Model)
	local eq = equipped[character]
	if eq and eq.destroy then pcall(eq.destroy) end
	equipped[character] = nil
end

local function setCharacterWeaponType(ch: Model, weaponId: string?, modelName: string?, modelInst: Instance?)
	local cfg = (weaponId and WeaponConfig[weaponId]) or nil
	local wtype = WeaponTypeResolver.bestEffort({
		character = ch,
		weaponId = weaponId,
		modelName = modelName,
		modelInstance = modelInst,
		weaponConfigType = cfg and cfg.Type or nil,
	})
	ch:SetAttribute("WeaponType", wtype)
end

-- Normalizador de strings (para matching robusto)
local function normKey(s: string?): string
	if typeof(s) ~= "string" then return "" end
	return s:lower():gsub("%s+", "")
end

local function isMazoUno(weaponId: string, cfg: any): boolean
	local idk = normKey(weaponId)
	local modelk = normKey(cfg and cfg.ModelName or nil)
	-- Soporta "Mazo1" o "Mazo Uno" tanto en id como en model name
	return (idk == "mazo1" or idk == "mazouno") or (modelk == "Mazo1" or modelk == "mazouno")
end

local function attachModelFor(character: Model, weaponId: string)
	destroyEquipped(character)
	local cfg = WeaponConfig[weaponId]
	if not cfg then return end

	if cfg.AttachSide == "RightArm" then
		equipped[character] = EquipUtil.AttachToRightArm({
			Character = character,
			ModelPath = cfg.ModelName or "Sword1",
			Looped = false,
			FadeIn = 0.08,
			FadeOut = 0.12,
			ForwardOffset = 0.2,
		})

		-- Ajuste especial de Motor6D para "Mazo1"
		if isMazoUno(weaponId, cfg) then
			local eq = equipped[character]
			if eq and eq.joint and eq.joint:IsA("Motor6D") then
				-- C0.Position = (0.015, -0.958, -0.086)
				-- C0.Orientation = (0, 0, 180) -> rotación en Z de 180°
				eq.joint.C0 = CFrame.new(0.015, -0.958, -0.086) * CFrame.Angles(0, 0, math.rad(180))
				-- Mantiene C1 tal cual para respetar el grip del modelo si existe.
			end
		end
	elseif cfg.AttachSide == "LeftArm" then
		equipped[character] = EquipUtil.AttachToLeftArm({
			Character = character,
			ModelPath = cfg.ModelName or "Shield1",
		})
	end

	local eq = equipped[character]
	setCharacterWeaponType(character, weaponId, cfg.ModelName, eq and eq.model or nil)
end

function WeaponManager.equip(player: Player, weaponId: string?)
	if not player or not player.Character then
		return { ok = false, err = "NoCharacter" }
	end
	local ch = player.Character

	-- Desequipar -> Fists
	if weaponId == nil or weaponId == "" then
		ch:SetAttribute("WeaponId", nil)
		destroyEquipped(ch)
		ch:SetAttribute("WeaponType", "Fists")
		return { ok = true, weapon = "" }
	end

	if type(weaponId) ~= "string" or not WeaponConfig[weaponId] then
		return { ok = false, err = "UnknownWeapon" }
	end

	-- evita equip mientras ataca o está caído
	if ch:GetAttribute("IsPunching") or ch:GetAttribute("IsRagdolled") then
		return { ok = false, err = "Busy" }
	end

	ch:SetAttribute("WeaponId", weaponId)
	attachModelFor(ch, weaponId)
	return { ok = true, weapon = weaponId }
end

EquipWeaponRF.OnServerInvoke = function(player: Player, weaponId: string?)
	return WeaponManager.equip(player, weaponId)
end

-- Normaliza hotbar: "última elección gana" por categoría.
local function normalizeHotbar(list: { [number]: string }?): { [number]: string }
	local out: { [number]: string } = {}

	if not list then return out end

	-- 1) Resolver última posición para cada categoría
	type Pos = { slot: number, wid: string }
	local posByKey: { [string]: Pos } = {} -- keys de categoría o ITEM:wid para ítems

	for s = 1, MAX_SLOTS do
		local wid = list[s]
		if wid and wid ~= "" then
			if wid == "Fists" then
				posByKey["Fists"] = { slot = 1, wid = "Fists" } -- siempre a 1
			else
				local cfg = WeaponConfig[wid]
				if cfg then
					local grp = WeaponTypeResolver.fromWeaponConfigType(cfg.Type)
					if grp and grp ~= "Fists" then
						posByKey[grp] = { slot = s, wid = wid } -- última gana
					else
						-- sin grupo válido => trata como ítem o arma desconocida, no deduplica
						posByKey["ITEM:" .. wid] = { slot = s, wid = wid }
					end
				else
					-- Ítems u otros
					posByKey["ITEM:" .. wid] = { slot = s, wid = wid }
				end
			end
		end
	end

	-- 2) Escribir posiciones finales
	for key, pos in pairs(posByKey) do
		if key == "Fists" then
			out[1] = "Fists"
		else
			out[pos.slot] = pos.wid
		end
	end

	-- 3) Garantizar Fists en slot 1 si existe en otro lado
	for s = 2, MAX_SLOTS do
		if out[s] == "Fists" then out[s] = nil end
	end

	return out
end

-- Sync desde cliente
SyncHotbarEvent.OnServerEvent:Connect(function(player: Player, hotbarList: { [number]: string })
	if not player then return end
	local normalized = normalizeHotbar(hotbarList)
	hotbars[player.UserId] = normalized
	SyncHotbarEvent:FireClient(player, normalized)
end)

-- Al entrar/respawn
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(ch)
		local current = ch:GetAttribute("WeaponId")
		if current and WeaponConfig[current] then
			attachModelFor(ch, current)
		else
			ch:SetAttribute("WeaponType", "Fists")
		end
		ch.AncestryChanged:Connect(function(_, parent)
			if not parent then equipped[ch] = nil end
		end)
		local hb = hotbars[p.UserId]
		if hb then
			SyncHotbarEvent:FireClient(p, hb)
		else
			local defaultHotbar = { [1] = "Fists" }
			hotbars[p.UserId] = defaultHotbar
			SyncHotbarEvent:FireClient(p, defaultHotbar)
		end
	end)
end)

return WeaponManager
