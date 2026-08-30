local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local RestartControl = require(Shared.Football.RestartControl)
local BallConfig = require(Shared.Config.BallConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GoalkeeperConfig = require(Shared.Config.GoalkeeperConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ControlledBallController = require(script.Parent:WaitForChild("ControlledBallController"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))
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
local lastShootPressAt = 0
local bufferedShotToken = 0
local bufferedShotActive = false

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


local function getFootball(): BasePart?
	local root = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local folder = root and root:FindFirstChild("Ball")
	local ball = folder and folder:FindFirstChild(BallConfig.Name)
	return if ball and ball:IsA("BasePart") then ball else nil
end

local function hasLocalPossession(ball: BasePart?): boolean
	return ball ~= nil
		and ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerFootballerId") == localPlayer.UserId
end

--[[
	Does the local player hold a live set piece? (§31)

	Deliberately separate from `hasLocalPossession`: this grants the right to
	PLAY the ball, never the right to carry it. Dribbling systems must keep
	asking `hasLocalPossession` and will keep getting false during a restart.
]]
local function hasRestartControl(ball: BasePart?): boolean
	return RestartControl.IsHeldBy(ball, localPlayer.UserId)
end

-- "May I play the ball right now?" -- open-play possession OR a live restart.
local function canPlayBall(ball: BasePart?): boolean
	return hasLocalPossession(ball) or hasRestartControl(ball)
end

-- Charge curve. Power only scales launch speed; placement accuracy is entirely
-- separate and still comes from Shooting Skill and body alignment.
local function getChargePower(holdDuration: number): number
	local charge = FootballActionConfig.Shoot.Charge
	if not charge or charge.Enabled ~= true then
		return charge and charge.MaximumPower or 1
	end
	local span = math.max(charge.MaximumHoldSeconds - charge.MinimumHoldSeconds, 1e-4)
	local alpha = math.clamp((holdDuration - charge.MinimumHoldSeconds) / span, 0, 1)
	alpha = alpha ^ charge.CurveExponent
	return charge.MinimumPower + (charge.MaximumPower - charge.MinimumPower) * alpha
end

-- Mirrors the server's contact window so the client does not send a request the
-- server would only reject.
local function isBallStrikeable(): boolean
	local ball = getFootball()
	--[[
		A set-piece ball is stationary on its spot, so there is no touch cycle to
		time and nothing to wait for -- it is strikeable the instant the restart
		goes live. Running the open-play contact window over it would reject the
		taker for standing the wrong distance from a ball that is not moving.
	]]
	if hasRestartControl(ball) then
		return true
	end
	if not hasLocalPossession(ball) then
		return false
	end
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	--[[
		The SAME window the server will apply, from the same function, judged the
		same way -- where the foot will meet the ball rather than where the ball
		is this instant. A local check that disagrees with the authoritative one
		either blocks a legal shot or predicts one that is about to be refused.
	]]
	local contact = FootballActionConfig.Shoot.Contact
	local playerVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local contactRadius, maximumForwardLead, maximumLateral =
		FootballActionConfig.GetShotContactWindow(playerVelocity.Magnitude)

	local relativeVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity) - playerVelocity
	local toBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
		+ relativeVelocity * contact.StrikeLookaheadSeconds
	if toBall.Magnitude > contactRadius then
		return false
	end
	local controlDirection = BallControlMath.SafeUnit(
		playerVelocity,
		BallControlMath.GetHorizontal(rootPart.CFrame.LookVector)
	)
	local forwardLead = toBall:Dot(controlDirection)
	if forwardLead > maximumForwardLead or forwardLead < -contact.MaximumBehindLead then
		return false
	end
	local lateral = (toBall - controlDirection * forwardLead).Magnitude
	return lateral <= contact.MaximumLateralOffset
end

local function cancelPendingShot(reason: string)
	pendingShootActionId = ""
	bufferedShotToken += 1
	bufferedShotActive = false
	presentationEvent:Fire({ Stage = "Rejected", ActionType = "Shoot", Reason = reason })
end

--[[
	Hold the shot intent locally until the football returns into a strikeable
	position. The player experience is: "I pressed Shoot while dribbling, so my
	footballer strikes the next valid touch" -- no pixel-perfect timing against
	the dribble cycle.
]]
local function bufferShotRequest(remote: RemoteEvent, payload, actionId: string)
	local config = FootballActionConfig.Shoot.Buffer
	bufferedShotToken += 1
	local token = bufferedShotToken
	bufferedShotActive = true
	--[[
		Ask the controlled ball to come back to a strikeable lead while the
		intent is held (§41). Without this the buffer can only wait out a full
		sprint touch; with it the next contact is pulled forward, so the shot
		normally releases in a fraction of the budget rather than at the timeout.
	]]
	ControlledBallController.BeginStrikePreparation(config.MaximumWaitSeconds)
	log("[ShotBuffer] holding shot intent until contact")

	task.spawn(function()
		local startedAt = os.clock()
		while token == bufferedShotToken do
			if pendingShootActionId ~= actionId then
				bufferedShotActive = false
				return
			end
			local ball = getFootball()
			-- Possession genuinely lost, or the ball is beyond recovery. A live
			-- restart counts as held, so a penalty taker is never treated as
			-- having lost a ball that is sitting on the spot in front of them.
			if not canPlayBall(ball) then
				local character = localPlayer.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				local distance = if ball and rootPart and rootPart:IsA("BasePart")
					then BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude
					else math.huge
				if distance > config.AbandonDistance then
					bufferedShotActive = false
					ControlledBallController.EndStrikePreparation()
					MovementController.CancelActionMovement("Shoot")
					cancelPendingShot("shot-buffer-possession-lost")
					log("[ShotBuffer] abandoned; possession lost")
					return
				end
			elseif isBallStrikeable() then
				bufferedShotActive = false
				ControlledBallController.EndStrikePreparation()
				payload.BufferedSeconds = os.clock() - startedAt
				remote:FireServer(payload)
				log(string.format("[ShotBuffer] released after %.0fms", (os.clock() - startedAt) * 1000))
				return
			end
			if os.clock() - startedAt >= config.MaximumWaitSeconds then
				-- Bounded: send anyway and let the server's contact preparation
				-- make the final call rather than silently dropping the input.
				bufferedShotActive = false
				ControlledBallController.EndStrikePreparation()
				payload.BufferedSeconds = os.clock() - startedAt
				remote:FireServer(payload)
				log("[ShotBuffer] timeout; deferring to server contact window")
				return
			end
			task.wait(config.PollInterval)
		end
		bufferedShotActive = false
		ControlledBallController.EndStrikePreparation()
	end)
end

-- The actions this controller is responsible for sending.
local OWNED_ACTIONS = {
	GroundPass = true,
	ThroughPass = true,
	LobPass = true,
	KnockOn = true,
	Shoot = true,
}

--[[
	A GOALKEEPER IS NOT AN OUTFIELDER.

	The keeper's dive and throw are rerouted from these same inputs by
	GoalkeeperController, so this controller must let them pass rather than also
	acting on them -- otherwise pressing dive would fire a tackle request at the
	same moment, and the server would be asked for two different football actions
	from one keypress.

	Read from the character attribute the server writes when it registers a
	keeper rather than from GoalkeeperController, so this file does not need to
	know that controller exists.
]]
local function isLocalGoalkeeper(): boolean
	local model = localPlayer.Character
	return model ~= nil
		and model:GetAttribute(GoalkeeperConfig.RoleAttributeName) == GoalkeeperConfig.Role
end

local function onFootballAction(action)
	local remote = requestRemote

	if not remote or localPlayer:GetAttribute("Beyond90MenuOpen") == true then
		return
	end

	local actionType = action.ActionType

	--[[
		This controller owns the ATTACKING actions only. Defensive intents such as
		Tackle travel on DefendingService's own remote, and everything else on the
		shared input event belongs to somebody else.

		This was previously a blacklist of the five attacking actions, so any
		other action fell through to the generic send at the bottom and was
		forwarded to the football-action remote -- which is why every tackle press
		also produced a server-side "Rejected unknown action 'Tackle'".
	]]
	if not OWNED_ACTIONS[actionType] then
		return
	end

	--[[
		A goalkeeper's pass key throws the ball out, and that is resolved by
		GoalkeeperService against the held football rather than by the ordinary
		passing pipeline. Letting the attacking actions through as well would
		send two competing requests for one press.
	]]
	if isLocalGoalkeeper() then
		return
	end

	if action.Phase ~= "Released" then
		return
	end

	if actionType == "Shoot" then
		local shootConfig = FootballActionConfig.Shoot
		local fakeConfig = shootConfig.FakeShot
		local now = os.clock()

		-- Double tap converts the pending shot into a fake. Handled before the
		-- request goes out, so no shot can physically release first.
		if fakeConfig and fakeConfig.Enabled == true
			and pendingShootActionId ~= ""
			and now - lastShootPressAt <= fakeConfig.DoubleTapWindow
		then
			cancelPendingShot("fake-shot")
			lastShootPressAt = 0
			presentationEvent:Fire({
				Stage = "FakeShot",
				ActionType = "Shoot",
				Timestamp = action.Timestamp or now,
			})
			MovementController.CancelActionMovement("Shoot")
			log("[FakeShot] pending shot cancelled; possession retained")
			return
		end
		lastShootPressAt = now

		shootActionSequence += 1
		local actionId = string.format("%d:%d:%d", localPlayer.UserId, shootActionSequence, math.floor(now * 1000))
		pendingShootActionId = actionId
		MovementController.BeginActionMovement("Shoot")

		local shootContact = shootConfig.Contact
		local releaseSuppression = if shootContact and shootContact.Enabled == true
			then shootContact.MaximumWaitSeconds + 0.15
			else shootConfig.ContactFallbackTime + 0.15
		ControlledBallController.NotifyLocalFootballActionRelease(releaseSuppression)
		presentationEvent:Fire({
			Stage = "Predicted",
			ActionType = "Shoot",
			ClientActionId = actionId,
			Timestamp = action.Timestamp or now,
		})

		local payload = {
			ActionType = "Shoot",
			Phase = "Prepare",
			ClientActionId = actionId,
			HoldDuration = action.HoldDuration or 0,
			ChargePower = getChargePower(action.HoldDuration or 0),
			AimDirection = getAimDirection(action),
			MoveMagnitude = action.MoveMagnitude or 0,
			Timestamp = action.Timestamp or now,
		}

		-- Sprint-shot buffering. The football is frequently out on a touch when
		-- Shoot is pressed; sending immediately is what produced the
		-- controlled-ball-out-of-range rejection before the server's contact
		-- preparation could ever run.
		local bufferConfig = shootConfig.Buffer
		if bufferConfig and bufferConfig.Enabled == true and not isBallStrikeable() then
			bufferShotRequest(remote, payload, actionId)
			return
		end
		remote:FireServer(payload)
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

	presentationEvent:Fire(payload)
	if payload.ActionType == "Shoot"
		and payload.Stage == "Prepared"
		and payload.Trajectory == "Clearance"
		and typeof(payload.TargetPosition) == "Vector3"
	then
		local character = localPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			local clearanceDirection = BallControlMath.GetHorizontal(payload.TargetPosition - rootPart.Position)
			if clearanceDirection.Magnitude > 0.05 then
				MovementController.FaceActionDirection(clearanceDirection, FootballActionConfig.Shoot.ContactFallbackTime)
			end
		end
	end
	if payload.ActionType == "Shoot" and payload.Stage == "Released" then
		pendingShootActionId = ""
		bufferedShotToken += 1
		bufferedShotActive = false
		AudioController.PlayFootballKick("Shoot")
	elseif payload.ActionType == "GroundPass" or payload.ActionType == "ThroughPass" or payload.ActionType == "LobPass" then
		AudioController.PlayFootballKick(payload.ActionType)
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
