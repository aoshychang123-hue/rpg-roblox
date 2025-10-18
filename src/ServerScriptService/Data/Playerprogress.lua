--!strict
-- PlayerProgress DataStore
-- - Guarda/restaura Level, XP, RequiredXP por jugador
-- - Sincroniza a Character al spawnear
-- - Autosave periódico y en salida
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local STORE_NAME = "PlayerProgress_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

type Progress = { Level: number, XP: number, RequiredXP: number }
type SessionEntry = {
	data: Progress,
	dirty: boolean,
	conns: { RBXScriptConnection },
	autosaveTask: thread?,
}

local sessions: { [number]: SessionEntry } = {}

local function defaultData(): Progress
	return { Level = 1, XP = 0, RequiredXP = 100 }
end

local function loadPlayerAsync(userId: number): Progress
	local ok, data = pcall(function()
		return store:GetAsync(("u_%d"):format(userId))
	end)
	if ok and typeof(data) == "table" then
		-- Sanitizar y defaults
		return {
			Level = tonumber(data.Level) or 1,
			XP = tonumber(data.XP) or 0,
			RequiredXP = tonumber(data.RequiredXP) or 100,
		}
	end
	return defaultData()
end

local function savePlayerAsync(userId: number, data: Progress)
	for i = 1, 3 do
		local ok, err = pcall(function()
			store:SetAsync(("u_%d"):format(userId), {
				Level = data.Level,
				XP = data.XP,
				RequiredXP = data.RequiredXP,
			})
		end)
		if ok then return true end
		warn(("[PlayerProgress] Save retry %d for %d failed: %s"):format(i, userId, tostring(err)))
		task.wait(1 + i) -- backoff incremental
	end
	return false
end

local function markDirty(userId: number)
	local s = sessions[userId]
	if s then s.dirty = true end
end

local function applyToCharacter(plr: Player, prog: Progress)
	local function setAttrs(char: Model?)
		if not char then return end
		char:SetAttribute("Level", prog.Level)
		char:SetAttribute("XP", prog.XP)
		char:SetAttribute("RequiredXP", prog.RequiredXP)
	end

	if plr.Character then setAttrs(plr.Character) end
	plr.CharacterAdded:Connect(setAttrs)
end

local function bindCharacterTracking(plr: Player)
	local s = sessions[plr.UserId]
	if not s then return end

	local function attach(char: Model?)
		-- Limpiar conexiones previas
		for _, c in ipairs(s.conns) do c:Disconnect() end
		s.conns = {}

		if not char then return end

		local function onAttr(name: string)
			local v = tonumber(char:GetAttribute(name))
			if name == "Level" and v then s.data.Level = v; markDirty(plr.UserId) end
			if name == "XP" and v then s.data.XP = v; markDirty(plr.UserId) end
			if name == "RequiredXP" and v then s.data.RequiredXP = math.max(1, v); markDirty(plr.UserId) end
		end

		table.insert(s.conns, char:GetAttributeChangedSignal("Level"):Connect(function() onAttr("Level") end))
		table.insert(s.conns, char:GetAttributeChangedSignal("XP"):Connect(function() onAttr("XP") end))
		table.insert(s.conns, char:GetAttributeChangedSignal("RequiredXP"):Connect(function() onAttr("RequiredXP") end))
	end

	attach(plr.Character)
	table.insert(s.conns, plr.CharacterAdded:Connect(attach))
	table.insert(s.conns, plr.CharacterRemoving:Connect(function() attach(nil) end))
end

local function startAutosave(plr: Player)
	local s = sessions[plr.UserId]
	if not s then return end
	s.autosaveTask = task.spawn(function()
		while Players:FindFirstChild(plr.Name) do
			if s.dirty then
				local ok = savePlayerAsync(plr.UserId, s.data)
				if ok then s.dirty = false end
			end
			task.wait(60) -- cada 60s
		end
	end)
end

Players.PlayerAdded:Connect(function(plr)
	local data = loadPlayerAsync(plr.UserId)
	sessions[plr.UserId] = { data = data, dirty = false, conns = {}, autosaveTask = nil }

	applyToCharacter(plr, data)
	bindCharacterTracking(plr)
	startAutosave(plr)
end)

local function cleanupPlayer(plr: Player)
	local s = sessions[plr.UserId]
	if not s then return end

	-- Guardar si queda pendiente
	if s.dirty then
		savePlayerAsync(plr.UserId, s.data)
		s.dirty = false
	end

	for _, c in ipairs(s.conns) do c:Disconnect() end
	sessions[plr.UserId] = nil
end

Players.PlayerRemoving:Connect(cleanupPlayer)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		cleanupPlayer(plr)
	end
end)
