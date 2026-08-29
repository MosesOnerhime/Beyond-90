local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local DefendingConfig = require(Shared.Config.DefendingConfig)
local GoalkeeperConfig = require(Shared.Config.GoalkeeperConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PositionConfig = require(Shared.Config.PositionConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local TackleEvaluator = require(Shared.Football.TackleEvaluator)

local InputController = require(script.Parent:WaitForChild("InputController"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))

--[[
	Client half of defending.

	HOLD-V PRESS (§41). V is held rather than tapped. While it is down the
	footballer keeps closing on the ball carrier and challenges by itself the
	moment the geometry becomes legal, so the player does not have to guess the
	exact frame to press. Releasing V stops the assistance immediately.

	The assistance is deliberately bounded (§42): it approaches, faces and times
	the challenge. It never teleports, never exceeds normal speed, never ignores
	acceleration or stamina, never wins the ball by fiat, and yields to manual
	movement input. The human still chooses WHOM to press and from which side.

	Prediction runs the same TackleEvaluator the server runs, on replicated
	positions -- so the assist waits for a genuinely legal angle instead of
	firing challenges that will be rejected. The server remains authoritative;
	this is local prediction, not local authority.
]]
local DefendingController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local connections: { RBXScriptConnection } = {}
local requestRemote: RemoteEvent? = nil
local feedbackRemote: RemoteEvent? = nil
local pressUntil = 0

local pressHeld = false
local pressHeldSince = 0
local lastTackleRequestAt = 0
local pressTargetPosition: Vector3? = nil
local pressCarrierId: number? = nil

local function log(message: string)
	if DefendingConfig.DebugEnabled then
		print(string.format("%s[Client][Defending] %s", GameConfig.LogPrefix, message))
	end
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

local function getLocalRoot(): BasePart?
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	return if rootPart and rootPart:IsA("BasePart") then rootPart :: BasePart else nil
end

--[[
	Who currently has the ball, if it is an opponent worth pressing.

	Bounded search: footballers publish their id on the character, so this walks
	the footballer folder and the player list rather than the whole Workspace
	(§102).
]]
local function resolveCarrier(ball: BasePart?): (BasePart?, number?)
	if not ball or ball:GetAttribute("State") ~= "Controlled" then
		return nil, nil
	end
	if ball:GetAttribute("GoalkeeperHeld") == true then
		return nil, nil
	end
	local carrierId = ball:GetAttribute("ControllerFootballerId")
	if typeof(carrierId) ~= "number" or carrierId == 0 or carrierId == localPlayer.UserId then
		return nil, nil
	end

	local localTeam = FootballTeamConfig.Normalize(localPlayer:GetAttribute(FootballTeamConfig.AttributeName))

	local function match(model: Instance): BasePart?
		if model:GetAttribute("Beyond90FootballerId") ~= carrierId then
			return nil
		end
		local rootPart = model:FindFirstChild("HumanoidRootPart")
		if not rootPart or not rootPart:IsA("BasePart") then
			return nil
		end
		local team = FootballTeamConfig.Normalize(model:GetAttribute(FootballTeamConfig.AttributeName))
		-- A team-mate in possession is never pressed.
		if localTeam and team and team == localTeam then
			return nil
		end
		return rootPart :: BasePart
	end

	local root = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local folder = root and root:FindFirstChild("Footballers")
	if folder then
		for _, model in folder:GetChildren() do
			local found = match(model)
			if found then
				return found, carrierId
			end
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local found = match(character)
			if found then
				return found, carrierId
			end
		end
	end
	return nil, nil
end

--[[
	Where to run while pressing.

	The same football reasoning the AI uses (§38): get GOAL-SIDE of the carrier
	rather than chasing their back, and approach from a slight angle so the two
	footballers do not try to occupy the same space.
]]
local function resolvePressTarget(rootPart: BasePart, carrierRoot: BasePart): Vector3
	local carrierPosition = carrierRoot.Position
	local defendedGoalId = localPlayer:GetAttribute(FootballTeamConfig.DefendedGoalAttributeName)
	local goalPosition: Vector3? = nil

	local root = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local goals = root and root:FindFirstChild("Goals")
	if goals and typeof(defendedGoalId) == "string" then
		local goal = goals:FindFirstChild(defendedGoalId)
		if goal then
			local marker = goal:FindFirstChild("MouthCenter")
			if marker and marker:IsA("BasePart") then
				goalPosition = marker.Position
			elseif goal:IsA("Model") and goal.PrimaryPart then
				goalPosition = goal.PrimaryPart.Position
			end
		end
	end

	if not goalPosition then
		-- Without a goal reference, close on the carrier directly. Still bounded.
		return carrierPosition
	end

	local toGoal = BallControlMath.GetHorizontal(goalPosition - carrierPosition)
	if toGoal.Magnitude <= 1e-3 then
		return carrierPosition
	end

	local goalDirection = toGoal.Unit
	local config = DefendingConfig.Press
	local fromCarrier = BallControlMath.GetHorizontal(rootPart.Position - carrierPosition)
	local lateralAxis = Vector3.new(-goalDirection.Z, 0, goalDirection.X)
	local side = if fromCarrier:Dot(lateralAxis) >= 0 then 1 else -1

	--[[
		AM I BEHIND THEM? (§38)

		The carrier's own heading is what decides this, not the goal. A defender
		trailing a carrier who is running at goal must not aim at a point in
		front of the GOAL -- that point is on the far side of the carrier, so the
		route to it goes straight through their back, which is the behaviour the
		runtime evidence showed.

		Behind, the target becomes a recovery line: down the carrier's path,
		offset to whichever side the defender is already on, so the approach
		curves around and arrives facing them.
	]]
	local carrierHeading = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(carrierRoot.AssemblyLinearVelocity),
		BallControlMath.SafeUnit(BallControlMath.GetHorizontal(carrierRoot.CFrame.LookVector), goalDirection)
	)
	local approach = BallControlMath.SafeUnit(-fromCarrier, carrierHeading)
	local behindDot = carrierHeading:Dot(approach)

	if behindDot >= config.BehindRecoveryDot then
		local gap = fromCarrier.Magnitude
		local lead = math.clamp(
			gap * config.RecoveryLeadScale,
			config.MinimumRecoveryLead,
			config.MaximumRecoveryLead
		)
		local recoveryLateral = Vector3.new(-carrierHeading.Z, 0, carrierHeading.X)
		local recoverySide = if fromCarrier:Dot(recoveryLateral) >= 0 then 1 else -1
		return carrierPosition
			+ carrierHeading * lead
			+ recoveryLateral * (recoverySide * config.RecoveryLateralOffset)
	end

	return carrierPosition
		+ goalDirection * config.GoalSideStandoff
		+ lateralAxis * (side * config.ApproachLateralOffset)
end

--[[
	Is the challenge on right now?

	Runs the SAME evaluator the server runs. Predicting with the real rule rather
	than a rough distance test is what stops the assist tackling through a back
	and burning the cooldown on attempts that cannot succeed.
]]
local function shouldChallenge(rootPart: BasePart, carrierRoot: BasePart, ball: BasePart): boolean
	if os.clock() - lastTackleRequestAt < DefendingConfig.Tackle.Cooldown then
		return false
	end
	--[[
		The evaluator reads FacingDirection, not Facing. Passing the wrong key made
		challenger.FacingDirection nil, which GetHorizontal then indexed -- the
		BallControlMath:6 error that fired every frame V was held. The server call
		in DefendingService uses FacingDirection, so this now matches it exactly and
		the local prediction sees the same geometry the server will.
	]]
	local result = TackleEvaluator.Evaluate(
		{
			Position = rootPart.Position,
			Velocity = rootPart.AssemblyLinearVelocity,
			FacingDirection = rootPart.CFrame.LookVector,
			TackleSkill = PositionConfig.GetSkill(
				localPlayer:GetAttribute(PositionConfig.SlotAttributeName),
				"Tackling"
			),
		},
		{
			Position = carrierRoot.Position,
			Velocity = carrierRoot.AssemblyLinearVelocity,
			FacingDirection = carrierRoot.CFrame.LookVector,
		},
		ball.Position,
		DefendingConfig.Tackle
	)
	if not result or not result.Valid then
		return false
	end
	return result.Score >= DefendingConfig.Press.AutoTackleScore
end

local function requestTackle()
	if not requestRemote then
		return
	end
	lastTackleRequestAt = os.clock()
	pressUntil = os.clock() + DefendingConfig.Press.Duration
	requestRemote:FireServer({ ActionType = DefendingConfig.Tackle.ActionType })
end

local function stopPress()
	pressHeld = false
	pressTargetPosition = nil
	pressCarrierId = nil
end

--[[
	One press tick, while V is held.

	Nothing here moves the player: it resolves a target and MovementController
	steers toward it under the ordinary locomotion model, so acceleration,
	turning, injury and stamina all still apply.
]]
local function updatePress()
	if not pressHeld then
		return
	end
	local ball = getFootball()
	if not ball or hasLocalPossession(ball) then
		-- Winning the ball ends the press, which is the natural exit.
		stopPress()
		return
	end
	local rootPart = getLocalRoot()
	if not rootPart then
		return
	end

	--[[
		GO TO THE BALL.

		Holding V means "get me to the football and win it". There are two shapes
		of that, and previously only the first existed -- so holding V while the
		ball was loose, or while an opponent was still collecting it, did nothing
		at all and the press looked broken.

		  an opponent is carrying it   -> close on a GOAL-SIDE point, so the
		                                  challenge arrives in front of them
		  anything else                -> run at the football itself

		The second case covers loose balls, deflections, tackles that spilled and
		the moment before an opponent settles it -- which is most of the time the
		player actually wants to be pressing.
	]]
	local carrierRoot, carrierId = resolveCarrier(ball)
	pressCarrierId = carrierId

	local anchor = if carrierRoot then carrierRoot.Position else ball.Position
	local distance = BallControlMath.GetHorizontal(anchor - rootPart.Position).Magnitude
	if distance > DefendingConfig.Press.MaximumDistance then
		-- Beyond this the run is a positional decision, not a press, and that
		-- decision stays the player's (§42). They can still run there manually.
		pressTargetPosition = nil
		return
	end

	if carrierRoot then
		pressTargetPosition = resolvePressTarget(rootPart, carrierRoot)
	else
		pressTargetPosition = ball.Position
	end

	-- Face the contest, so the challenge is legal when it comes.
	local toBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
	if toBall.Magnitude > 0.5 then
		MovementController.FaceActionDirection(toBall, 0.12)
	end

	if carrierRoot and shouldChallenge(rootPart, carrierRoot, ball) then
		requestTackle()
	end
end

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
	if action.ActionType ~= DefendingConfig.Tackle.ActionType then
		return
	end
	if isLocalGoalkeeper() then
		stopPress()
		return
	end
	if localPlayer:GetAttribute("Beyond90MenuOpen") == true then
		stopPress()
		return
	end

	if action.Phase == "Released" then
		-- Releasing V stops the assistance immediately (§41).
		stopPress()
		return
	end
	if action.Phase ~= "Pressed" then
		return
	end

	local ball = getFootball()
	-- In possession this input does nothing; the contextual mobile slot maps to
	-- the attacking action instead.
	if hasLocalPossession(ball) then
		return
	end
	if not requestRemote then
		return
	end

	pressHeld = true
	pressHeldSince = os.clock()

	--[[
		A TAP still challenges immediately. Holding is the assisted press; tapping
		must stay a direct "tackle now", so an experienced player is never made
		slower by the assistance being there.
	]]
	local rootPart = getLocalRoot()
	if ball and rootPart then
		local toBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
		if toBall.Magnitude > 0.5 then
			MovementController.FaceActionDirection(toBall, DefendingConfig.Press.Duration * 0.4)
		end
	end
	requestTackle()
end

local function onFeedback(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Accepted then
		log(string.format("tackle outcome=%s score=%.2f", tostring(payload.Outcome), tonumber(payload.Score) or 0))
	else
		log(string.format("tackle rejected=%s", tostring(payload.Reason)))
	end
end

--[[
	Consumed by MovementController.

	Returns the point to press toward and the config that bounds how strongly the
	assistance may act. Nil whenever the press is not running, which is what makes
	releasing V an immediate stop rather than a fade.
]]
function DefendingController.GetPressState()
	if not pressHeld or not pressTargetPosition then
		return nil
	end
	local ball = getFootball()
	if not ball or hasLocalPossession(ball) then
		return nil
	end
	local rootPart = getLocalRoot()
	local distance = if rootPart
		then BallControlMath.GetHorizontal(pressTargetPosition - rootPart.Position).Magnitude
		else 0
	return {
		TargetPosition = pressTargetPosition,
		BallPosition = ball.Position,
		CarrierId = pressCarrierId,
		HeldSeconds = os.clock() - pressHeldSince,
		-- How far there is left to close, so MovementController can decide
		-- whether this is still a sprint or already a jockey (§37).
		Distance = distance,
		ShouldSprint = distance > DefendingConfig.Press.SprintDistance,
		Config = DefendingConfig.Press,
	}
end

-- Driven from the client step so the press runs every frame it is held.
function DefendingController.Update()
	updatePress()
end

function DefendingController.Initialize()
	if initialized then
		return
	end
	initialized = true
	pressUntil = 0
	stopPress()

	table.insert(connections, InputController.GetFootballActionEvent().Event:Connect(onFootballAction))

	--[[
		MovementController consumes the press target through a provider rather
		than requiring this module, which keeps the dependency one-way.
	]]
	MovementController.SetPressStateProvider(DefendingController.GetPressState)
	table.insert(connections, RunService.Heartbeat:Connect(updatePress))

	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild(FootballActionConfig.RemotesFolderName, 10)
		if not remotes or not initialized then
			return
		end
		requestRemote = remotes:WaitForChild(DefendingConfig.RemoteName, 10) :: RemoteEvent?
		local feedback = remotes:WaitForChild(DefendingConfig.FeedbackRemoteName, 10)
		if feedback and feedback:IsA("RemoteEvent") and initialized then
			feedbackRemote = feedback
			table.insert(connections, feedback.OnClientEvent:Connect(onFeedback))
		end
	end)
end

function DefendingController.Destroy()
	if not initialized then
		return
	end
	initialized = false
	pressUntil = 0
	stopPress()
	MovementController.SetPressStateProvider(nil)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	requestRemote = nil
	feedbackRemote = nil
end

return DefendingController
