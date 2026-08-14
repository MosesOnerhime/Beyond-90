local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PassPlanner = require(Shared.Football.PassPlanner)
local BallControlService = require(script.Parent.BallControlService)

local FootballActionService = {}

local initialized = false
local requestRemote: RemoteEvent? = nil
local feedbackRemote: RemoteEvent? = nil
local lastActionAtByPlayer: { [Player]: { [string]: number } } = {}

local function log(message: string)
	print(string.format("%s[FootballAction] %s", GameConfig.LogPrefix, message))
end

local function warnLog(message: string)
	warn(string.format("%s[FootballAction] %s", GameConfig.LogPrefix, message))
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)

	if existing then
		assert(existing:IsA("Folder"), string.format("%s exists but is not a Folder", existing:GetFullName()))
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)

	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s exists but is not a RemoteEvent", existing:GetFullName()))
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getFootball(): BasePart?
	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = rootFolder and rootFolder:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)

	if ball and ball:IsA("BasePart") then
		return ball
	end

	return nil
end

local function getPlayerRoot(player: Player): BasePart?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function getAimDirection(player: Player, payload): Vector3
	local rootPart = getPlayerRoot(player)
	local fallback = if rootPart
		then BallControlMath.SafeUnit(BallControlMath.GetHorizontal(rootPart.CFrame.LookVector), Vector3.new(0, 0, -1))
		else Vector3.new(0, 0, -1)
	local requested = payload and payload.AimDirection

	if typeof(requested) ~= "Vector3" then
		return fallback
	end

	local horizontal = BallControlMath.GetHorizontal(requested)

	if horizontal.Magnitude <= 0.05 then
		return fallback
	end

	return horizontal.Unit
end

local function getPartFromTarget(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	end

	if target:IsA("Model") then
		local primaryPart = target.PrimaryPart

		if primaryPart then
			return primaryPart
		end

		local rootPart = target:FindFirstChild("HumanoidRootPart")

		if rootPart and rootPart:IsA("BasePart") then
			return rootPart
		end

		local descendant = target:FindFirstChildWhichIsA("BasePart", true)

		if descendant then
			return descendant
		end
	end

	return nil
end

local function isSameTeamOrDevelopment(passer: Player, candidatePlayer: Player): boolean
	if passer == candidatePlayer then
		return false
	end

	if passer.Team and candidatePlayer.Team then
		return passer.Team == candidatePlayer.Team
	end

	return true
end

local function collectCandidates(passer: Player)
	local candidates = {}

	for _, player in Players:GetPlayers() do
		if isSameTeamOrDevelopment(passer, player) then
			local rootPart = getPlayerRoot(player)

			if rootPart then
				table.insert(candidates, {
					Kind = "Player",
					Name = player.Name,
					Instance = player,
					Position = rootPart.Position,
					Velocity = rootPart.AssemblyLinearVelocity,
					FacingDirection = BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
				})
			end
		end
	end

	for _, tagged in CollectionService:GetTagged(FootballActionConfig.DevelopmentPassTargetTag) do
		local part = getPartFromTarget(tagged)

		if part then
			table.insert(candidates, {
				Kind = "DevelopmentTarget",
				Name = tagged.Name,
				Instance = tagged,
				Position = part.Position,
				Velocity = part.AssemblyLinearVelocity,
				FacingDirection = BallControlMath.GetHorizontal(part.CFrame.LookVector),
			})
		end
	end

	return candidates
end

local function isCooldownReady(player: Player, actionType: string, cooldown: number): boolean
	local now = os.clock()
	local playerTimes = lastActionAtByPlayer[player]

	if not playerTimes then
		playerTimes = {}
		lastActionAtByPlayer[player] = playerTimes
	end

	local lastActionAt = playerTimes[actionType]

	if lastActionAt and now - lastActionAt < cooldown then
		return false
	end

	playerTimes[actionType] = now
	return true
end

local function sendFeedback(player: Player, accepted: boolean, reason: string?, plan)
	local remote = feedbackRemote

	if not remote then
		return
	end

	remote:FireClient(player, {
		Accepted = accepted,
		Reason = reason or "",
		ActionType = plan and plan.ActionType or "",
		TargetPosition = plan and plan.TargetPosition or nil,
		TargetName = plan and plan.SelectedCandidate and plan.SelectedCandidate.Name or "",
		LaunchSpeed = plan and plan.LaunchSpeed or 0,
		Distance = plan and plan.Distance or 0,
		PredictedArrivalTime = plan and plan.PredictedArrivalTime or 0,
		PredictedArrivalSpeed = plan and plan.PredictedArrivalSpeed or 0,
		Intensity = plan and plan.Intensity or 1,
		RelativeForwardSpeed = plan and plan.RelativeForwardSpeed or 0,
		VerticalLaunchSpeed = plan and plan.VerticalLaunchSpeed or 0,
		Score = plan and plan.Score or 0,
	})
end

local function getHoldIntensity(actionConfig, holdDuration: number): number
	local minIntensity = actionConfig.MinIntensity or 1
	local maxIntensity = actionConfig.MaxIntensity or minIntensity
	local holdMaxTime = math.max(actionConfig.HoldMaxTime or 0.75, 0.05)
	local alpha = math.clamp(holdDuration / holdMaxTime, 0, 1)
	local intensity = minIntensity + (maxIntensity - minIntensity) * alpha
	local globalIntensity = FootballActionConfig.DevelopmentIntensity

	return math.clamp(intensity, globalIntensity.Min, globalIntensity.Max)
end

local function getSelectedReceiverUserId(plan): number
	if not plan or not plan.SelectedCandidate or plan.SelectedCandidate.Kind ~= "Player" then
		return 0
	end

	local instance = plan.SelectedCandidate.Instance

	if typeof(instance) == "Instance" and instance:IsA("Player") then
		return instance.UserId
	end

	return 0
end

local function handlePass(player: Player, actionType: string, payload)
	local ball = getFootball()
	local rootPart = getPlayerRoot(player)

	if not ball or not rootPart then
		sendFeedback(player, false, "missing ball or character", nil)
		return
	end

	if not BallControlService.IsControlledBy(player, ball) then
		sendFeedback(player, false, "player does not control ball", nil)
		return
	end

	local actionConfig = if actionType == "ThroughPass" then FootballActionConfig.ThroughPass else FootballActionConfig.Pass

	if not isCooldownReady(player, actionType, actionConfig.Cooldown) then
		sendFeedback(player, false, "cooldown", nil)
		return
	end

	local ballDistance = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude

	if ballDistance > BallConfig.Control.HardControlDistance then
		sendFeedback(player, false, "ball too far", nil)
		return
	end

	local holdDuration = if payload and typeof(payload.HoldDuration) == "number" then payload.HoldDuration else 0
	local aimDirection = getAimDirection(player, payload)
	local intensity = getHoldIntensity(actionConfig, holdDuration)
	local plan, reason = PassPlanner.Plan(
		ball.Position,
		aimDirection,
		holdDuration,
		actionType,
		collectCandidates(player),
		FootballActionConfig,
		intensity
	)

	if not plan then
		sendFeedback(player, false, reason or "could not plan pass", nil)
		return
	end

	local released = BallControlService.ReleaseForFootballAction(
		ball,
		player,
		actionType,
		plan.LaunchVelocity,
		plan.ReleaseReacquireSuppression,
		plan.ReleaseReacquireExitDistance,
		{
			IntendedReceiverUserId = getSelectedReceiverUserId(plan),
			IntendedReceiverName = plan.SelectedCandidate and plan.SelectedCandidate.Name or "",
			TargetPosition = plan.TargetPosition,
			TargetKind = plan.SelectedCandidate and plan.SelectedCandidate.Kind or "Space",
		}
	)

	if not released then
		sendFeedback(player, false, "release rejected", plan)
		return
	end

	log(string.format(
		"%s by %s target=%s intensity=%.2fx distance=%.1f launchSpeed=%.1f predictedArrivalSpeed=%.1f eta=%.2f score=%.2f",
		actionType,
		player.Name,
		plan.SelectedCandidate and plan.SelectedCandidate.Name or "space",
		plan.Intensity,
		plan.Distance,
		plan.LaunchSpeed,
		plan.PredictedArrivalSpeed,
		plan.PredictedArrivalTime,
		plan.Score
	))
	sendFeedback(player, true, "", plan)
end

local function handleKnockOn(player: Player, payload)
	local ball = getFootball()
	local rootPart = getPlayerRoot(player)

	if not ball or not rootPart then
		sendFeedback(player, false, "missing ball or character", nil)
		return
	end

	if not BallControlService.IsControlledBy(player, ball) then
		sendFeedback(player, false, "player does not control ball", nil)
		return
	end

	local actionConfig = FootballActionConfig.KnockOn

	if not isCooldownReady(player, "KnockOn", actionConfig.Cooldown) then
		sendFeedback(player, false, "cooldown", nil)
		return
	end

	local ballDistance = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude

	if ballDistance > actionConfig.ControlDistance then
		sendFeedback(player, false, "ball too far", nil)
		return
	end

	local holdDuration = if payload and typeof(payload.HoldDuration) == "number" then payload.HoldDuration else 0
	local requestedAimDirection = getAimDirection(player, payload)
	local intensity = getHoldIntensity(actionConfig, holdDuration)
	local playerHorizontalVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local aimDirection = requestedAimDirection

	if playerHorizontalVelocity.Magnitude >= actionConfig.MovingAimSpeedThreshold then
		aimDirection = playerHorizontalVelocity.Unit
	end

	local playerForwardSpeed = math.max(0, playerHorizontalVelocity:Dot(aimDirection))
	local playerForwardVelocity = aimDirection * playerForwardSpeed
	local playerLateralVelocity = playerHorizontalVelocity - playerForwardVelocity
	local desiredRelativeSpeed = (actionConfig.PeakSeparation / math.max(actionConfig.CatchUpTime, 0.1)) * intensity
	local relativeForwardSpeed = math.clamp(
		desiredRelativeSpeed,
		actionConfig.MinRelativeForwardSpeed,
		actionConfig.MaxRelativeForwardSpeed
	)
	local launchVelocity = playerForwardVelocity * actionConfig.PlayerForwardCarry
		+ playerLateralVelocity * actionConfig.PlayerLateralCarry
		+ aimDirection * relativeForwardSpeed
		+ Vector3.yAxis * actionConfig.VerticalVelocity
	local plan = {
		ActionType = "KnockOn",
		TargetPosition = ball.Position + aimDirection * actionConfig.PeakSeparation,
		LaunchVelocity = launchVelocity,
		LaunchSpeed = BallControlMath.GetHorizontal(launchVelocity).Magnitude,
		RelativeForwardSpeed = relativeForwardSpeed,
		PlayerForwardSpeed = playerForwardSpeed,
		VerticalLaunchSpeed = actionConfig.VerticalVelocity,
		Distance = actionConfig.PeakSeparation,
		PredictedArrivalTime = actionConfig.CatchUpTime,
		Intensity = intensity,
		Score = 0,
	}

	local released = BallControlService.ReleaseForFootballAction(
		ball,
		player,
		"KnockOn",
		launchVelocity,
		actionConfig.ReleaseReacquireSuppression,
		actionConfig.ReacquireExitDistance,
		{
			IntendedReceiverUserId = 0,
			IntendedReceiverName = "",
			TargetPosition = plan.TargetPosition,
			TargetKind = "Space",
			PredictedCatchTime = actionConfig.CatchUpTime,
			PeakSeparation = actionConfig.PeakSeparation,
		}
	)

	if not released then
		sendFeedback(player, false, "release rejected", plan)
		return
	end

	log(string.format(
		"KnockOn by %s intensity=%.2fx playerSpeed=%.1f relativeForwardSpeed=%.1f finalWorldSpeed=%.1f verticalSpeed=%.1f peakSeparation=%.1f predictedChaseTime=%.2f",
		player.Name,
		plan.Intensity,
		playerHorizontalVelocity.Magnitude,
		plan.RelativeForwardSpeed,
		plan.LaunchSpeed,
		plan.VerticalLaunchSpeed,
		plan.Distance,
		plan.PredictedArrivalTime
	))
	sendFeedback(player, true, "", plan)
end

local function onActionRequested(player: Player, payload)
	if typeof(payload) ~= "table" then
		warnLog(string.format("Rejected malformed action payload from %s", player.Name))
		return
	end

	local actionType = payload.ActionType

	if actionType == "GroundPass" then
		handlePass(player, actionType, payload)
	elseif actionType == "ThroughPass" then
		handlePass(player, actionType, payload)
	elseif actionType == "KnockOn" then
		handleKnockOn(player, payload)
	else
		warnLog(string.format("Rejected unknown action '%s' from %s", tostring(actionType), player.Name))
	end
end

function FootballActionService.Initialize()
	if initialized then
		return
	end

	initialized = true
	local remotes = getOrCreateFolder(ReplicatedStorage, FootballActionConfig.RemotesFolderName)
	requestRemote = getOrCreateRemoteEvent(remotes, FootballActionConfig.RequestRemoteName)
	feedbackRemote = getOrCreateRemoteEvent(remotes, FootballActionConfig.FeedbackRemoteName)
	requestRemote.OnServerEvent:Connect(onActionRequested)

	Players.PlayerRemoving:Connect(function(player)
		lastActionAtByPlayer[player] = nil
	end)
end

return FootballActionService
