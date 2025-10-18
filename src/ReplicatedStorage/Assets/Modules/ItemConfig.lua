--!strict
-- ItemConfig: catálogo de objetos NO-arma que pueden mostrarse en la Hotbar/Inventario.
-- Estructura: [ItemId] = { Name: string, Image: string, Type?: string, Description?: string, Stackable?: boolean, MaxStack?: number }
-- Nota: reemplaza los rbxassetid://0 por tus assets reales.

export type ItemEntry = {
	Name: string,
	Image: string,
	Type: string?,
	Description: string?,
	Stackable: boolean?,
	MaxStack: number?,
	Rarity: string?, -- "Común" | "Raro" | "Épico" | "Legendario" | etc.
}

local ItemConfig: { [string]: ItemEntry } = {
	-- Consumibles
	HealthPotion = {
		Name = "Poción de Vida",
		Image = "rbxassetid://0",
		Type = "Consumible",
		Description = "Restaura 50 de vida.",
		Stackable = true,
		MaxStack = 10,
		Rarity = "Común",
	},
	ManaPotion = {
		Name = "Poción de Energía",
		Image = "rbxassetid://0",
		Type = "Consumible",
		Description = "Restaura 30 de energía.",
		Stackable = true,
		MaxStack = 10,
		Rarity = "Común",
	},
	Bomb = {
		Name = "Bomba",
		Image = "rbxassetid://0",
		Type = "Consumible",
		Description = "Explota causando daño en área.",
		Stackable = true,
		MaxStack = 5,
		Rarity = "Raro",
	},

	-- Llaves y progreso
	DungeonKey = {
		Name = "Llave de Mazmorra",
		Image = "rbxassetid://0",
		Type = "Llave",
		Description = "Abre puertas de mazmorra.",
		Stackable = false,
	},

	-- Munición / Materiales
	ArrowBundle = {
		Name = "Flechas",
		Image = "rbxassetid://0",
		Type = "Munición",
		Stackable = true,
		MaxStack = 99,
	},
	ShieldRepairKit = {
		Name = "Kit de Reparación",
		Image = "rbxassetid://0",
		Type = "Material",
		Description = "Repara durabilidad de escudo.",
		Stackable = true,
		MaxStack = 20,
	},
}

return ItemConfig
