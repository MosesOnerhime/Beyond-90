local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ControlledBallController = require(script.Parent:WaitForChild("ControlledBallController"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))
local PassTargetResolver = require(script.Parent:WaitForChild("PassTargetResolver"))

local FootballActionController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local requestRemote: RemoteEvent? = nil
local feedbackRemote: RemoteEvent? = nil
local connections: { RBXScriptConnection } = {}
local presentationEvent = Instance.new("BindableEvent")
local shootActionSequence = 0
local pendingShootActionId = ""

local function log(message: string)
	print(string.format("%s[Client][FootballAction] %s", GameConfig.LogPrefix, message))
end

local function getRemotes()
	local remotes = ReplicatedStorage:WaitForChild(FootballActionConfig.RemotesFolderName, 10)

	if not remotes then
		return nil, nil
	end

	local request = remotes:WaitForChild(FootballActionConfig.RequestRemoteName, 10)
	local feedback = remotes:WaitForChild(FootballActionConfig.FeedbackRemoteName, 10)

	if not request or not request:IsA("RemoteEvent") or not feedback or not feedback:IsA("RemoteEvent") then
		return nil, nil
	end

	return request, feedback
end

local function getFacingDirection(): Vector3
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return BallControlMath.SafeUnit(BallControlMath.GetHorizontal(rootPart.CFrame.LookVector), Vector3.new(0, 0, -1))
	end

	return Vector3.new(0, 0, -1)
end

local function getAimDirection(action)
	if action and typeof(action.AimDirection) == "Vector3" then
		local horizontal = BallControlMath.GetHorizontal(action.AimDirection)

		if horizontal.Magnitude > 0.05 then
			return horizontal.Unit
		end
	end

	return getFacingDirection()
end

local function createTargetMarker(position: Vector3, targetName: string?)
	if not FootballActionConfig.DebugEnabled or not FootballActionConfig.Debug.ShowPassTargetMarker then
		return
	end

	local marker = Instance.new("Part")
	marker.Name = "Beyond90PassTargetPointMarker"
	marker:SetAttribute("Beyond90DebugOnly", true)
	marker:SetAttribute("MarkerMeaning", FootballActionConfig.Debug.PassTargetMarkerMeaning)
	marker.Shape = Enum.PartType.Ball
	marker.Size = Vector3.new(
		FootballActionConfig.Debug.TargetMarkerSize,
		FootballActionConfig.Debug.TargetMarkerSize,
		FootballActionConfig.Debug.TargetMarkerSize
	)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(89, 214, 255)
	marker.Transparency = 0.15
	marker.CFrame = CFrame.new(position)
	marker.Parent = Workspace

	if targetName and targetName ~= "" then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "TargetLabel"
		billboard.Size = UDim2.fromOffset(150, 32)
		billboard.StudsOffset = Vector3.new(0, FootballActionConfig.Debug.ReceiverMarkerHeight, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = marker

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamSemibold
		label.Text = targetName
		label.TextColor3 = Color3.fromRGB(235, 250, 255)
		label.TextStrokeTransparency = 0.35
		label.TextScaled = true
		label.Parent = billboard
	end

	Debris:AddItem(marker, FootballActionConfig.Debug.MarkerDuration)
end

local function onFootballAction(action)
	local remote = requestRemote

	if not remote or localPlayer:GetAttribute("Beyond90MenuOpen") == true then
		return
	end

	local actionType = action.ActionType

	if (actionType == "GroundPass" or actionType == "ThroughPass" or actionType == "LobPass" or actionType == "KnockOn" or actionType == "Shoot")
		and action.Phase ~= "Released"
	then
		return
	end

	if actionType == "Shoot" then
		shootActionSequence += 1
		pendingShootActionId = string.format("%d:%d:%d", localPlayer.UserId, shootActionSequence, math.floor(os.clock() * 1000))
		MovementController.BeginActionMovement("Shoot")
		ControlledBallController.NotifyLocalFootballActionRelease(FootballActionConfig.Shoot.ContactFallbackTime + 0.15)
		presentationEvent:Fire({
			Stage = "Predicted",
			ActionType = "Shoot",
			ClientActionId = pendingShootActionId,
			Timestamp = action.Timestamp or os.clock(),
		})
		remote:FireServer({
			ActionType = "Shoot",
			Phase = "Prepare",
			ClientActionId = pendingShootActionId,
			HoldDuration = action.HoldDuration or 0,
			AimDirection = getAimDirection(action),
			MoveMagnitude = action.MoveMagnitude or 0,
			Timestamp = action.Timestamp or os.clock(),
		})
		return
	end

	if actionType == "GroundPass" or actionType == "ThroughPass" or actionType == "LobPass" then
		local plan = PassTargetResolver.ConsumeSelection(actionType)

		if not plan or not plan.SelectedCandidate or not plan.SelectedCandidate.UserId then
			log("[PassTarget] result=none reason=no-valid-receiver")
			return
		end
		local aimDirection = plan.AimDirection or getAimDirection(action)

		MovementController.BeginActionMovement("Pass")
		presentationEvent:Fire({
			Stage = "Predicted",
			ActionType = actionType,
			Timestamp = action.Timestamp or os.clock(),
			IntendedReceiverUserId = plan.SelectedCandidate.UserId,
		})
		log(string.format(
			"[PassTarget] receiver=%s distance=%.1f angle=%.1f score=%.2f targetPosition=%s",
			plan.SelectedCandidate.Name,
			plan.Distance,
			plan.AngleDegrees or 0,
			plan.Score,
			tostring(plan.TargetPosition)
		))

		local remoteAtRelease = remote
		task.delay(FootballActionConfig.Targeting.ServerReleaseDelay, function()
			if requestRemote ~= remoteAtRelease then
				MovementController.CancelActionMovement("Pass")
				return
			end

			ControlledBallController.NotifyLocalFootballActionRelease(0.22)
			remoteAtRelease:FireServer({
				ActionType = actionType,
				HoldDuration = action.HoldDuration or 0,
				AimDirection = aimDirection,
				MoveMagnitude = action.MoveMagnitude or 0,
				Timestamp = action.Timestamp or os.clock(),
				IntendedReceiverUserId = plan.SelectedCandidate.UserId,
				SelectedTargetPosition = plan.TargetPosition,
			})
		end)
		return
	end

	ControlledBallController.NotifyLocalFootballActionRelease(0.22)
	remote:FireServer({
		ActionType = actionType,
		HoldDuration = action.HoldDuration or 0,
		AimDirection = getAimDirection(action),
		MoveMagnitude = action.MoveMagnitude or 0,
		Timestamp = action.Timestamp or os.clock(),
	})
end

local function onFeedback(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if not payload.Accepted then
		if payload.ActionType == "GroundPass" or payload.ActionType == "ThroughPass" or payload.ActionType == "LobPass" then
			MovementController.CancelActionMovement("Pass")
		elseif payload.ActionType == "Shoot" then
			MovementController.CancelActionMovement("Shoot")
			pendingShootActionId = ""
		end
		presentationEvent:Fire({
			Stage = "Rejected",
			ActionType = payload.ActionType,
			Reason = payload.Reason,
		})

		if FootballActionConfig.DebugEnabled then
			log(string.format("%s rejected: %s", tostring(payload.ActionType), tostring(payload.Reason)))
		end

		return
	end

	if payload.Stage ~= "Prepared" then
		presentationEvent:Fire({
			Stage = "Accepted",
			ActionType = payload.ActionType,
		})
	end
	if payload.ActionType == "Shoot" and payload.Stage == "Released" then
		pendingShootActionId = ""
	end

	if typeof(payload.TargetPosition) == "Vector3" then
		createTargetMarker(payload.TargetPosition, payload.TargetName)
	end

	if FootballActionConfig.DebugEnabled then
		if payload.ActionType == "KnockOn" then
			log(string.format(
				"%s accepted intensity=%.2fx peakSeparation=%.1f relativeForwardSpeed=%.1f finalWorldSpeed=%.1f verticalSpeed=%.1f eta=%.2f",
				tostring(payload.ActionType),
				tonumber(payload.Intensity) or 1,
				tonumber(payload.Distance) or 0,
				tonumber(payload.RelativeForwardSpeed) or 0,
				tonumber(payload.LaunchSpeed) or 0,
				tonumber(payload.VerticalLaunchSpeed) or 0,
				tonumber(payload.PredictedArrivalTime) or 0
			))
			return
		end
		if payload.ActionType == "Shoot" then
			log(string.format(
				"Shoot %s goal=%s distance=%.1f launchSpeed=%.1f verticalSpeed=%.1f eta=%.2f",
				tostring(payload.Stage),
				tostring(payload.GoalId),
				tonumber(payload.Distance) or 0,
				tonumber(payload.LaunchSpeed) or 0,
				tonumber(payload.VerticalLaunchSpeed) or 0,
				tonumber(payload.PredictedArrivalTime) or 0
			))
			return
		end

		log(string.format(
			"%s accepted target=%s intensity=%.2fx distance=%.1f launchSpeed=%.1f verticalSpeed=%.1f predictedArrivalSpeed=%.1f eta=%.2f trajectory=%s",
			tostring(payload.ActionType),
			tostring(payload.TargetName),
			tonumber(payload.Intensity) or 1,
			tonumber(payload.Distance) or 0,
			tonumber(payload.LaunchSpeed) or 0,
			tonumber(payload.VerticalLaunchSpeed) or 0,
			tonumber(payload.PredictedArrivalSpeed) or 0,
			tonumber(payload.PredictedArrivalTime) or 0,
			tostring(payload.Trajectory)
		))
	end
end

function FootballActionController.Initialize()
	if initialized then
		return
	end

	initialized = true
	requestRemote, feedbackRemote = getRemotes()

	if not requestRemote or not feedbackRemote then
		warn(string.format("%s[Client][FootballAction] Remotes unavailable; football actions disabled", GameConfig.LogPrefix))
		return
	end

	table.insert(connections, InputController.GetFootballActionEvent().Event:Connect(onFootballAction))
	table.insert(connections, feedbackRemote.OnClientEvent:Connect(onFeedback))
end

function FootballActionController.GetPresentationEvent(): BindableEvent
	return presentationEvent
end

function FootballActionController.NotifyAnimationMarker(actionType: string, markerName: string)
	if actionType ~= "Shoot" or markerName ~= "BallContact" or pendingShootActionId == "" or not requestRemote then
		return
	end
	requestRemote:FireServer({
		ActionType = "Shoot",
		Phase = "Commit",
		ClientActionId = pendingShootActionId,
	})
end

function FootballActionController.Destroy()
	if not initialized then
		return
	end

	initialized = false

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	requestRemote = nil
	feedbackRemote = nil
	pendingShootActionId = ""
end

return FootballActionController
