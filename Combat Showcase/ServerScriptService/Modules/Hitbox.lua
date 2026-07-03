local Hitbox = {}

local function isAlive(humanoid)
	return humanoid and humanoid.Health > 0
end

function Hitbox.Box(params)
	-- params:
	-- OriginCFrame (CFrame), Size (Vector3), Ignore (Instance), MaxHits (number)
	local origin = params.OriginCFrame
	local size = params.Size
	local ignore = params.Ignore
	local maxHits = params.MaxHits or 1

	local hits = {}
	local hitCount = 0

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { ignore }

	local parts = workspace:GetPartBoundsInBox(origin, size, overlap)

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if isAlive(hum) and model ~= ignore then
				if not hits[model] then
					hits[model] = hum
					hitCount += 1
					if hitCount >= maxHits then
						break
					end
				end
			end
		end
	end

	return hits -- [Model] = Humanoid
end

return Hitbox
