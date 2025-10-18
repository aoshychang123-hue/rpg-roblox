--!strict
-- KNOCKBACK con LinearVelocity temporales y soporte para SelfForceMultiplier

local Debris = game:GetService("Debris")

local KnockbackHandler = {}

export type KnockbackOpts = {
	MirrorAttacker: boolean?,
	SelfForceMultiplier: number?, -- NUEVO: Multiplicador para la fuerza del atacante (ej: 0.7 para 70%)
	NoVertical: boolean?,
	Lifetime: number?,
}

local function applyLinearVelocityImpulse(part: BasePart, vec: Vector3, name: string, lifetime: number)
	if not part or part.Anchored then return end
	for _, obj in ipairs(part:GetChildren()) do
		if obj:IsA("LinearVelocity") and obj.Name == name then
			obj:Destroy()
		end
	end
	local attachment = part:FindFirstChildOfClass("Attachment") or Instance.new("Attachment", part)
	local lv = Instance.new("LinearVelocity")
	lv.Name = name
	lv.MaxForce = math.huge
	lv.Attachment0 = attachment
	lv.VectorVelocity = vec
	lv.Parent = part
	Debris:AddItem(lv, lifetime)
end

function KnockbackHandler.applyKnockback(attackerCharacter: Model, targetCharacter: Model, force: number?, verticalForce: number?, opts: KnockbackOpts?)
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local attackerRoot = attackerCharacter and attackerCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot or not attackerRoot then return end

	local dir = (targetRoot.Position - attackerRoot.Position)
	if dir.Magnitude < 0.001 then return end
	dir = dir.Unit

	local life = (opts and opts.Lifetime) or 0.18
	local horiz = dir * math.max(force or 0, 0)
	local vertY = (opts and opts.NoVertical) and 0 or (verticalForce or 0)
	local vec = horiz + Vector3.new(0, vertY, 0)

	applyLinearVelocityImpulse(targetRoot, vec, "KnockbackVelocity", life)

	-- LÓGICA DE MOVIMIENTO PROPIO CORREGIDA
	if opts and opts.MirrorAttacker and attackerRoot then
		local selfMultiplier = opts.SelfForceMultiplier or 1 -- Por defecto es 1 (100% de la fuerza)
		local selfVec = vec * selfMultiplier
		applyLinearVelocityImpulse(attackerRoot, selfVec, "SelfKnockVelocity", life)
	end
end

return KnockbackHandler
