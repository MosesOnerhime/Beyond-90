--!strict
--[[
	Set pieces.

	Places every footballer for a restart and reports when it has been taken.
	MatchRulesService owns the decision and the timing; this owns the geometry.

	Placement follows GameplayFootball's approach exactly: each footballer's own
	normalized formation anchor is remapped into a per-restart box (see
	SetPieceFormation), so a defender defends a corner and a forward attacks it,
	rather than everyone being teleported into a fixed arrangement.
	See docs/research/gameplay-football/match-rules-and-positions.md.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MatchRulesConfig = require(Shared.Config.MatchRulesConfig)
local PitchGeometry = require(Shared.Football.PitchGeometry)
local PositionConfig = require(Shared.Config.PositionConfig)
local SetPieceFormation = require(Shared.Football.SetPieceFormation)

local BallControlService = require(script.Parent.BallControlService)
local FootballerRegistryService = require(script.Parent.FootballerRegistryService)
local GoalService = require(script.Parent.GoalService)
local PitchService = require(script.Parent.PitchService)

local RestartService = {}

--[[
	Who takes a penalty. See the taker-selection block for why this is not
	simply "whoever is nearest the ball".

	The preference is a distance bonus rather than a hard filter: it is larger
	than any pitch, so a forward always outranks a non-forward, while a team with
	no forward available still produces a taker instead of none.
]]
local PENALTY_TAKER_SLOT = "FWD"
local PENALTY_TAKER_PREFERENCE = 1e6

local ball: BasePart? = nil

local active: { [string]: any }? = nil

--[[
	Publish who holds the restart, on the football itself.

	RestartControl is a real possession state, not an internal server flag
	(§31). The client reads it from the ball exactly as it reads ordinary
	control, so the moment the whistle goes the taker's action system already
	knows the ball is theirs -- no walking to it, no proximity acquisition, no
	waiting for a touch.

	It is deliberately a SEPARATE pair of attributes from `ControllerFootballerId`
	so that nothing which grants dribbling can mistake a restart for open play
	(§32).
]]
local function publishRestartControl()
	local control = MatchRulesConfig.RestartControl
	local ballPart = ball
	if not ballPart then
		return
	end
	local takerId = nil
	local awaiting = false
	if active and active.Taker then
		takerId = active.Taker.Id
		awaiting = active.AwaitingAction == true
	end
	ballPart:SetAttribute(control.ControlAttributeName, takerId)
	ballPart:SetAttribute(control.AwaitingAttributeName, awaiting)
	ballPart:SetAttribute("MatchRestartKind", if active then active.Restart else nil)
end

RestartService.PublishRestartControl = publishRestartControl

-- Cached penalty geometry discovered from the stadium; see resolvePenaltyDepth.
local penaltyDepthRatio: number? = nil
local penaltyProbeDone = false

local function log(message: string)
	if MatchRulesConfig.Debug.Enabled then
		print(string.format("%s[Restart] %s", GameConfig.LogPrefix, message))
	end
end

function RestartService.SetBall(newBall: BasePart?)
	ball = newBall
end

-- The frame whose +1 longitudinal is `teamId`'s attacking goal.
local function getTeamFrame(teamId: string): PitchGeometry.Frame?
	local pitchState = PitchService.GetState()
	if not pitchState then
		return nil
	end
	local mapping = FootballTeamConfig.GetGoalMapping(teamId)
	local goals = GoalService.GetGoals()
	local attacking = mapping and goals[mapping.AttackingGoalId]
	local defended = mapping and goals[mapping.DefendedGoalId]
	if not attacking or not defended then
		return nil
	end
	local attackDirection = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(attacking.MouthCenter - defended.MouthCenter),
		Vector3.zAxis
	)
	return PitchGeometry.CreateFrame(pitchState, attackDirection)
end

RestartService.GetTeamFrame = getTeamFrame

--[[
	The penalty spot, taken from the stadium rather than from a metre constant.

	The build may carry an explicit marker:

		Workspace.StadiumDevelopment.PenaltyPoint

	When present it is authoritative. Only ONE marker is needed: its distance in
	from the nearer goal line is measured as a ratio of the half-length, and the
	opposite spot is that same ratio mirrored -- a pitch has two symmetrical
	penalty spots, so a second marker would only be a chance to disagree with the
	first. A Model, a BasePart or an Attachment all work.

	With no marker the ratio falls back to MatchRulesConfig.Pitch, which is itself
	measured from the painted markings rather than converted from metres.
]]
local function resolvePenaltyDepth(frame: PitchGeometry.Frame): number
	local fallback = MatchRulesConfig.Pitch.PenaltySpotDepth
	if penaltyDepthRatio then
		return penaltyDepthRatio
	end
	if penaltyProbeDone then
		return fallback
	end
	penaltyProbeDone = true

	local stadium = Workspace:FindFirstChild("StadiumDevelopment")
	local marker = stadium and stadium:FindFirstChild("PenaltyPoint", true)
	if not marker then
		log(string.format(
			"No StadiumDevelopment.PenaltyPoint found; penalty spot uses the measured ratio %.4f",
			fallback
		))
		return fallback
	end

	local position: Vector3? = nil
	if marker:IsA("BasePart") then
		position = marker.Position
	elseif marker:IsA("Attachment") then
		position = marker.WorldPosition
	elseif marker:IsA("Model") then
		local ok, cframe = pcall(function()
			return (marker :: Model):GetBoundingBox()
		end)
		position = if ok then cframe.Position else nil
	end
	if not position then
		return fallback
	end

	local longitudinal = PitchGeometry.ToNormalized(frame, position)
	-- Distance in from whichever goal line the marker sits nearer to.
	local depth = 1 - math.abs(longitudinal)
	if depth <= 0.02 or depth >= 0.6 then
		warn(string.format(
			"%s[Restart] PenaltyPoint at longitudinal %.3f is not a plausible penalty spot; using %.4f",
			GameConfig.LogPrefix,
			longitudinal,
			fallback
		))
		return fallback
	end

	penaltyDepthRatio = depth
	log(string.format(
		"PenaltyPoint found at %s -> depth ratio %.4f (mirrored for both ends)",
		marker:GetFullName(),
		depth
	))
	return depth
end

--[[
	Where the ball is placed for each restart, in world space.

	`context` carries what the decision produced: the crossing point for a ball
	that went out, the foul position for a free kick, and so on.
]]
function RestartService.ResolveBallPosition(restart: string, teamId: string, context): Vector3?
	local frame = getTeamFrame(teamId)
	local pitchState = PitchService.GetState()
	if not frame or not pitchState then
		return nil
	end
	local ratios = MatchRulesConfig.Pitch
	local restarts = MatchRulesConfig.Restarts

	if restart == restarts.Kickoff then
		return PitchGeometry.FromNormalized(frame, 0, 0)
	end

	if restart == restarts.ThrowIn then
		local crossing = context and context.Crossing
		if not crossing then
			return nil
		end
		local longitudinal, lateral = PitchGeometry.ToNormalized(frame, crossing)
		-- Clamped in from both goal lines, and set exactly on the touchline.
		return PitchGeometry.FromNormalized(
			frame,
			math.clamp(longitudinal, -1 + ratios.ThrowInLongitudinalInset, 1 - ratios.ThrowInLongitudinalInset),
			if lateral > 0 then 1 - ratios.ThrowInLateralInset else -1 + ratios.ThrowInLateralInset
		)
	end

	if restart == restarts.CornerKick then
		local crossing = context and context.Crossing
		local lateral = 1
		if crossing then
			local _, crossingLateral = PitchGeometry.ToNormalized(frame, crossing)
			lateral = if crossingLateral >= 0 then 1 else -1
		end
		-- The attacking team's corner is at their attacking goal line.
		return PitchGeometry.FromNormalized(frame, 0.998, lateral * 0.998)
	end

	if restart == restarts.GoalKick then
		-- Taken from deep in the taking team's own half.
		return PitchGeometry.FromNormalized(frame, -ratios.GoalKickDepth, 0)
	end

	if restart == restarts.FreeKick then
		local spot = context and context.Position
		if not spot then
			return nil
		end
		return PitchGeometry.ClampToPitch(frame, spot, 0.02)
	end

	if restart == restarts.Penalty then
		return PitchGeometry.FromNormalized(frame, 1 - resolvePenaltyDepth(frame), 0)
	end

	return nil
end

-- Every footballer currently on the pitch, split by team.
local function collectActors(): ({ [string]: { any } }, { any })
	local byTeam: { [string]: { any } } = { Home = {}, Away = {} }
	local all = {}
	for _, actor in FootballerRegistryService.GetAll() do
		if actor.RootPart and actor.RootPart.Parent then
			local teamId = actor.TeamId
			if teamId and byTeam[teamId] then
				table.insert(byTeam[teamId], actor)
				table.insert(all, actor)
			end
		end
	end
	return byTeam, all
end

local function getAnchor(actor)
	local slotId = actor.PositionSlotId
	local position = PositionConfig.Get(slotId)
	if position then
		return position.Anchor
	end
	-- Fall back to the AI role name when no slot has been assigned yet.
	for _, candidate in PositionConfig.Positions do
		if candidate.AIRole == actor.Role then
			return candidate.Anchor
		end
	end
	return { Longitudinal = 0, Lateral = 0 }
end

local function placeActor(actor, position: Vector3, facePosition: Vector3, record: { [number]: Vector3 }?)
	if not actor.RootPart or not actor.RootPart.Parent then
		return
	end
	if record and typeof(actor.Id) == "number" then
		record[actor.Id] = position
	end

	--[[
		REPOSITION EPOCH (§64).

		A restart teleports the footballer, and the Broadcast Camera's ordinary
		smoothing is deliberately slow -- so it spent a long time drifting across
		the pitch to find the player again. Bumping this counter tells the camera
		that the jump was AUTHORITATIVE rather than a tracking error, so it can
		use a brief high-acceleration catch-up and then return to normal
		smoothing. Nothing about ordinary Broadcast smoothing changes.
	]]
	if actor.Character then
		local epoch = actor.Character:GetAttribute(MatchRulesConfig.RepositionEpochAttributeName)
		actor.Character:SetAttribute(
			MatchRulesConfig.RepositionEpochAttributeName,
			(if typeof(epoch) == "number" then epoch else 0) + 1
		)
	end
	local target = Vector3.new(position.X, actor.RootPart.Position.Y, position.Z)
	local look = BallControlMath.GetHorizontal(facePosition - target)
	if look.Magnitude <= 1e-3 then
		look = actor.RootPart.CFrame.LookVector
	end
	actor.RootPart.AssemblyLinearVelocity = Vector3.zero
	actor.RootPart.CFrame = CFrame.lookAt(target, target + BallControlMath.SafeUnit(look, Vector3.zAxis))
end

--[[
	WHICH WAY DOES THE TAKER FACE?

	They used to face the football. That is where the ball IS, and it is not
	where the restart is going -- so every kick-off, free kick and goal kick
	began with the taker looking at their own feet, and the first thing a human
	taker had to do was turn round before they could aim anything. Facing is not
	cosmetic here: a pass and a shot are both aimed from the body, so the default
	facing is the default aim.

	So the taker faces where the ball is most likely to GO:

		Kick-off                           their OWN half -- see below
		Free kick / goal kick              the attacking goal -- upfield
		Penalty                            the goal being shot at
		Corner                             the goal mouth being crossed into
		Throw-in                           infield, because the thrower is
		                                   standing off the pitch and upfield is
		                                   not a legal direction to throw from
		                                   where they are

	Everyone who is NOT the taker still faces the ball, which is correct: they
	are waiting for it.
]]
local function getTakerFacingPoint(
	restart: string,
	ballPosition: Vector3,
	frame,
	attackingGoal
): Vector3
	local restarts = MatchRulesConfig.Restarts

	--[[
		A throw-in is taken from outside the touchline, so "toward the attacking
		goal" points along the line the thrower is standing on. Infield is the
		direction that actually has team-mates in it; blending a little upfield
		keeps it from being a flat square throw.
	]]
	if restart == restarts.ThrowIn and frame then
		local _, lateral = PitchGeometry.ToNormalized(frame, ballPosition)
		local infield = frame.Right * (if lateral > 0 then -1 else 1)
		local blended = infield
		if attackingGoal then
			local upfield = BallControlMath.SafeUnit(
				BallControlMath.GetHorizontal(attackingGoal.MouthCenter - ballPosition),
				infield
			)
			blended = BallControlMath.SafeUnit(infield * 0.75 + upfield * 0.25, infield)
		end
		return ballPosition + blended * 30
	end

	--[[
		A KICK-OFF IS PLAYED BACKWARDS.

		Every other restart is aimed upfield, and treating kick-off as one more
		of them stood the taker on the centre spot facing the opposition goal
		with his own team behind him -- backing his own half, with no team-mate
		in front of him to find. The runtime consequence was a kick-off passed
		141 studs to the taker's own GOALKEEPER, because the only thing the pass
		resolver could see in the facing cone was the length of the pitch:

			[Pass] type=GroundPass receiver=HOME_AI_91 distance=141.0

		Real kick-offs are rolled back into the taker's own half to a team-mate
		who is already square. Facing is the default aim here, so the taker faces
		where the ball is actually going: back the way they came.
	]]
	if restart == restarts.Kickoff and attackingGoal then
		return ballPosition + BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(ballPosition - attackingGoal.MouthCenter),
			if frame then -frame.Forward else Vector3.zAxis
		) * 30
	end

	if attackingGoal then
		return attackingGoal.MouthCenter
	end
	if frame then
		return ballPosition + frame.Forward * 30
	end
	return ballPosition
end

--[[
	Position everyone for `restart`, awarded to `takingTeamId`, and choose a
	taker. Returns the taker actor, or nil if the pitch is not ready.
]]
function RestartService.Prepare(restart: string, takingTeamId: string, ballPosition: Vector3)
	local pitchState = PitchService.GetState()
	if not pitchState or not ball then
		return nil
	end

	--[[
		The football must be genuinely free before it is placed.

		A ball still under control is pulled back to its controller by the
		possession servo the moment it is teleported, which left the taker
		chasing a corner that had already returned to midfield.
	]]
	BallControlService.ForceRelease(ball, "restart-prepare")

	local ratios = MatchRulesConfig.Pitch
	local byTeam = collectActors()
	local goals = GoalService.GetGoals()

	local keepOut = ratios.KeepOutDistance * pitchState.Length
	local centreKeepOut = ratios.KickoffCentreKeepOut * pitchState.Length

	local takerActor = nil
	local takerDistance = math.huge
	local placedPositions: { [number]: Vector3 } = {}

	for teamId, actors in byTeam do
		local frame = getTeamFrame(teamId)
		if frame then
			local taking = teamId == takingTeamId
			local ballLongitudinal, ballLateral = PitchGeometry.ToNormalized(frame, ballPosition)
			local box = SetPieceFormation.GetBox(restart, taking, ballLongitudinal, ballLateral)

			local mapping = FootballTeamConfig.GetGoalMapping(teamId)
			local defendedGoal = mapping and goals[mapping.DefendedGoalId]

			for _, actor in actors do
				local isKeeper = PositionConfig.IsGoalkeeper(actor.PositionSlotId)
					or actor.Position == "Goalkeeper"

				local target
				if isKeeper then
					-- Keepers always go back to their line, exactly as the source
					-- resets them before every set piece.
					target = PitchGeometry.FromNormalized(frame, -0.96, 0)
				else
					target = SetPieceFormation.Resolve(frame, getAnchor(actor), box)

					-- Nobody stands on the ball.
					local minimum = if taking then keepOut * 0.25 else keepOut * 0.6
					target = PitchGeometry.PushOutside(ballPosition, target, minimum)

					if restart == MatchRulesConfig.Restarts.Kickoff then
						-- The centre circle belongs to the taking team only.
						target = PitchGeometry.PushOutside(ballPosition, target, centreKeepOut)
					elseif not taking
						and (restart == MatchRulesConfig.Restarts.FreeKick
							or restart == MatchRulesConfig.Restarts.CornerKick)
					then
						target = PitchGeometry.PushOutside(ballPosition, target, keepOut)
					elseif restart == MatchRulesConfig.Restarts.Penalty then
						--[[
							Everyone except the taker and the defending keeper leaves
							BOTH the penalty area and the arc. The source applies the
							same two clamps; the arc alone is not enough, because a
							player can be well clear of the spot and still be standing
							inside the box.
						]]
						target = PitchGeometry.PushOutside(ballPosition, target, keepOut)

						local longitudinal, lateral = PitchGeometry.ToNormalized(frame, target)
						local edge = 1 - ratios.PenaltyAreaDepth - 0.01
						if taking then
							-- The box is at this team's attacking end.
							longitudinal = math.min(longitudinal, edge)
						else
							-- Same box, but it sits at this team's own end.
							longitudinal = math.max(longitudinal, -edge)
						end
						target = PitchGeometry.FromNormalized(frame, longitudinal, lateral)
						-- Re-apply the arc: clamping out of the box can move a player
						-- back toward the spot.
						target = PitchGeometry.PushOutside(ballPosition, target, keepOut)
					end

					target = PitchGeometry.ClampToPitch(frame, target, 0.015)
				end

				placeActor(actor, target, ballPosition, placedPositions)

				--[[
					Taker: the closest outfielder on the taking team -- EXCEPT for a
					penalty, which the forward takes.

					Distance is the right rule for a free kick or a throw-in, where
					whoever is nearest the ball gets on with it. It is the wrong
					rule for a penalty: the ball is placed on the spot and everyone
					walks to it, so "closest" is an accident of where the foul
					happened, and it handed the biggest single moment in a match to
					whichever defender happened to be jogging back through the box.

					A penalty is given to the player most likely to score it, and in
					Beyond 90's formations that is the forward. The preference is
					expressed as a rank rather than by excluding everyone else, so a
					side with no forward on the pitch still gets a taker.
				]]
				if taking and not isKeeper then
					local distance = BallControlMath.GetHorizontal(target - ballPosition).Magnitude
					if restart == MatchRulesConfig.Restarts.Penalty
						and actor.PositionSlotId == PENALTY_TAKER_SLOT
					then
						-- Forwards sort ahead of everyone; nearest forward wins.
						distance -= PENALTY_TAKER_PREFERENCE
					end
					if distance < takerDistance then
						takerDistance = distance
						takerActor = actor
					end
				elseif taking and isKeeper and restart == MatchRulesConfig.Restarts.GoalKick then
					takerActor = actor
					takerDistance = -1
				end
			end

			--[[
				Defensive wall, only for a free kick within range of goal, and only
				for the defending side -- the source's same condition.
			]]
			if not taking and restart == MatchRulesConfig.Restarts.FreeKick and defendedGoal then
				local toGoal = BallControlMath.GetHorizontal(defendedGoal.MouthCenter - ballPosition).Magnitude
				if toGoal < pitchState.Length * 0.36 then
					local candidates = {}
					for _, actor in actors do
						if not (PositionConfig.IsGoalkeeper(actor.PositionSlotId) or actor.Position == "Goalkeeper") then
							table.insert(candidates, actor)
						end
					end
					table.sort(candidates, function(a, b)
						return BallControlMath.GetHorizontal(a.RootPart.Position - ballPosition).Magnitude
							< BallControlMath.GetHorizontal(b.RootPart.Position - ballPosition).Magnitude
					end)
					local wall = SetPieceFormation.GetWallPositions(
						ballPosition,
						defendedGoal.MouthCenter,
						math.min(2, #candidates),
						keepOut,
						0.07
					)
					for index, position in wall do
						placeActor(candidates[index], position, ballPosition, placedPositions)
					end
				end
			end
		end
	end

	-- Stand the taker over the ball, on the side that makes sense for the restart.
	--[[
		A RESTART WITHOUT A TAKER CANNOT BE TAKEN.

		The selection above only considers OUTFIELDERS on the taking side, which
		is right -- a kick-off is not the keeper's job. But it leaves a real gap:
		a side with no outfielder registered at that moment, because the team is
		short, a slot is mid-handoff between a human and the AI, or the only
		footballer present is the goalkeeper, produced `taker=none`. Nobody was
		given the ball, so the whistle went and the restart simply never happened.

		The fallback is what football does in the same situation: SOMEBODY takes
		it. The nearest available footballer on the taking side, keeper included,
		is better than a match that has stopped.
	]]
	if not takerActor then
		local fallbackDistance = math.huge
		for _, actor in byTeam[takingTeamId] or {} do
			if actor.RootPart and actor.RootPart.Parent then
				local distance = BallControlMath.GetHorizontal(
					actor.RootPart.Position - ballPosition
				).Magnitude
				if distance < fallbackDistance then
					fallbackDistance = distance
					takerActor = actor
				end
			end
		end
		if takerActor then
			log(string.format(
				"No outfielder available for %s; %s takes it",
				restart,
				takerActor.DisplayName
			))
		end
	end

	if takerActor then
		local frame = getTeamFrame(takingTeamId)
		local offsetDistance = if restart == MatchRulesConfig.Restarts.Penalty
			then keepOut * 0.35
			elseif restart == MatchRulesConfig.Restarts.ThrowIn then keepOut * 0.1
			else keepOut * 0.26
		local away = Vector3.zero
		if frame then
			if restart == MatchRulesConfig.Restarts.ThrowIn then
				-- The thrower stands outside the touchline.
				local _, lateral = PitchGeometry.ToNormalized(frame, ballPosition)
				away = frame.Right * (if lateral > 0 then 1 else -1)
			elseif restart == MatchRulesConfig.Restarts.Kickoff then
				--[[
					THE KICK-OFF TAKER STANDS IN THE OPPONENT'S HALF.

					Every other restart puts the taker BEHIND the ball so they run
					onto it going forwards. A kick-off is the one restart where
					that is wrong: the ball is on the halfway line, the taker's
					own team is all behind it -- the Laws require it -- and
					standing behind the ball too puts the taker among his own
					team-mates with nothing in front of him but opponents.

					So he steps over the line. Combined with the facing rule in
					getTakerFacingPoint, that leaves him where a kick-off is
					actually taken from: just inside the opponent half, turned
					back towards his own team, with every passing option in front
					of him instead of behind his shoulder.
				]]
				away = frame.Forward
			else
				-- Behind the ball, facing the attacking goal.
				away = -frame.Forward
			end
		end
		local takerPosition = ballPosition + away * offsetDistance
		--[[
			Placed behind the ball, but facing where the restart is going rather
			than at the ball itself -- so a human taker's first touch is already
			aimed the way they would want to play it.
		]]
		local takerMapping = FootballTeamConfig.GetGoalMapping(takingTeamId)
		local takerAttackingGoal = takerMapping and GoalService.GetGoals()[takerMapping.AttackingGoalId]
		placeActor(
			takerActor,
			takerPosition,
			getTakerFacingPoint(restart, ballPosition, frame, takerAttackingGoal),
			placedPositions
		)
	end

	if ball then
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.CFrame = CFrame.new(Vector3.new(ballPosition.X, pitchState.GroundY + ball.Size.Y * 0.5, ballPosition.Z))
	end

	local holdHeight = MatchRulesConfig.GetRestartBallHeight(restart)
	local holdPosition = Vector3.new(
		ballPosition.X,
		pitchState.GroundY + ball.Size.Y * 0.5 + holdHeight,
		ballPosition.Z
	)

	active = {
		Restart = restart,
		TeamId = takingTeamId,
		Taker = takerActor,
		BallPosition = ballPosition,
		--[[
			Where the football is HELD until the restart is taken. For a throw-in
			this is above the thrower's head, which is why a throw-in cannot be a
			ground pass from the taker's feet (§32).
		]]
		HoldPosition = holdPosition,
		HoldHeight = holdHeight,
		-- Set once the restart is actually ready to be played; until then the
		-- players are still walking into position.
		AwaitingAction = false,
		--[[
			Where every footballer was placed. Used only by HoldAssembly, so the
			pre-match freeze is enforced against the arrangement itself rather
			than against a formation the AI would otherwise drift back toward.
		]]
		PlacedPositions = placedPositions,
	}

	-- The taker owns the ball from the moment the restart is set up, not from
	-- the whistle -- so by RestartReady the client has already been showing it
	-- as theirs and can act on the first frame it is allowed to (§31).
	publishRestartControl()

	log(string.format(
		"%s for %s at (%.1f, %.1f) taker=%s",
		restart,
		takingTeamId,
		ballPosition.X,
		ballPosition.Z,
		takerActor and takerActor.DisplayName or "none"
	))

	return takerActor
end

function RestartService.GetActive()
	return active
end

function RestartService.GetTaker()
	return active and active.Taker or nil
end

--[[
	May `actor` play the ball right now? During a restart only the taker may, so
	nobody can start play early (§77).
]]
function RestartService.IsAuthorizedTaker(actor): boolean
	if not active then
		return true
	end
	local taker = active.Taker
	if not taker then
		return false
	end
	return actor ~= nil and actor.Id == taker.Id
end

--[[
	Hand the restart to an AI team-mate.

	A human designated as taker keeps control (§67), but if they simply do not
	take it the match must not stall. After a grace period the nearest AI on the
	same side steps up and plays it instead.

	Returns the new taker, or nil when there is no AI to hand it to.
]]
function RestartService.ReassignTakerToAI()
	if not active or not ball then
		return nil
	end
	local ballPosition = active.BallPosition or ball.Position

	local best, bestDistance = nil, math.huge
	for _, actor in FootballerRegistryService.GetAll() do
		if actor.IsAI and actor.TeamId == active.TeamId and actor.RootPart and actor.RootPart.Parent then
			local isKeeper = PositionConfig.IsGoalkeeper(actor.PositionSlotId) or actor.Position == "Goalkeeper"
			-- A goal kick is the keeper's; everything else goes to an outfielder.
			local eligible = if active.Restart == MatchRulesConfig.Restarts.GoalKick then isKeeper else not isKeeper
			if eligible then
				local distance = BallControlMath.GetHorizontal(actor.RootPart.Position - ballPosition).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					best = actor
				end
			end
		end
	end

	if not best then
		return nil
	end

	active.Taker = best
	publishRestartControl()
	log(string.format(
		"Taker reassigned to %s after the human grace period (%.0fs)",
		best.DisplayName,
		MatchRulesConfig.Timing.HumanTakerGraceSeconds
	))
	return best
end

--[[
	The restart is now live and waiting for its taker to play it.

	Called when the buffer reaches RestartReady. Before this the ball is placed
	but nobody is expected to act.
]]
function RestartService.BeginControl()
	if not active then
		return
	end
	active.AwaitingAction = true
	active.AwaitingSince = os.clock()
	publishRestartControl()
end

function RestartService.IsAwaitingAction(): boolean
	return active ~= nil and active.AwaitingAction == true
end

function RestartService.GetActiveRestartKind(): string?
	return active and active.Restart or nil
end

--[[
	May `actor` take the restart with `actionType` right now?

	Both halves matter. Restart authority stops an opponent playing the ball, and
	the action rule stops the taker choosing an action the restart does not
	permit -- a penalty is a shot, a throw-in is a throw, and a kick-off is a
	pass (§29).
]]
function RestartService.IsLegalRestartAction(actor, actionType: string?): boolean
	if not active then
		-- No restart pending: ordinary play, ordinary rules.
		return true
	end
	if not RestartService.IsAuthorizedTaker(actor) then
		return false
	end
	return MatchRulesConfig.IsRestartActionAllowed(active.Restart, actionType)
end

--[[
	Hold the restart together, every frame.

	Two jobs, and they are the reason a restart can no longer be dribbled away:

	  1. The football stays on its spot. Anything that nudges it -- a footballer
	     walking through it, a stray impulse, the possession servo -- is undone.
	  2. The taker stays within a bounded radius of that spot. They can turn,
	     aim and take a short run-up; they cannot walk the ball up the pitch.

	Non-takers are already prevented from acquiring the ball by BallControlService.
]]
function RestartService.UpdateControl()
	if not active or not ball or not ball.Parent then
		return
	end
	if MatchRulesConfig.RestartControl.Enabled ~= true then
		return
	end

	local hold = active.HoldPosition
	if hold then
		-- The ball is not simulating during a restart; it is placed.
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero
		if (ball.Position - hold).Magnitude > 0.05 then
			ball.CFrame = CFrame.new(hold)
		end
	end

	local taker = active.Taker
	if not taker or not taker.RootPart or not taker.RootPart.Parent then
		return
	end
	local radius = MatchRulesConfig.GetTakerMovementRadius(active.Restart)
	local spot = active.BallPosition or ball.Position
	local offset = BallControlMath.GetHorizontal(taker.RootPart.Position - spot)
	if offset.Magnitude > radius then
		--[[
			Pull back to the edge of the allowed region rather than to the spot.
			Snapping to the centre would fight the player's own input every frame;
			this only removes the part of the movement that broke the rule.
		]]
		local clamped = spot + BallControlMath.SafeUnit(offset, Vector3.zAxis) * radius
		taker.RootPart.CFrame = CFrame.new(
			Vector3.new(clamped.X, taker.RootPart.Position.Y, clamped.Z)
		) * (taker.RootPart.CFrame - taker.RootPart.CFrame.Position)
		local velocity = taker.RootPart.AssemblyLinearVelocity
		taker.RootPart.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
	end
end

--[[
	PRE-MATCH FREEZE (§25).

	A real gameplay restriction, not a loading screen. The client already refuses
	to move while the match has not been started, but this is the server half:
	every footballer is held at the position field assembly placed it at, so a
	client that ignored the phase could still not walk out of the kick-off shape.

	Cheap by design -- it only acts on a footballer that has actually drifted.
]]
function RestartService.HoldAssembly()
	if not active or not active.PlacedPositions then
		return
	end
	for _, actor in FootballerRegistryService.GetAll() do
		local placed = active.PlacedPositions[actor.Id]
		if placed and actor.RootPart and actor.RootPart.Parent then
			local drift = BallControlMath.GetHorizontal(actor.RootPart.Position - placed).Magnitude
			if drift > 1.5 then
				local look = actor.RootPart.CFrame - actor.RootPart.CFrame.Position
				actor.RootPart.CFrame = CFrame.new(
					Vector3.new(placed.X, actor.RootPart.Position.Y, placed.Z)
				) * look
			end
			local velocity = actor.RootPart.AssemblyLinearVelocity
			if math.abs(velocity.X) > 0.1 or math.abs(velocity.Z) > 0.1 then
				actor.RootPart.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
			end
		end
	end
end

function RestartService.Clear()
	active = nil
	-- Publish AFTER clearing, so the cleared state is what reaches the ball. A
	-- stale taker id surviving into open play would leave the client still
	-- offering restart actions after play had resumed.
	publishRestartControl()
end

return RestartService
