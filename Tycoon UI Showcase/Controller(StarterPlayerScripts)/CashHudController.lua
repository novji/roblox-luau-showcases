--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Utils = Shared:WaitForChild("Utils")

local NumberFormatter = require(Utils:WaitForChild("NumberFormatter"))

local CashHudController = {}

local LocalPlayer: Player = Players.LocalPlayer
local PlayerGui: PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local MainHud: ScreenGui
local MoneyFrame: Frame
local MoneyStroke: Frame
local CashLabel: TextLabel
local CashPerSecondFrame: Frame
local CashPerSecondValueLabel: TextLabel

local DisplayedCash: number = 0
local PulseTween: Tween? = nil
local BaseCashTextSize: number = 22

local function resolve_gui(): ()
	MainHud = PlayerGui:WaitForChild("MainHUD") :: ScreenGui
	MoneyFrame = MainHud:WaitForChild("Money") :: Frame
	MoneyStroke = MoneyFrame:WaitForChild("Stroke") :: Frame
	CashLabel = MoneyStroke:WaitForChild("Cash") :: TextLabel
	CashPerSecondFrame = MainHud:WaitForChild("CashPerSecond") :: Frame
	CashPerSecondValueLabel = CashPerSecondFrame:WaitForChild("Value") :: TextLabel

	BaseCashTextSize = CashLabel.TextSize
	CashLabel.TextScaled = false
end

local function pulse_value(): ()
	if PulseTween then
		PulseTween:Cancel()
		PulseTween = nil
	end

	CashLabel.TextSize = BaseCashTextSize

	local tween: Tween = TweenService:Create(
		CashLabel,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
		{TextSize = BaseCashTextSize + 3}
	)

	PulseTween = tween
	tween:Play()
end

local function update_cash_value(): ()
	local formatted: string = NumberFormatter.Format(DisplayedCash)
	formatted = string.gsub(formatted, "^%$", "")

	CashLabel.TextSize = BaseCashTextSize
	CashLabel.Text = formatted
	pulse_value()
end

local function update_cash_per_second(): ()
	local cash_per_second: number = LocalPlayer:GetAttribute("CashPerSecond") or 0
	CashPerSecondValueLabel.Text = tostring(math.max(0, math.floor(cash_per_second)))
end

local function on_cash_changed(): ()
	DisplayedCash = LocalPlayer:GetAttribute("Cash") or 0
	update_cash_value()
end

local function on_cash_per_second_changed(): ()
	update_cash_per_second()
end

function CashHudController.Init(): ()
	resolve_gui()
	update_cash_per_second()
	on_cash_changed()

	LocalPlayer:GetAttributeChangedSignal("Cash"):Connect(on_cash_changed)
	LocalPlayer:GetAttributeChangedSignal("CashPerSecond"):Connect(on_cash_per_second_changed)
end

return CashHudController
