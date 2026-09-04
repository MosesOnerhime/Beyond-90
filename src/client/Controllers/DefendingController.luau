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
local BallControlMath = require(Shared.Football.BallControlMath)
local TackleEvaluator = require(Shared.Football.TackleEvaluator)

local InputController = require(script.Parent:WaitForChild("InputController"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))

--[[
	Client half of defending.

	THREE DEFENSIVE VERBS, NOT ONE.

	The supplied eFootball capture shows the model this is built on, and its
	defensive control set is explicit about it: MATCH UP, DASH & PRESSURE and
	TACKLE are three separate things a defender does, and the game gives them
	three separate controls. They are separate because they are separate football
	decisions with different risks -- containing is safe and wins nothing,
	dashing wins the ball back sooner and is beaten by a turn, tackling ends the
	situation one way or the other.

	Beyond 90 maps all three onto the one defensive input, by duration and by
	whether sprint is also held:

	    TAP                    -> TACKLE. An immediate challenge at a moment of
	                              the player's exact choosing.
	    HOLD                   -> PRESS. Run the carrier down and challenge when
	                              a legal challenge becomes available.
	    HOLD + SPRINT          -> DASH & PRESSURE. The same, with the standoff
	                              pulled in and the speed cap lifted.

	THE HOLD CHALLENGES, AND WHY THAT IS NOT THE GAME DECIDING.

	An earlier revision removed the automatic challenge, on the grounds that it
	decided when to commit -- a football question AGENTS.md reserves to the
	player -- and that it made pressing a lunge. Both objections were fair
	against the version that existed. Neither survives the current one, and the
	rule they appealed to has since been written down properly: see the "A Held
	Input Is Itself A Decision" subsection of AGENTS.md section 2.

	On WHO DECIDES: holding this input is not a request to stand near the
	carrier, it is a request to take the ball off him, repeated for as long as
	the player holds it. Letting go stops it immediately. The player is deciding
	continuously and this is executing -- which is the side of the line
	assistance belongs on. The tap remains for players who want the moment
	themselves.

	On LUNGING: answered by geometry rather than by argument. The challenge is
	gated on the ball-duel angle (TackleEvaluator.BallDuelLikeliness, a close
	port of GameplayFootball's own test), so a challenge whose path runs through
	the carrier's body is never requested at all.

	The assistance is bounded (§42): it approaches, positions and faces. It never
	teleports, never exceeds normal speed, never ignores acceleration or stamina,
	never wins the ball by fiat, and yields to manual movement input. It asks;
	the server re-runs the full evaluation and is free to refuse. The human
	chooses whom to press, from which side, and whether to commit at all.
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
-- DASH & PRESSURE: containment with sprint also held. See DefendingConfig.Press.
local pressDashing = false
local lastTackleRequestAt = 0
-- Double-tap detection for the slide. See DefendingConfig.Slide.
local lastTapAt = 0
local pressTargetPosition: Vector3? = nil
-- When the held press last asked for a challenge, so it asks once and waits.
local lastAutoChallengeAt = 0
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
local function resolvePressTarget(rootPart: BasePart, carrierRoot: BasePart, dashRequested: boolean): Vector3
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

	--[[
		MATCH UP.

		Once the defender is close enough to actually be pressing, the target
		stops being "get to the carrier" and becomes "hold a position in front of
		them". Square and goal-side, at jockeying distance, leading their
		sideways movement slightly so a change of direction does not beat the
		containment outright.

		The angled approach offset is dropped here on purpose. Approaching at an
		angle is how you arrive without being run past; STANDING at an angle
		leaves an open side, and a contained carrier will take it.
	]]
	local contain = config.Contain
	local gap = fromCarrier.Magnitude
	if contain.Enabled == true and gap <= contain.ContainRange then
		local dash = config.Dash
		local standoff = if dashRequested and dash.Enabled == true
			then dash.StandoffDistance
			else contain.StandoffDistance
		standoff = math.max(standoff, contain.MinimumBodyGap)

		local carrierLateralVelocity = BallControlMath.GetHorizontal(carrierRoot.AssemblyLinearVelocity)
		-- Only the component ACROSS the goal line is worth leading; leading their
		-- forward run just means standing where they already are not.
		local lateralSpeed = carrierLateralVelocity:Dot(lateralAxis)
		local lead = math.clamp(
			lateralSpeed * contain.LateralLeadSeconds,
			-contain.MaximumLateralLead,
			contain.MaximumLateralLead
		)
		return carrierPosition + goalDirection * standoff + lateralAxis * lead
	end

	return carrierPosition
		+ goalDirection * config.GoalSideStandoff
		+ lateralAxis * (side * config.ApproachLateralOffset)
end

local function requestTackle()
	if not requestRemote then
		return
	end
	lastTackleRequestAt = os.clock()
	pressUntil = os.clock() + DefendingConfig.Press.Duration
	--[[
		A tap is a challenge too, so it also starts the held press's interval.
		Without this, tapping and then holding would let the hold fire again on
		the very next frame.
	]]
	lastAutoChallengeAt = os.clock()
	requestRemote:FireServer({ ActionType = DefendingConfig.Tackle.ActionType })
end

--[[
	The slide.

	Nothing is predicted locally. A slide commits the body and can concede a free
	kick, so the server owns both the launch and the outcome -- guessing at either
	and being corrected would be worse than the small latency of asking.
]]
local function requestSlideTackle()
	if not requestRemote then
		return
	end
	lastTackleRequestAt = os.clock()
	requestRemote:FireServer({ ActionType = DefendingConfig.Slide.ActionType })
end

--[[
	Is this footballer committed to a slide right now?

	The server writes the window; the client only reads it. That ordering matters:
	a client that decided its own slide had ended could act during the recovery
	the server is still enforcing.
]]
local function isSliding(): boolean
	local character = localPlayer.Character
	if not character then
		return false
	end
	local until_ = character:GetAttribute(DefendingConfig.Slide.SlidingAttribute)
	return typeof(until_) == "number" and os.clock() < until_
end

local function stopPress()
	pressHeld = false
	pressTargetPosition = nil
	pressCarrierId = nil
	pressDashing = false
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
	--[[
		A committed slide overrides everything. Steering out of a slide is
		precisely what makes it a free challenge instead of a risk, so the
		assistance stands down entirely for its duration.
	]]
	if isSliding() then
		pressTargetPosition = nil
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

	--[[
		DASH & PRESSURE is the same containment with sprint also held.

		Read from the ordinary sprint input rather than given a binding of its
		own: "press harder" is not a new verb, it is pressing while running, and
		the player already knows which control means run.
	]]
	local inputState = InputController.GetInputState()
	pressDashing = inputState ~= nil and inputState.SprintRequested == true

	if carrierRoot then
		pressTargetPosition = resolvePressTarget(rootPart, carrierRoot, pressDashing)
	else
		pressTargetPosition = ball.Position
	end

	-- Face the contest, so a challenge is legal the instant the player asks for
	-- one, and so containment is squared up to the carrier rather than side-on.
	local toBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
	if toBall.Magnitude > 0.5 then
		MovementController.FaceActionDirection(toBall, 0.12)
	end

	--[[
		AND WHEN IT ARRIVES, IT CHALLENGES.

		The automatic challenge used to live here, was removed as "unlike football
		and on the wrong side of the assistance line", and is now back by explicit
		design decision. Both positions are worth recording, because the second
		is not a reversal of the first so much as a different reading of who
		decided what.

		The objection was that an auto-tackle decides WHEN TO COMMIT, which
		AGENTS.md section 2 reserves to the player. The answer is that holding this
		input IS the commitment -- the player is not asking to stand near the
		carrier, they are asking to take the ball off him, exactly as eFootball's
		Dash & Pressure does. The tap remains available for a challenge at a
		moment of the player's precise choosing. What the hold delegates is
		execution, which is the side of the line assistance belongs on.

		The other half of the old objection -- that it "made pressing a lunge" --
		is answered by the duel-angle gate below rather than by argument. A
		challenge whose path runs through the carrier's body is refused, so this
		cannot become a defender throwing himself through the back of an opponent
		on a timer. That test is a close port of GameplayFootball's own
		(TackleEvaluator.BallDuelLikeliness); the reference gates its automatic
		challenge on precisely the same thing.
	]]
	if not (requestRemote and carrierRoot) then
		return
	end

	--[[
		Two gates, and the server is the third.

		RANGE, from the standing tackle's own reach, so the challenge is only
		asked for once it could actually connect. And the ANGLE, so a challenge
		whose path runs through the carrier is never requested at all.

		Nothing here decides the outcome. This asks; DefendingService.AttemptTackle
		re-runs the full evaluation authoritatively and is free to refuse, exactly
		as it does for a tapped challenge. The client is predicting the moment, not
		awarding the ball.
	]]
	--[[
		ASK ONCE PER CHALLENGE, NOT ONCE PER FRAME.

		This ran every frame the press was held and the range gate was satisfied,
		which fired a tackle request ~60 times a second. The server refused all
		but the first -- the logs are walls of `rejected=already-committed` and
		`rejected=recovering` -- so the press appeared to do nothing while
		saturating the remote with requests that could never succeed.

		Three things stop that, cheapest first: a committed challenge already
		running, a local cooldown covering the server's own recovery, and only
		then the football gates below. The behaviour the player asked for is
		unchanged -- hold the input and it challenges when it can -- it just asks
		once and waits for the answer.
	]]
	local character = rootPart.Parent
	local committedUntil = character
		and character:GetAttribute(DefendingConfig.ContactWindow.CommittedAttribute)
	if typeof(committedUntil) == "number" and os.clock() < committedUntil then
		return
	end
	local now = os.clock()
	if now - lastAutoChallengeAt < DefendingConfig.Press.AutoChallengeIntervalSeconds then
		return
	end

	local ballOffset = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
	if ballOffset.Magnitude > DefendingConfig.Tackle.MaximumBallDistance then
		return
	end

	local duel = TackleEvaluator.BallDuelLikeliness(
		rootPart.Position,
		BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity),
		carrierRoot.Position,
		BallControlMath.GetHorizontal(carrierRoot.AssemblyLinearVelocity),
		ball.Position,
		BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	)
	if duel < DefendingConfig.AI.MinimumDuelLikeliness then
		return
	end

	lastAutoChallengeAt = now
	requestRemote:FireServer({ ActionType = DefendingConfig.Tackle.ActionType })
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

	-- A footballer already on the floor cannot start another challenge.
	if isSliding() then
		return
	end

	local now = os.clock()
	pressHeld = true
	pressHeldSince = now

	local rootPart = getLocalRoot()
	if ball and rootPart then
		local toBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
		if toBall.Magnitude > 0.5 then
			MovementController.FaceActionDirection(toBall, DefendingConfig.Press.Duration * 0.4)
		end
	end

	--[[
		DOUBLE-TAP SLIDES; A SINGLE TAP TACKLES.

		The second tap inside the window replaces the challenge the first one
		asked for. It is not additive -- the server's cooldown would have refused
		a standing tackle immediately followed by a slide anyway, and a player
		double-tapping means the slide, not both.

		A slide is deliberately harder to ask for than a tackle. It concedes free
		kicks and puts the defender on the floor, and neither should ever happen
		because a finger slipped.
	]]
	local slide = DefendingConfig.Slide
	if slide.Enabled == true and now - lastTapAt <= slide.DoubleTapWindow then
		lastTapAt = 0
		stopPress()
		requestSlideTackle()
		return
	end
	lastTapAt = now

	--[[
		A TAP still challenges immediately. Holding is the containment; tapping
		must stay a direct "tackle now", so an experienced player is never made
		slower by the assistance being there.
	]]
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
	--[[
		The carrier's position travels with the press state so the movement
		assist can refuse to drive the defender into their body. Nil when the
		ball is loose, which is the one case where there is nothing to avoid.
	]]
	local carrierRoot = resolveCarrier(ball)
	-- Gap to the man, which is what jockeying range and sprinting both key off.
	local carrierGap = if carrierRoot and rootPart
		then BallControlMath.GetHorizontal(carrierRoot.Position - rootPart.Position).Magnitude
		else distance
	return {
		TargetPosition = pressTargetPosition,
		BallPosition = ball.Position,
		CarrierPosition = if carrierRoot then carrierRoot.Position else nil,
		CarrierId = pressCarrierId,
		HeldSeconds = os.clock() - pressHeldSince,
		-- How far there is left to close, so MovementController can decide
		-- whether this is still a sprint or already a jockey (§37).
		Distance = distance,
		--[[
			Sprint while there is still ground to cover, or while the player is
			explicitly asking for DASH & PRESSURE. Containment itself never
			sprints -- a defender at top speed cannot turn, which is the whole
			thing jockeying exists to preserve.
		]]
		ShouldSprint = pressDashing or carrierGap > DefendingConfig.Press.Contain.ContainRange,
		Dashing = pressDashing,
		--[[
			Which of the two containment speed caps applies. DASH & PRESSURE is
			allowed full commitment; MATCH UP is deliberately held below it so the
			defender stays balanced and able to change direction.
		]]
		--[[
			MEASURED TO THE CARRIER, NOT TO THE TARGET.

			This used to test the distance to the press TARGET, which sits
			goal-side of the carrier rather than on him. A defender still a long
			way from the opponent could therefore be close to that point, get
			flagged as jockeying, and be capped at the containment speed with
			sprinting forbidden -- for the whole chase.

			That is the second half of "the player is still not fast enough", and
			the reason the run to get in front never happened at pace. Jockeying
			range is a distance to the MAN, so that is what it now measures.
		]]
		Containing = carrierGap <= DefendingConfig.Press.Contain.ContainRange,
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
