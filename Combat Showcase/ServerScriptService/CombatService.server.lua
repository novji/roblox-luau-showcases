-- Discord: syruppifying | Roblox: syruppifying
--!strict
-- Services

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")
local RunService: RunService = game:GetService("RunService")
local CollectionService: CollectionService = game:GetService("CollectionService")

-- Variables

-- The client only asks the server to perform combat actions through CombatEvent.
-- HitFeedback is kept separate because feedback effects are visual only, while
-- damage, stun, parry, block, and knockback are all decided on the server.
local Remotes: Folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
local CombatEvent: RemoteEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent
local HitFeedback: RemoteEvent = Remotes:WaitForChild("HitFeedback") :: RemoteEvent

local AnimRoot: Folder = ServerStorage:WaitForChild("Animations") :: Folder
local MeleeFolder: Folder = AnimRoot:WaitForChild("Meele") :: Folder
local HitFolder: Folder = AnimRoot:WaitForChild("Hit") :: Folder

-- Constants

-- Combat values are grouped here so the system can be tuned without changing
-- the attack flow itself. The hitbox size is intentionally close to the R6 limb
-- size, with padding added later to make fast swings feel consistent.
local HitboxSize: Vector3 = Vector3.new(1, 2.2, 1)
local HitboxPadding: Vector3 = Vector3.new(0.25, 0.25, 0.25)

local UseBlockcastSweep: boolean = true

local SwingTime: number = 0.3
local AttackCooldown: number = 0.4
local StunTime: number = 0.35

local ParryWindow: number = 0.18
local ParryRecover: number = 0.45
local ParryStun: number = 0.65
local DefendFacingDotMin: number = 0.25

local ArmDamage: number = 10
local LegDamage: number = 14

local NpcTag: string = "CombatNPC"
local AiTick: number = 0.2
local AiAggroRange: number = 26
local AiAttackRange: number = 5.25
local AiAttackDotMin: number = 0.35
local AiParryChance: number = 0.08
local AiBlockChance: number = 0.18
local AiDecisionCooldown: number = 0.75

-- Types

type KnockbackProfile = {
	minPower: number,
	maxPower: number,
	upMin: number,
	upMax: number,
	maxImpulse: number,
	spikeChance: number?,
	spikeMult: number?,
}

type ParryState = {
	active_until: number,
	recover_until: number,
}

type BlockState = {
	active: boolean,
}

-- State

-- Temporary combat state is keyed by either Player or NPC Model.
-- This allows the same attack, block, parry, stun, and combo functions to work
-- for both real players and tagged NPCs without duplicating combat logic.
local Cooldowns: { [Instance]: number } = {}
local StunnedUntil: { [Instance]: number } = {}
local Combo: { [Instance]: number } = {}
local LastAttackTime: { [Instance]: number } = {}

local ParryStates: { [Instance]: ParryState } = {}
local BlockStates: { [Instance]: BlockState } = {}
local NpcDecisionCooldowns: { [Instance]: number } = {}

local TrackCache: { [Humanoid]: { [string]: AnimationTrack } } = {}

-- Private Functions

local function now(): number
	return os.clock()
end

local function alive(humanoid: Humanoid?): boolean
	return humanoid ~= nil and humanoid.Health > 0
end

-- Animations are loaded and cached per Humanoid.
-- Roblox animation loading can be expensive if repeated every swing, so each
-- track is cached by name and reused until the matching Animation object changes.
local function ensure_animator(humanoid: Humanoid): Animator
	local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local created: Animator = Instance.new("Animator")
	created.Parent = humanoid
	return created
end

local function get_anim(folder: Instance, name: string): Animation?
	local animation_instance: Instance? = folder:FindFirstChild(name)
	if not animation_instance or not animation_instance:IsA("Animation") then
		return nil
	end

	local animation: Animation = animation_instance :: Animation
	if animation.AnimationId == "" then
		return nil
	end

	return animation
end

local function stop_cached(humanoid: Humanoid, except_name: string?)
	local tracks: { [string]: AnimationTrack }? = TrackCache[humanoid]
	if not tracks then
		return
	end

	for name: string, track: AnimationTrack in pairs(tracks) do
		if except_name and name == except_name then
			continue
		end

		if track.IsPlaying then
			track:Stop(0.05)
		end
	end
end

local function get_track(humanoid: Humanoid, name: string, animation: Animation): AnimationTrack
	local tracks: { [string]: AnimationTrack } = TrackCache[humanoid] or {}
	TrackCache[humanoid] = tracks

	local cached: AnimationTrack? = tracks[name]
	if cached and cached.Animation == animation then
		return cached
	end

	local animator: Animator = ensure_animator(humanoid)
	local track: AnimationTrack = animator:LoadAnimation(animation)
	tracks[name] = track

	return track
end

local function play_anim(humanoid: Humanoid, name: string, animation: Animation?, priority: Enum.AnimationPriority)
	if not alive(humanoid) then
		return
	end

	if not animation then
		return
	end

	stop_cached(humanoid, name)

	local track: AnimationTrack = get_track(humanoid, name, animation)
	track.Priority = priority
	track.Looped = false

	if track.IsPlaying then
		track:Stop(0)
	end

	track:Play(0.05, 1, 1)
end

-- Knockback uses ApplyImpulse on the target root part so the result stays
-- physics-based instead of teleporting the character. The power is randomized
-- within a safe range, then clamped so a lucky roll cannot create extreme launches.
local function apply_knockback(attacker_hrp: BasePart, target_hrp: BasePart, profile: KnockbackProfile)
	local direction: Vector3 = target_hrp.Position - attacker_hrp.Position
	if direction.Magnitude <= 0.001 then
		return
	end

	local unit: Vector3 = direction.Unit
	local roll: number = math.random()
	local bias: number = roll * roll
	local power: number = profile.minPower + (profile.maxPower - profile.minPower) * bias

	if profile.spikeChance and profile.spikeMult then
		if math.random(1, 100) <= profile.spikeChance then
			power *= profile.spikeMult
		end
	end

	local up: number = profile.upMin + (profile.upMax - profile.upMin) * math.random()
	local impulse: Vector3 = (unit * power) + Vector3.new(0, up, 0)

	if impulse.Magnitude > profile.maxImpulse then
		impulse = impulse.Unit * profile.maxImpulse
	end

	target_hrp:ApplyImpulse(impulse)
end

-- Players and NPCs are represented differently in Roblox.
-- Player characters are mapped back to the Player object, while NPCs use their
-- Model. This keeps state cleanup and combat checks consistent for both.
local function get_subject_from_model(model: Model): Instance
	local player: Player? = Players:GetPlayerFromCharacter(model)
	if player then
		return player
	end

	return model
end

-- This combat example is built around R6.
-- The attack limbs are read directly from the character model, and the function
-- fails early if the character is missing required R6 parts or is already dead.
local function get_rig_parts(model: Model): (Humanoid?, BasePart?, BasePart?, BasePart?, BasePart?)
	local humanoid: Humanoid? = model:FindFirstChildOfClass("Humanoid")
	local hrp: BasePart? = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local left_arm: BasePart? = model:FindFirstChild("Left Arm") :: BasePart?
	local right_arm: BasePart? = model:FindFirstChild("Right Arm") :: BasePart?
	local right_leg: BasePart? = model:FindFirstChild("Right Leg") :: BasePart?

	if not humanoid or not hrp or not left_arm or not right_arm or not right_leg then
		return nil, nil, nil, nil, nil
	end

	if not alive(humanoid) then
		return nil, nil, nil, nil, nil
	end

	return humanoid, hrp, left_arm, right_arm, right_leg
end

local function reaction_name_from_attack(attack_name: string): string
	if attack_name == "PunchLeft" then
		return "HitLeft"
	end

	if attack_name == "PunchRight" then
		return "HitRight"
	end

	return "HitKick"
end

-- Blocking only works when the defender is facing the attacker.
-- This prevents players from holding block while being protected from every angle.
local function facing_ok(defender_hrp: BasePart, attacker_hrp: BasePart): boolean
	local to_attacker: Vector3 = attacker_hrp.Position - defender_hrp.Position
	if to_attacker.Magnitude <= 0.001 then
		return false
	end

	local dot: number = defender_hrp.CFrame.LookVector:Dot(to_attacker.Unit)
	return dot >= DefendFacingDotMin
end

-- Parry and block are stored separately because they have different rules.
-- Parry is a short timing window with recovery, while block is a held state that
-- only works when the defender is facing the attacker.
local function get_parry_state(subject: Instance): ParryState
	local parry_state: ParryState? = ParryStates[subject]
	if parry_state then
		return parry_state
	end

	local created: ParryState = {
		active_until = 0,
		recover_until = 0,
	}

	ParryStates[subject] = created
	return created
end

local function get_block_state(subject: Instance): BlockState
	local block_state: BlockState? = BlockStates[subject]
	if block_state then
		return block_state
	end

	local created: BlockState = {
		active = false,
	}

	BlockStates[subject] = created
	return created
end

local function is_stunned(subject: Instance): boolean
	return now() < (StunnedUntil[subject] or 0)
end

local function stun(subject: Instance, seconds: number)
	local stun_until: number = now() + seconds
	if stun_until > (StunnedUntil[subject] or 0) then
		StunnedUntil[subject] = stun_until
	end
end

local function is_parrying(subject: Instance): boolean
	local parry_state: ParryState = get_parry_state(subject)
	return now() < parry_state.active_until
end

local function try_start_parry(subject: Instance): boolean
	local parry_state: ParryState = get_parry_state(subject)
	local current_time: number = now()

	if current_time < parry_state.recover_until then
		return false
	end

	parry_state.active_until = current_time + ParryWindow
	parry_state.recover_until = current_time + ParryWindow + ParryRecover

	return true
end

local function clear_parry(subject: Instance)
	local parry_state: ParryState = get_parry_state(subject)
	parry_state.active_until = 0
end

local function is_blocking(subject: Instance): boolean
	return get_block_state(subject).active
end

local function set_block(subject: Instance, enabled: boolean)
	get_block_state(subject).active = enabled
end

-- Runs the active hitbox window for one attack.
-- The server checks the attacking limb for a short duration, ignores the attacker,
-- prevents one swing from hitting the same Humanoid multiple times, and resolves
-- parry/block before applying damage. This keeps damage server-authoritative.
local function overlap_hit(
	attacker_subject: Instance,
	attacker_char: Model,
	attacker_hrp: BasePart,
	limb_part: BasePart,
	duration: number,
	damage: number,
	kb_profile: KnockbackProfile,
	attack_name: string
)
	local overlap_params: OverlapParams = OverlapParams.new()
	overlap_params.FilterType = Enum.RaycastFilterType.Exclude
	overlap_params.FilterDescendantsInstances = { attacker_char }

	local ray_params: RaycastParams = RaycastParams.new()
	ray_params.FilterType = Enum.RaycastFilterType.Exclude
	ray_params.FilterDescendantsInstances = { attacker_char }
	ray_params.IgnoreWater = true

	local end_time: number = now() + duration
	local box_size: Vector3 = HitboxSize + HitboxPadding
	local seen_humanoids: { [Humanoid]: boolean } = {}

	local function try_hit_from_part(hit_part: BasePart)
		local model: Model? = hit_part:FindFirstAncestorOfClass("Model")
		if not model or model == attacker_char then
			return
		end

		local humanoid: Humanoid? = model:FindFirstChildOfClass("Humanoid")
		local hrp: BasePart? = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not hrp or not alive(humanoid) then
			return
		end

		if seen_humanoids[humanoid] then
			return
		end

		seen_humanoids[humanoid] = true

		local defender_subject: Instance = get_subject_from_model(model)

		-- Defensive checks happen before damage.
		-- A successful parry stuns the attacker, while a valid block cancels the hit
		-- only if the defender is facing the attacker.
		if is_parrying(defender_subject) then
			clear_parry(defender_subject)
			stun(attacker_subject, ParryStun)
			HitFeedback:FireAllClients("Parry", hrp)
			return
		end

		if facing_ok(hrp, attacker_hrp) and is_blocking(defender_subject) then
			HitFeedback:FireAllClients("Block", hrp)
			return
		end

		humanoid:TakeDamage(damage)
		apply_knockback(attacker_hrp, hrp, kb_profile)

		local reaction_name: string = reaction_name_from_attack(attack_name)
		local reaction_anim: Animation? = get_anim(HitFolder, reaction_name)
		play_anim(humanoid, reaction_name, reaction_anim, Enum.AnimationPriority.Action4)

		stun(defender_subject, StunTime)
		HitFeedback:FireAllClients("Hit", hrp)
	end

	local function check_overlap_at(cframe: CFrame)
		local parts: { BasePart } = workspace:GetPartBoundsInBox(cframe, box_size, overlap_params)

		for _, part: BasePart in ipairs(parts) do
			try_hit_from_part(part)
		end
	end

	local prev_cframe: CFrame = limb_part.CFrame
	check_overlap_at(prev_cframe)

	while now() < end_time do
		RunService.Heartbeat:Wait()

		if not limb_part.Parent then
			break
		end

		local current_cframe: CFrame = limb_part.CFrame

		if UseBlockcastSweep then
			-- Blockcast sweeps from the previous limb position to the current one.
			-- This catches fast punches or kicks that could skip over a target between
			-- Heartbeat frames if only overlap boxes were used.
			local delta: Vector3 = current_cframe.Position - prev_cframe.Position
			if delta.Magnitude > 0.001 then
				local result: RaycastResult? = workspace:Blockcast(prev_cframe, HitboxSize, delta, ray_params)
				if result and result.Instance and result.Instance:IsA("BasePart") then
					try_hit_from_part(result.Instance :: BasePart)
				end
			end
		end

		check_overlap_at(current_cframe)
		prev_cframe = current_cframe
	end
end

-- Starts a complete attack from a player or NPC.
-- The function validates cooldown/stun/parry state, advances the combo counter,
-- chooses the limb, animation, damage, and knockback profile, then opens the
-- timed hitbox window in a separate task.
local function do_attack(attacker_subject: Instance, attacker_char: Model)
	if now() < (Cooldowns[attacker_subject] or 0) then
		return
	end

	if is_stunned(attacker_subject) then
		return
	end

	if is_parrying(attacker_subject) then
		return
	end

	local humanoid: Humanoid?
	local hrp: BasePart?
	local left_arm: BasePart?
	local right_arm: BasePart?
	local right_leg: BasePart?

	humanoid, hrp, left_arm, right_arm, right_leg = get_rig_parts(attacker_char)
	if not humanoid or not hrp or not left_arm or not right_arm or not right_leg then
		return
	end

	Cooldowns[attacker_subject] = now() + AttackCooldown

	if now() - (LastAttackTime[attacker_subject] or 0) > 1 then
		Combo[attacker_subject] = 0
	end

	LastAttackTime[attacker_subject] = now()

	local combo_count: number = (Combo[attacker_subject] or 0) + 1
	if combo_count > 3 then
		combo_count = 1
	end

	Combo[attacker_subject] = combo_count

	local attack_name: string
	local limb: BasePart
	local hit_damage: number
	local knockback: KnockbackProfile
	local attack_anim: Animation?

	if combo_count == 1 then
		attack_name = "PunchRight"
		limb = right_arm
		hit_damage = ArmDamage
		knockback = {
			minPower = 220,
			maxPower = 380,
			upMin = 0,
			upMax = 0,
			maxImpulse = 800,
			spikeChance = 10,
			spikeMult = 1.35,
		}
		attack_anim = get_anim(MeleeFolder, "PunchRight")
	elseif combo_count == 2 then
		attack_name = "PunchLeft"
		limb = left_arm
		hit_damage = ArmDamage
		knockback = {
			minPower = 220,
			maxPower = 380,
			upMin = 0,
			upMax = 0,
			maxImpulse = 800,
			spikeChance = 10,
			spikeMult = 1.35,
		}
		attack_anim = get_anim(MeleeFolder, "PunchLeft")
	else
		attack_name = "Kick"
		limb = right_leg
		hit_damage = LegDamage
		knockback = {
			minPower = 320,
			maxPower = 520,
			upMin = 0,
			upMax = 0,
			maxImpulse = 950,
			spikeChance = 12,
			spikeMult = 1.35,
		}
		attack_anim = get_anim(MeleeFolder, "Kick")
	end

	play_anim(humanoid, attack_name, attack_anim, Enum.AnimationPriority.Action2)
	CombatEvent:FireAllClients("Debug", attacker_char, attack_name, HitboxSize, SwingTime)

	task.spawn(function()
		overlap_hit(attacker_subject, attacker_char, hrp, limb, SwingTime, hit_damage, knockback, attack_name)
	end)
end

-- Parry is intentionally short and has recovery.
-- This makes it timing-based instead of a permanent defensive state, and clearing
-- block on parry prevents stacking both defenses at the same time.
local function do_parry(subject: Instance, character: Model)
	if is_stunned(subject) then
		clear_parry(subject)
		return
	end

	if not try_start_parry(subject) then
		return
	end

	set_block(subject, false)

	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not alive(humanoid) then
		return
	end

	local parry_anim: Animation? = get_anim(MeleeFolder, "Parry")
	play_anim(humanoid, "Parry", parry_anim, Enum.AnimationPriority.Action4)
end

-- Block is a held defensive state, but it is disabled while stunned.
-- Starting a block also clears parry so only one defensive mode is active.
local function do_block(subject: Instance, enabled: boolean)
	if is_stunned(subject) then
		set_block(subject, false)
		return
	end

	if enabled then
		clear_parry(subject)
	end

	set_block(subject, enabled)
end

-- Removes all temporary combat state when a player leaves or an NPC is removed.
-- Without this cleanup, old Player/Model keys could stay in memory after the
-- character is gone.
local function clear_subject(subject: Instance)
	Cooldowns[subject] = nil
	StunnedUntil[subject] = nil
	Combo[subject] = nil
	LastAttackTime[subject] = nil
	ParryStates[subject] = nil
	BlockStates[subject] = nil
	NpcDecisionCooldowns[subject] = nil
end

-- Handling

-- Clients never send damage numbers or target information.
-- They only request Attack, Parry, or Block, and the server validates the
-- character state before running the actual combat logic.
CombatEvent.OnServerEvent:Connect(function(player: Player, action: string, value: any?)
	if action == "Attack" then
		local character: Model? = player.Character
		if not character then
			return
		end

		do_attack(player, character)
		return
	end

	if action == "Parry" then
		local character: Model? = player.Character
		if not character then
			return
		end

		do_parry(player, character)
		return
	end

	if action == "Block" then
		do_block(player, value == true)
	end
end)

CollectionService:GetInstanceRemovedSignal(NpcTag):Connect(function(instance: Instance)
	clear_subject(instance)
end)

-- NPCs use the same combat functions as players.
-- Tagged NPCs search for the nearest alive player, move into range, and then
-- make a simple decision to attack, block, or parry. Reusing the same functions
-- keeps player combat and NPC combat under the same rules.
task.spawn(function()
	while true do
		task.wait(AiTick)

		local npcs: { Instance } = CollectionService:GetTagged(NpcTag)
		if #npcs == 0 then
			continue
		end

		local players: { Player } = Players:GetPlayers()

		for _, instance: Instance in ipairs(npcs) do
			if not instance:IsA("Model") then
				continue
			end

			local npc: Model = instance :: Model
			local npc_humanoid: Humanoid? = npc:FindFirstChildOfClass("Humanoid")
			local npc_hrp: BasePart? = npc:FindFirstChild("HumanoidRootPart") :: BasePart?

			if not npc_humanoid or not npc_hrp or not alive(npc_humanoid) then
				continue
			end

			if is_stunned(npc) then
				clear_parry(npc)
				set_block(npc, false)
				continue
			end

			-- The NPC picks the closest alive player inside aggro range.
			-- This is cheap enough for a small showcase and avoids pathfinding work
			-- when no valid target is nearby.
			local best_character: Model? = nil
			local best_hrp: BasePart? = nil
			local best_distance: number = AiAggroRange

			for _, player: Player in ipairs(players) do
				local character: Model? = player.Character
				if not character then
					continue
				end

				local player_hrp: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local player_humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")

				if not player_hrp or not player_humanoid or not alive(player_humanoid) then
					continue
				end

				local distance: number = (player_hrp.Position - npc_hrp.Position).Magnitude
				if distance < best_distance then
					best_distance = distance
					best_character = character
					best_hrp = player_hrp
				end
			end

			if not best_character or not best_hrp then
				clear_parry(npc)
				set_block(npc, false)
				continue
			end

			local to_target: Vector3 = best_hrp.Position - npc_hrp.Position
			local distance: number = to_target.Magnitude
			local target_subject: Instance = get_subject_from_model(best_character)

			if is_parrying(target_subject) then
				clear_parry(npc)
				set_block(npc, false)
				continue
			end

			if distance > 2 then
				npc_humanoid:MoveTo(best_hrp.Position)
			end

			if distance > AiAttackRange then
				clear_parry(npc)
				set_block(npc, false)
				continue
			end

			if to_target.Magnitude <= 0.001 then
				continue
			end

			local dot: number = npc_hrp.CFrame.LookVector:Dot(to_target.Unit)
			if dot < AiAttackDotMin then
				continue
			end

			local current_time: number = now()
			if current_time < (NpcDecisionCooldowns[npc] or 0) then
				continue
			end

			NpcDecisionCooldowns[npc] = current_time + AiDecisionCooldown

			local roll: number = math.random()

			-- NPC defense is probabilistic so it does not feel identical every tick.
			-- The decision cooldown prevents the AI from rapidly switching states.
			if roll < AiParryChance then
				do_parry(npc, npc)
			elseif roll < AiParryChance + AiBlockChance then
				set_block(npc, true)

				task.delay(0.25, function()
					if npc.Parent then
						set_block(npc, false)
					end
				end)
			else
				clear_parry(npc)
				set_block(npc, false)
				do_attack(npc, npc)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	clear_subject(player)
end)
