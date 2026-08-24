local Workspace = game:GetService("Workspace")

local BallControlMath = require(script.Parent.BallControlMath)
local GoalConfig = require(script.Parent.Parent.Config.GoalConfig)

local GoalGeometry = {}

local function findPath(path: { string }): Instance?
	local current: Instance = Workspace
	for _, name in path do
		current = current:FindFirstChild(name)
		if not current then
			return nil
		end
	end
	return current
end

local function extentAlong(part: BasePart, axis: Vector3): number
	return math.abs(part.CFrame.RightVector:Dot(axis)) * part.Size.X / 2
		+ math.abs(part.CFrame.UpVector:Dot(axis)) * part.Size.Y / 2
		+ math.abs(part.CFrame.LookVector:Dot(axis)) * part.Size.Z / 2
end

local function getWidthAxis(bounds: BasePart, inward: Vector3, fallback: Vector3): Vector3
	local candidates = {
		BallControlMath.GetHorizontal(bounds.CFrame.RightVector),
		BallControlMath.GetHorizontal(bounds.CFrame.LookVector),
	}
	local best = fallback
	local bestScore = math.huge
	for _, candidate in candidates do
		if candidate.Magnitude > 0.05 then
			local unit = candidate.Unit
			local score = math.abs(unit:Dot(inward))
			if score < bestScore then
				best = unit
				bestScore = score
			end
		end
	end
	return BallControlMath.SafeUnit(best, fallback)
end

local function resolveGoal(goalId: string, definition, container: Instance, pitchState)
	local bounds = container:FindFirstChild(definition.BoundsName)
	local line = container:FindFirstChild(definition.LineName)
	if not bounds or not bounds:IsA("BasePart") then
		return nil, string.format("%s missing BasePart %s", goalId, definition.BoundsName)
	end
	if not line or not line:IsA("BasePart") then
		return nil, string.format("%s missing BasePart %s", goalId, definition.LineName)
	end

	local inward = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(pitchState.Center - line.Position),
		pitchState.LengthAxis
	)
	local widthAxis = getWidthAxis(bounds, inward, pitchState.WidthAxis)
	local halfWidth = extentAlong(bounds, widthAxis)
	local halfHeight = extentAlong(bounds, Vector3.yAxis)
	local halfDepth = extentAlong(bounds, inward)
	local mouthCenter = Vector3.new(line.Position.X, bounds.Position.Y, line.Position.Z)

	return {
		Id = goalId,
		Bounds = bounds,
		Line = line,
		LinePoint = line.Position,
		MouthCenter = mouthCenter,
		WidthAxis = widthAxis,
		InwardDirection = inward,
		OutwardDirection = -inward,
		Width = halfWidth * 2,
		Height = halfHeight * 2,
		Depth = halfDepth * 2,
		BottomY = bounds.Position.Y - halfHeight,
		TopY = bounds.Position.Y + halfHeight,
	}, nil
end

function GoalGeometry.ResolveAll(pitchState)
	local container = findPath(GoalConfig.WorkspaceGoalBoundsPath)
	if not container then
		return {}, string.format("Missing Workspace.%s", table.concat(GoalConfig.WorkspaceGoalBoundsPath, "."))
	end

	local goals = {}
	local errors = {}
	for goalId, definition in GoalConfig.Definitions do
		local goal, reason = resolveGoal(goalId, definition, container, pitchState)
		if goal then
			goals[goalId] = goal
		else
			table.insert(errors, reason)
		end
	end
	return goals, if #errors > 0 then table.concat(errors, "; ") else nil
end

return GoalGeometry
