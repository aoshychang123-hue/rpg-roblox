--!strict
-- WeaponConfig: ajustado para el nuevo sistema de habilidades por AbilitySets.
-- Nota clave:
-- - Las habilidades (Z/X/C/V) YA NO se definen aquí. Se declaran en AbilitySets:
--     - AbilitySets.Universal (para todas)
--     - AbilitySets.Groups.<WeaponType> (por grupo: Sword/Bow/Maze/Spear/Shield/Fists)
--     - AbilitySets.Weapons.<WeaponId> (overrides específicos por arma)
-- - Este módulo mantiene stats de M1, reacciones, modelo y side de attach.
-- - Type puede estar en español (Espada/Mazo, etc.); WeaponTypeResolver lo normaliza.

local WeaponConfig: { [string]: any } = {
	Sword1 = {
		DisplayName = "Sword",
		Type = "Espada", -- normaliza a "Sword"
		Image = "rbxassetid://88760774954912",
		ModelName = "Sword1",
		AttachSide = "RightArm",
		GripJoint = "RightGrip",
		Block = {
			Start = "Sword_BlockStart",
			Idle = "Sword_BlockIdle",
			StartDuration = 0.2,
			UseShield = false,
		},
		M1_Combo = {
			[1] = { Animation = "Sword_M1_1", HitInfo = { Damage = 3, StunDuration = 0.25, KnockbackForce = 4 } },
			[2] = { Animation = "Sword_M1_2", HitInfo = { Damage = 3, StunDuration = 0.25, KnockbackForce = 5 } },
			[3] = { Animation = "Sword_M1_3", HitInfo = { Damage = 4, StunDuration = 0.3, KnockbackForce = 7, VerticalKnockbackForce = 2 } },
			[4] = { Animation = "Sword_M1_4", HitInfo = { Damage = 4, StunDuration = 0.3, KnockbackForce = 10, VerticalKnockbackForce = 6, RagdollDuration = 0.8 } },
		},
		HitReactions = {
			Block = "Sword_BlockHit",
			M1_HitReactions = { "Sword_Hit1", "Sword_Hit2" },
		},
		-- Habilidades removidas: ahora en AbilitySets (grupo "Sword")
	},

	Greatsword = {
		DisplayName = "Greatsword",
		Type = "Espada", -- normaliza a "Sword"
		Image = "rbxassetid://108502312497644",
		ModelName = "GSword",
		AttachSide = "RightArm",
		GripJoint = "RightGrip",
		Block = {
			Start = "GS_BlockStart",
			Idle = "GS_BlockIdle",
			StartDuration = 0.25,
			UseShield = false,
		},
		M1_Combo = {
			[1] = { Animation = "GS_M1_1", HitInfo = { Damage = 5, StunDuration = 0.25, KnockbackForce = 6 } },
			[2] = { Animation = "GS_M1_2", HitInfo = { Damage = 6, StunDuration = 0.3, KnockbackForce = 9 } },
			[3] = { Animation = "GS_M1_3", HitInfo = { Damage = 9, StunDuration = 0.35, KnockbackForce = 14, VerticalKnockbackForce = 8, RagdollDuration = 1.2 } },
		},
		HitReactions = { Block = "GS_BlockHit" },
		-- Habilidades: hereda las del grupo "Sword" (AbilitySets.Groups.Sword)
	},

	-- MAZO
	Mazo1 = {
		DisplayName = "HolyHammer",
		Type = "Mazo", -- normaliza a "Maze"
		Image = "rbxassetid://94206330860608", -- reemplaza por tu asset ID real
		ModelName = "Mazo1",
		AttachSide = "RightArm",
		GripJoint = "RightGrip",
		Block = {
			Start = "Mazo_BlockStart",
			Idle = "Mazo_BlockIdle",
			StartDuration = 0.24,
			UseShield = false,
		},
		M1_Combo = {
			[1] = { Animation = "Holy1", HitInfo = { Damage = 10, StunDuration = 3, KnockbackForce = 7 } },
			[2] = { Animation = "Holy2", HitInfo = { Damage = 9, StunDuration = 0.3, KnockbackForce = 10, VerticalKnockbackForce = 3 } },
			[3] = { Animation = "Holy3", HitInfo = { Damage = 12, StunDuration = 0.45, KnockbackForce = 16,} },
			[4] = { Animation = "Holy4", HitInfo = { Damage = 12, StunDuration = 0.45, KnockbackForce = 16, VerticalKnockbackForce = 10, RagdollDuration = 1.2 } },

		},
		HitReactions = {
			Block = "Mazo_BlockHit",
			M1_HitReactions = { "Mazo_Hit1", "Mazo_Hit2" },
		},
		-- Habilidades removidas de aquí.
		-- Sus habilidades exclusivas (Z/X) se migran a AbilitySets.Weapons.Mazo1 más abajo.
	},
	
	Katana = {
		DisplayName = "Katana",
		Type = "Espada", -- normaliza a "Maze"
		Image = "rbxassetid://12345678901234", -- reemplaza por tu asset ID real
		ModelName = "Katana",
		AttachSide = "RightArm",
		GripJoint = "RightGrip",
		Block = {
			Start = "Mazo_BlockStart",
			Idle = "Mazo_BlockIdle",
			StartDuration = 0.24,
			UseShield = false,
		},
		M1_Combo = {
			[1] = { Animation = "Mazo_M1_1", HitInfo = { Damage = 7, StunDuration = 0.2, KnockbackForce = 7 } },
			[2] = { Animation = "Mazo_M1_2", HitInfo = { Damage = 9, StunDuration = 0.3, KnockbackForce = 10, VerticalKnockbackForce = 3 } },
			[3] = { Animation = "Mazo_M1_3", HitInfo = { Damage = 12, StunDuration = 0.45, KnockbackForce = 16, VerticalKnockbackForce = 10, RagdollDuration = 1.2 } },
		},
		HitReactions = {
			Block = "Mazo_BlockHit",
			M1_HitReactions = { "Mazo_Hit1", "Mazo_Hit2" },
		},
		-- Habilidades removidas de aquí.
		-- Sus habilidades exclusivas (Z/X) se migran a AbilitySets.Weapons.Mazo1 más abajo.
	},
}

return WeaponConfig
