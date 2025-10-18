--[[
	MÓDULO DE PROPIEDADES DEL PERSONAJE
	Define todos los atributos por defecto que un personaje tendrá al entrar al juego.
]]

local CharacterProperties = {

	--// Estadísticas de Combate \\--
	MaxHealth = 100,
	Stamina = 100,
	MaxStamina = 100,
	Strength = 10,
	Defense = 5,

	--// Estado y Configuración \\--
	Moveset = "MainCharacter", -- El moveset por defecto
	IsAdmin = false,
	M1_Combo = 0,
	ComboResetTimer = 0,

	--// Progresión \\--
	Level = 1,
	XP = 0,
	RequiredXP = 100,

}

return CharacterProperties
