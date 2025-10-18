--!strict
-- STUN: tag + atributo IsStunned para gating en cliente/servidor

local CollectionService = game:GetService("CollectionService")
local StunHandler = {}

function StunHandler.applyStun(targetCharacter: Model, duration: number)
	if not targetCharacter or CollectionService:HasTag(targetCharacter, "Stunned") then
		return
	end
	CollectionService:AddTag(targetCharacter, "Stunned")
	targetCharacter:SetAttribute("IsStunned", true)

	task.delay(duration, function()
		if targetCharacter and targetCharacter.Parent then
			CollectionService:RemoveTag(targetCharacter, "Stunned")
			targetCharacter:SetAttribute("IsStunned", false)
		end
	end)
end

return StunHandler
