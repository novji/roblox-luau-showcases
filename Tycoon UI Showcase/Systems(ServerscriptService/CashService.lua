--!strict

-- Services

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Variables

local CashService = {}

local CashStore: GlobalDataStore = DataStoreService:GetDataStore("PlayerCashV1")

local PlayerCash: {[Player]: number} = {}
local PlayerCashPerSecond: {[Player]: number} = {}
local LoadedPlayers: {[Player]: boolean} = {}
local DirtyPlayers: {[Player]: boolean} = {}

local TickConnection: RBXScriptConnection? = nil
local TickAccumulator: number = 0
local AutosaveConnection: thread? = nil
local IsClosing: boolean = false

-- Constants

local DefaultCash: number = 0
local DefaultCashPerSecond: number = 0
local TickIntervalSeconds: number = 1
local AutosaveIntervalSeconds: number = 60
local SaveRetries: number = 3
local SchemaVersion: number = 1

-- Types

type CashData = {
	schema_version: number,
	cash: number,
	cash_per_second: number,
}

-- Private Functions

local function get_store_key(player: Player): string
	return "cash_" .. tostring(player.UserId)
end

local function get_default_data(): CashData
	return {
		schema_version = SchemaVersion,
		cash = DefaultCash,
		cash_per_second = DefaultCashPerSecond,
	}
end

local function sanitize_number(value: unknown, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end

	if value ~= value then
		return fallback
	end

	return math.max(0, math.floor(value))
end

local function sanitize_data(value: unknown): CashData
	local default_data: CashData = get_default_data()

	if typeof(value) ~= "table" then
		return default_data
	end

	local raw_data: {[string]: unknown} = value :: {[string]: unknown}

	return {
		schema_version = SchemaVersion,
		cash = sanitize_number(raw_data.cash, default_data.cash),
		cash_per_second = sanitize_number(raw_data.cash_per_second, default_data.cash_per_second),
	}
end

local function get_or_create_leaderstats(player: Player): Folder
	local leaderstats: Instance? = player:FindFirstChild("leaderstats")

	if leaderstats and leaderstats:IsA("Folder") then
		return leaderstats
	end

	local created_leaderstats: Folder = Instance.new("Folder")
	created_leaderstats.Name = "leaderstats"
	created_leaderstats.Parent = player

	return created_leaderstats
end

local function get_or_create_cash_value(player: Player): IntValue
	local leaderstats: Folder = get_or_create_leaderstats(player)
	local cash_value: Instance? = leaderstats:FindFirstChild("Cash")

	if cash_value and cash_value:IsA("IntValue") then
		return cash_value
	end

	if cash_value then
		cash_value:Destroy()
	end

	local created_cash_value: IntValue = Instance.new("IntValue")
	created_cash_value.Name = "Cash"
	created_cash_value.Value = 0
	created_cash_value.Parent = leaderstats

	return created_cash_value
end

local function apply_cash(player: Player, cash: number, mark_dirty: boolean): ()
	cash = math.max(0, math.floor(cash))

	PlayerCash[player] = cash
	player:SetAttribute("Cash", cash)

	local cash_value: IntValue = get_or_create_cash_value(player)
	cash_value.Value = cash

	if mark_dirty then
		DirtyPlayers[player] = true
	end
end

local function apply_cash_per_second(player: Player, cash_per_second: number, mark_dirty: boolean): ()
	cash_per_second = math.max(0, math.floor(cash_per_second))

	PlayerCashPerSecond[player] = cash_per_second
	player:SetAttribute("CashPerSecond", cash_per_second)

	if mark_dirty then
		DirtyPlayers[player] = true
	end
end

local function load_data(player: Player): CashData
	local ok: boolean, result: unknown = pcall(function()
		return CashStore:GetAsync(get_store_key(player))
	end)

	if not ok then
		warn("[CashService] Failed to load cash for " .. player.Name)
		return get_default_data()
	end

	return sanitize_data(result)
end

local function build_save_data(player: Player): CashData
	return {
		schema_version = SchemaVersion,
		cash = CashService.GetCash(player),
		cash_per_second = CashService.GetCashPerSecond(player),
	}
end

local function save_data(player: Player): boolean
	if not LoadedPlayers[player] then
		return false
	end

	local save_data_to_write: CashData = build_save_data(player)
	local key: string = get_store_key(player)

	for attempt: number = 1, SaveRetries do
		local ok: boolean = pcall(function()
			CashStore:UpdateAsync(key, function(_old_value: unknown)
				return save_data_to_write
			end)
		end)

		if ok then
			DirtyPlayers[player] = nil
			return true
		end

		task.wait(0.5 * attempt)
	end

	warn("[CashService] Failed to save cash for " .. player.Name)
	return false
end

local function save_if_dirty(player: Player): ()
	if not DirtyPlayers[player] then
		return
	end

	save_data(player)
end

local function on_player_added(player: Player): ()
	local data: CashData = load_data(player)

	LoadedPlayers[player] = true
	DirtyPlayers[player] = nil

	apply_cash(player, data.cash, false)
	apply_cash_per_second(player, data.cash_per_second, false)
end

local function on_player_removing(player: Player): ()
	save_data(player)

	PlayerCash[player] = nil
	PlayerCashPerSecond[player] = nil
	LoadedPlayers[player] = nil
	DirtyPlayers[player] = nil
end

local function run_income_tick(): ()
	for _, player: Player in Players:GetPlayers() do
		local cash_per_second: number = CashService.GetCashPerSecond(player)

		if cash_per_second <= 0 then
			continue
		end

		CashService.AddCash(player, cash_per_second)
	end
end

local function start_tick_loop(): ()
	if TickConnection then
		return
	end

	TickConnection = RunService.Heartbeat:Connect(function(delta_time: number)
		TickAccumulator += delta_time

		if TickAccumulator < TickIntervalSeconds then
			return
		end

		while TickAccumulator >= TickIntervalSeconds do
			TickAccumulator -= TickIntervalSeconds
			run_income_tick()
		end
	end)
end

local function start_autosave_loop(): ()
	if AutosaveConnection then
		return
	end

	AutosaveConnection = task.spawn(function()
		while not IsClosing do
			task.wait(AutosaveIntervalSeconds)

			for _, player: Player in Players:GetPlayers() do
				save_if_dirty(player)
			end
		end
	end)
end

local function bind_close_save(): ()
	game:BindToClose(function()
		IsClosing = true

		for _, player: Player in Players:GetPlayers() do
			save_data(player)
		end
	end)
end

-- Public Functions

function CashService.GetCash(player: Player): number
	local cash: number? = PlayerCash[player]

	if cash then
		return cash
	end

	return 0
end

function CashService.GetCashPerSecond(player: Player): number
	local cash_per_second: number? = PlayerCashPerSecond[player]

	if cash_per_second then
		return cash_per_second
	end

	return 0
end

function CashService.SetCash(player: Player, cash: number): ()
	if not player.Parent then
		return
	end

	if not LoadedPlayers[player] then
		return
	end

	apply_cash(player, cash, true)
end

function CashService.AddCash(player: Player, amount: number): ()
	if not player.Parent then
		return
	end

	if not LoadedPlayers[player] then
		return
	end

	if amount <= 0 then
		return
	end

	local current_cash: number = CashService.GetCash(player)
	apply_cash(player, current_cash + amount, true)
end

function CashService.RemoveCash(player: Player, amount: number): boolean
	if not player.Parent then
		return false
	end

	if not LoadedPlayers[player] then
		return false
	end

	if amount <= 0 then
		return false
	end

	local current_cash: number = CashService.GetCash(player)

	if current_cash < amount then
		return false
	end

	apply_cash(player, current_cash - amount, true)

	return true
end

function CashService.SetCashPerSecond(player: Player, cash_per_second: number): ()
	if not player.Parent then
		return
	end

	if not LoadedPlayers[player] then
		return
	end

	apply_cash_per_second(player, cash_per_second, true)
end

function CashService.AddCashPerSecond(player: Player, amount: number): ()
	if not player.Parent then
		return
	end

	if not LoadedPlayers[player] then
		return
	end

	if amount <= 0 then
		return
	end

	local current_cash_per_second: number = CashService.GetCashPerSecond(player)
	apply_cash_per_second(player, current_cash_per_second + amount, true)
end

function CashService.RemoveCashPerSecond(player: Player, amount: number): ()
	if not player.Parent then
		return
	end

	if not LoadedPlayers[player] then
		return
	end

	if amount <= 0 then
		return
	end

	local current_cash_per_second: number = CashService.GetCashPerSecond(player)
	apply_cash_per_second(player, math.max(0, current_cash_per_second - amount), true)
end

function CashService.Save(player: Player): boolean
	return save_data(player)
end

function CashService.IsLoaded(player: Player): boolean
	return LoadedPlayers[player] == true
end

function CashService.Start(): ()
	for _, player: Player in Players:GetPlayers() do
		task.spawn(on_player_added, player)
	end

	Players.PlayerAdded:Connect(on_player_added)
	Players.PlayerRemoving:Connect(on_player_removing)

	start_tick_loop()
	start_autosave_loop()
	bind_close_save()
end

return CashService