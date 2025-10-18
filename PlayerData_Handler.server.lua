-- Servicios
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local RS = game:GetService("ReplicatedStorage")

-- Módulos
local CharacterProperties = require(RS.Assets.Modules:WaitForChild("CharacterProperties"))
local RagdollHandler = require(RS.Assets.Modules:WaitForChild("RagdollHandler"))

-- Asegurarse de que exista el folder Players en Workspace
local playersFolder = workspace:FindFirstChild("Players")
if not playersFolder then
	playersFolder = Instance.new("Folder")
	playersFolder.Name = "Players"
	playersFolder.Parent = workspace
end

-- Asegurarse de que el grupo de colisiones "Players" exista
local COLLISION_GROUP_NAME = "Players"

local groups = PhysicsService:GetRegisteredCollisionGroups()
local exists = false
for _, group in ipairs(groups) do
	if group.name == COLLISION_GROUP_NAME then
		exists = true
		break
	end
end

if not exists then
	print("El grupo de colisiones '" .. COLLISION_GROUP_NAME .. "' no existía. Creándolo ahora.")
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_NAME)

	-- Configura con qué puede colisionar este grupo
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_NAME, COLLISION_GROUP_NAME, true)
end

-- Funciones
local function applyDefaultProperties(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.BreakJointsOnDeath = false

	print("Aplicando propiedades por defecto a: " .. character.Name)

	-- Asignar todas las partes del personaje al grupo de colisiones
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP_NAME
		end
	end
	print("Asignado '" .. character.Name .. "' al grupo de colisión: " .. COLLISION_GROUP_NAME)

	for propertyName, defaultValue in pairs(CharacterProperties) do
		character:SetAttribute(propertyName, defaultValue)
	end

	humanoid.MaxHealth = character:GetAttribute("MaxHealth")
	humanoid.Health = humanoid.MaxHealth

	humanoid.Died:Connect(function()
		RagdollHandler.applyRagdoll(character, 10)
	end)

	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed then
			if CollectionService:HasTag(character, "HasDoubleJumped") then
				CollectionService:RemoveTag(character, "HasDoubleJumped")
			end
		end
	end)

	-- ✅ Mover el Character al folder Players en Workspace
	character.Parent = playersFolder
end

local function onPlayerAdded(player)
	player:SetAttribute("IsSprinting", false)
	player.CharacterAdded:Connect(applyDefaultProperties)
end

-- Conexiones
Players.PlayerAdded:Connect(onPlayerAdded)