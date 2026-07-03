local State = {}

export type Entry = {
	stunned_until: number,
	is_blocking: boolean,
	block_stamina: number,
	parry_until: number,
}

local states: { [Instance]: Entry } = {}

local function now(): number
	return os.clock()
end

local function get_key(subject: any): Instance?
	if typeof(subject) == "Instance" then
		return subject
	end

	return nil
end

function State.Get(subject: Instance): Entry
	local s = states[subject]
	if not s then
		s = {
			stunned_until = 0,
			is_blocking = false,
			block_stamina = 100,
			parry_until = 0,
		}
		states[subject] = s
	end
	return s
end

function State.IsStunned(subject: Instance): boolean
	local s = State.Get(subject)
	return now() < s.stunned_until
end

function State.Stun(subject: Instance, seconds: number)
	local s = State.Get(subject)
	local t = now() + seconds
	if t > s.stunned_until then
		s.stunned_until = t
	end
end

function State.SetBlocking(subject: Instance, enabled: boolean, stamina_max: number)
	local s = State.Get(subject)
	s.is_blocking = enabled
	if enabled and s.block_stamina <= 0 then
		s.block_stamina = stamina_max
	end
end

function State.IsBlocking(subject: Instance): boolean
	local s = State.Get(subject)
	return s.is_blocking
end

function State.GetBlockStamina(subject: Instance): number
	local s = State.Get(subject)
	return s.block_stamina
end

function State.DrainBlock(subject: Instance, amount: number): number
	local s = State.Get(subject)
	s.block_stamina -= amount
	if s.block_stamina < 0 then
		s.block_stamina = 0
	end
	return s.block_stamina
end

function State.Parry(subject: Instance, window: number)
	local s = State.Get(subject)
	s.parry_until = now() + window
end

function State.IsParrying(subject: Instance): boolean
	local s = State.Get(subject)
	return now() < s.parry_until
end

function State.Clear(subject: Instance)
	states[subject] = nil
end

return State
