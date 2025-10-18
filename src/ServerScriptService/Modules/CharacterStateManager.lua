-- CharacterStateManager.lua
-- Inicializa y resetea atributos del personaje (preserva CharacterProperties)

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterProperties = require(RS.Assets.Modules:WaitForChild("CharacterProperties"))

local CharacterStateManager = {}

local BLOCK_HEALTH_DEFAULT = 3

-- setupCharacterStateManager(character, player)
function CharacterStateManager.setupCharacterStateManager(character, player)
	if not character then return end

	-- Copiar propiedades base del módulo CharacterProperties
	for property, value in pairs(CharacterProperties) do
		character:SetAttribute(property, value)
	end

	-- Estados base (igual que en tu script original)
	character:SetAttribute("IsStunned", false)
	character:SetAttribute("IsDashing", false)
	character:SetAttribute("IsPunching", false)
	character:SetAttribute("IsInAir", false)
	character:SetAttribute("HasDoubleJumped", false)
	character:SetAttribute("SideDashOnCD", false)
	character:SetAttribute("FrontDashOnCD", false)
	character:SetAttribute("IsBlocking", false)
	character:SetAttribute("BlockHealth", BLOCK_HEALTH_DEFAULT)
	character:SetAttribute("LastM1Time", 0)
	character:SetAttribute("M1_Queued", false)
	character:SetAttribute("LastDashDirection", nil)
	character:SetAttribute("AirDashCount", 0)
	character:SetAttribute("AirDashOnCD", false)

	-- Ajustar humanoid (salud inicial)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = character:GetAttribute("MaxHealth") or humanoid.MaxHealth or 100
		humanoid.Health = humanoid.MaxHealth
		humanoid.StateChanged:Connect(function(oldState, newState)
			-- detectar cuando está en aire o aterriza
			if newState == Enum.HumanoidStateType.Jumping or newState == Enum.HumanoidStateType.Freefall then
				character:SetAttribute("IsInAir", true)
			elseif newState == Enum.HumanoidStateType.Landed then
				-- reset completo al tocar suelo (idem script original)
				character:SetAttribute("AirDashCount", 0)
				character:SetAttribute("AirDashOnCD", false)
				character:SetAttribute("IsInAir", false)
				character:SetAttribute("HasDoubleJumped", false)
			end
		end)
	end
end

return CharacterStateManager
