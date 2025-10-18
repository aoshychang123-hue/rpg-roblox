--!strict
-- AbilitySets: habilidades universales, por grupo y por arma concreta.

local AbilitySets = {
	Universal = { Abilities = { } },

	Groups = {
		Sword = {
			Abilities = {
				Z = {
					DisplayName = "Pierce",
					Animation = "Sword_Z",
					Cooldown = 6,
					EventWindow = 1.5,
					MarkerHit = {
						Dynamic = true,
						Duration = 0.12,
						QueryHz = 60,
						Size = Vector3.new(6, 5, 7),
						Offset = CFrame.new(0, 0, -7),
						MaxHits = 5,
						HitInfo = { Damage = 10, StunDuration = 0.2, KnockbackForce = 14, VerticalKnockbackForce = 6 },
						EmitPart = "Zmove",
						EmitOffset = CFrame.new(0, 0, -8),
						EmitLifetime = 5,
					},
				},
			},
		},
		Bow =   { Abilities = { } },
		Maze =  { Abilities = { } },
		Spear = { Abilities = { } },
		Shield ={ Abilities = { } },
		Fists = { Abilities = { } },
	},

	Weapons = {
		Mazo1 = {
			Abilities = {
				Z = {
					DisplayName = "Crush",
					Animation = "Mazo_Z",
					Cooldown = 10,
					EventWindow = 1.4,
					MarkerHit = {
						Dynamic = true,
						Duration = 0.14,
						QueryHz = 60,
						Size = Vector3.new(7, 6, 11),
						Offset = CFrame.new(0, 0, -7),
						MaxHits = 8,
						HitInfo = { Damage = 18, StunDuration = 0.35, KnockbackForce = 22, VerticalKnockbackForce = 12 },
						EmitPart = "MazoHit",
						EmitOffset = CFrame.new(0, 0, -7),
						EmitLifetime = 6,
					},
				},
				X = {
					DisplayName = "Quake",
					Animation = "Mazo_X",
					Cooldown = 1,
					EmitPart = "Zmove",
					Timeline = {
						{ t = 0.5, type = "Hitbox", Dynamic = true, Duration = 0.18, Size = Vector3.new(10,4,14), Offset = CFrame.new(0,-1,0),
							HitInfo = { Damage = 24, StunDuration = 0.55, KnockbackForce = 30, VerticalKnockbackForce = 20 } },
						{ t = 0.5, type = "VFX", Effect = "Webo", Params = { Radius = 12, Rings = 2, PartsPerRing = 10 } },
					},
				},
			},
		},
	},
}

return AbilitySets
