--!strict
-- AnimationHandler con canales:
--  - play(character, animName, fadeTime)  -> canal "Global" (legacy)
--  - playChannel(character, channel, animName, fadeTime)
-- Cada canal mantiene su propio lastTrack y no interrumpe otros canales.
-- Búsqueda: primero moveset (Assets/Animations/<Moveset>), después global.
-- Limpieza automática al morir o destruir el character.

local RS = game:GetService("ReplicatedStorage")
local AnimationsFolder = RS:WaitForChild("Assets"):WaitForChild("Animations")

export type TrackCache = {
	[string]: AnimationTrack,
	_lastTrack: AnimationTrack?,
}

-- Estructura:
-- loaded[character] = {
--    channels = { [channelName] = TrackCache },
--    diedConn = RBXScriptConnection?,
-- }
local loaded: { [Model]: { channels: { [string]: TrackCache } } } = {}

local AnimationHandler = {}

local function findAnimation(moveset: string, animName: string): Animation?
	local movesetFolder = AnimationsFolder:FindFirstChild(moveset)
	if movesetFolder then
		local anim = movesetFolder:FindFirstChild(animName, true)
		if anim and anim:IsA("Animation") then
			return anim
		end
	end
	local globalAnim = AnimationsFolder:FindFirstChild(animName, true)
	if globalAnim and globalAnim:IsA("Animation") then
		return globalAnim
	end
	warn(("[AnimationHandler] Anim '%s' not found (moveset '%s')"):format(animName, moveset))
	return nil
end

local function getAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function ensureCharacterCache(character: Model, humanoid: Humanoid)
	if loaded[character] then return end
	loaded[character] = {
		channels = {},
	}
	-- Limpieza en Died
	humanoid.Died:Connect(function()
		local data = loaded[character]
		if data then
			for _, cache in pairs(data.channels) do
				for k, track in pairs(cache) do
					if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
						track:Stop()
					end
					cache[k] = nil
				end
				cache._lastTrack = nil
			end
			loaded[character] = nil
		end
	end)
	-- Limpieza si se destruye
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			loaded[character] = nil
		end
	end)
end

local function playInternal(character: Model, channel: string, animName: string, fadeTime: number?): AnimationTrack?
	if typeof(animName) ~= "string" then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local animator = getAnimator(humanoid)
	ensureCharacterCache(character, humanoid)

	local moveset = (character:GetAttribute("Moveset") or "MainCharacter") :: string
	local animation = findAnimation(moveset, animName)
	if not animation then return nil end

	local data = loaded[character]
	local chanCache = data.channels[channel]
	if not chanCache then
		chanCache = {}
		data.channels[channel] = chanCache
	end

	-- track cache por anim name dentro del canal
	local track = chanCache[animName]
	if not track then
		track = animator:LoadAnimation(animation)
		chanCache[animName] = track
	end

	-- cross fade SOLO dentro del canal
	local last = chanCache._lastTrack
	if last and last ~= track and last.IsPlaying then
		last:Stop(fadeTime or 0.15)
	end

	if not track.IsPlaying then
		track:Play(fadeTime or 0.15)
	end
	chanCache._lastTrack = track
	return track
end

function AnimationHandler.playChannel(character: Model, channel: string, animName: string, fadeTime: number?): AnimationTrack?
	return playInternal(character, channel, animName, fadeTime)
end

-- Legacy (canal "Global")
function AnimationHandler.play(character: Model, animName: any, fadeTime: number?): AnimationTrack?
	if typeof(animName) ~= "string" then return nil end
	return playInternal(character, "Global", animName, fadeTime)
end

return AnimationHandler
