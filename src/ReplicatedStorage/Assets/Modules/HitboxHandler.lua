--!strict
-- MÓDULO DE HITBOX AVANZADO (corregido y optimizado)
-- Integración: respeta bloqueo llamando BlockHandler.tryBlock antes de aplicar daño.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local DamageHandler = require(RS.Assets.Modules:WaitForChild("DamageHandler"))
local BlockHandler = require(RS.Assets.Modules:WaitForChild("BlockHandler"))

export type HitInfo = {
	Damage: number?,
	StunDuration: number?,
	KnockbackForce: number?,
	VerticalKnockbackForce: number?,
	IsDownslam: boolean?,
	RagdollDuration: number?,
	IsDashHit: boolean?,
}

export type Visuals = {
	Enabled: boolean?,
	Size: Vector3?,
	Offset: CFrame?,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	WorldCFrame: CFrame?,
}

export type TeamFilter = "EnemiesOnly" | "AlliesOnly" | "Any"

export type Options = {
	Attacker: Model?,
	Duration: number?,
	Type: "Static" | "Dynamic"?,
	Shape: "Box" | "Sphere"?,
	HitInfo: HitInfo?,
	-- Query control
	QueryHz: number?, -- solo para dinámicos
	CollisionGroup: string?, -- opcional
	IncludeTag: string?, -- si lo das, solo impacta instancias con este tag
	-- Filtrado lógico
	TeamFilter: TeamFilter?,
	AllowSelfHit: boolean?, -- por defecto false
	-- Reglas de impacto
	MaxHits: number?, -- máximo de modelos únicos a golpear por Fire
	PerTargetCooldown: number?, -- s de cooldown por objetivo (persistente entre Fires si reutilizas la instancia)
	-- Visuales
	Visuals: Visuals?,
}

type HitResult = {
	Target: Model,
	Humanoid: Humanoid,
}

local HitboxHandler = {}
HitboxHandler.__index = HitboxHandler

function HitboxHandler.new(opts: Options?)
	local self = setmetatable({}, HitboxHandler)

	self.Attacker = opts and opts.Attacker or nil
	self.Duration = opts and opts.Duration or 0.3
	self.Type = opts and opts.Type or "Static"
	self.Shape = opts and opts.Shape or "Box"
	self.HitInfo = opts and opts.HitInfo or { Damage = 10, StunDuration = 0.3, KnockbackForce = 0 }

	self.QueryHz = math.clamp(opts and opts.QueryHz or 60, 5, 120)
	self.CollisionGroup = opts and opts.CollisionGroup or nil
	self.IncludeTag = opts and opts.IncludeTag or nil

	self.TeamFilter = opts and opts.TeamFilter or "EnemiesOnly"
	self.AllowSelfHit = opts and opts.AllowSelfHit or false

	self.MaxHits = opts and opts.MaxHits or math.huge
	self.PerTargetCooldown = opts and opts.PerTargetCooldown or 0

	self.Visuals = opts and opts.Visuals or {
		Enabled = false,
		Size = Vector3.new(5, 5, 5),
		Offset = CFrame.new(0, 0, -3),
		Color = Color3.fromRGB(255, 0, 0),
		Material = Enum.Material.Neon,
		Transparency = 0.7,
		WorldCFrame = nil,
	}

	self.onHit = nil :: ((attacker: Model, target: Model) -> ("Blocked" | "Parried" | any))?

	-- Internos
	self._conn = nil :: RBXScriptConnection?
	self._active = false
	self._endTime = 0
	self._lastCF = nil :: CFrame?
	self._debugPart = nil :: Part?
	self._alreadyHit = {} :: {[Model]: boolean}
	self._lastHitAt = {} :: {[Model]: number}

	-- OverlapParams reutilizable
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = {}
	params.FilterType = Enum.RaycastFilterType.Exclude
	if self.CollisionGroup then
		params.CollisionGroup = self.CollisionGroup
	end
	self._params = params

	return self
end

-- Utilidades
local function getPlayerFromCharacter(model: Model): Player?
	return Players:GetPlayerFromCharacter(model)
end

local function sameTeamFilter(attacker: Model, target: Model, mode: TeamFilter): boolean
	if mode == "Any" then return true end
	local pa = getPlayerFromCharacter(attacker)
	local pb = getPlayerFromCharacter(target)
	if not pa or not pb or pa.Team == nil or pb.Team == nil then
		-- Si falta info, por defecto permite en EnemiesOnly y bloquea en AlliesOnly
		return mode == "EnemiesOnly"
	end
	local same = (pa.Team == pb.Team)
	if mode == "EnemiesOnly" then return not same end
	if mode == "AlliesOnly" then return same end
	return true
end

local function ensureFolder(path: Instance, name: string): Folder
	local f = path:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = path
	end
	return f :: Folder
end

local function gatherTargetsBox(cf: CFrame, size: Vector3, params: OverlapParams): {BasePart}
	return workspace:GetPartBoundsInBox(cf, size, params)
end

local function gatherTargetsSphere(center: Vector3, radius: number, params: OverlapParams): {BasePart}
	return workspace:GetPartBoundsInRadius(center, radius, params)
end

local function getCharacterFromPart(part: BasePart): Model?
	return part:FindFirstAncestorOfClass("Model")
end

local function now(): number
	return time()
end

function HitboxHandler:Fire(): {HitResult}
	-- En dinámicos, espera hasta terminar para devolver los impactos.
	if self._active then return {} end
	self._active = true

	local attacker = self.Attacker
	if not attacker or not attacker.Parent then
		self._active = false
		return {}
	end

	local hrp = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
	if self.Type == "Dynamic" and not hrp then
		self._active = false
		return {}
	end

	table.clear(self._alreadyHit)
	self._params.FilterDescendantsInstances = { attacker }

	-- Debug visuals
	if self.Visuals.Enabled then
		local part = Instance.new("Part")
		part.Name = "HitboxDebug"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Color = self.Visuals.Color or Color3.new(1, 0, 0)
		part.Material = self.Visuals.Material or Enum.Material.Neon
		part.Transparency = self.Visuals.Transparency or 0.7
		part.Size = self.Visuals.Size or Vector3.new(5, 5, 5)
		part.Parent = ensureFolder(workspace, "Hitbox")
		self._debugPart = part
		Debris:AddItem(part, self.Duration + 0.1)
	else
		self._debugPart = nil
	end

	self._endTime = now() + self.Duration
	local results: {HitResult} = {}

	local function considerParts(parts: {BasePart})
		if #parts == 0 then return end
		-- Deduplicar por Character
		local uniqueModels: {[Model]: boolean} = {}
		for _, p in ipairs(parts) do
			local m = getCharacterFromPart(p)
			if m then uniqueModels[m] = true end
		end

		for model, _ in pairs(uniqueModels) do
			if model ~= attacker or self.AllowSelfHit then
				if not self._alreadyHit[model] then
					local hum = model:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						if sameTeamFilter(attacker, model, self.TeamFilter) then
							if not self.IncludeTag or CollectionService:HasTag(model, self.IncludeTag) or CollectionService:HasTag(hum, self.IncludeTag) then
								local lastT = self._lastHitAt[model]
								if not lastT or (now() - lastT) >= self.PerTargetCooldown then
									self._alreadyHit[model] = true
									self._lastHitAt[model] = now()

									-- Callback externo (si define bloqueo personalizado en un caso)
									local cbOutcome = self.onHit and self.onHit(attacker, model)
									if cbOutcome == "Blocked" or cbOutcome == "Parried" then
										-- Cancelar daño (ya reaccionó el callback)
									else
										-- Integración global de bloqueo (frontal cancela, espalda rompe)
										local outcome = BlockHandler.tryBlock(attacker, model, self.HitInfo)
										if outcome ~= "Blocked" then
											DamageHandler.applyDamage(attacker, model, self.HitInfo)
										end
									end

									table.insert(results, { Target = model, Humanoid = hum })
									if #results >= self.MaxHits then
										return
									end
								end
							end
						end
					end
				end
			end
		end
	end

	local function safePivot(cfDefault: CFrame): CFrame
		if hrp then
			return hrp.CFrame
		end
		local ok, pivot = pcall(function()
			return attacker:GetPivot()
		end)
		return ok and pivot or cfDefault
	end

	local function currentCF(): CFrame
		-- Estático con WorldCFrame tiene prioridad
		if self.Type == "Static" and self.Visuals.WorldCFrame then
			return self.Visuals.WorldCFrame
		end
		local offset = self.Visuals.Offset or CFrame.new()
		local base = safePivot(CFrame.identity)
		return base * offset
	end

	local function queryAt(cf: CFrame)
		local size = self.Visuals.Size or Vector3.new(5, 5, 5)
		if self._debugPart then
			self._debugPart.CFrame = cf
			self._debugPart.Size = size
		end

		local hits: {BasePart}
		if self.Shape == "Sphere" then
			local radius = math.max(size.X, size.Y, size.Z) * 0.5
			hits = gatherTargetsSphere(cf.Position, radius, self._params)
		else
			hits = gatherTargetsBox(cf, size, self._params)
		end
		considerParts(hits)
	end

	if self.Type == "Static" then
		queryAt(currentCF())
		self:Stop()
		return results
	end

	-- Dynamic: muestreo por pasos y barrido básico
	local dtAcc = 0
	local step = 1 / self.QueryHz
	self._lastCF = currentCF()
	if self._debugPart then self._debugPart.CFrame = self._lastCF end

	self._conn = RunService.Heartbeat:Connect(function(dt)
		if not attacker.Parent then self:Stop() return end
		if now() >= self._endTime then self:Stop() return end

		dtAcc += dt
		if dtAcc < step then
			if self._debugPart then self._debugPart.CFrame = currentCF() end
			return
		end
		dtAcc -= step

		local prev = self._lastCF :: CFrame
		local cf = currentCF()
		self._lastCF = cf

		local moved = (cf.Position - prev.Position).Magnitude
		if moved > 6 then
			queryAt(prev)
			if #results < self.MaxHits then
				queryAt(cf)
			end
		else
			queryAt(cf)
		end

		if #results >= self.MaxHits then
			self:Stop()
		end
	end)

	task.delay(self.Duration + 0.05, function()
		if self._active then self:Stop() end
	end)

	while self._active do
		RunService.Heartbeat:Wait()
	end
	return results
end

function HitboxHandler:FireAsync(): {HitResult}
	return self:Fire()
end

function HitboxHandler:Stop()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._active = false
	self._endTime = 0
	self._lastCF = nil
	if self._debugPart then
		self._debugPart:Destroy()
		self._debugPart = nil
	end
end

return HitboxHandler
