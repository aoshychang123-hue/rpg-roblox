--!strict
-- Wrapper del nuevo sistema de habilidades.
-- Solo requiere el AbilityModule para que registre los remotos y la lógica.
-- Evita llamadas directas (que causaban "attempt to call a nil value").

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local AbilityModule = require(SSS:WaitForChild("Modules"):WaitForChild("AbilityModule"))

print("[Ability_Handler] AbilityModule cargado y remotos registrados.")
return AbilityModule
