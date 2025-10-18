--!strict
-- BlockHandler: bloqueo frontal total (0 daño) y break por espalda (cooldown 3s).
-- Devuelve "Blocked" | "BackBreak" | nil. No incluye parry ni chip.

local RS = game:GetService("ReplicatedStorage")
local Modules = RS.Assets:WaitForChild("Modules")

local AnimationHandler = require(Modules:WaitForChild("AnimationHandler"))
local MovesetConfig = require(Modules:WaitForChild("MovesetConfig"))

local Remotes = RS:WaitForChild("Remotes")
local Replicate = Remotes:WaitForChild("Replicate")

local BlockHandler = {}

local function now() return os.clock() end

local function getRoot(model: Model): BasePart?
	return (model:FindFirstChild("HumanoidRootPart") :: BasePart?) or model.PrimaryPart
end

local function angleFromFront(defenderHRP: BasePart, attackerHRP: BasePart): number
	local f = defenderHRP.CFrame.LookVector
	local dir = attackerHRP.Position - defenderHRP.Position
	if dir.Magnitude <= 1e-3 then return 0 end
	dir = dir.Unit
	return math.deg(math.acos(math.clamp(f:Dot(dir), -1, 1))) -- 0° frente, 180° espalda
end

function BlockHandler.tryBlock(attacker: Model, target: Model, hitInfo: any): string?
	if not target or not target.Parent then return nil end
	if target:GetAttribute("IsBlocking") ~= true then return nil end

	-- En cooldown (bloqueo roto) => no bloquea
	local brokenUntil = tonumber(target:GetAttribute("BlockBrokenUntil")) or 0
	if now() < brokenUntil then return nil end

	local tRoot = getRoot(target)
	local aRoot = getRoot(attacker)
	if not tRoot or not aRoot then return nil end

	-- Ángulo de frente permitido para bloquear (default 120° totales)
	local totalFrontAngle = tonumber(target:GetAttribute("BlockAngleDegrees")) or 120
	local halfCone = totalFrontAngle * 0.5

	-- Umbral para considerar "espalda" (default >= 100° desde el frente)
	local backBreakAngle = tonumber(target:GetAttribute("BlockBackBreakAngle")) or 100

	local ang = angleFromFront(tRoot, aRoot)

	-- Golpe por espalda => romper bloqueo 3s y permitir daño normal
	if ang >= backBreakAngle then
		target:SetAttribute("IsBlocking", false)
		target:SetAttribute("BlockBrokenUntil", now() + 3.0)

		-- VFX de rotura por espalda
		Replicate:FireAllClients("AbilityVFX", {
			Character = target,
			Effect = "GuardBreak",
			Params = { Position = tRoot.Position }
		})

		-- Reacción opcional
		local cfg = MovesetConfig[(target:GetAttribute("Moveset") or "MainCharacter") :: string]
		if cfg and cfg.HitReactions and cfg.HitReactions.Block then
			pcall(function() AnimationHandler.play(target, cfg.HitReactions.Block) end)
		end

		return "BackBreak"
	end

	-- Si no está dentro del cono frontal, tampoco bloquea (pega lateral)
	if ang > halfCone then
		return nil
	end

	-- Bloqueo frontal: anula todo el daño
	Replicate:FireAllClients("AbilityVFX", {
		Character = target,
		Effect = "BlockSpark",
		Params = { Position = tRoot.Position }
	})

	-- Reacción opcional
	local cfg = MovesetConfig[(target:GetAttribute("Moveset") or "MainCharacter") :: string]
	if cfg and cfg.HitReactions and cfg.HitReactions.Block then
		pcall(function() AnimationHandler.play(target, cfg.HitReactions.Block) end)
	end

	return "Blocked"
end

return BlockHandler
