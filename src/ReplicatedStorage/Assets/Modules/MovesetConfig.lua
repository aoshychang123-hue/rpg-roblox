--!strict
-- MovesetConfig con soporte de bloqueo (BlockStart/BlockIdle) y Shield1 en Left Arm.

local MovesetConfig: { [string]: any } = {}

MovesetConfig.MainCharacter = {
	M1_Combo = {
		[1] = { Animation = "1", HitInfo = { Damage = 2, StunDuration = 0.25, KnockbackForce = 2 } },
		[2] = { Animation = "2", HitInfo = { Damage = 1, StunDuration = 0.25, KnockbackForce = 2 } },
		[3] = { Animation = "3", HitInfo = { Damage = 2, StunDuration = 0.3, KnockbackForce = 2, VerticalKnockbackForce = 1 } },
		[4] = { Animation = "4", HitInfo = { Damage = 1, StunDuration = 0.25, KnockbackForce = 2 } },
		[5] = { Animation = "5", HitInfo = { Damage = 1, StunDuration = 0.25, KnockbackForce = 2 } },
		[6] = { Animation = "6", HitInfo = { Damage = 4, StunDuration = 0.5, KnockbackForce = 10, VerticalKnockbackForce = 25, RagdollDuration = 1.5 } },
	},

	Downslam = {
		Animation = "Downslam",
		HitInfo = { Damage = 3, StunDuration = 0.1, IsDownslam = true, RagdollDuration = 1 },
		Visuals = { Color = Color3.fromRGB(255, 255, 0), Size = Vector3.new(12, 2, 12), Material = Enum.Material.Neon },
	},

	Dashes = {
		Forward = "DashFront",
		Left = "DashLeft",
		Right = "DashRight",
		Backward = "DashBack",
	},

	HitReactions = {
		Dash = "DashFrontHit",
		Block = "BlockNormal",
		M1_HitReactions = { "Hit1", "Hit2", "Hit3", "Hit4" },
	},

	DashesAir = {
		Forward = "AirDashForwardAnim",
		Backward = "AirDashBackwardAnim",
		Left = "AirDashLeftAnim",
		Right = "AirDashRightAnim",
		DoubleForward = "AirDashDoubleForwardAnim",
	},

	Jump = {
		DoubleJumpAnim = "DJump",
		NormalJump = "AirDashBackwardAnim",
	},

	-- NUEVO: Configuración de bloqueo
	Block = {
		Start = "BlockStart",     -- anim de inicio (no loop)
		Idle = "BlockIdle",       -- anim de ciclo mientras se mantiene
		StartDuration = 0.22,     -- duración aprox para pasar a Idle (ajústalo a tu clip)
		ShieldModel = "Shield1",  -- modelo a equipar con EquipUtil en Left Arm
	},

	Abilities = {
		-- Z usa marker "Hit" y emite VFX "Zmove"
		Z = {
			Animation = "Ability_Z",
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
		X = {
			Animation = "Ability_X",
			Cooldown = 10,
			Timeline = {
				{ t = 0.45, type = "Hitbox", Dynamic = false, Duration = 0.08, Size = Vector3.new(12,4,12), Offset = CFrame.new(0,-1,0),
					HitInfo = { Damage = 14, StunDuration = 0.35, KnockbackForce = 16, VerticalKnockbackForce = 10 } },
				{ t = 0.45, type = "VFX", Effect = "Webo", Params = { Radius = 10, Rings = 1, PartsPerRing = 12 } },
			},
		},
		C = {
			Animation = "Ability_C",
			Cooldown = 12,
			Timeline = {
				{ t = 0.20, type = "Hitbox", Dynamic = true, Duration = 0.16, Size = Vector3.new(5,5,10), Offset = CFrame.new(0,0,-5),
					HitInfo = { Damage = 12, StunDuration = 0.25, KnockbackForce = 18, VerticalKnockbackForce = 4 } },
			},
		},
		V = {
			Animation = "Ability_V",
			Cooldown = 20,
			Timeline = {
				{ t = 0.30, type = "Hitbox", Dynamic = false, Duration = 0.10, Size = Vector3.new(16,5,16), Offset = CFrame.new(0,0,0),
					HitInfo = { Damage = 20, StunDuration = 0.5, KnockbackForce = 22, VerticalKnockbackForce = 12, RagdollDuration = 1 } },
				{ t = 0.30, type = "VFX", Effect = "Webo", Params = { Radius = 14, Rings = 2, PartsPerRing = 16 } },
			},
		},
	},
}

return MovesetConfig
