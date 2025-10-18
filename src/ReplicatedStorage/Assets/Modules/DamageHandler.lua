--!strict
-- MÓDULO DE DAÑO - Integrado con bloqueo/parry y mantiene knockback antes de ragdoll

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage.Assets:WaitForChild("Modules")

local RagdollHandler = require(Modules:WaitForChild("RagdollHandler"))
local StunHandler = require(Modules:WaitForChild("StunHandler"))
local AnimationHandler = require(Modules:WaitForChild("AnimationHandler"))
local MovesetConfig = require(Modules:WaitForChild("MovesetConfig"))
local KnockbackHandler = require(Modules:WaitForChild("KnockbackHandler"))
local BlockHandler = require(Modules:WaitForChild("BlockHandler"))

local DamageHandler = {}

function DamageHandler.applyDamage(attacker: Model, target: Model, hitInfo: any)
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then return end

	-- Bloqueo / Parry (anula daño si procede)
	local blocked = BlockHandler.tryBlock(attacker, target, hitInfo)
	if blocked == "Parried" or blocked == "Blocked" then
		return
	end

	local hasRagdoll = (hitInfo.RagdollDuration and hitInfo.RagdollDuration > 0)

	-- Reacciones de impacto (no mostrar si dash/downslam/ragdoll)
	if not hitInfo.IsDashHit and not hitInfo.IsDownslam and not hasRagdoll then
		local reactions = MovesetConfig.MainCharacter.HitReactions.M1_HitReactions
		if reactions and #reactions > 0 then
			AnimationHandler.play(target, reactions[math.random(1, #reactions)])
		end
	end

	-- Stun (omitido si habrá ragdoll)
	if hitInfo.StunDuration and hitInfo.StunDuration > 0 and not hasRagdoll then
		StunHandler.applyStun(target, hitInfo.StunDuration)
	end

	-- Knockback antes del ragdoll
	if hitInfo.KnockbackForce and hitInfo.KnockbackForce > 0 then
		local kbOpts: KnockbackHandler.KnockbackOpts = {
			MirrorAttacker = hitInfo.MirrorAttacker or false,
			SelfForceMultiplier = 0.7,
			Lifetime = 0.18,
		}
		KnockbackHandler.applyKnockback(attacker, target, hitInfo.KnockbackForce, hitInfo.VerticalKnockbackForce, kbOpts)
	end

	-- Ragdoll (al final)
	if hasRagdoll then
		RagdollHandler.applyRagdoll(target, hitInfo.RagdollDuration)
	end

	-- Daño final
	targetHumanoid:TakeDamage(hitInfo.Damage or 0)
end

return DamageHandler
