--!strict
-- VFXPreloader
-- - Recorre ReplicatedStorage/Assets/VFX y hace PreloadAsync de recursos (ParticleEmitters, Beams, Trails, Images).
-- - Permite "precalentar" plantillas concretas por nombre.
-- - Expuesto para cliente; invocar en una LocalScript de StarterPlayerScripts.

local ContentProvider = game:GetService("ContentProvider")
local RS = game:GetService("ReplicatedStorage")

local VFXPreloader = {}

local assets = RS:WaitForChild("Assets")
local vfxFolder = assets:WaitForChild("VFX")

local _preloaded: {[Instance]: boolean} = {}
local _templatesIndexed: {[string]: Instance} = {}
local _initDone = false

local function indexTemplates()
	if next(_templatesIndexed) ~= nil then return end
	for _, inst in ipairs(vfxFolder:GetDescendants()) do
		-- Indexa sólo primer nivel por nombre (Model/Part directamente bajo VFX) y subcarpetas si las usas así
	end
	for _, child in ipairs(vfxFolder:GetChildren()) do
		_templatesIndexed[child.Name] = child
	end
end

local function addIfHasAsset(inst: Instance, bucket: {Instance})
	-- Cualquier instancia con asset referenciable vale para PreloadAsync
	if inst:IsA("ParticleEmitter")
		or inst:IsA("Beam")
		or inst:IsA("Trail")
		or inst:IsA("ImageLabel")
		or inst:IsA("ImageButton")
		or inst:IsA("Decal")
		or inst:IsA("Texture")
	then
		table.insert(bucket, inst)
	end
end

local function collectPreloadables(root: Instance): {Instance}
	local list: {Instance} = {}
	for _, d in ipairs(root:GetDescendants()) do
		addIfHasAsset(d, list)
	end
	return list
end

local function safePreload(list: {Instance})
	if #list == 0 then return end
	-- Filtra ya-preloaded
	local todo: {Instance} = {}
	for _, inst in ipairs(list) do
		if not _preloaded[inst] then
			table.insert(todo, inst)
			_preloaded[inst] = true
		end
	end
	if #todo == 0 then return end
	-- PreloadAsync puede lanzar warnings si algo no es válido; encapsulamos
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(todo)
	end)
	if not ok then
		warn("[VFXPreloader] PreloadAsync error:", err)
	end
end

-- Inicializa: pre-carga TODO el folder VFX
function VFXPreloader.init()
	if _initDone then return end
	indexTemplates()
	safePreload(collectPreloadables(vfxFolder))
	_initDone = true
end

-- Pre-carga por nombre una plantilla específica (útil si añades nuevas en runtime)
function VFXPreloader.ensureTemplate(name: string)
	indexTemplates()
	local t = _templatesIndexed[name]
	if not t then
		warn("[VFXPreloader] Template no encontrada en Assets/VFX:", name)
		return
	end
	safePreload(collectPreloadables(t))
end

-- Devuelve la instancia de plantilla (no clonada)
function VFXPreloader.getTemplate(name: string): Instance?
	indexTemplates()
	return _templatesIndexed[name]
end

return VFXPreloader
