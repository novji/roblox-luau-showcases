--!strict

-- Services

local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")

-- Types

export type GraphicsQuality = "low" | "mid" | "high"

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

type SettingsStoreRecord = {
	schema_version: number,
	music_enabled: boolean?,
	sfx_enabled: boolean?,
	notifications_enabled: boolean?,
	camera_sensitivity: number?,
	music_volume: number?,
	ambient_volume: number?,
	ui_volume: number?,
	graphics_quality: GraphicsQuality?,
	show_items: boolean?,
	hints_enabled: boolean?,
	show_other_cars: boolean?,
	tycoon_name: string?,
}

-- Variables

local SettingsService = {}

local SettingsStore = DataStoreService:GetDataStore("PlayerSettingsV3")
local SettingsSchemaVersion: number = 5

local CachedSettings: {[Player]: SettingsData} = {}

-- Constants

local DefaultTycoonName: string = "My Car Factory"
local MinimumTycoonNameLength: number = 3
local MaximumTycoonNameLength: number = 24

-- Private Functions

local function get_store_key(player: Player): string
	return "settings_" .. tostring(player.UserId)
end

local function get_default_settings(): SettingsData
	return {
		music_enabled = true,
		sfx_enabled = true,
		notifications_enabled = true,
		camera_sensitivity = 1,
		music_volume = 1,
		ambient_volume = 1,
		ui_volume = 1,
		graphics_quality = "mid",
		show_items = true,
		hints_enabled = true,
		show_other_cars = true,
		tycoon_name = DefaultTycoonName,
	}
end

local function normalize_graphics_quality(value: unknown): GraphicsQuality
	if value == "low" then
		return "low"
	end

	if value == "mid" then
		return "mid"
	end

	if value == "high" then
		return "high"
	end

	return "mid"
end

local function clamp_volume(value: number): number
	return math.clamp(value, 0, 1)
end

local function clamp_camera_sensitivity(value: number): number
	return math.clamp(value, 0.1, 5)
end

local function trim_text(value: string): string
	return string.gsub(value, "^%s*(.-)%s*$", "%1")
end

local function normalize_tycoon_name(value: unknown): string
	if typeof(value) ~= "string" then
		return DefaultTycoonName
	end

	local name: string = trim_text(value)

	if #name < MinimumTycoonNameLength then
		return DefaultTycoonName
	end

	if #name > MaximumTycoonNameLength then
		name = string.sub(name, 1, MaximumTycoonNameLength)
	end

	return name
end

local function filter_tycoon_name(player: Player, value: unknown): string?
	if typeof(value) ~= "string" then
		return nil
	end

	local name: string = trim_text(value)

	if #name < MinimumTycoonNameLength then
		return nil
	end

	if #name > MaximumTycoonNameLength then
		name = string.sub(name, 1, MaximumTycoonNameLength)
	end

	local ok: boolean, result: TextFilterResult = pcall(function()
		return TextService:FilterStringAsync(name, player.UserId)
	end)

	if not ok then
		return nil
	end

	local filtered_ok: boolean, filtered_name: string = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)

	if not filtered_ok then
		return nil
	end

	filtered_name = trim_text(filtered_name)

	if #filtered_name < MinimumTycoonNameLength then
		return nil
	end

	return filtered_name
end

local function sanitize_settings(value: unknown): SettingsData
	local defaults: SettingsData = get_default_settings()

	if typeof(value) ~= "table" then
		return defaults
	end

	local raw: {[string]: unknown} = value :: {[string]: unknown}
	local schema_version: number = if typeof(raw.schema_version) == "number" then raw.schema_version :: number else 1

	local music_enabled: boolean = defaults.music_enabled
	local sfx_enabled: boolean = defaults.sfx_enabled
	local notifications_enabled: boolean = defaults.notifications_enabled
	local camera_sensitivity: number = defaults.camera_sensitivity
	local music_volume: number = defaults.music_volume
	local ambient_volume: number = defaults.ambient_volume
	local ui_volume: number = defaults.ui_volume
	local graphics_quality: GraphicsQuality = defaults.graphics_quality
	local show_items: boolean = defaults.show_items
	local hints_enabled: boolean = defaults.hints_enabled
	local show_other_cars: boolean = defaults.show_other_cars
	local tycoon_name: string = defaults.tycoon_name

	if typeof(raw.music_enabled) == "boolean" then
		music_enabled = raw.music_enabled
	end

	if typeof(raw.sfx_enabled) == "boolean" then
		sfx_enabled = raw.sfx_enabled
	end

	if typeof(raw.notifications_enabled) == "boolean" then
		notifications_enabled = raw.notifications_enabled
	end

	if typeof(raw.camera_sensitivity) == "number" then
		camera_sensitivity = clamp_camera_sensitivity(raw.camera_sensitivity)
	end

	if typeof(raw.music_volume) == "number" then
		music_volume = clamp_volume(raw.music_volume)
	end

	if typeof(raw.ambient_volume) == "number" then
		ambient_volume = clamp_volume(raw.ambient_volume)
	end

	if typeof(raw.ui_volume) == "number" then
		ui_volume = clamp_volume(raw.ui_volume)
	end

	if typeof(raw.show_items) == "boolean" then
		show_items = raw.show_items
	end

	if typeof(raw.hints_enabled) == "boolean" then
		hints_enabled = raw.hints_enabled
	end

	if typeof(raw.show_other_cars) == "boolean" then
		show_other_cars = raw.show_other_cars
	end

	graphics_quality = normalize_graphics_quality(raw.graphics_quality)
	tycoon_name = normalize_tycoon_name(raw.tycoon_name)

	if schema_version <= 2 then
		if typeof(raw.music_enabled) ~= "boolean" and typeof(raw.music_volume) == "number" then
			music_enabled = music_volume > 0
		end

		if typeof(raw.sfx_enabled) ~= "boolean" and typeof(raw.ambient_volume) == "number" then
			sfx_enabled = ambient_volume > 0
		end

		if typeof(raw.notifications_enabled) ~= "boolean" and typeof(raw.ui_volume) == "number" then
			notifications_enabled = ui_volume > 0
		end
	end

	return {
		music_enabled = music_enabled,
		sfx_enabled = sfx_enabled,
		notifications_enabled = notifications_enabled,
		camera_sensitivity = camera_sensitivity,
		music_volume = music_volume,
		ambient_volume = ambient_volume,
		ui_volume = ui_volume,
		graphics_quality = graphics_quality,
		show_items = show_items,
		hints_enabled = hints_enabled,
		show_other_cars = show_other_cars,
		tycoon_name = tycoon_name,
	}
end

local function to_store_record(settings: SettingsData): SettingsStoreRecord
	return {
		schema_version = SettingsSchemaVersion,
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

local function load_from_store(player: Player): SettingsData
	local ok: boolean, result: unknown = pcall(function()
		return SettingsStore:GetAsync(get_store_key(player))
	end)

	if not ok then
		return get_default_settings()
	end

	return sanitize_settings(result)
end

local function settings_equal(left: SettingsData, right: SettingsData): boolean
	return left.music_enabled == right.music_enabled
		and left.sfx_enabled == right.sfx_enabled
		and left.notifications_enabled == right.notifications_enabled
		and left.camera_sensitivity == right.camera_sensitivity
		and left.music_volume == right.music_volume
		and left.ambient_volume == right.ambient_volume
		and left.ui_volume == right.ui_volume
		and left.graphics_quality == right.graphics_quality
		and left.show_items == right.show_items
		and left.hints_enabled == right.hints_enabled
		and left.show_other_cars == right.show_other_cars
		and left.tycoon_name == right.tycoon_name
end

local function save_to_store(player: Player, settings: SettingsData): boolean
	local key: string = get_store_key(player)
	local record: SettingsStoreRecord = to_store_record(settings)

	for _ = 1, 3 do
		local ok: boolean = pcall(function()
			SettingsStore:UpdateAsync(key, function(old_value: unknown)
				local old_settings: SettingsData = sanitize_settings(old_value)

				if settings_equal(old_settings, settings) then
					return old_value
				end

				return record
			end)
		end)

		if ok then
			return true
		end

		task.wait(0.25)
	end

	return false
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

local function apply_partial(player: Player, base: SettingsData, partial: {[string]: unknown}): SettingsData
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
		next_settings.camera_sensitivity = clamp_camera_sensitivity(camera_sensitivity)
	end

	if typeof(music_volume) == "number" then
		next_settings.music_volume = clamp_volume(music_volume)
	end

	if typeof(ambient_volume) == "number" then
		next_settings.ambient_volume = clamp_volume(ambient_volume)
	end

	if typeof(ui_volume) == "number" then
		next_settings.ui_volume = clamp_volume(ui_volume)
	end

	if typeof(graphics_quality) == "string" then
		next_settings.graphics_quality = normalize_graphics_quality(graphics_quality)
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

	local filtered_name: string? = filter_tycoon_name(player, tycoon_name)

	if filtered_name then
		next_settings.tycoon_name = filtered_name
	end

	return next_settings
end

-- Public Functions

function SettingsService.GetDefault(): SettingsData
	return get_default_settings()
end

function SettingsService.Get(player: Player): SettingsData
	local cached: SettingsData? = CachedSettings[player]

	if cached then
		return cached
	end

	local loaded: SettingsData = load_from_store(player)
	CachedSettings[player] = loaded

	return loaded
end

function SettingsService.Save(player: Player, partial: {[string]: unknown}): (boolean, SettingsData)
	local current: SettingsData = SettingsService.Get(player)
	local next_settings: SettingsData = apply_partial(player, current, partial)

	CachedSettings[player] = next_settings

	local saved: boolean = save_to_store(player, next_settings)

	if saved then
		return true, next_settings
	end

	CachedSettings[player] = current
	return false, current
end

function SettingsService.Set(player: Player, settings: SettingsData): (boolean, SettingsData)
	local current: SettingsData = SettingsService.Get(player)
	local sanitized: SettingsData = sanitize_settings(to_store_record(settings))

	CachedSettings[player] = sanitized

	local saved: boolean = save_to_store(player, sanitized)

	if saved then
		return true, sanitized
	end

	CachedSettings[player] = current
	return false, current
end

function SettingsService.Reset(player: Player): (boolean, SettingsData)
	return SettingsService.Set(player, get_default_settings())
end

function SettingsService.Clear(player: Player): ()
	CachedSettings[player] = nil
end

return SettingsService