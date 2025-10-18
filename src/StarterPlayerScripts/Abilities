--!strict
-- AbilityClient (Z/X/C/V)
-- - No invoca AbilityUse si la tecla no tiene habilidad (ConfigResolver)
-- - Z: envía Marker "Hit" al server
-- - X (Mazo1/Maze): respeta markers de anim:
--     Emit1 / Emit  -> ClientVFXModule.MazoX_emit1
--     BeamActive    -> ClientVFXModule.MazoX_beamActive
--     Glow          -> ClientVFXModule.MazoX_glow
--     Jump          -> ClientVFXModule.MazoX_jump
--     Hit           -> ClientVFXModule.MazoX_hit
--     end / End     -> ClientVFXModule.MazoX_end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Eliminamos TweenService, RunService y Debris porque ya no se usan en este script
-- local TweenService = game:GetService("TweenService")
-- local RunService = game:GetService("RunService")
-- local Debris = game:GetService("Debris")

local Player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityUse = Remotes:WaitForChild("AbilityUse")
local AbilityAction = Remotes:WaitForChild("AbilityAction")

local ModulesRoot = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Modules")
local AnimationHandler = require(ModulesRoot:WaitForChild("AnimationHandler"))
local ClientVFXModule = require(ModulesRoot:WaitForChild("ClientVFXModule"))
local ConfigResolver = require(ModulesRoot:WaitForChild("ConfigResolver"))

local keyMap = {
	[Enum.KeyCode.Z] = "Z",
	[Enum.KeyCode.X] = "X",
	[Enum.KeyCode.C] = "C",
	[Enum.KeyCode.V] = "V",
}

local localCd: {[string]: number} = {}
local markerConns: {[string]: RBXScriptConnection?} = {}

local function now() return os.clock() end

local function abilityAvailable(key: string): boolean
	local char = Player.Character
	if not char then return false end
	local ok, cfg = pcall(function() return ConfigResolver.get(char) end)
	if not ok or not cfg or not cfg.Abilities then return false end
	return cfg.Abilities[key] ~= nil
end

-- ===================================================================================
-- --- FUNCIÓN ELIMINADA ---
-- Se ha borrado la función local "quickAirNudgeSmooth" para evitar el doble impulso.
-- Toda la lógica del salto ahora reside en ClientVFXModule.MazoX_jump.
-- ===================================================================================

-- Markers de la X (Mazo1/Maze)
local function attachMazo1XMarkers(track: AnimationTrack, character: Model)
	if not track or not character then return end

	local cEmit1 = track:GetMarkerReachedSignal("Emit1"):Connect(function()
		ClientVFXModule.MazoX_emit1(character)
	end)
	local cEmit = track:GetMarkerReachedSignal("Emit"):Connect(function()
		ClientVFXModule.MazoX_emit1(character) -- Asumo que también querías que llamara a emit1
	end)
	local cBeam = track:GetMarkerReachedSignal("BeamActive"):Connect(function()
		ClientVFXModule.MazoX_beamActive(character)
	end)
	local cGlow = track:GetMarkerReachedSignal("Glow"):Connect(function()
		ClientVFXModule.MazoX_glow(character)
	end)
	local cHit = track:GetMarkerReachedSignal("Hit"):Connect(function()
		ClientVFXModule.MazoX_hit(character)
	end)

	-- AHORA SOLO HAY UNA CONEXIÓN PARA "JUMP", LA CORRECTA
	local cJump = track:GetMarkerReachedSignal("Jump"):Connect(function()
		ClientVFXModule.MazoX_jump(character)
	end)

	-- --- LÍNEA REDUNDANTE ELIMINADA ---
	-- Se quitó la línea que conectaba "Jump" con quickAirNudgeSmooth.

	local function cleanup()
		ClientVFXModule.MazoX_end(character)
		-- Asegúrate de que todas las conexiones están en la tabla para limpiarlas
		for _, c in ipairs({cEmit1, cEmit, cBeam, cGlow, cJump, cHit}) do
			if c then c:Disconnect() end
		end
	end

	track:GetMarkerReachedSignal("end"):Connect(cleanup)
	track:GetMarkerReachedSignal("End"):Connect(cleanup)
	track.Stopped:Connect(cleanup)
end


local function tryUse(key: string)
	local t = now()
	if (localCd[key] or 0) > t then return end
	if not abilityAvailable(key) then return end

	local ok, meta = pcall(function() return AbilityUse:InvokeServer(key) end)
	if not ok or not meta or meta.Accepted ~= true then return end

	localCd[key] = t + (meta.Cooldown or 0.5)

	local character = Player.Character
	if character and meta.Animation then
		local track = AnimationHandler.play(character, meta.Animation)

		-- Z: Marker "Hit" al server
		if key == "Z" and track then
			if markerConns[key] then
				(markerConns[key] :: RBXScriptConnection):Disconnect()
				markerConns[key] = nil
			end
			local sig = track:GetMarkerReachedSignal("Hit")
			markerConns[key] = sig:Connect(function()
				AbilityAction:FireServer(key, "Hit")
				if markerConns[key] then
					(markerConns[key] :: RBXScriptConnection):Disconnect()
					markerConns[key] = nil
				end
			end)
		end

		-- X: engancha markers si es Mazo1/Maze
		if key == "X" and track then
			local wtype = character:GetAttribute("WeaponType")
			local wid = character:GetAttribute("WeaponId")
			if (typeof(wid) == "string" and string.lower(wid) == "mazo1")
				or (typeof(wtype) == "string" and string.lower(wtype) == "maze") then
				attachMazo1XMarkers(track, character)
			end
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	local key = keyMap[input.KeyCode]
	if key then tryUse(key) end
end)
