local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local BallConfig = require(script.Parent.Parent.Config.BallConfig)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local GroundProbe = {}

local function addUnique(list: { Instance }, seen: { [Instance]: boolean }, instance: Instance?)
	if instance and instance.Parent and not seen[instance] then
		seen[instance] = true
		table.insert(list, instance)
	end
end

local function hasHumanoidAncestor(instance: Instance): boolean
	local ancestor = instance.Parent
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function isTransient(instance: Instance): boolean
	if instance:GetAttribute("Beyond90DebugOnly") == true then
		return true
	end

	local ancestor: Instance? = instance
	while ancestor and ancestor ~= Workspace do
		if ancestor.Name == "Beyond90LocalPlayerIndicator"
			or ancestor.Name == "Beyond90LocalPassTargetLine"
			or ancestor.Name == "Beyond90PassTargetPointMarker"
		then
			return true
		end
		ancestor = ancestor.Parent
	end

	return false
end

function GroundProbe.BuildExclusions(extra: { Instance }?): { Instance }
	local exclusions = {}
	local seen = {}

	for _, player in Players:GetPlayers() do
		addUnique(exclusions, seen, player.Character)
	end

	local gameRoot = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = gameRoot and gameRoot:FindFirstChild("Ball")
	addUnique(exclusions, seen, ballFolder and ballFolder:FindFirstChild(BallConfig.Name))
	local stadium = Workspace:FindFirstChild("StadiumDevelopment")
	addUnique(exclusions, seen, stadium and stadium:FindFirstChild("GoalBounds"))
	for _, child in Workspace:GetChildren() do
		if child:GetAttribute("Beyond90IgnoreGroundProbe") == true
			or child.Name == "Beyond90LocalPlayerIndicator"
			or child.Name == "Beyond90LocalPassTargetLine"
			or string.find(string.lower(child.Name), "reference", 1, true)
		then
			addUnique(exclusions, seen, child)
		end
	end

	if extra then
		for _, instance in extra do
			addUnique(exclusions, seen, instance)
		end
	end

	return exclusions
end

function GroundProbe.IsValidSurface(instance: Instance?): boolean
	return instance ~= nil
		and instance:IsA("BasePart")
		and instance.CanCollide
		and not hasHumanoidAncestor(instance)
		and not isTransient(instance)
end

function GroundProbe.Raycast(origin: Vector3, distance: number, extraExclusions: { Instance }?): RaycastResult?
	local exclusions = GroundProbe.BuildExclusions(extraExclusions)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true

	for _ = 1, 6 do
		params.FilterDescendantsInstances = exclusions
		local result = Workspace:Raycast(origin, Vector3.yAxis * -math.abs(distance), params)
		if not result or GroundProbe.IsValidSurface(result.Instance) then
			return result
		end
		table.insert(exclusions, result.Instance)
	end

	return nil
end

return GroundProbe
