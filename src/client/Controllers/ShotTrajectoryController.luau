local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local TrajectoryPredictor = require(Shared.Football.TrajectoryPredictor)
local FootballActionController = require(script.Parent.FootballActionController)

local ShotTrajectoryController = {}

local localPlayer = Players.LocalPlayer
local config = FootballActionConfig.ShotTrajectory
local initialized = false
local segments = {}
local actionConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local activePath = nil

local function log(message: string)
	print(string.format("%s[Client][ShotTrajectory] %s", GameConfig.LogPrefix, message))
end

local function getFootball(): BasePart?
	local root = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local folder = root and root:FindFirstChild("Ball")
	local found = folder and folder:FindFirstChild(BallConfig.Name)
	return if found and found:IsA("BasePart") then found else nil
end

local function ensureSegments()
	if #segments > 0 then
		return
	end
	for index = 1, config.SegmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Beyond90LocalShotTrajectory_" .. tostring(index)
		segment:SetAttribute("Beyond90LocalOnly", true)
		segment.Shape = Enum.PartType.Ball
		segment.Size = Vector3.new(config.SegmentDiameter, config.SegmentDiameter, config.SegmentDiameter)
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanTouch = false
		segment.CanQuery = false
		segment.CastShadow = false
		segment.Material = Enum.Material.Neon
		segment.Color = config.Colors[(index - 1) % #config.Colors + 1]
		segment.Transparency = 1
		segment.Parent = Workspace
		table.insert(segments, segment)
	end
end

local function hideSegments()
	for _, segment in segments do
		segment.Transparency = 1
	end
end

local function finishPath(reason: string)
	if activePath and activePath.Released and activePath.ActualCount > 0 and FootballActionConfig.DebugEnabled then
		log(string.format(
			"result=%s samples=%d meanError=%.2f maxError=%.2f",
			reason,
			activePath.ActualCount,
			activePath.ErrorSum / activePath.ActualCount,
			activePath.MaxError
		))
	end
	activePath = nil
	hideSegments()
end

local function showPath(payload)
	if typeof(payload.ReleasePosition) ~= "Vector3" or typeof(payload.LaunchVelocity) ~= "Vector3" then
		return
	end
	ensureSegments()
	local duration = math.clamp(tonumber(payload.PredictedArrivalTime) or 1, 0.15, config.MaximumLifetime)
	--[[
		Draw the SAME flight the server will integrate, curve included (§71). The
		curve is fixed at release, so the preview is exact rather than an
		approximation -- and it stays non-authoritative and non-homing, because it
		is only reading what the server already decided.
	]]
	local curve = if typeof(payload.CurveAcceleration) == "Vector3" then payload.CurveAcceleration else nil
	local samples = TrajectoryPredictor.Sample(
		payload.ReleasePosition,
		payload.LaunchVelocity,
		duration,
		config.SegmentCount,
		curve
	)
	for index, position in samples do
		local segment = segments[index]
		segment.Position = position
		segment.Transparency = config.PreparedTransparency
	end
	activePath = {
		ActionId = payload.ClientActionId,
		Origin = payload.ReleasePosition,
		LaunchVelocity = payload.LaunchVelocity,
		CurveAcceleration = curve,
		Duration = duration,
		Samples = samples,
		Released = payload.Stage == "Released",
		ReleasedAt = if payload.Stage == "Released" then os.clock() else 0,
		LastActualSampleAt = 0,
		ActualCount = 0,
		ErrorSum = 0,
		MaxError = 0,
	}
end

local function onPresentation(payload)
	if typeof(payload) ~= "table" or payload.ActionType ~= "Shoot" then
		return
	end
	if payload.Stage == "Prepared" and payload.Accepted ~= false then
		-- Preview only. The football has not left the foot yet, so this arc is a
		-- prediction from the requested contact and is never scored for accuracy.
		showPath(payload)
	elseif payload.Stage == "Released" and payload.Accepted ~= false then
		-- Authoritative. Re-lock the arc to the launch the server actually used,
		-- from the position the football actually left. Error is measured only
		-- against this path.
		showPath(payload)
	elseif payload.Stage == "Rejected" then
		finishPath("rejected")
	end
end

local function update()
	local path = activePath
	if not path or not path.Released then
		return
	end
	local now = os.clock()
	local elapsed = now - path.ReleasedAt
	local fadeAlpha = math.clamp((elapsed - config.FadeDelay) / config.FadeDuration, 0, 1)
	for _, segment in segments do
		segment.Transparency = config.PreparedTransparency
			+ (1 - config.PreparedTransparency) * fadeAlpha
	end
	local football = getFootball()
	if football and now - path.LastActualSampleAt >= config.DiagnosticSampleInterval then
		path.LastActualSampleAt = now
		local expected = TrajectoryPredictor.SamplePosition(
			path.Origin,
			path.LaunchVelocity,
			math.min(elapsed, path.Duration),
			path.CurveAcceleration
		)
		local errorDistance = (football.Position - expected).Magnitude
		path.ActualCount += 1
		path.ErrorSum += errorDistance
		path.MaxError = math.max(path.MaxError, errorDistance)
	end
	if elapsed >= config.MaximumLifetime then
		finishPath("timeout")
	elseif football and elapsed > 0.12
		and (football:GetAttribute("FootballFlightComplete") == true
			or football:GetAttribute("FootballGrounded") == true)
	then
		finishPath("flight-complete")
	elseif fadeAlpha >= 1 then
		finishPath("faded")
	end
end

function ShotTrajectoryController.Initialize()
	if initialized or config.Enabled ~= true then
		return
	end
	initialized = true
	actionConnection = FootballActionController.GetPresentationEvent().Event:Connect(onPresentation)
	renderConnection = RunService.RenderStepped:Connect(update)
	localPlayer:SetAttribute("Beyond90ShotTrajectoryLocalOnly", true)
end

function ShotTrajectoryController.Destroy()
	initialized = false
	if actionConnection then actionConnection:Disconnect() end
	if renderConnection then renderConnection:Disconnect() end
	actionConnection = nil
	renderConnection = nil
	activePath = nil
	for _, segment in segments do
		segment:Destroy()
	end
	table.clear(segments)
	localPlayer:SetAttribute("Beyond90ShotTrajectoryLocalOnly", nil)
end

return ShotTrajectoryController
