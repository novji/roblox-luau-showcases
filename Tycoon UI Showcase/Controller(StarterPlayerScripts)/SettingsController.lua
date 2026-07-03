--!strict

-- Services

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

-- Types

type GraphicsQuality = "low" | "mid" | "high"

export type SettingsData = {
	music_enabled: boolean,
	sfx_enabled: boolean,
	notifications_enabled: boolean,
	camera_sensitivity: number,
	music_volume: number,
	ambient_volume: number,
	ui_volume: number,
	graphics_quality: GraphicsQuality,
	show_items: boolean,
	hints_enabled: boolean,
	show_other_cars: boolean,
	tycoon_name: string,
}

-- Variables

local LocalPlayer: Player = Players.LocalPlayer

local SettingsRemotes: Folder = ReplicatedStorage:WaitForChild("SettingsRemotes") :: Folder
local GetSettings: RemoteFunction = SettingsRemotes:WaitForChild("GetSettings") :: RemoteFunction
local SaveSettings: RemoteFunction = SettingsRemotes:WaitForChild("SaveSettings") :: RemoteFunction

local CurrentSettings: SettingsData? = nil
local PendingPartial: {[string]: unknown} = {}
local SaveToken: number = 0
local SaveDelay: number = 0.35
local IsSaving: boolean = false

-- Private Functions

local function set_instance_enabled(instance: Instance, enabled: boolean): ()
	if instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam") then
		instance.Enabled = enabled
		return
	end

	if instance:IsA("Smoke") or instance:IsA("Fire") or instance:IsA("Sparkles") then
		instance.Enabled = enabled
		return
	end

	if instance:IsA("PostEffect") then
		instance.Enabled = enabled
		return
	end

	if instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
		instance.Enabled = enabled
		return
	end

	if instance:IsA("Decal") or instance:IsA("Texture") then
		instance.Transparency = if enabled then 0 else 1
		return
	end

	if instance:IsA("BasePart") then
		instance.LocalTransparencyModifier = if enabled then 0 else 1
	end
end

local function apply_graphics_tags(quality: GraphicsQuality): ()
	for _, instance: Instance in CollectionService:GetTagged("graphics_low_disable") do
		set_instance_enabled(instance, quality ~= "low")
	end

	for _, instance: Instance in CollectionService:GetTagged("graphics_mid_disable") do
		set_instance_enabled(instance, quality == "high")
	end

	for _, instance: Instance in CollectionService:GetTagged("graphics_high_only") do
		set_instance_enabled(instance, quality == "high")
	end
end

local function apply_lighting_quality(quality: GraphicsQuality): ()
	local atmosphere: Atmosphere? = Lighting:FindFirstChildOfClass("Atmosphere")
	local bloom: BloomEffect? = Lighting:FindFirstChildOfClass("BloomEffect")
	local sun_rays: SunRaysEffect? = Lighting:FindFirstChildOfClass("SunRaysEffect")
	local blur: BlurEffect? = Lighting:FindFirstChildOfClass("BlurEffect")
	local color_correction: ColorCorrectionEffect? = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")

	if quality == "low" then
		Lighting.GlobalShadows = false

		if atmosphere then
			atmosphere.Density = 0
		end

		if bloom then
			bloom.Enabled = false
		end

		if sun_rays then
			sun_rays.Enabled = false
		end

		if blur then
			blur.Enabled = false
		end

		if color_correction then
			color_correction.Enabled = false
		end

		return
	end

	if quality == "mid" then
		Lighting.GlobalShadows = true

		if atmosphere then
			atmosphere.Density = 0.25
		end

		if bloom then
			bloom.Enabled = false
		end

		if sun_rays then
			sun_rays.Enabled = false
		end

		if blur then
			blur.Enabled = false
		end

		if color_correction then
			color_correction.Enabled = true
		end

		return
	end

	Lighting.GlobalShadows = true

	if atmosphere then
		atmosphere.Density = 0.35
	end

	if bloom then
		bloom.Enabled = true
	end

	if sun_rays then
		sun_rays.Enabled = true
	end

	if blur then
		blur.Enabled = true
	end

	if color_correction then
		color_correction.Enabled = true
	end
end

local function apply_music(settings: SettingsData): ()
	for _, descendant: Instance in SoundService:GetDescendants() do
		if not descendant:IsA("Sound") then
			continue
		end

		if descendant:GetAttribute("sound_group") ~= "music" then
			continue
		end

		descendant.Volume = if settings.music_enabled then settings.music_volume else 0
	end
end

local function apply_sfx(settings: SettingsData): ()
	for _, descendant: Instance in SoundService:GetDescendants() do
		if not descendant:IsA("Sound") then
			continue
		end

		local sound_group: unknown = descendant:GetAttribute("sound_group")

		if sound_group == "ambient" then
			descendant.Volume = if settings.sfx_enabled then settings.ambient_volume else 0
			continue
		end

		if sound_group == "ui" then
			descendant.Volume = if settings.notifications_enabled then settings.ui_volume else 0
		end
	end
end

local function apply_camera(settings: SettingsData): ()
	LocalPlayer:SetAttribute("camera_sensitivity", settings.camera_sensitivity)
end

local function apply_graphics(settings: SettingsData): ()
	apply_graphics_tags(settings.graphics_quality)
	apply_lighting_quality(settings.graphics_quality)
end

local function apply_all(settings: SettingsData): ()
	apply_music(settings)
	apply_sfx(settings)
	apply_camera(settings)
	apply_graphics(settings)
end

local function clone_settings(settings: SettingsData): SettingsData
	return {
		music_enabled = settings.music_enabled,
		sfx_enabled = settings.sfx_enabled,
		notifications_enabled = settings.notifications_enabled,
		camera_sensitivity = settings.camera_sensitivity,
		music_volume = settings.music_volume,
		ambient_volume = settings.ambient_volume,
		ui_volume = settings.ui_volume,
		graphics_quality = settings.graphics_quality,
		show_items = settings.show_items,
		hints_enabled = settings.hints_enabled,
		show_other_cars = settings.show_other_cars,
		tycoon_name = settings.tycoon_name,
	}
end

local function apply_partial_local(base: SettingsData, partial: {[string]: unknown}): SettingsData
	local next_settings: SettingsData = clone_settings(base)

	local music_enabled: unknown = partial.music_enabled
	local sfx_enabled: unknown = partial.sfx_enabled
	local notifications_enabled: unknown = partial.notifications_enabled
	local camera_sensitivity: unknown = partial.camera_sensitivity
	local music_volume: unknown = partial.music_volume
	local ambient_volume: unknown = partial.ambient_volume
	local ui_volume: unknown = partial.ui_volume
	local graphics_quality: unknown = partial.graphics_quality
	local show_items: unknown = partial.show_items
	local hints_enabled: unknown = partial.hints_enabled
	local show_other_cars: unknown = partial.show_other_cars
	local tycoon_name: unknown = partial.tycoon_name

	if typeof(music_enabled) == "boolean" then
		next_settings.music_enabled = music_enabled
	end

	if typeof(sfx_enabled) == "boolean" then
		next_settings.sfx_enabled = sfx_enabled
	end

	if typeof(notifications_enabled) == "boolean" then
		next_settings.notifications_enabled = notifications_enabled
	end

	if typeof(camera_sensitivity) == "number" then
		next_settings.camera_sensitivity = math.clamp(camera_sensitivity, 0.1, 5)
	end

	if typeof(music_volume) == "number" then
		next_settings.music_volume = math.clamp(music_volume, 0, 1)
	end

	if typeof(ambient_volume) == "number" then
		next_settings.ambient_volume = math.clamp(ambient_volume, 0, 1)
	end

	if typeof(ui_volume) == "number" then
		next_settings.ui_volume = math.clamp(ui_volume, 0, 1)
	end

	if graphics_quality == "low" or graphics_quality == "mid" or graphics_quality == "high" then
		next_settings.graphics_quality = graphics_quality
	end

	if typeof(show_items) == "boolean" then
		next_settings.show_items = show_items
	end

	if typeof(hints_enabled) == "boolean" then
		next_settings.hints_enabled = hints_enabled
	end

	if typeof(show_other_cars) == "boolean" then
		next_settings.show_other_cars = show_other_cars
	end

	if typeof(tycoon_name) == "string" then
		next_settings.tycoon_name = tycoon_name
	end

	return next_settings
end

local function apply_changed(settings: SettingsData, partial: {[string]: unknown}): ()
	if partial.music_enabled ~= nil or partial.music_volume ~= nil then
		apply_music(settings)
	end

	if partial.sfx_enabled ~= nil or partial.notifications_enabled ~= nil or partial.ambient_volume ~= nil or partial.ui_volume ~= nil then
		apply_sfx(settings)
	end

	if partial.camera_sensitivity ~= nil then
		apply_camera(settings)
	end

	if partial.graphics_quality ~= nil then
		apply_graphics(settings)
	end
end

local function preview_partial(partial: {[string]: unknown}): ()
	local settings: SettingsData? = CurrentSettings

	if not settings then
		return
	end

	local next_settings: SettingsData = apply_partial_local(settings, partial)
	CurrentSettings = next_settings
	apply_changed(next_settings, partial)
end

local function copy_pending(): {[string]: unknown}
	local partial: {[string]: unknown} = PendingPartial
	PendingPartial = {}

	return partial
end

local function merge_pending(partial: {[string]: unknown}): ()
	for key: string, value: unknown in partial do
		PendingPartial[key] = value
	end
end

local function flush_pending(): ()
	if IsSaving then
		return
	end

	if next(PendingPartial) == nil then
		return
	end

	IsSaving = true

	while next(PendingPartial) ~= nil do
		local partial_to_save: {[string]: unknown} = copy_pending()

		local ok: boolean, saved: boolean, settings: SettingsData = pcall(function()
			return SaveSettings:InvokeServer(partial_to_save)
		end)

		if not ok or not saved then
			merge_pending(partial_to_save)
			break
		end

		CurrentSettings = settings
	end

	IsSaving = false
end

local function queue_save(partial: {[string]: unknown}): ()
	if not CurrentSettings then
		return
	end

	merge_pending(partial)
	preview_partial(partial)

	SaveToken += 1

	local current_token: number = SaveToken

	task.delay(SaveDelay, function()
		if current_token ~= SaveToken then
			return
		end

		flush_pending()
	end)
end

local function save_now(partial: {[string]: unknown}): (boolean, SettingsData?)
	if not CurrentSettings then
		return false, nil
	end

	merge_pending(partial)
	preview_partial(partial)

	SaveToken += 1

	task.spawn(function()
		flush_pending()
	end)

	return true, CurrentSettings
end

local function on_tag_added(_instance: Instance): ()
	local settings: SettingsData? = CurrentSettings

	if not settings then
		return
	end

	apply_graphics(settings)
end

local function on_sound_added(instance: Instance): ()
	local settings: SettingsData? = CurrentSettings

	if not settings then
		return
	end

	if not instance:IsA("Sound") then
		return
	end

	local sound_group: unknown = instance:GetAttribute("sound_group")

	if sound_group == "music" then
		apply_music(settings)
		return
	end

	if sound_group == "ambient" or sound_group == "ui" then
		apply_sfx(settings)
	end
end

-- API

local SettingsApi = {}

function SettingsApi.Get(): SettingsData?
	return CurrentSettings
end

function SettingsApi.Save(partial: {[string]: unknown}): ()
	queue_save(partial)
end

function SettingsApi.SaveNow(partial: {[string]: unknown}): (boolean, SettingsData?)
	return save_now(partial)
end

function SettingsApi.SetGraphicsQuality(graphics_quality: GraphicsQuality): ()
	queue_save({
		graphics_quality = graphics_quality,
	})
end

function SettingsApi.SetMusicEnabled(music_enabled: boolean): ()
	queue_save({
		music_enabled = music_enabled,
	})
end

function SettingsApi.SetSfxEnabled(sfx_enabled: boolean): ()
	queue_save({
		sfx_enabled = sfx_enabled,
	})
end

function SettingsApi.SetNotificationsEnabled(notifications_enabled: boolean): ()
	queue_save({
		notifications_enabled = notifications_enabled,
	})
end

function SettingsApi.SetMusicVolume(music_volume: number): ()
	queue_save({
		music_volume = music_volume,
	})
end

function SettingsApi.SetAmbientVolume(ambient_volume: number): ()
	queue_save({
		ambient_volume = ambient_volume,
	})
end

function SettingsApi.SetUiVolume(ui_volume: number): ()
	queue_save({
		ui_volume = ui_volume,
	})
end

function SettingsApi.SetCameraSensitivity(camera_sensitivity: number): ()
	queue_save({
		camera_sensitivity = camera_sensitivity,
	})
end

function SettingsApi.SetShowItems(show_items: boolean): ()
	queue_save({
		show_items = show_items,
	})
end

function SettingsApi.SetHintsEnabled(hints_enabled: boolean): ()
	queue_save({
		hints_enabled = hints_enabled,
	})
end

function SettingsApi.SetShowOtherCars(show_other_cars: boolean): ()
	queue_save({
		show_other_cars = show_other_cars,
	})
end

function SettingsApi.SetTycoonName(tycoon_name: string): ()
	queue_save({
		tycoon_name = tycoon_name,
	})
end

-- Handling

local loaded_settings: SettingsData = GetSettings:InvokeServer()
CurrentSettings = loaded_settings
apply_all(loaded_settings)

CollectionService:GetInstanceAddedSignal("graphics_low_disable"):Connect(on_tag_added)
CollectionService:GetInstanceAddedSignal("graphics_mid_disable"):Connect(on_tag_added)
CollectionService:GetInstanceAddedSignal("graphics_high_only"):Connect(on_tag_added)

SoundService.DescendantAdded:Connect(on_sound_added)

game:BindToClose(function()
	flush_pending()
end)

shared.SettingsApi = SettingsApi