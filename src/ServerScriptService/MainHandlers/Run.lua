--!strict
-- Run con Stamina + Exhaust (cooldown) estable y sin rebotes de animación.
-- Atributos (Character):
--  MaxStamina, Stamina, IsRunning, ClientRunKeyActive,
--  LastRunStopTime, RunExhaust (bool), RunExhaustUntil (number)
-- Regla: mientras RunExhaust==true NO se puede poner IsRunning=true.
-- Liberación: os.clock() >= RunExhaustUntil y (Stamina/MaxStamina) >= RESUME_THRESHOLD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RunKeyEvent: RemoteEvent = Remotes:FindFirstChild("RunKeyState") or Instance.new("RemoteEvent")
RunKeyEvent.Name = "RunKeyState"
RunKeyEvent.Parent = Remotes

-- Balance
local WALK_SPEED = 10
local RUN_SPEED  = 22

local DEFAULT_MAX_STAMINA = 100
local DRAIN_PER_SEC  = 22
local REGEN_PER_SEC  = 16
local REGEN_DELAY    = 0.65
local EXHAUST_COOLDOWN = 3.0        -- segundos bloqueado tras vaciar Stamina
local RESUME_THRESHOLD = 0.15       -- fracción mínima (15%) para poder salir de exhaust
local AUTO_RESUME_AT: number? = nil -- opcional (ej 0.6) o nil

-- Utilidades
local function ensureInit(char: Model)
	if char:GetAttribute("MaxStamina") == nil then char:SetAttribute("MaxStamina", DEFAULT_MAX_STAMINA) end
	if char:GetAttribute("Stamina") == nil then char:SetAttribute("Stamina", char:GetAttribute("MaxStamina")) end
	if char:GetAttribute("RunExhaust") == nil then char:SetAttribute("RunExhaust", false) end
	if char:GetAttribute("RunExhaustUntil") == nil then char:SetAttribute("RunExhaustUntil", 0) end
	if char:GetAttribute("LastRunStopTime") == nil then char:SetAttribute("LastRunStopTime", os.clock()) end
end

local function applySpeed(hum: Humanoid, running: boolean)
	hum.WalkSpeed = running and RUN_SPEED or WALK_SPEED
end

local function setRunning(char: Model, hum: Humanoid, state: boolean)
	local current = char:GetAttribute("IsRunning") == true
	if current == state then return end
	char:SetAttribute("IsRunning", state)
	applySpeed(hum, state)
	if not state then
		char:SetAttribute("LastRunStopTime", os.clock())
	end
end

local function inExhaust(char: Model): boolean
	if char:GetAttribute("RunExhaust") ~= true then
		return false
	end
	local untilTime = (char:GetAttribute("RunExhaustUntil") :: any) :: number
	-- Si ya pasó el tiempo, verificamos si la fracción de Stamina >= RESUME_THRESHOLD
	if os.clock() >= (untilTime or 0) then
		local stamina = (char:GetAttribute("Stamina") :: any) or 0
		local maxS = (char:GetAttribute("MaxStamina") :: any) or 100
		if maxS < 1 then maxS = 1 end
		if stamina / maxS >= RESUME_THRESHOLD then
			char:SetAttribute("RunExhaust", false)
			return false
		end
	end
	return char:GetAttribute("RunExhaust") == true
end

RunKeyEvent.OnServerEvent:Connect(function(plr, active: boolean)
	local char = plr.Character
	if not char then return end
	char:SetAttribute("ClientRunKeyActive", active == true)
end)

RunService.Heartbeat:Connect(function(dt)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if not hum then continue end

		ensureInit(char)

		local maxS = (char:GetAttribute("MaxStamina") :: any) :: number
		if maxS < 1 then maxS = 1 end
		local stamina    = (char:GetAttribute("Stamina") :: any) :: number
		local running    = char:GetAttribute("IsRunning") == true
		local keyActive  = char:GetAttribute("ClientRunKeyActive") == true
		local moveMag    = hum.MoveDirection.Magnitude

		local exhausted = inExhaust(char)
		local canCandidate = (not exhausted)
			and (stamina > 1)
			and (char:GetAttribute("IsRagdolled") ~= true)
			and (char:GetAttribute("IsPunching") ~= true)
			and (char:GetAttribute("IsDashing") ~= true)

		local wantRun = keyActive and moveMag > 0.05 and canCandidate

		if running then
			-- Drenaje
			stamina -= DRAIN_PER_SEC * dt
			if stamina <= 0 then
				stamina = 0
				-- Activar exhaust firme
				char:SetAttribute("RunExhaust", true)
				char:SetAttribute("RunExhaustUntil", os.clock() + EXHAUST_COOLDOWN)
				setRunning(char, hum, false)
			elseif not wantRun then
				setRunning(char, hum, false)
			end
		else
			-- Regen
			local lastStop = (char:GetAttribute("LastRunStopTime") :: any) :: number
			if not lastStop or (os.clock() - lastStop) >= REGEN_DELAY then
				if stamina < maxS then
					stamina = math.min(maxS, stamina + REGEN_PER_SEC * dt)
				end
			end

			-- Recalcular exhaust después de regen
			exhausted = inExhaust(char)

			-- Intentar auto-run sólo si no exhaust
			if wantRun and not exhausted then
				setRunning(char, hum, true)
			elseif AUTO_RESUME_AT
				and keyActive and moveMag > 0.05
				and not exhausted
				and (stamina / maxS) >= AUTO_RESUME_AT
				and canCandidate then
				setRunning(char, hum, true)
			end
		end

		char:SetAttribute("Stamina", stamina)
	end
end)

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		ensureInit(char)
		char:SetAttribute("IsRunning", false)
		char:SetAttribute("ClientRunKeyActive", false)
		-- asegurar valores
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		applySpeed(hum, false)
	end)
end)
