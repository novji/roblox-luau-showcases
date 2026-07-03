local Cooldown = {}

local cds = {} -- [player] = { [key] = time }

function Cooldown.Ready(player, key)
	local p = cds[player]
	if not p then return true end
	local t = p[key]
	return (not t) or (os.clock() >= t)
end

function Cooldown.Set(player, key, seconds)
	local p = cds[player]
	if not p then
		p = {}
		cds[player] = p
	end
	p[key] = os.clock() + seconds
end

function Cooldown.Clear(player)
	cds[player] = nil
end

return Cooldown
