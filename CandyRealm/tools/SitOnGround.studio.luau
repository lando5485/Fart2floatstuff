-- Paste into the Studio COMMAND BAR with the model selected. Safe to re-run.
local model = game:GetService("Selection"):Get()[1]
assert(model and model:IsA("Model"), "Select a Model first.")

if not model.PrimaryPart then                     -- biggest BasePart by volume wins
	local best, bestVol = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestVol then best, bestVol = d, v end
		end
	end
	assert(best, "That model has no BasePart descendants.")
	model.PrimaryPart = best
	print(("PrimaryPart set to '%s'"):format(best.Name))
end

-- True world-space bottom. GetBoundingBox() is oriented to the PIVOT, so on a tilted prop its
-- bottom is not the real bottom; projecting each part's half-extents onto world Y is.
local minY = math.huge
for _, d in ipairs(model:GetDescendants()) do
	if d:IsA("BasePart") then
		local cf, s = d.CFrame, d.Size
		minY = math.min(minY, cf.Position.Y - 0.5 * (math.abs(cf.RightVector.Y) * s.X
			+ math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z))
	end
end

local pivot  = model:GetPivot()
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { model }     -- else it just hits its own sunk parts
params.IgnoreWater = true

-- Start ABOVE the model, not at the pivot: a pivot buried in the ground casts from below the surface.
local hit = workspace:Raycast(Vector3.new(pivot.Position.X, minY + 500, pivot.Position.Z),
	Vector3.new(0, -2000, 0), params)
assert(hit, "No ground found under the model -- is anything actually beneath it?")

local oldY = pivot.Position.Y
model:PivotTo(pivot + Vector3.new(0, hit.Position.Y - minY, 0))
print(("%s   Y %.3f -> %.3f   (ground %.3f, moved %+.3f, hit '%s')"):format(model.Name, oldY,
	model:GetPivot().Position.Y, hit.Position.Y, model:GetPivot().Position.Y - oldY,
	hit.Instance and hit.Instance.Name or "Terrain"))
