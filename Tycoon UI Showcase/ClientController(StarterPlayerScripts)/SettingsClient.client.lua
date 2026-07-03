--!strict

-- Services

local Players: Players = game:GetService("Players")
local UserInputService: UserInputService = game:GetService("UserInputService")
local Lighting: Lighting = game:GetService("Lighting")
local SoundService: SoundService = game:GetService("SoundService")

-- Types

type GraphicsQuality = "low" | "mid" | "high"

-- Constants

local VolumeOffPosition: UDim2 = UDim2.new(-0.033, 0, -1.143, 0)
local VolumeMiddlePosition: UDim2 = UDim2.new(0.448, 0, -1.276, 0)
local VolumeFullPosition: UDim2 = UDim2.new(0.93, 0, -1.276, 0)

local GraphicsLowPosition: UDim2 = UDim2.new(-0.049, 0, 0, 0)
local GraphicsMiddlePosition: UDim2 = UDim2.new(0.305, 0, 0, 0)
local GraphicsHighPosition: UDim2 = UDim2.new(0.681, 0, 0, 0)

local ToggleOffPosition: UDim2 = UDim2.new(-0.011, 0, 0, 0)
local ToggleOnPosition: UDim2 = UDim2.new(0.455, 0, 0, 0)

-- Variables

local LocalPlayer: Player = Players.LocalPlayer
local PlayerGui: PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local MusicVolume: number = 0.5
local AmbientVolume: number = 0.5
local UiVolume: number = 0.5
local GraphicsQualityValue: GraphicsQuality = "high"

local ShowItems: boolean = true
local ShowOtherCars: boolean = true

local DraggingKnob: GuiObject? = nil
local DraggingSetting: string? = nil

-- Private Functions

local function get_main_hud(): ScreenGui?
	local gui: Instance? = PlayerGui:WaitForChild("MainHUD", 10)

	if gui and gui:IsA("ScreenGui") then
		return gui
	end

	return nil
end

local function get_main_uis(): ScreenGui?
	local gui: Instance? = PlayerGui:WaitForChild("Main Uis", 10)

	if gui and gui:IsA("ScreenGui") then
		return gui
	end

	return nil
end

local function find_object(root: Instance?, name: string): Instance?
	if not root then
		return nil
	end

	return root:FindFirstChild(name, true)
end

local function find_gui_object(root: Instance?, name: string): GuiObject?
	local object: Instance? = find_object(root, name)

	if object and object:IsA("GuiObject") then
		return object
	end

	return nil
end

local function find_button(root: Instance?, name: string): GuiButton?
	local object: Instance? = find_object(root, name)

	if object and object:IsA("GuiButton") then
		return object
	end

	return nil
end

local function get_settings_frame(): GuiObject?
	return find_gui_object(get_main_uis(), "Settings")
end

local function get_section(section_name: string): GuiObject?
	return find_gui_object(get_settings_frame(), section_name)
end

local function get_track(section: GuiObject): GuiObject
	local frame: Instance? = section:FindFirstChild("Frame")

	if frame and frame:IsA("GuiObject") then
		return frame
	end

	return section
end

local function get_knob(section: GuiObject?): GuiObject?
	if not section then
		return nil
	end

	local named_knob: Instance? = section:FindFirstChild("Knob", true)

	if named_knob and named_knob:IsA("GuiObject") then
		return named_knob
	end

	local text_button: Instance? = section:FindFirstChild("TextButton", true)

	if text_button and text_button:IsA("GuiObject") then
		return text_button
	end

	for _, object: Instance in ipairs(section:GetDescendants()) do
		if not object:IsA("GuiButton") then
			continue
		end

		return object
	end

	for _, object: Instance in ipairs(section:GetDescendants()) do
		if not object:IsA("GuiObject") then
			continue
		end

		if object:IsA("TextLabel") or object:IsA("TextBox") then
			continue
		end

		if object.BackgroundTransparency >= 1 then
			continue
		end

		return object
	end

	return nil
end

local function prepare_knob(knob: GuiObject): ()
	knob.AnchorPoint = Vector2.new(0, 0)
end

local function save_setting(partial: {[string]: unknown}): ()
	local settings_api: unknown = shared.SettingsApi

	if typeof(settings_api) ~= "table" then
		return
	end

	local api: {[string]: unknown} = settings_api :: {[string]: unknown}
	local save: unknown = api.Save

	if typeof(save) ~= "function" then
		return
	end

	task.spawn(function()
		(save :: (partial: {[string]: unknown}) -> ())(partial)
	end)
end

local function get_x_value_from_mouse(track: GuiObject, screen_x: number): number
	local relative_x: number = (screen_x - track.AbsolutePosition.X) / track.AbsoluteSize.X

	return math.clamp(relative_x, 0, 1)
end

local function get_volume_from_mouse(section: GuiObject, screen_x: number): number
	local track: GuiObject = get_track(section)

	return get_x_value_from_mouse(track, screen_x)
end

local function get_volume_position(value: number): UDim2
	if value <= 0.05 then
		return VolumeOffPosition
	end

	if value >= 0.95 then
		return VolumeFullPosition
	end

	if value < 0.5 then
		local alpha: number = value / 0.5
		local x_scale: number = VolumeOffPosition.X.Scale + ((VolumeMiddlePosition.X.Scale - VolumeOffPosition.X.Scale) * alpha)
		local y_scale: number = VolumeOffPosition.Y.Scale + ((VolumeMiddlePosition.Y.Scale - VolumeOffPosition.Y.Scale) * alpha)

		return UDim2.new(x_scale, 0, y_scale, 0)
	end

	local alpha: number = (value - 0.5) / 0.5
	local x_scale: number = VolumeMiddlePosition.X.Scale + ((VolumeFullPosition.X.Scale - VolumeMiddlePosition.X.Scale) * alpha)
	local y_scale: number = VolumeMiddlePosition.Y.Scale + ((VolumeFullPosition.Y.Scale - VolumeMiddlePosition.Y.Scale) * alpha)

	return UDim2.new(x_scale, 0, y_scale, 0)
end

local function set_volume_visual(section_name: string, value: number): ()
	local knob: GuiObject? = get_knob(get_section(section_name))

	if not knob then
		warn(section_name .. " knob missing")
		return
	end

	prepare_knob(knob)

	knob.Position = get_volume_position(value)
end

local function apply_music_volume(): ()
	for _, object: Instance in ipairs(game:GetDescendants()) do
		if not object:IsA("Sound") then
			continue
		end

		local sound_group: unknown = object:GetAttribute("sound_group")
		local lower_name: string = string.lower(object.Name)

		if sound_group == "music" or string.find(lower_name, "music") then
			object.Volume = MusicVolume
		end
	end
end

local function apply_ambient_volume(): ()
	for _, object: Instance in ipairs(game:GetDescendants()) do
		if not object:IsA("Sound") then
			continue
		end

		local sound_group: unknown = object:GetAttribute("sound_group")
		local lower_name: string = string.lower(object.Name)

		if sound_group == "ambient" or string.find(lower_name, "ambient") then
			object.Volume = AmbientVolume
		end
	end
end

local function apply_ui_volume(): ()
	for _, object: Instance in ipairs(game:GetDescendants()) do
		if not object:IsA("Sound") then
			continue
		end

		local sound_group: unknown = object:GetAttribute("sound_group")
		local lower_name: string = string.lower(object.Name)

		if sound_group == "ui" or string.find(lower_name, "click") or string.find(lower_name, "button") then
			object.Volume = UiVolume
		end
	end
end

local function apply_volume_setting(setting_name: string, value: number): ()
	if setting_name == "MusicVolume" then
		MusicVolume = value
		apply_music_volume()
		save_setting({
			music_volume = value,
		})
		return
	end

	if setting_name == "AmbientVolume" then
		AmbientVolume = value
		apply_ambient_volume()
		save_setting({
			ambient_volume = value,
		})
		return
	end

	if setting_name == "UserInterfaceVolume" then
		UiVolume = value
		apply_ui_volume()
		save_setting({
			ui_volume = value,
		})
	end
end

local function get_graphics_from_mouse(section: GuiObject, screen_x: number): GraphicsQuality
	local track: GuiObject = get_track(section)
	local relative_x: number = get_x_value_from_mouse(track, screen_x)

	if relative_x < 0.33 then
		return "low"
	end

	if relative_x < 0.66 then
		return "mid"
	end

	return "high"
end

local function set_graphics_visual(): ()
	local knob: GuiObject? = get_knob(get_section("Graphics"))

	if not knob then
		warn("Graphics knob missing")
		return
	end

	prepare_knob(knob)

	if GraphicsQualityValue == "low" then
		knob.Position = GraphicsLowPosition
		return
	end

	if GraphicsQualityValue == "mid" then
		knob.Position = GraphicsMiddlePosition
		return
	end

	knob.Position = GraphicsHighPosition
end

local function apply_graphics(): ()
	if GraphicsQualityValue == "low" then
		Lighting.GlobalShadows = false
		Lighting.EnvironmentDiffuseScale = 0
		Lighting.EnvironmentSpecularScale = 0
		return
	end

	if GraphicsQualityValue == "mid" then
		Lighting.GlobalShadows = true
		Lighting.EnvironmentDiffuseScale = 0.5
		Lighting.EnvironmentSpecularScale = 0.5
		return
	end

	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
end

local function set_toggle_visual(section_name: string, enabled: boolean): ()
	local knob: GuiObject? = get_knob(get_section(section_name))

	if not knob then
		warn(section_name .. " knob missing")
		return
	end

	prepare_knob(knob)

	knob.Position = if enabled then ToggleOnPosition else ToggleOffPosition
end

local function get_toggle_from_mouse(section: GuiObject, screen_x: number): boolean
	local track: GuiObject = get_track(section)
	local relative_x: number = get_x_value_from_mouse(track, screen_x)

	return relative_x >= 0.5
end

local function apply_show_items(): ()
	local main_hud: ScreenGui? = get_main_hud()
	local main_uis: ScreenGui? = get_main_uis()

	for _, root: ScreenGui? in ipairs({main_hud, main_uis}) do
		if not root then
			continue
		end

		for _, object: Instance in ipairs(root:GetDescendants()) do
			if not object:IsA("GuiObject") then
				continue
			end

			local lower_name: string = string.lower(object.Name)

			if string.find(lower_name, "item") then
				object.Visible = ShowItems
			end
		end
	end
end

local function apply_show_other_cars(): ()
	for _, object: Instance in ipairs(workspace:GetDescendants()) do
		if not object:IsA("Model") then
			continue
		end

		local lower_name: string = string.lower(object.Name)

		if not string.find(lower_name, "car") then
			continue
		end

		local owner_id: unknown = object:GetAttribute("OwnerUserId")

		if owner_id == LocalPlayer.UserId then
			continue
		end

		for _, descendant: Instance in ipairs(object:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = if ShowOtherCars then 0 else 1
			end
		end
	end
end

local function bind_volume(section_name: string, default_value: number): ()
	local section: GuiObject? = get_section(section_name)

	if not section then
		warn(section_name .. " missing")
		return
	end

	set_volume_visual(section_name, default_value)

	section.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local knob: GuiObject? = get_knob(section)

		if not knob then
			return
		end

		prepare_knob(knob)

		DraggingKnob = knob
		DraggingSetting = section_name

		local value: number = get_volume_from_mouse(section, input.Position.X)

		knob.Position = get_volume_position(value)
		apply_volume_setting(section_name, value)
	end)
end

local function bind_graphics(): ()
	local section: GuiObject? = get_section("Graphics")

	if not section then
		warn("Graphics missing")
		return
	end

	set_graphics_visual()
	apply_graphics()

	section.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		GraphicsQualityValue = get_graphics_from_mouse(section, input.Position.X)

		set_graphics_visual()
		apply_graphics()

		save_setting({
			graphics_quality = GraphicsQualityValue,
		})
	end)
end

local function bind_toggle(section_name: string): ()
	local section: GuiObject? = get_section(section_name)

	if not section then
		warn(section_name .. " missing")
		return
	end

	if section_name == "Show Items" then
		set_toggle_visual(section_name, ShowItems)
	end

	if section_name == "Show Other Cars" then
		set_toggle_visual(section_name, ShowOtherCars)
	end

	section.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local enabled: boolean = get_toggle_from_mouse(section, input.Position.X)

		if section_name == "Show Items" then
			ShowItems = enabled
			set_toggle_visual(section_name, ShowItems)
			apply_show_items()
			save_setting({
				show_items = ShowItems,
			})
			return
		end

		if section_name == "Show Other Cars" then
			ShowOtherCars = enabled
			set_toggle_visual(section_name, ShowOtherCars)
			apply_show_other_cars()
			save_setting({
				show_other_cars = ShowOtherCars,
			})
		end
	end)
end

local function bind_open_close(): ()
	local main_hud: ScreenGui? = get_main_hud()
	local main_uis: ScreenGui? = get_main_uis()
	local settings: GuiObject? = get_settings_frame()

	if not main_hud then
		warn("MainHUD missing")
		return
	end

	if not main_uis then
		warn("Main Uis missing")
		return
	end

	if not settings then
		warn("Settings missing")
		return
	end

	local open_button: GuiButton? = find_button(main_hud, "settings")
	local exit_button: GuiButton? = find_button(settings, "Exit")

	if not open_button then
		warn("settings button missing")
		return
	end

	main_uis.Enabled = true
	settings.Visible = false

	open_button.MouseButton1Click:Connect(function()
		settings.Visible = not settings.Visible
	end)

	if exit_button then
		exit_button.MouseButton1Click:Connect(function()
			settings.Visible = false
		end)
	end
end

local function setup(): ()
	bind_open_close()

	bind_volume("MusicVolume", MusicVolume)
	bind_volume("AmbientVolume", AmbientVolume)
	bind_volume("UserInterfaceVolume", UiVolume)

	bind_graphics()

	bind_toggle("Show Items")
	bind_toggle("Show Other Cars")

	apply_music_volume()
	apply_ambient_volume()
	apply_ui_volume()
	apply_graphics()
	apply_show_items()
	apply_show_other_cars()
end

-- Handling

UserInputService.InputChanged:Connect(function(input: InputObject)
	if not DraggingKnob or not DraggingSetting then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local section: GuiObject? = get_section(DraggingSetting)

	if not section then
		return
	end

	local value: number = get_volume_from_mouse(section, input.Position.X)

	DraggingKnob.Position = get_volume_position(value)
	apply_volume_setting(DraggingSetting, value)
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	DraggingKnob = nil
	DraggingSetting = nil
end)

setup()