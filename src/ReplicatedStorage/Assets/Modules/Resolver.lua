--!strict
-- ConfigResolver: MovesetConfig + WeaponConfig + AbilitySets + WeaponTypeResolver
-- Abilities: SOLO AbilitySets (Universal + Group + Weapon). Sin fallback al moveset base.

local RS = game:GetService("ReplicatedStorage")
local Modules = RS.Assets:WaitForChild("Modules")

local MovesetConfig = require(Modules:WaitForChild("MovesetConfig"))
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local AbilitySets = require(Modules:WaitForChild("AbilitySets"))
local WeaponTypeResolver = require(Modules:WaitForChild("WeaponTypeResolver"))

local Resolver = {}

local function shallowCopy(tbl: any): any
	if type(tbl) ~= "table" then return tbl end
	local out = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			local inner = {}
			for k2, v2 in pairs(v) do inner[k2] = v2 end
			out[k] = inner
		else
			out[k] = v
		end
	end
	return out
end

local function shallowMerge(base: any, override: any): any
	if type(base) ~= "table" then return shallowCopy(override or base) end
	local out = shallowCopy(base)
	if type(override) ~= "table" then return out end
	for k, v in pairs(override) do
		if type(v) == "table" and type(out[k]) == "table" then
			local inner = shallowCopy(out[k])
			for k2, v2 in pairs(v) do inner[k2] = v2 end
			out[k] = inner
		else
			out[k] = v
		end
	end
	return out
end

local function abilitiesFromSets(group: string?, weaponId: string?): any
	local result = {}

	if AbilitySets.Universal and AbilitySets.Universal.Abilities then
		result = shallowMerge(result, AbilitySets.Universal.Abilities)
	end
	if group and AbilitySets.Groups and AbilitySets.Groups[group] and AbilitySets.Groups[group].Abilities then
		result = shallowMerge(result, AbilitySets.Groups[group].Abilities)
	end
	if weaponId and AbilitySets.Weapons and AbilitySets.Weapons[weaponId] and AbilitySets.Weapons[weaponId].Abilities then
		result = shallowMerge(result, AbilitySets.Weapons[weaponId].Abilities)
	end

	return result
end

function Resolver.get(character: Model): any
	local movesetName = (character:GetAttribute("Moveset") or "MainCharacter") :: string
	local base = MovesetConfig[movesetName] or {}

	local merged = shallowCopy(base)
	merged.Abilities = nil

	local weaponId = character:GetAttribute("WeaponId")
	local weaponCfg = (weaponId and WeaponConfig[weaponId]) or nil

	local group = WeaponTypeResolver.bestEffort({
		character = character,
		weaponId = weaponId,
		modelName = weaponCfg and weaponCfg.ModelName or nil,
		modelInstance = character, -- escaneará tags del arma clonada en el rig
		weaponConfigType = weaponCfg and weaponCfg.Type or nil,
	})

	local resolvedAbilities = abilitiesFromSets(group, weaponId)
	merged.Abilities = resolvedAbilities or {}

	if weaponCfg and weaponCfg.M1_Combo then
		merged.M1_Combo = shallowCopy(weaponCfg.M1_Combo)
	end

	for _, key in ipairs({ "HitReactions", "Dashes", "DashesAir", "Block" }) do
		local fromBase = base[key] or {}
		local fromWeapon = weaponCfg and weaponCfg[key] or nil
		merged[key] = shallowMerge(fromBase, fromWeapon or {})
	end

	return merged
end

return Resolver
