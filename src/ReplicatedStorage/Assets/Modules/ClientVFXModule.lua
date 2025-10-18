--!strict
-- ClientVFXModule (Mazo1.X optimizado: aún más rápido, robusto y eficiente)
-- - Cachea plantillas y minimiza búsquedas
-- - Limpieza extra de conexiones y objetos
-- - Desconexión segura en todos los paths
-- - Minimiza raycasts, reduce instancias y uso de task.wait
-- - Opcional: pooling simple para debris
-- - Estructura y comentarios avanzados

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ClientVFXModule = {}

-- Carpetas de mundo
local debrisFolder = workspace:FindFirstChild("Debris") or (function()
	local f = Instance.new("Folder"); f.Name = "Debris"; f.Parent = workspace; return f
end)()
local effectsFolder = workspace:FindFirstChild("Effects") or (function()
	local f = Instance.new("Folder"); f.Name = "Effects"; f.Parent = workspace; return f
end)()

-- Assets y cache local de plantillas
local assets = ReplicatedStorage:FindFirstChild("Assets")
local vfxFolder = assets and assets:FindFirstChild("VFX")
local meshesFolder = assets and assets:FindFirstChild("Meshes")
local templateCache: {[string]: Instance} = {}

local function getTemplateCaseInsensitive(folder: Instance?, name: string): Instance?
	if not folder then return nil end
	local key = folder:GetFullName().."__"..name
	if templateCache[key] and templateCache[key].Parent then
		return templateCache[key]
	end
	local exact = folder:FindFirstChild(name)
	if exact then templateCache[key]=exact return exact end
	local target = string.lower(name)
	for _, child in ipairs(folder:GetChildren()) do
		if string.lower(child.Name) == target then
			templateCache[key] = child
			return child
		end
	end
	return nil
end

-- Defaults
local function createRockTemplate(): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.Rock
	p.Size = Vector3.new(1, 1, 1)
	return p
end

local vfxTemplates = {
	rockPart = getTemplateCaseInsensitive(vfxFolder, "DefaultPart"),
	smoke = getTemplateCaseInsensitive(vfxFolder, "Smoke"),
}

-- ===================== SHAKE CAMERA HELPER =====================
local camera = workspace.CurrentCamera
local cameraShakeConnection: RBXScriptConnection?
local function shakeCamera(duration: number, intensity: number, speed: number)
	if cameraShakeConnection then
		cameraShakeConnection:Disconnect()
		cameraShakeConnection = nil
	end
	local startTime = os.clock()
	local randomSeed = Vector3.new(math.random()*1000, math.random()*1000, math.random()*1000)
	cameraShakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= duration then
			cameraShakeConnection:Disconnect()
			cameraShakeConnection = nil
			return
		end
		local alpha = 1 - (elapsed / duration)
		local currentIntensity = intensity * alpha * alpha
		local shake = Vector3.new(
			(math.noise(elapsed*speed + randomSeed.X, 0)*2-1)*currentIntensity,
			(math.noise(0, elapsed*speed + randomSeed.Y)*2-1)*currentIntensity,
			0
		)
		if camera then
			camera.CFrame = camera.CFrame * CFrame.new(shake)
		end
	end)
end

local function rayDown(origin: Vector3, maxDistance: number, exclude: Instance?): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { debrisFolder, effectsFolder }
	if exclude then table.insert(ignore, exclude) end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local res = workspace:Raycast(origin, Vector3.new(0, -maxDistance, 0), params)
	if res then return res end
	res = workspace:Raycast(origin + Vector3.new(0, 50, 0), Vector3.new(0, -(maxDistance+50), 0), params)
	if res then return res end
	return workspace:Raycast(origin + Vector3.new(0, 150, 0), Vector3.new(0, -(maxDistance+150), 0), params)
end

-- Particle helpers
local function computeEmitCount(em: ParticleEmitter, root: Instance?): number
	for _, key in ipairs({ "EmitCount", "BurstCount", "EMIT_COUNT", "emitCount", "emitcount", "emit_count" }) do
		local v = em:GetAttribute(key)
		if typeof(v) == "number" and v > 0 then
			return math.floor(v + 0.5)
		end
	end
	if root then
		for _, key in ipairs({ "EmitCount", "BurstCount", "EMIT_COUNT", "emitCount", "emitcount", "emit_count" }) do
			local v2 = root:GetAttribute(key)
			if typeof(v2) == "number" and v2 > 0 then
				return math.floor(v2 + 0.5)
			end
		end
	end
	return 1
end

local function emitParticleBurst(em: ParticleEmitter, root: Instance?)
	pcall(function() em:Emit(computeEmitCount(em, root)) end)
end

local function emitAllParticleEmitters(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") then emitParticleBurst(d, root) end
	end
	for _, s in ipairs(root:GetDescendants()) do
		if s:IsA("Sound") then pcall(function() s:Play() end) end
	end
end

local function enableDescendants(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Beam") or d:IsA("Trail") then
			pcall(function() (d :: any).Enabled = true end)
		elseif d:IsA("ParticleEmitter") then
			emitParticleBurst(d, root)
		elseif d:IsA("Sound") then
			pcall(function() d:Play() end)
		end
	end
end

local function disableDescendants(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			pcall(function() (d :: any).Enabled = false end)
		end
	end
end

-- Transparencia y escala
local function gatherPartsAndDecals(root: Instance): {Instance}
	local items: {Instance} = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then table.insert(items, d) end
	end
	if root:IsA("BasePart") or root:IsA("Decal") then table.insert(items, root) end
	return items
end
local function setTransp(items: {Instance}, t: number)
	for _, it in ipairs(items) do
		if it:IsA("BasePart") then it.Transparency = t; it.Anchored = true; it.CanCollide = false
		elseif it:IsA("Decal") then it.Transparency = t end
	end
end
local function tweenTransp(items: {Instance}, toT: number, dur: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	for _, it in ipairs(items) do
		local ti = TweenInfo.new(dur, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
		pcall(function() TweenService:Create(it, ti, { Transparency = toT }):Play() end)
	end
end

type Sized = { part: BasePart, size: Vector3 }
local function collectPartsWithSize(root: Instance): { Sized }
	local arr: { Sized } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(arr, { part = d, size = d.Size }) end
	end
	if root:IsA("BasePart") then table.insert(arr, { part = root :: BasePart, size = (root :: BasePart).Size }) end
	return arr
end
local function setScaled(parts: { Sized }, factor: number)
	for _, r in ipairs(parts) do r.part.Size = r.size * factor end
end
local function tweenScaled(parts: { Sized }, factor: number, dur: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	for _, r in ipairs(parts) do
		local ti = TweenInfo.new(dur, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
		pcall(function() TweenService:Create(r.part, ti, { Size = r.size * factor }):Play() end)
	end
end

-- ===================== Utilidades de arma / estado =====================
local function findWeaponModel(character: Model, preferName: string?): Instance?
	local targetName = preferName or "Mazo1"
	local obj = character:FindFirstChild(targetName, true)
	if obj then return obj end
	local wid = character:GetAttribute("WeaponId")
	if typeof(wid) == "string" and #wid > 0 then
		local wobj = character:FindFirstChild(wid, true)
		if wobj then return wobj end
	end
	return nil
end

local function findWeaponBasePart(character: Model, preferName: string?): BasePart?
	local obj = findWeaponModel(character, preferName)
	if obj then
		local bp = (obj:IsA("BasePart") and obj) or obj:FindFirstChildWhichIsA("BasePart", true)
		if bp then return bp end
	end
	local right = character:FindFirstChild("RightHand", true)
		or character:FindFirstChild("RightLowerArm", true)
		or character:FindFirstChild("RightUpperArm", true)
		or character:FindFirstChild("Right Arm", true)
	if right and right:IsA("BasePart") then return right end
	return character:FindFirstChildWhichIsA("BasePart", true)
end

type MazoXState = { emitAttach: Instance?, beamAttachments: { Instance }, impactInstances: { Instance }, vignetteInstance: Instance? }
local mazoX: { [Model]: MazoXState } = {}
local function ensureState(ch: Model): MazoXState
	local st = mazoX[ch]
	if not st then st = { emitAttach = nil, beamAttachments = {}, impactInstances = {}, vignetteInstance = nil }; mazoX[ch] = st end
	return st
end

-- ===================== Soporte genérico pedido por otros sistemas =====================

function ClientVFXModule.createWindEffect(params: any)
	local pos = params.Position or Vector3.zero
	local hit = rayDown(pos + Vector3.new(0, 50, 0), 200, params.Character)
	local ground = (hit and hit.Position or pos) + Vector3.new(0, 0.05, 0)
	local mesh = meshesFolder and getTemplateCaseInsensitive(meshesFolder, "End")
	if not (mesh and mesh:IsA("BasePart")) then return end
	local wind = mesh:Clone()
	wind.CFrame = CFrame.new(ground)
	wind.Anchored = true; wind.CanCollide = false; wind.Transparency = 0.6
	local finalSize = Vector3.new(14, 0.2, 14)
	wind.Size = finalSize * 0.06
	wind.Parent = effectsFolder
	local t1 = TweenService:Create(wind, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = finalSize, Transparency = 0.32 })
	local t2 = TweenService:Create(wind, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
	t1:Play(); t1.Completed:Connect(function() t2:Play(); t2.Completed:Connect(function() wind:Destroy() end) end)
end

function ClientVFXModule.emitFromTemplate(templateName: string, worldCF: CFrame, lifetime: number?)
	if not vfxFolder then return end
	local template = getTemplateCaseInsensitive(vfxFolder, templateName); if not template then return end
	local clone = template:Clone(); clone.Parent = effectsFolder
	if clone:IsA("Model") then
		if not clone.PrimaryPart then
			local pp = clone:FindFirstChildWhichIsA("BasePart", true); if pp then clone.PrimaryPart = pp end
		end
		if clone.PrimaryPart then clone:PivotTo(worldCF) end
	elseif clone:IsA("BasePart") then
		clone.CFrame = worldCF
	elseif clone:IsA("Folder") then
		local bp = clone:FindFirstChildWhichIsA("BasePart", true); if bp then bp.CFrame = worldCF end
	end
	enableDescendants(clone)
	Debris:AddItem(clone, lifetime or 5)
end

-- ===================== Mazo X: Beams y Spawners "bonitos" =====================

local function ensureMazeBeams(character: Model)
	if not vfxFolder then return end
	local templateFolder = getTemplateCaseInsensitive(vfxFolder, "MazeBeam")
	if not templateFolder or not templateFolder:IsA("Folder") then
		warn("[VFX] VFX/MazeBeam no encontrado"); return
	end
	local weaponPart = findWeaponBasePart(character, "Mazo1"); if not weaponPart then return end
	local st = ensureState(character)
	-- limpia referencias muertas
	for i = #st.beamAttachments, 1, -1 do
		local inst = st.beamAttachments[i]
		if not inst or not inst.Parent then table.remove(st.beamAttachments, i) end
	end
	if #st.beamAttachments > 0 then
		for _, inst in ipairs(st.beamAttachments) do if inst and inst.Parent then enableDescendants(inst) end end
		return
	end
	local folderClone = templateFolder:Clone()
	for _, att in ipairs(folderClone:GetDescendants()) do
		if att:IsA("Attachment") then
			att.Parent = weaponPart
			enableDescendants(att)
			table.insert(st.beamAttachments, att)
			Debris:AddItem(att, 8)
		end
	end
	folderClone:Destroy()
end

local function spawnImpactMeshAdvanced(kind: "Start" | "End", worldCF: CFrame, profile: {
	appearT: number, holdT: number, fadeT: number, alphaMid: number, scaleFrom: number, scaleTo: number, rotateYdeg: number?, easingAppear: Enum.EasingStyle?, easingFade: Enum.EasingStyle?,
	}, st: MazoXState)
	if not vfxFolder then return end
	local impactFolder = getTemplateCaseInsensitive(vfxFolder, "ImpactMesh")
	if not impactFolder or not impactFolder:IsA("Folder") then return end
	local template = getTemplateCaseInsensitive(impactFolder, kind)
	if not template then return end
	local clone = template:Clone(); clone.Parent = effectsFolder
	if clone:IsA("Model") then
		if not clone.PrimaryPart then
			local pp = clone:FindFirstChildWhichIsA("BasePart", true); if pp then clone.PrimaryPart = pp end
		end
		if clone.PrimaryPart then clone:PivotTo(worldCF) end
	elseif clone:IsA("BasePart") then
		clone.CFrame = worldCF
	else
		local bp = clone:FindFirstChildWhichIsA("BasePart", true); if bp then bp.CFrame = worldCF end
	end
	local items = gatherPartsAndDecals(clone)
	local parts = collectPartsWithSize(clone)
	setTransp(items, 1)
	setScaled(parts, profile.scaleFrom)
	tweenTransp(items, profile.alphaMid, profile.appearT, profile.easingAppear or Enum.EasingStyle.Quad)
	tweenScaled(parts, profile.scaleTo, profile.appearT, profile.easingAppear or Enum.EasingStyle.Quad)
	if profile.rotateYdeg and profile.rotateYdeg ~= 0 then
		local tgt: BasePart? = nil
		if clone:IsA("Model") then tgt = clone.PrimaryPart
		elseif clone:IsA("BasePart") then tgt = clone
		else tgt = clone:FindFirstChildWhichIsA("BasePart", true) end
		if tgt then
			local ori = tgt.Orientation
			TweenService:Create(
				tgt, TweenInfo.new(profile.appearT+profile.holdT+profile.fadeT, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Orientation = Vector3.new(ori.X, ori.Y + profile.rotateYdeg, ori.Z) }
			):Play()
		end
	end
	task.delay(profile.appearT+profile.holdT, function()
		tweenTransp(items, 1, profile.fadeT, profile.easingFade or Enum.EasingStyle.Quad)
		task.delay(profile.fadeT, function() if clone and clone.Parent then clone:Destroy() end end)
	end)
	table.insert(st.impactInstances, clone)
	Debris:AddItem(clone, profile.appearT+profile.holdT+profile.fadeT+0.6)
end

local function spawnWindRing(worldCF: CFrame, baseSize: Vector3)
	local mesh = meshesFolder and getTemplateCaseInsensitive(meshesFolder, "End")
	if not (mesh and mesh:IsA("BasePart")) then return end
	local wind = mesh:Clone()
	wind.CFrame = worldCF
	wind.Anchored, wind.CanCollide = true, false
	wind.Transparency = 0.75
	wind.Size = baseSize * 0.05
	wind.Parent = effectsFolder
	local appearT, overshootT, fadeT = 0.06, 0.06, 0.16
	local peakSize = baseSize * 1.05
	local t1 = TweenService:Create(wind, TweenInfo.new(appearT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = baseSize, Transparency = 0.22 })
	local t1b = TweenService:Create(wind, TweenInfo.new(overshootT, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Size = peakSize })
	local rot = TweenService:Create(wind, TweenInfo.new(appearT+overshootT+fadeT, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Orientation = wind.Orientation+Vector3.new(0,60,0) })
	local t2 = TweenService:Create(wind, TweenInfo.new(fadeT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
	t1:Play(); rot:Play()
	t1.Completed:Connect(function()
		t1b:Play()
		t1b.Completed:Connect(function()
			t2:Play()
			t2.Completed:Connect(function() wind:Destroy() end)
		end)
	end)
end

function ClientVFXModule.createRockTrail(character: Model, duration: number)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local CONFIG = { MIN_ROCK_SIZE=0.7, MAX_ROCK_SIZE=1, SPAWN_INTERVAL=0.03, STAY_DURATION=0.2,
		FADE_OUT_DURATION=0.35, EMERGE_DURATION=0.12, STEP_OFFSET=1.8, RANDOM_OFFSET=1.1 }
	local startTime = os.clock()
	local trailFolder = Instance.new("Folder")
	trailFolder.Name = character.Name.."_RockTrail"
	trailFolder.Parent = debrisFolder
	Debris:AddItem(trailFolder, duration+2)
	local map = workspace:FindFirstChild("Map")
	local includeParams = RaycastParams.new()
	if map then
		includeParams.FilterType = Enum.RaycastFilterType.Include
		includeParams.FilterDescendantsInstances = { map }
	end
	while os.clock()-startTime < duration*0.8 and (hrp:FindFirstChild("DashVelocity") or hrp:FindFirstChild("DashSpeed")) do
		local right = hrp.CFrame.RightVector
		for _, side in ipairs({-1,1}) do
			local randomSideOffset = CONFIG.STEP_OFFSET * side + (math.random()*2-1)*CONFIG.RANDOM_OFFSET
			local forwardOffset = (math.random()*2-1)*0.8
			local spawnPos = hrp.Position + right*randomSideOffset + hrp.CFrame.LookVector*forwardOffset
			local groundResult: RaycastResult?
			if map then
				groundResult = workspace:Raycast(spawnPos, Vector3.yAxis*-10, includeParams)
			else
				groundResult = rayDown(spawnPos, 20, character)
			end
			if groundResult then
				local rockTemplate = vfxTemplates.rockPart
				local rock = (rockTemplate and rockTemplate:IsA("BasePart")) and rockTemplate:Clone() or createRockTemplate()
				rock.Anchored = true
				rock.CanCollide = false
				rock.CanTouch = false
				rock.CanQuery = false
				if groundResult.Instance:IsA("BasePart") then
					rock.Material = groundResult.Instance.Material
					rock.Color = groundResult.Instance.Color
				elseif groundResult.Instance:IsA("Terrain") then
					rock.Material = Enum.Material.Slate
					rock.Color = Color3.fromRGB(109, 113, 120)
				end
				local randomSize = math.random(CONFIG.MIN_ROCK_SIZE*10, CONFIG.MAX_ROCK_SIZE*10)/10
				rock.Size = Vector3.zero
				rock.CFrame = CFrame.new(groundResult.Position)*CFrame.new(0, -randomSize*0.5, 0)
				rock.Parent = trailFolder
				local emergeTween = TweenService:Create(
					rock, TweenInfo.new(CONFIG.EMERGE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = Vector3.one*randomSize, CFrame = rock.CFrame*CFrame.new(0, randomSize*0.5, 0) }
				)
				local fadeTween = TweenService:Create(
					rock, TweenInfo.new(CONFIG.FADE_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Size = Vector3.zero, Transparency = 1, CFrame = rock.CFrame*CFrame.new(0, randomSize, 0) }
				)
				emergeTween:Play()
				emergeTween.Completed:Connect(function()
					task.wait(CONFIG.STAY_DURATION)
					if rock.Parent then
						fadeTween:Play()
						fadeTween.Completed:Connect(function() rock:Destroy() end)
					end
				end)
			end
		end
		task.wait(CONFIG.SPAWN_INTERVAL)
	end
end

function ClientVFXModule.MazoX_emit1(character: Model)
	if not character or not character.Parent then return end
	
	local weaponPart = findWeaponBasePart(character, "Mazo1")
	if not weaponPart then return end
	shakeCamera(0.45, 1.8, 25)

	local st = ensureState(character)
	local player = Players.LocalPlayer
	if not player then return end
	if player.Character == character then
		if st.vignetteInstance and st.vignetteInstance.Parent then
			st.vignetteInstance:Destroy()
		end
		local vignetteGui = Instance.new("ScreenGui")
		vignetteGui.Name = "MazoXVignetteEffect"
		vignetteGui.ResetOnSpawn = false
		vignetteGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		vignetteGui.IgnoreGuiInset = true
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "VignetteImage"
		imageLabel.Image = "rbxassetid://102000718488836"
		imageLabel.BackgroundTransparency = 1
		imageLabel.Size = UDim2.new(1, 0, 1, 0)
		imageLabel.ImageTransparency = 1
		imageLabel.ScaleType = Enum.ScaleType.Slice
		imageLabel.SliceCenter = Rect.new(100, 100, 900, 900)
		imageLabel.Parent = vignetteGui
		vignetteGui.Parent = player:WaitForChild("PlayerGui")
		st.vignetteInstance = vignetteGui
		local appearTween = TweenService:Create(
			imageLabel,
			TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ ImageTransparency = 0.35 }
		)
		appearTween:Play()
		task.delay(0.15, function()
			if imageLabel and imageLabel.Parent then
				local fadeTween = TweenService:Create(
					imageLabel,
					TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
					{ ImageTransparency = 1 }
				)
				fadeTween:Play()
				fadeTween.Completed:Connect(function()
					if vignetteGui then vignetteGui:Destroy() end
					st.vignetteInstance = nil
				end)
			end
		end)
	end
	local template = vfxFolder and getTemplateCaseInsensitive(vfxFolder, "emitXmaze")
	if template and template:IsA("Attachment") then
		local clone = template:Clone()
		clone.Parent = weaponPart
		enableDescendants(clone)
		st.emitAttach = clone
		Debris:AddItem(clone, 8)
	end
	ensureMazeBeams(character)
end

function ClientVFXModule.MazoX_beamActive(character: Model)
	ensureMazeBeams(character)
end

function ClientVFXModule.MazoX_hit(character: Model)
	if not character or not character.Parent then return end
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")

	shakeCamera(0.45, 1.8, 25)

	local st = ensureState(character)
	for _, inst in ipairs(st.beamAttachments) do
		if inst and inst.Parent then disableDescendants(inst) end
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local forward = hrp.CFrame.LookVector
	local right = hrp.CFrame.RightVector
	local basePos = hrp.Position + forward * 5.0 + right * 1.4

	-- Prepare map-only raycast params (whitelist)
	local map = workspace:FindFirstChild("Map")
	local mapRayParams = RaycastParams.new()
	if map then
		mapRayParams.FilterType = Enum.RaycastFilterType.Whitelist
		mapRayParams.FilterDescendantsInstances = { map }
	else
		mapRayParams.FilterType = Enum.RaycastFilterType.Exclude
		mapRayParams.FilterDescendantsInstances = { character }
	end
	mapRayParams.IgnoreWater = true

	-- Helper: sample hit at a position using the map-only params
	local function sampleMapHitFrom(pos, downDist)
		downDist = downDist or 200
		local origin = pos + Vector3.new(0, math.max(5, downDist/4), 0)
		local dir = Vector3.new(0, -downDist, 0)
		return workspace:Raycast(origin, dir, mapRayParams)
	end

	-- Helper: apply map appearance (Color/Material) to a part when possible
	local function applyMapAppearance(part: BasePart?, hit)
		if not part then return end
		if hit and hit.Instance and hit.Instance:IsA("BasePart") then
			part.Color = hit.Instance.Color
			part.Material = hit.Instance.Material
		end
	end

	local hit = sampleMapHitFrom(basePos, 200)
	local groundPos = (hit and hit.Position or basePos) + Vector3.new(0, 0.05, 0)
	local yaw = math.rad(hrp.Orientation.Y)
	local worldCF = CFrame.new(groundPos) * CFrame.Angles(0, yaw, 0)

	-- === GROUND IMPACT MODEL ===
	do
		local ground = vfxFolder and getTemplateCaseInsensitive(vfxFolder, "groundmaze")
		if ground then
			local clone = ground:Clone()
			if clone:IsA("Model") then
				if not clone.PrimaryPart then
					local pp = clone:FindFirstChildWhichIsA("BasePart", true)
					if pp then clone.PrimaryPart = pp end
				end
				if clone.PrimaryPart then clone:PivotTo(worldCF) end
			elseif clone:IsA("BasePart") then
				clone.CFrame = worldCF
				clone.Anchored = true
			else
				local bp = clone:FindFirstChildWhichIsA("BasePart", true)
				if bp then bp.CFrame = worldCF end
			end
			clone.Parent = effectsFolder

			-- Apply map appearance to all baseparts inside the cloned ground (use the ground hit we already sampled)
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then
					applyMapAppearance(d, hit)
				end
			end

			emitAllParticleEmitters(clone)
			enableDescendants(clone)
			Debris:AddItem(clone, 6)
		end
	end

	-- === CRATER ROCKS (small & smooth, inside groundmaze area) ===
	do
		local NUM_CRATER_ROCKS = 6
		local ROCK_RADIUS = 3.2
		local ROCK_SIZE = Vector3.new(1.4, 1.2, 1.8)
		local ROCK_EMERGE_TIME = 0.25
		local ROCK_FADE_TIME = 0.4
		local ROT_OFFSET = CFrame.Angles(math.rad(37.587), math.rad(90), math.rad(180))
		local BURY_OFFSET = 0.06
		local START_BURY_FACTOR = 0.6

		for i = 1, NUM_CRATER_ROCKS do
			local angle = math.rad((360 / NUM_CRATER_ROCKS) * i)
			local offset = Vector3.new(math.cos(angle) * ROCK_RADIUS, 0, math.sin(angle) * ROCK_RADIUS)
			local spawnPos = groundPos + offset

			local ray = sampleMapHitFrom(spawnPos, 10)
			local finalPos = (ray and ray.Position or spawnPos) - Vector3.new(0, BURY_OFFSET, 0)

			local lookCF = CFrame.lookAt(finalPos, groundPos, Vector3.new(0, 1, 0))
			local baseCF = lookCF * ROT_OFFSET

			local rock = Instance.new("Part")
			rock.Size = ROCK_SIZE
			rock.Anchored = true
			rock.CanCollide = false
			rock.CanTouch = false
			rock.Material = Enum.Material.Slate
			rock.Color = Color3.fromRGB(107, 111, 118)
			rock.CFrame = baseCF
			rock.Parent = effectsFolder

			applyMapAppearance(rock, ray or hit)

			local startCF = baseCF * CFrame.new(0, -ROCK_SIZE.Y * START_BURY_FACTOR, 0)
			rock.CFrame = startCF

			local emergeTween = TweenService:Create(
				rock,
				TweenInfo.new(ROCK_EMERGE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = baseCF }
			)
			emergeTween:Play()

			task.delay(3.0, function()
				if not rock or not rock.Parent then return end
				local fadeTween = TweenService:Create(
					rock,
					TweenInfo.new(ROCK_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 }
				)
				fadeTween:Play()
				fadeTween.Completed:Connect(function()
					if rock and rock.Parent then rock:Destroy() end
				end)
			end)
			Debris:AddItem(rock, 6)
		end
	end

	-- === EXISTING WIND RING (kept as requested) ===

	-- === ADDITIONAL WIND MESH EFFECT (positioned at same place as wind ring) ===
	do
		local posWind = worldCF.Position

		local windFolder = Instance.new("Folder")
		windFolder.Name = "CraterWindMesh_" .. tostring(math.random(1000, 9999))
		windFolder.Parent = effectsFolder
		Debris:AddItem(windFolder, 2)

		local APPEAR_DURATION    = 0.18
		local FADE_DURATION      = 0.10
		local MESH_Y_OFFSET      = 2.5
		local INITIAL_TRANSPARENCY = 0.95
		local VISIBLE_TRANSPARENCY = 0.9
		local windMeshTemplate = meshesFolder and getTemplateCaseInsensitive(meshesFolder, "End")

		if windMeshTemplate and windMeshTemplate:IsA("BasePart") then
			local windMesh = windMeshTemplate:Clone()
			local baseCFrame = CFrame.new(posWind - Vector3.new(0, MESH_Y_OFFSET, 0)) * CFrame.Angles(0, math.rad(-45), 0)
			windMesh.CFrame = baseCFrame
			windMesh.Size = Vector3.new(1, 1, 1)
			local finalSize = windMesh.Size * 15
			windMesh.Transparency = INITIAL_TRANSPARENCY
			windMesh.Parent = windFolder
			windMesh.CanCollide = false
			windMesh.Anchored = true

			local SPIN_SPEED_DEGREES = 720
			local totalAngle = 0
			local connSpin
			connSpin = RunService.Heartbeat:Connect(function(dt)
				if not windMesh or not windMesh.Parent then
					if connSpin then connSpin:Disconnect() end
					return
				end
				local rotationThisFrame = math.rad(SPIN_SPEED_DEGREES) * dt
				totalAngle = totalAngle + rotationThisFrame
				pcall(function()
					if windMesh and windMesh.Parent then
						windMesh.CFrame = baseCFrame * CFrame.Angles(0, totalAngle, 0)
					end
				end)
			end)

			local appearTween = TweenService:Create(
				windMesh,
				TweenInfo.new(APPEAR_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = VISIBLE_TRANSPARENCY, Size = finalSize }
			)
			appearTween:Play()
			appearTween.Completed:Connect(function()
				local fadeTween = TweenService:Create(
					windMesh,
					TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Transparency = 1 }
				)
				fadeTween:Play()
				fadeTween.Completed:Connect(function()
					if connSpin then connSpin:Disconnect() end
					if windMesh and windMesh.Parent then windMesh:Destroy() end
				end)
			end)
		end
	end

	-- === SECONDARY IMPACT MESHes ===
	spawnImpactMeshAdvanced("Start", worldCF, {
		appearT = 0.05, holdT = 0.03, fadeT = 0.12,
		alphaMid = 0.20, scaleFrom = 0.34, scaleTo = 1.08,
		rotateYdeg = 30, easingAppear = Enum.EasingStyle.Quad, easingFade = Enum.EasingStyle.Quad,
	}, st)

	task.delay(0.09, function()
		spawnImpactMeshAdvanced("End", worldCF, {
			appearT = 0.09, holdT = 0.03, fadeT = 0.15,
			alphaMid = 0.18, scaleFrom = 0.18, scaleTo = 1.90,
			rotateYdeg = 70, easingAppear = Enum.EasingStyle.Sine, easingFade = Enum.EasingStyle.Quad,
		}, st)
	end)

	-- === REALISTIC DEBRIS (manual damping, more vertical, settle detection) ===
	do
		local NUM_DEBRIS = 6
		local MIN_HORZ = 3
		local MAX_HORZ = 12
		local MIN_VERT = 30
		local MAX_VERT = 50

		local MIN_SIZE, MAX_SIZE = 0.35, 0.7
		local GROUND_STAY_TIME = 2.5
		local POST_LAND_FADE = 0.45
		local ROT_OFFSET = CFrame.Angles(math.rad(37.587), math.rad(90), math.rad(180))
		local LAND_SINK = 0.14

		-- manual damping parameters
		local linearDrag = 1.15
		local angularDrag = 1.6

		for i = 1, NUM_DEBRIS do
			local debrisOffset = Vector3.new((math.random() - 0.5) * 2.2, 1.2, (math.random() - 0.5) * 2.2)
			local debrisOrigin = (worldCF * CFrame.new(debrisOffset)).Position
			local debrisRay = sampleMapHitFrom(debrisOrigin, 20)

			local debrisCube = Instance.new("Part")
			debrisCube.Shape = Enum.PartType.Block
			local size = math.random() * (MAX_SIZE - MIN_SIZE) + MIN_SIZE
			debrisCube.Size = Vector3.new(size, size, size)
			debrisCube.CFrame = CFrame.new(debrisOrigin)
			debrisCube.Anchored = false
			debrisCube.CanCollide = true
			debrisCube.Material = Enum.Material.Slate
			debrisCube.Color = Color3.fromRGB(107, 111, 118)
			debrisCube.Parent = effectsFolder

			applyMapAppearance(debrisCube, debrisRay or hit)

			-- Compose a more vertical launch
			local horz = math.random(MIN_HORZ, MAX_HORZ)
			local vert = math.random(MIN_VERT, MAX_VERT)
			local hx = (math.random() - 0.5)
			local hz = (math.random() - 0.5)
			local horizVec = Vector3.new(hx, 0, hz)
			if horizVec.Magnitude < 0.01 then horizVec = Vector3.new(0.2, 0, 0.1) end
			horizVec = horizVec.Unit * horz
			local vel = horizVec + Vector3.new(0, vert, 0)

			if debrisCube and debrisCube:IsA("BasePart") then
				pcall(function() debrisCube.AssemblyLinearVelocity = vel end)
				pcall(function()
					debrisCube.AssemblyAngularVelocity = Vector3.new(math.random(-3,3), math.random(-6,6), math.random(-3,3))
				end)
			end

			-- Manual damping loop
			if debrisCube and debrisCube:IsA("BasePart") then
				task.spawn(function()
					task.wait(0.02)
					local conn
					conn = RunService.Heartbeat:Connect(function(dt)
						if not debrisCube or not debrisCube.Parent or debrisCube.Anchored then
							if conn then conn:Disconnect() end
							return
						end
						local okV, v = pcall(function() return debrisCube.AssemblyLinearVelocity end)
						if okV and v then
							local mult = math.max(0, 1 - linearDrag * dt)
							pcall(function() debrisCube.AssemblyLinearVelocity = v * mult end)
						end
						local okA, av = pcall(function() return debrisCube.AssemblyAngularVelocity end)
						if okA and av then
							local multA = math.max(0, 1 - angularDrag * dt)
							pcall(function() debrisCube.AssemblyAngularVelocity = av * multA end)
						end
					end)
				end)
			end

			-- settle detection & final anchoring/orientation
			task.spawn(function()
				if not debrisCube then return end
				local settled = false
				local maxChecks = 40
				for check = 1, maxChecks do
					if not debrisCube or not debrisCube.Parent then break end
					local ok, v = pcall(function() return debrisCube.AssemblyLinearVelocity end)
					v = (ok and v) and v or Vector3.new(0,0,0)
					if v.Magnitude < 1.6 and math.abs(v.Y) < 0.8 then
						settled = true
						break
					end
					task.wait(0.1)
				end

				if not settled and debrisCube and debrisCube.Parent then
					task.wait(0.08)
					local ok2, v2 = pcall(function() return debrisCube.AssemblyLinearVelocity end)
					v2 = (ok2 and v2) and v2 or Vector3.new(0,0,0)
					if v2.Magnitude < 2.8 then settled = true end
				end

				if settled and debrisCube and debrisCube.Parent then
					pcall(function() debrisCube.AssemblyLinearVelocity = Vector3.new(0,0,0) end)
					pcall(function() debrisCube.AssemblyAngularVelocity = Vector3.new(0,0,0) end)
					debrisCube.Anchored = true

					local downRay = sampleMapHitFrom(debrisCube.Position, 50)
					local landPos = (downRay and downRay.Position) or debrisCube.Position

					local sinkPos = landPos - Vector3.new(0, LAND_SINK, 0)
					local lookCF = CFrame.lookAt(sinkPos, groundPos, Vector3.new(0,1,0))
					local oriented = lookCF * ROT_OFFSET
					debrisCube.CFrame = CFrame.new(sinkPos) * (oriented - oriented.Position)

					task.delay(GROUND_STAY_TIME, function()
						if not debrisCube or not debrisCube.Parent then return end
						local tween = TweenService:Create(
							debrisCube,
							TweenInfo.new(POST_LAND_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{ Size = debrisCube.Size * 0.08, Transparency = 1 }
						)
						tween:Play()
						tween.Completed:Connect(function()
							if debrisCube and debrisCube.Parent then debrisCube:Destroy() end
						end)
					end)
				else
					if debrisCube and debrisCube.Parent then
						task.delay(4.0, function()
							if debrisCube and debrisCube.Parent then debrisCube:Destroy() end
						end)
					end
				end
			end)

			Debris:AddItem(debrisCube, 8)
		end
	end
end


function ClientVFXModule.MazoX_end(character: Model)
	local st = mazoX[character]; if not st then return end
	if st.emitAttach and st.emitAttach.Parent then pcall(function() st.emitAttach:Destroy() end) end
	for _, inst in ipairs(st.beamAttachments) do if inst and inst.Parent then pcall(function() inst:Destroy() end) end end
	for _, inst in ipairs(st.impactInstances) do if inst and inst.Parent then pcall(function() inst:Destroy() end) end end
	if st.vignetteInstance and st.vignetteInstance.Parent then pcall(function() st.vignetteInstance:Destroy() end) end
	mazoX[character] = nil
end

function ClientVFXModule.MazoX_glow(character: Model)
	local weaponObj = findWeaponModel(character, "Mazo1")
	local basePart = findWeaponBasePart(character, "Mazo1")
	if not basePart then return end
	local h = Instance.new("Highlight")
	h.Adornee = (weaponObj and weaponObj:IsA("Model")) and weaponObj or basePart
	h.FillTransparency = 1
	h.OutlineTransparency = 0.25
	h.OutlineColor = Color3.new(1,1,1)
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = effectsFolder
	local showT = 0.22
	local holdT = 0.30
	local fadeT = 0.36
	local tweenIn = TweenService:Create(h, TweenInfo.new(showT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { OutlineTransparency = 0.25 })
	tweenIn:Play()
	tweenIn.Completed:Connect(function()
		task.delay(holdT, function()
			local tweenOut = TweenService:Create(h, TweenInfo.new(fadeT, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { OutlineTransparency = 1 })
			tweenOut:Play()
			tweenOut.Completed:Connect(function() h:Destroy() end)
		end)
	end)
end

function ClientVFXModule.MazoX_jump(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end
	shakeCamera(0.25, 0.6, 20)
	local look = hrp.CFrame.LookVector
	local upSpeed = 90
	local backSpeed = 70
	local att = hrp:FindFirstChildOfClass("Attachment") or Instance.new("Attachment", hrp)
	local lv = Instance.new("LinearVelocity")
	lv.MaxForce = math.huge
	lv.Attachment0 = att
	lv.Parent = hrp
	local alpha = Instance.new("NumberValue")
	alpha.Name = "JumpAlpha"
	alpha.Value = 1
	alpha.Parent = lv
	local con: RBXScriptConnection?
	con = RunService.RenderStepped:Connect(function()
		if not lv.Parent or not hrp.Parent then if con then con:Disconnect() end return end
		local v = Vector3.new(-look.X * backSpeed, upSpeed, -look.Z * backSpeed) * alpha.Value
		lv.VectorVelocity = v
	end)
	TweenService:Create(alpha, TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = 0 }):Play()
	Debris:AddItem(lv, 0.32)
	task.delay(0.32, function()
		if con then con:Disconnect() end
		if alpha then alpha:Destroy() end
	end)
	if vfxFolder then
		local smoke = vfxFolder:FindFirstChild("JumpSmoke")
		if smoke and smoke:IsA("BasePart") then
			local posSmoke = hrp.Position + Vector3.new(0, -3.2, 0)
			local posWind  = hrp.Position + Vector3.new(0, -2, 0)
			local cfSmoke = CFrame.new(posSmoke)
			local clone = smoke:Clone()
			clone.CFrame = cfSmoke
			clone.Anchored = true
			clone.Parent = effectsFolder
			for _, pe in ipairs(clone:GetDescendants()) do
				if pe:IsA("ParticleEmitter") then
					pcall(function()
						local cnt = (pe:GetAttribute("EmitCount") or 16)
						pe:Emit(cnt)
					end)
				end
			end
			Debris:AddItem(clone, 2)
			local windFolder = Instance.new("Folder")
			windFolder.Name = "CraterWind_" .. tostring(math.random(1000, 9999))
			windFolder.Parent = effectsFolder
			Debris:AddItem(windFolder, 2)
			local APPEAR_DURATION    = 0.18
			local FADE_DURATION      = 0.10
			local MESH_Y_OFFSET      = 2.5
			local PARTICLES_Y_OFFSET = 3
			local INITIAL_TRANSPARENCY = 0.95
			local VISIBLE_TRANSPARENCY = 0.9
			local windMeshTemplate = meshesFolder and getTemplateCaseInsensitive(meshesFolder, "End")
			if windMeshTemplate and windMeshTemplate:IsA("BasePart") then
				local windMesh = windMeshTemplate:Clone()
				local baseCFrame = CFrame.new(posWind - Vector3.new(0, MESH_Y_OFFSET, 0)) * CFrame.Angles(0, math.rad(-45), 0)
				windMesh.CFrame = baseCFrame
				windMesh.Size = Vector3.new(1, 1, 1)
				local finalSize = windMesh.Size * 15
				windMesh.Transparency = INITIAL_TRANSPARENCY
				windMesh.Parent = windFolder
				windMesh.CanCollide = false
				windMesh.Anchored = true
				local SPIN_SPEED_DEGREES = 720
				local totalAngle = 0
				local connSpin
				connSpin = RunService.Heartbeat:Connect(function(dt)
					if not windMesh or not windMesh.Parent then
						if connSpin then connSpin:Disconnect() end
						return
					end
					local rotationThisFrame = math.rad(SPIN_SPEED_DEGREES) * dt
					totalAngle = totalAngle + rotationThisFrame
					windMesh.CFrame = baseCFrame * CFrame.Angles(0, totalAngle, 0)
				end)
				local appearTween = TweenService:Create(
					windMesh,
					TweenInfo.new(APPEAR_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Transparency = VISIBLE_TRANSPARENCY, Size = finalSize }
				)
				appearTween:Play()
				appearTween.Completed:Connect(function()
					local fadeTween = TweenService:Create(
						windMesh,
						TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ Transparency = 1 }
					)
					fadeTween:Play()
					fadeTween.Completed:Connect(function()
						if connSpin then connSpin:Disconnect() end
						if windMesh and windMesh.Parent then windMesh:Destroy() end
					end)
				end)
			end
			local windVFX = vfxFolder:FindFirstChild("Wind") or (vfxFolder and getTemplateCaseInsensitive and getTemplateCaseInsensitive(vfxFolder, "Wind"))
			if windVFX and windVFX:IsA("BasePart") then
				local vfxClone = windVFX:Clone()
				vfxClone.CFrame = CFrame.new(posWind - Vector3.new(0, PARTICLES_Y_OFFSET, 0))
				vfxClone.Orientation = Vector3.new(0, -90, -90)
				vfxClone.Parent = windFolder
				for _, emitter in ipairs(vfxClone:GetDescendants()) do
					if emitter:IsA("ParticleEmitter") then
						if type(emitParticleBurst) == "function" then
							pcall(function() emitParticleBurst(emitter, vfxClone) end)
						else
							pcall(function() emitter:Emit(emitter:GetAttribute("EmitCount") or 8) end)
						end
					end
				end
				Debris:AddItem(vfxClone, 1.2)
			end
		end
	end
end

return ClientVFXModule
