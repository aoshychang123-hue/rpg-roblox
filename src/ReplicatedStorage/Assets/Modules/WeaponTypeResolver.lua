--!strict
-- WeaponTypeResolver
-- - Detecta el grupo del arma a partir de tags o de WeaponConfig.Type.
-- - Orden de prioridad (más confiable -> menos confiable):
--   1) Tags en la instancia equipada dentro del Character (modelInstance)
--   2) Tags en la plantilla (ReplicatedStorage.Assets.Models[ModelName])
--   3) Type del WeaponConfig (Espada/Mazo/… -> Sword/Maze/…)
--   4) Atributo Character.WeaponType (puede estar desfasado)
--   5) Fallback: "Fists"
--
-- Tags esperados: "Sword", "Bow", "Maze", "Spear", "Shield"
-- Nota: “Fists” no requiere tag.

local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local assets = RS:FindFirstChild("Assets")
local modelsFolder = assets and assets:FindFirstChild("Models")

local WeaponTypeResolver = {}

local TAGS: {[string]: {string}} = {
	Sword  = { "Sword" },
	Bow    = { "Bow" },
	Maze   = { "Maze", "Mazo", "Mace", "Hammer" },
	Spear  = { "Spear" },
	Shield = { "Shield" },
}

local TYPE_TO_GROUP = {
	-- Español
	["Espada"] = "Sword",
	["Arco"]   = "Bow",
	["Mazo"]   = "Maze",
	["Lanza"]  = "Spear",
	["Escudo"] = "Shield",
	["Puños"]  = "Fists",
	-- Inglés/alias
	["Sword"]  = "Sword",
	["Bow"]    = "Bow",
	["Maze"]   = "Maze",
	["Mace"]   = "Maze",
	["Hammer"] = "Maze",
	["Spear"]  = "Spear",
	["Shield"] = "Shield",
	["Fists"]  = "Fists",
}

local function normalizeGroup(s: string?): string?
	if typeof(s) ~= "string" or #s == 0 then return nil end
	return TYPE_TO_GROUP[s] or s
end

local function hasAnyTag(inst: Instance, tagList: {string}): boolean
	for _, t in ipairs(tagList) do
		if CollectionService:HasTag(inst, t) then return true end
	end
	return false
end

local function detectOnInstance(inst: Instance): string?
	-- root
	for group, tagList in pairs(TAGS) do
		if hasAnyTag(inst, tagList) then return group end
	end
	-- descendientes
	for _, d in ipairs(inst:GetDescendants()) do
		for group, tagList in pairs(TAGS) do
			if hasAnyTag(d, tagList) then return group end
		end
	end
	return nil
end

function WeaponTypeResolver.detectFromInstance(inst: Instance?): string?
	if not inst then return nil end
	return detectOnInstance(inst)
end

function WeaponTypeResolver.detectFromModelName(modelName: string?): string?
	if not modelName or not modelsFolder then return nil end
	local templ = modelsFolder:FindFirstChild(modelName)
	if not templ then return nil end
	return detectOnInstance(templ)
end

function WeaponTypeResolver.fromWeaponConfigType(t: string?): string?
	return normalizeGroup(t)
end

-- Prioridad fuerte: instancia -> plantilla -> config -> atributo -> Fists
function WeaponTypeResolver.bestEffort(args: {
	character: Model?,
	weaponId: string?,
	modelName: string?,
	modelInstance: Instance?,
	weaponConfigType: string?,
	}): string
	-- 1) Tags en la instancia equipada dentro del Character (si se pasa)
	local t = WeaponTypeResolver.detectFromInstance(args.modelInstance)
	if t then return t end

	-- 2) Tags en la plantilla del modelo
	t = WeaponTypeResolver.detectFromModelName(args.modelName)
	if t then return t end

	-- 3) Type del WeaponConfig
	t = WeaponTypeResolver.fromWeaponConfigType(args.weaponConfigType)
	if t then return t end

	-- 4) Atributo del Character (podría estar desfasado)
	if args.character then
		local attr = args.character:GetAttribute("WeaponType")
		local norm = normalizeGroup(typeof(attr) == "string" and (attr :: any) or nil)
		if norm then return norm end
	end

	-- 5) Fallback
	return "Fists"
end

return WeaponTypeResolver
