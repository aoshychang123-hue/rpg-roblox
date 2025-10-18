--!strict
-- Debug avanzado: imprime WeaponId, WeaponType y habilidades disponibles (Z/X/C/V).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Modules = RS:WaitForChild("Assets"):WaitForChild("Modules")
local ConfigResolver = require(Modules:WaitForChild("ConfigResolver"))
local WeaponTypeResolver = require(Modules:WaitForChild("WeaponTypeResolver"))
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))

local player = Players.LocalPlayer
local ORDER = { "Z", "X", "C", "V" }

local function dump()
	local ch = player.Character
	if not ch then return end
	local wid = ch:GetAttribute("WeaponId")
	local wtypeAttr = ch:GetAttribute("WeaponType")
	local cfg = WeaponConfig[wid or ""]
	local byTemplate = WeaponTypeResolver.detectFromModelName(cfg and cfg.ModelName or nil)

	local ok, res = pcall(function() return ConfigResolver.get(ch) end)
	print(("[AbilityDebug] WeaponId=%s | Attr.WeaponType=%s | byTemplate=%s | resolverOk=%s")
		:format(tostring(wid), tostring(wtypeAttr), tostring(byTemplate), tostring(ok)))

	if ok and res and res.Abilities then
		for _, k in ipairs(ORDER) do
			local ab = res.Abilities[k]
			if ab then
				print(string.format("[AbilityDebug] %s: name='%s' anim='%s' cd=%s",
					k, tostring(ab.DisplayName or ab.Name or k), tostring(ab.Animation), tostring(ab.Cooldown)))
			else
				print(string.format("[AbilityDebug] %s: (Without Skill)", k))
			end
		end
	end
end

local function bind(ch: Model)
	ch:GetAttributeChangedSignal("WeaponType"):Connect(dump)
	ch:GetAttributeChangedSignal("WeaponId"):Connect(dump)
	task.delay(0.1, dump)
end

if player.Character then bind(player.Character) end
player.CharacterAdded:Connect(bind)
