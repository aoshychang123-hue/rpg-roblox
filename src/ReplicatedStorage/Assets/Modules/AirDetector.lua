--!strict
-- AirDetector (cliente) mejorado:
-- - Usa Humanoid.FloorMaterial + raycast vertical con HipHeight
-- - Histéresis para evitar "pegado" en estados limítrofes
-- - Expone IsAirborne() y actualiza atributo Character:IsInAir (solo informativo/cliente)

local RunService = game:GetService("RunService")

local AirDetector = {}
AirDetector.__index = AirDetector

type Self = {
	_character: Model,
	_humanoid: Humanoid?,
	_hrp: BasePart?,
	_conn: RBXScriptConnection?,
	_lastInAir: boolean,
	_accum: number,
}

local function rayDown(origin: Vector3, excludeList: {Instance}): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList
	params.IgnoreWater = true
	return workspace:Raycast(origin, Vector3.new(0, -12, 0), params)
end

-- Umbrales con histéresis para estabilidad
local AIR_ENTER_DIST = 0.6   -- para pasar a "en aire" (desde suelo)
local AIR_EXIT_DIST  = 0.3   -- para salir de "aire" (aterrizar)
local SAMPLE_DT      = 0.05  -- 20 Hz

function AirDetector.new(character: Model)
	local self: Self = setmetatable({}, AirDetector)
	self._character = character
	self._humanoid = character:FindFirstChildOfClass("Humanoid")
	self._hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	self._lastInAir = false
	self._accum = 0

	self._conn = RunService.Heartbeat:Connect(function(dt: number)
		local hum = self._humanoid
		local hrp = self._hrp
		if not hum or not hrp or not character.Parent then return end

		self._accum += dt
		if self._accum < SAMPLE_DT then return end
		self._accum = 0

		-- Raycast hacia abajo excluyendo al character y contenedores comunes
		local exclude = { character }
		local dFolder = workspace:FindFirstChild("Debris")
		if dFolder then table.insert(exclude, dFolder) end
		local eFolder = workspace:FindFirstChild("Effects")
		if eFolder then table.insert(exclude, eFolder) end

		local rd = rayDown(hrp.Position, exclude)

		local floorIsAir = (hum.FloorMaterial == Enum.Material.Air)
		local groundDistFromFeet = math.huge
		if rd then
			-- Distancia del "pie" (centro HRP menos HipHeight) al suelo
			groundDistFromFeet = (hrp.Position.Y - rd.Position.Y) - hum.HipHeight
		end

		-- Estado bruto por sensores
		local freefall = (hum:GetState() == Enum.HumanoidStateType.Freefall)
		local wantAir = (floorIsAir and groundDistFromFeet > AIR_ENTER_DIST) or freefall
		local wantGround = (not floorIsAir) or (rd ~= nil and groundDistFromFeet <= AIR_EXIT_DIST)

		local inAir = self._lastInAir
		if self._lastInAir then
			-- Para salir de aire, pide condición de suelo estable
			if wantGround then inAir = false end
		else
			-- Para entrar a aire, pide condición de aire "suficiente"
			if wantAir then inAir = true end
		end
		self._lastInAir = inAir

		-- Atributo (informativo para cliente/UI). El server no debería depender de esto.
		character:SetAttribute("IsInAir", inAir)
	end)

	return self
end

function AirDetector:IsAirborne(): boolean
	return (self._character:GetAttribute("IsInAir") == true)
end

function AirDetector:Destroy()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

return AirDetector
