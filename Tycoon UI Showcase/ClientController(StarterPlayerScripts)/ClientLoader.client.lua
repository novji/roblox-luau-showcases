--!strict

local Players = game:GetService("Players")

local LocalPlayer: Player = Players.LocalPlayer
local PlayerScripts: PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local Controllers = PlayerScripts:WaitForChild("Controllers")

local CashHudController = require(Controllers:WaitForChild("CashHudController"))
local DebugCashController = require(Controllers:WaitForChild("DebugCashController"))
local MainMenuController = require(Controllers:WaitForChild("MainMenuController"))
local PlotChooserController = require(Controllers:WaitForChild("PlotChooserController"))
local ShopController = require(Controllers:WaitForChild("ShopController"))
local TycoonUiController = require(Controllers:WaitForChild("TycoonUiController"))

local function init_controller(name: string, controller: {[string]: any}): ()
	local ok: boolean, err: any = pcall(function()
		controller.Init()
	end)

	if ok then
		return
	end

	warn(string.format("[ClientLoader] %s.Init failed: %s", name, tostring(err)))
end

init_controller("CashHudController", CashHudController)
init_controller("DebugCashController", DebugCashController)
init_controller("PlotChooserController", PlotChooserController)
init_controller("ShopController", ShopController)
init_controller("TycoonUiController", TycoonUiController)
init_controller("MainMenuController", MainMenuController)
