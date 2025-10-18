--!strict
-- RagdollHandler: Versión Completa y Corregida
-- Módulo final con todas las soluciones implementadas para una caída física,
-- natural y libre de errores.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local RS = game:GetService("ReplicatedStorage")

local Modules = RS.Assets:WaitForChild("Modules")
local StunHandler = require(Modules:WaitForChild("StunHandler"))

local RagdollHandler = {}

--============================================================================--
-- [+] CONFIGURACIÓN
--============================================================================--

-- PARÁMETROS PARA AJUSTAR LA SENSACIÓN DEL RAGDOLL
local PARAMS = {
	-- La fuerza del impulso inicial que lo hace caer de espaldas.
	BACKWARD_IMPulse_STRENGTH = 120,

	-- Qué tan rápido el alineador suave intenta corregir la pose final (valor bajo = suave).
	ALIGN_RESPONSIVENESS = 3.5,

	-- La fuerza máxima del alineador (valor bajo para no interferir con la física).
	ALIGN_MAX_TORQUE = 2500,

	-- Cuánto tiempo (en segundos) el alineador suave permanece activo antes de desactivarse.
	ALIGN_RELEASE_DELAY = 1.0,

	-- Propiedades Físicas de los Colliders (Fricción, Rebote, etc.).
	COLLIDER_PHYSICS = PhysicalProperties.new(0.8, 0.9, 0.15, 1, 0),
}

-- LÍMITES DE ARTICULACIONES (R6/R15 compatibles en lo básico)
local JOINT_LIMITS = {
	["Right Shoulder"] = { upper = 22, twist = 8 },
	["Left Shoulder"]  = { upper = 22, twist = 8 },
	["Right Hip"]      = { upper = 14, twist = 6 },
	["Left Hip"]       = { upper = 14, twist = 6 },
}

-- GRUPO DE COLISIÓN PARA LOS COLLIDERS
local RAGDOLL_CG = "RagdollColliders"


--============================================================================--
-- [+] FUNCIONES AUXILIARES
--============================================================================--

local function ensureCollisionGroup()
	pcall(function() PhysicsService:RegisterCollisionGroup(RAGDOLL_CG) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(RAGDOLL_CG, "Default", true) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(RAGDOLL_CG, RAGDOLL_CG, false) end)
end

local function tagRagdoll(inst: Instance)
	inst:SetAttribute("Ragdoll", true)
end

local function setColliderProps(p: BasePart)
	p.Transparency = 1
	p.CanCollide = true
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = false
	p.Name = "RagdollCollider"
	p.CustomPhysicalProperties = PARAMS.COLLIDER_PHYSICS
	p.CollisionGroup = RAGDOLL_CG
end

local function weldTo(base: BasePart, part: BasePart)
	local wc = Instance.new("WeldConstraint")
	wc.Part0 = base
	wc.Part1 = part
	wc.Parent = part
	tagRagdoll(wc)
end

local function createCollider(base: BasePart, size: Vector3, offset: CFrame, name: string): BasePart
	local col = Instance.new("Part")
	col.Size = size
	col.Anchored = false
	setColliderProps(col)
	col.Name = name
	col.CFrame = base.CFrame * offset
	col.Parent = base
	tagRagdoll(col)
	weldTo(base, col)
	return col
end

local function createAttachment(part: BasePart, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.CFrame = cf
	a.Parent = part
	a.Name = "RagdollAttachment"
	tagRagdoll(a)
	return a
end

local function createBallSocket(motor: Motor6D, upper: number, twist: number)
	local p0, p1 = motor.Part0, motor.Part1
	if not (p0 and p1) then return end
	local a0 = createAttachment(p0, motor.C0)
	local a1 = createAttachment(p1, motor.C1)
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "RagdollConstraint"
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.LimitsEnabled = true
	socket.UpperAngle = upper
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -twist
	socket.TwistUpperAngle = twist
	socket.Restitution = 0
	socket.Parent = p0
	tagRagdoll(socket)
end

local function createRigidNeck(motor: Motor6D)
	local p0, p1 = motor.Part0, motor.Part1
	if not (p0 and p1) then return end
	local a0 = createAttachment(p0, motor.C0)
	local a1 = createAttachment(p1, motor.C1)
	local rigid = Instance.new("RigidConstraint")
	rigid.Name = "RagdollConstraint"
	rigid.Attachment0 = a0
	rigid.Attachment1 = a1
	rigid.Parent = p0
	tagRagdoll(rigid)
end

local function addGroundColliders(character: Model)
	-- Afirmación de tipo: asegurar que sean BasePart
	local torso = (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")) :: BasePart?
	local head = character:FindFirstChild("Head") :: BasePart?
	local lLeg = (character:FindFirstChild("Left Leg") or character:FindFirstChild("LeftLowerLeg") or character:FindFirstChild("LeftFoot")) :: BasePart?
	local rLeg = (character:FindFirstChild("Right Leg") or character:FindFirstChild("RightLowerLeg") or character:FindFirstChild("RightFoot")) :: BasePart?

	if lLeg then
		createCollider(lLeg, Vector3.new(1.4, 0.3, 1.4), CFrame.new(0, -lLeg.Size.Y/2 - 0.15, 0), "RagdollFoot_L")
	end
	if rLeg then
		createCollider(rLeg, Vector3.new(1.4, 0.3, 1.4), CFrame.new(0, -rLeg.Size.Y/2 - 0.15, 0), "RagdollFoot_R")
	end
	if torso then
		createCollider(torso, Vector3.new(2.8, 0.35, 2.8), CFrame.new(0, -torso.Size.Y/2 - 0.18, 0), "RagdollTorsoPlate")
	end
	if head then
		createCollider(head, Vector3.new(1.6, 0.35, 1.6), CFrame.new(0, -head.Size.Y/2 - 0.18, 0), "RagdollHeadPad")
	end
end


local function addGentleLaydownAlign(hrp: BasePart): AlignOrientation
	local att = hrp:FindFirstChildOfClass("Attachment") or Instance.new("Attachment", hrp)
	att.Name = "RagdollAttachment"
	tagRagdoll(att)
	local align = Instance.new("AlignOrientation")
	align.Name = "RagdollConstraint"
	align.Attachment0 = att
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Responsiveness = PARAMS.ALIGN_RESPONSIVENESS
	align.MaxTorque = PARAMS.ALIGN_MAX_TORQUE
	align.ReactionTorqueEnabled = true
	align.CFrame = CFrame.Angles(math.rad(90), 0, 0)
	align.Parent = hrp
	tagRagdoll(align)
	return align
end

local function disableMotors(character: Model): { Motor6D }
	local motors = {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") then
			d.Enabled = false
			table.insert(motors, d)
		end
	end
	return motors
end

local function setBodypartsNonCollide(character: Model)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Ragdoll") ~= true then
			if d.Name ~= "HumanoidRootPart" then
				d.CanCollide = false
			end
		end
	end
end


--============================================================================--
-- [+] MÉTODOS PRINCIPALES
--============================================================================--

function RagdollHandler.applyRagdoll(character: Model, duration: number)
	if not character or not character.Parent or CollectionService:HasTag(character, "Ragdolled") then
		return
	end

	ensureCollisionGroup()

	StunHandler.applyStun(character, duration)
	CollectionService:AddTag(character, "Ragdolled")
	character:SetAttribute("IsRagdolled", true)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") 
	if not humanoid or not hrp then return end

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local motors = disableMotors(character)
	for _, m in ipairs(motors) do
		if m.Name == "Neck" then
			createRigidNeck(m)
		else
			local lim = JOINT_LIMITS[m.Name] or { upper = 16, twist = 6 }
			createBallSocket(m, lim.upper, lim.twist)
		end
	end

	setBodypartsNonCollide(character)
	addGroundColliders(character)

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?


		local impulseVector = -hrp.CFrame.RightVector * PARAMS.BACKWARD_IMPulse_STRENGTH
		hrp:ApplyAngularImpulse(impulseVector)


	local align = addGentleLaydownAlign(hrp)


	task.delay(PARAMS.ALIGN_RELEASE_DELAY, function()
		if align and align.Parent then
			align:Destroy()
		end
	end)

	task.delay(duration, function()
		if character and character.Parent then
			RagdollHandler.cancelRagdoll(character, motors)
		end
	end)
end

function RagdollHandler.cancelRagdoll(character: Model, motors: { Motor6D }?)
	if not character or not CollectionService:HasTag(character, "Ragdolled") then
		return
	end

	CollectionService:RemoveTag(character, "Ragdolled")
	character:SetAttribute("IsRagdolled", false)

	for _, inst in ipairs(character:GetDescendants()) do
		if (inst:IsA("Attachment") and inst.Name == "RagdollAttachment")
			or ((inst:IsA("BallSocketConstraint") or inst:IsA("RigidConstraint") or inst:IsA("AlignOrientation")) and inst.Name == "RagdollConstraint")
			or (inst:IsA("WeldConstraint") and inst:GetAttribute("Ragdoll"))
			or (inst:IsA("BasePart") and inst.Name:match("^Ragdoll"))
		then
			inst:Destroy()
		end
	end

	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = true
		end
	end

	if motors then
		for _, m in ipairs(motors) do
			if m and m.Parent then
				m.Enabled = true
			end
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

return RagdollHandler
