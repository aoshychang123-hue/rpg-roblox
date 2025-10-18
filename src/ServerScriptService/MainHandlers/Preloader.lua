--!strict
-- Precarga todas las animaciones del folder Assets/Animations para el personaje local

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations")
local AnimationHandler = require(ReplicatedStorage.Assets.Modules:WaitForChild("AnimationHandler"))

-- Recorre recursivamente y devuelve todos los objetos Animation
local function getAllAnimationsInFolder(folder: Instance, anims: {Animation})
	for _, obj in ipairs(folder:GetChildren()) do
		if obj:IsA("Animation") then
			table.insert(anims, obj)
		elseif #obj:GetChildren() > 0 then
			getAllAnimationsInFolder(obj, anims)
		end
	end
end

local function preloadAllAnimations(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local allAnims = {}
	getAllAnimationsInFolder(AnimationsFolder, allAnims)

	-- Preload/cargar cada animación usando AnimationHandler (o directamente el Animator)
	for _, anim in ipairs(allAnims) do
		-- Si AnimationHandler.play acepta Animation objects:
		-- local track = AnimationHandler.play(character, anim)
		-- Si requiere nombre, usa anim.Name (y asegúrate que AnimationHandler lo soporte)
		local track = AnimationHandler.play(character, anim.Name)
		if track then
			track:Play(0)
			track:Stop()
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		task.wait(0.1)
		preloadAllAnimations(character)
	end)
end)

if Players.LocalPlayer and Players.LocalPlayer.Character then
	local char = Players.LocalPlayer.Character
	char:WaitForChild("Humanoid")
	task.wait(0.1)
	preloadAllAnimations(char)
end
