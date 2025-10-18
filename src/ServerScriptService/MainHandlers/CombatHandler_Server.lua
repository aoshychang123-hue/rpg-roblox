--!strict
-- Script de orquestación: conecta remotes, registra estados y carga WeaponManager para RF EquipWeapon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatEvent = Remotes:WaitForChild("CombatEvent")
local DashGet = Remotes:WaitForChild("DashGet")

local ModulesFolder = ServerScriptService:WaitForChild("Modules")
local CombatModule = require(ModulesFolder:WaitForChild("CombatModule"))
local DashModule = require(ModulesFolder:WaitForChild("DashModule"))
local CharacterStateManager = require(ModulesFolder:WaitForChild("CharacterStateManager"))

-- NUEVO: cargar WeaponManager para inicializar RF EquipWeapon y re-equip en respawn
local WeaponManager = require(ModulesFolder:WaitForChild("WeaponManager"))

Players.PlayerAdded:Connect(function(player)
	local function onCharacterAdded(character)
		CharacterStateManager.setupCharacterStateManager(character, player)
		if CombatModule.attachBlockVisualWatcher then
			CombatModule.attachBlockVisualWatcher(character)
		end
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end)

CombatEvent.OnServerEvent:Connect(function(player, action, params)
	if not player or not player.Character then return end
	if action == "DashHit" then
		DashModule.handleDashHit(player, params and params.Target, params and params.Direction)
		return
	end
	CombatModule.handleCombat(player, action, params)
end)

DashGet.OnServerInvoke = function(player, direction)
	if not player or not player.Character then return false end
	return DashModule.performDash(player, direction)
end

print("✅ Combat_Handler_Server + WeaponManager listos")




