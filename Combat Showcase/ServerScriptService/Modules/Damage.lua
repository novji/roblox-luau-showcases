local Damage = {}

function Damage.Apply(attackerPlayer, targetHumanoid, amount)
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return false
	end
	targetHumanoid:TakeDamage(amount)
	return true
end

return Damage
