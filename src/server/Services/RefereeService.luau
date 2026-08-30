--!strict
--[[
	The match referee.

	A visible official who follows play and whistles decisions.

	This service is deliberately DOWNSTREAM of every rule. MatchRulesService
	decides; the referee reacts. It holds no authority, changes no state, and
	touches neither the football nor a footballer -- so nothing here can affect a
	competitive outcome, which is exactly what section 17 requires of a purely
	presentational system.

	Positioning follows the real diagonal system: an official stays OFF the line
	of play, trailing the ball on a diagonal, so they can see the challenge
	without standing in it. During a stoppage the referee walks to the restart
	spot instead, which is what makes a decision readable.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared.Config.AnimationConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local OffsideEvaluator = require(Shared.Football.OffsideEvaluator)
local PitchGeometry = require(Shared.Football.PitchGeometry)
local PositionConfig = require(Shared.Config.PositionConfig)
local GameModeConfig = require(Shared.Config.GameModeConfig)
local RefereeConfig = require(Shared.Config.RefereeConfig)
local CollisionGroupConfig = require(Shared.Config.CollisionGroupConfig)

local CharacterAppearanceService = require(script.Parent.CharacterAppearanceService)
--[[
	One direction only: the referee LISTENS to the rules. MatchRulesService must
	never require this module back, or a decision would depend on its own
	presentation.
]]
local MatchRulesService = require(script.Parent.MatchRulesService)
local FootballerRegistryService = require(script.Parent.FootballerRegistryService)
local GoalService = require(script.Parent.GoalService)
local MatchService = require(script.Parent.MatchService)
local PitchService = require(script.Parent.PitchService)
local PlayerService = require(script.Parent.PlayerService)

local RefereeService = {}

local initialized = false
local ball: BasePart? = nil
local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local whistle: Sound? = nil
local connection: RBXScriptConnection? = nil
local currentSpeed = 0
local sinceUpdate = 0
local holdTarget: Vector3? = nil
local whistleToken = 0
local inertnessConnections: { RBXScriptConnection } = {}
--[[
	Assistant referees. Each entry is { Character, Humanoid, RootPart, Side,
	CurrentSpeed, Target, Tracks }, where Side is +1 / -1 along the pitch WIDTH
	axis -- which touchline this assistant runs.
]]
local assistants: { any } = {}
local assistantAccumulator = 0
local refereeTracks: any = nil

local function log(message: string)
	if RefereeConfig.DebugEnabled then
		print(string.format("%s[Referee] %s", GameConfig.LogPrefix, message))
	end
end

local function getContainer(): Instance
	local root = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	if not root then
		root = Instance.new("Folder")
		root.Name = GameConfig.WorkspaceContainerName
		root.Parent = Workspace
	end
	local existing = root:FindFirstChild(RefereeConfig.FolderName)
	if existing then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = RefereeConfig.FolderName
	created.Parent = root
	return created
end

--[[
	The referee must never be part of the football simulation.

	Collisions are disabled outright: an official who can body-check a striker or
	deflect a shot is not presentation any more, it is a gameplay change nobody
	asked for. This is also why the referee lives in its own folder rather than
	the Footballers folder -- the minimap, pass targeting, offside evaluation and
	tackling all enumerate that folder, and none of them should ever see it.
]]
--[[
	Keep the referee out of the football.

	Collision is handled by COLLISION GROUP, not by CanCollide. Roblox's Humanoid
	re-forces collision on R15 torso parts at the engine level, so clearing the
	flag is silently overridden; and that same torso collision is what holds a
	Humanoid up, so clearing it would drop the referee through the pitch even if
	it did stick. The group says the thing that is actually true: the referee
	stands on the world but can never collide with a footballer.

	Touch and query are still cleared directly, so the referee cannot trigger a
	`.Touched` handler or be returned by a raycast.
]]
local function clearInertnessWatches()
	for _, connection in inertnessConnections do
		connection:Disconnect()
	end
	table.clear(inertnessConnections)
end

local function makePartInert(part: BasePart)
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CollisionGroup = CollisionGroupConfig.Official
end

local function makeNonInteractive(model: Model)
	clearInertnessWatches()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			makePartInert(part)
		end
	end
	--[[
		The appearance pass rebuilds the R15 body parts, so replacements arrive
		back in the default group. Watching covers that and anything added later.
	]]
	table.insert(inertnessConnections, model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			makePartInert(descendant)
		end
	end))
end

--[[
	Build one official's body.

	Shared by the referee and both assistants so an assistant is physically the
	same kind of object as the referee: same template, same grounding, same
	collision group, same exclusion from every footballer enumeration.
]]
local function buildOfficialBody(name: string, displayName: string, kitColor: Color3, kitBlend: number)
	local template, source = PlayerService.CloneFootballerTemplate()
	if not template then
		warn(string.format("%s[Referee] Could not create official '%s'", GameConfig.LogPrefix, name))
		return nil
	end

	template.Name = name
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end

	local model = template
	local modelHumanoid = model:FindFirstChildOfClass("Humanoid")
	local modelRoot = model:FindFirstChild("HumanoidRootPart")
	if not modelHumanoid or not modelRoot or not modelRoot:IsA("BasePart") then
		model:Destroy()
		return nil
	end

	CharacterAppearanceService.StandardizeNPC(name, model, modelHumanoid)
	PlayerService.NormalizeFootballerPhysics(model)
	PlayerService.ApplyFootballerGrounding(model, modelHumanoid)

	modelHumanoid.DisplayName = displayName
	modelHumanoid.AutoRotate = true
	modelHumanoid.WalkSpeed = 0
	modelHumanoid.UseJumpPower = true
	modelHumanoid.JumpPower = 0
	modelHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	modelHumanoid.AutomaticScalingEnabled = false

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not part.Parent:IsA("Accessory") then
			part.Color = part.Color:Lerp(kitColor, kitBlend)
		end
	end

	model:SetAttribute("Beyond90Official", true)
	model:SetAttribute("Beyond90UsesHumanoidLocomotion", true)
	model:SetAttribute("Beyond90FootballerTemplateSource", source)
	makeNonInteractive(model)

	model.Parent = getContainer()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
	end

	return model, modelHumanoid, modelRoot :: BasePart, source
end

local function createCharacter(): boolean
	local kit = RefereeConfig.Character
	local model, modelHumanoid, modelRoot, source =
		buildOfficialBody(RefereeConfig.Name, kit.DisplayName, kit.KitColor, kit.KitBlend)
	if not model or not modelHumanoid or not modelRoot then
		return false
	end

	local sound = Instance.new("Sound")
	sound.Name = "RefereeWhistle"
	sound.SoundId = "rbxassetid://" .. RefereeConfig.Whistle.AssetId
	sound.Volume = RefereeConfig.Whistle.Volume
	sound.RollOffMinDistance = RefereeConfig.Whistle.RollOffMinDistance
	sound.RollOffMaxDistance = RefereeConfig.Whistle.RollOffMaxDistance
	sound.Parent = modelRoot

	character = model
	humanoid = modelHumanoid
	rootPart = modelRoot
	whistle = sound
	currentSpeed = 0
	log(string.format("Referee ready (body source=%s)", source))
	return true
end

--[[
	OFFICIAL LOCOMOTION ANIMATION (§58, §63).

	Officials were sliding across the pitch with no clip playing at all, which is
	what read as "floating". They now use the shared off-ball locomotion set --
	and ONLY that set. A referee never passes, shoots or tackles, so loading those
	clips would just be a chance to play one by accident.

	The clip is chosen from MEASURED world-space velocity rather than from the
	official's intent, so the feet always match the motion even while
	accelerating, decelerating or being clamped by the pitch boundary.
]]
local function loadOfficialTracks(officialHumanoid: Humanoid)
	if RefereeConfig.Animation.Enabled ~= true then
		return nil
	end
	local animator = officialHumanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = officialHumanoid
	end

	local function load(assetId: string, priority: Enum.AnimationPriority)
		local animation = Instance.new("Animation")
		animation.AnimationId = assetId
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		animation:Destroy()
		if not ok or not track then
			return nil
		end
		track.Priority = priority
		track.Looped = true
		return track
	end

	local offBall = AnimationConfig.Assets.Locomotion.OffBall
	return {
		Idle = load(offBall.Idle, Enum.AnimationPriority.Idle),
		Jog = load(offBall.Jog.Forward, Enum.AnimationPriority.Movement),
		Sprint = load(offBall.Sprint.Forward, Enum.AnimationPriority.Movement),
		Current = "",
	}
end

local function updateOfficialAnimation(tracks, officialRoot: BasePart)
	if not tracks or not officialRoot or not officialRoot.Parent then
		return
	end
	local config = RefereeConfig.Animation
	local speed = BallControlMath.GetHorizontal(officialRoot.AssemblyLinearVelocity).Magnitude

	local name, reference
	if speed < config.IdleSpeedThreshold then
		name, reference = "Idle", 1
	elseif speed >= config.SprintSpeedThreshold then
		name, reference = "Sprint", config.SprintReferenceSpeed
	else
		name, reference = "Jog", config.JogReferenceSpeed
	end

	local playback = if name == "Idle"
		then 1
		else math.clamp(speed / math.max(reference, 1e-3), config.MinimumPlaybackSpeed, config.MaximumPlaybackSpeed)

	if tracks.Current == name then
		local active = tracks[name]
		if active and name ~= "Idle" then
			active:AdjustSpeed(playback)
		end
		return
	end

	for _, other in { "Idle", "Jog", "Sprint" } do
		local track = tracks[other]
		if track and track.IsPlaying then
			track:Stop(config.MoveFadeSeconds)
		end
	end
	local nextTrack = tracks[name]
	if nextTrack then
		nextTrack:Play(if name == "Idle" then config.IdleFadeSeconds else config.MoveFadeSeconds, 1, playback)
	end
	tracks.Current = name
end

local function destroyCharacter()
	clearInertnessWatches()
	if character then
		character:Destroy()
	end
	character = nil
	humanoid = nil
	rootPart = nil
	whistle = nil
	currentSpeed = 0
	holdTarget = nil
	refereeTracks = nil
end

--[[
	ASSISTANT REFEREES (§60-§63).

	Two officials, one on each touchline, each covering the half that contains
	the end they are responsible for. They stay outside the field of play and
	track the OFFSIDE LINE.

	Critically, they are not rule authority (§62). The line they stand on is read
	FROM the authoritative evaluation -- the same OffsideEvaluator.GetOffsideLine
	the rules use -- rather than being computed independently here. An offside
	decision therefore never depends on whether an NPC visually reached a spot,
	and the two can never disagree.
]]
local function createAssistants(): boolean
	if RefereeConfig.Assistants.Enabled ~= true then
		return true
	end
	if #assistants > 0 then
		return true
	end
	local config = RefereeConfig.Assistants

	for index = 1, config.Count do
		local model, assistantHumanoid, assistantRoot = buildOfficialBody(
			string.format(config.NameFormat, index),
			config.DisplayName,
			config.KitColor,
			config.KitBlend
		)
		if not model or not assistantHumanoid or not assistantRoot then
			return false
		end
		table.insert(assistants, {
			Character = model,
			Humanoid = assistantHumanoid,
			RootPart = assistantRoot,
			-- Assistant 1 runs one touchline, assistant 2 the other.
			Side = if index == 1 then 1 else -1,
			-- ...and each is responsible for the half at the matching end, so
			-- between them they cover the whole pitch.
			EndSign = if index == 1 then 1 else -1,
			CurrentSpeed = 0,
			Target = nil,
			Tracks = nil,
		})
	end
	log(string.format("%d assistant referees ready", #assistants))
	return true
end

local function destroyAssistants()
	for _, assistant in assistants do
		if assistant.Character then
			assistant.Character:Destroy()
		end
	end
	table.clear(assistants)
end

--[[
	Where the offside line currently is, as a normalized longitudinal coordinate
	in the frame of the team attacking `attackingTeamId`.

	Returns nil when the line is undefined -- too few opponents on the pitch, or
	no pitch yet -- in which case the assistant holds position rather than
	guessing.
]]
local function resolveOffsideLine(attackingTeamId: string)
	local pitchState = PitchService.GetState()
	if not pitchState then
		return nil, nil
	end
	local mapping = FootballTeamConfig.GetGoalMapping(attackingTeamId)
	local goals = GoalService.GetGoals()
	local attacking = mapping and goals[mapping.AttackingGoalId]
	local defended = mapping and goals[mapping.DefendedGoalId]
	if not attacking or not defended then
		return nil, nil
	end

	local attackDirection = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(attacking.MouthCenter - defended.MouthCenter),
		Vector3.zAxis
	)
	local frame = PitchGeometry.CreateFrame(pitchState, attackDirection)

	local opponents = {}
	for _, actor in FootballerRegistryService.GetAll() do
		if actor.TeamId and actor.TeamId ~= attackingTeamId and actor.RootPart and actor.RootPart.Parent then
			table.insert(opponents, {
				Id = actor.Id,
				Position = actor.RootPart.Position,
				IsGoalkeeper = PositionConfig.IsGoalkeeper(actor.PositionSlotId) or actor.Position == "Goalkeeper",
			})
		end
	end

	local line = OffsideEvaluator.GetOffsideLine(frame, opponents, if ball then ball.Position else nil)
	return line, frame
end

--[[
	Where one assistant should stand.

	Level with the offside line for the team attacking the end this assistant
	covers, clamped inside the goal lines, and held a fixed distance OUTSIDE the
	touchline so they never enter the field of play (§60).
]]
local function resolveAssistantTarget(assistant)
	local pitchState = PitchService.GetState()
	if not pitchState then
		return nil
	end
	local config = RefereeConfig.Assistants

	--[[
		Which team attacks this assistant's end? That is the team whose offside
		line this assistant is watching.
	]]
	local attackingTeamId = "Home"
	local mapping = FootballTeamConfig.GetGoalMapping("Home")
	local goals = GoalService.GetGoals()
	local homeAttacking = mapping and goals[mapping.AttackingGoalId]
	if homeAttacking then
		local toGoal = BallControlMath.GetHorizontal(homeAttacking.MouthCenter - pitchState.Center)
		local homeEndSign = if toGoal:Dot(pitchState.LengthAxis) >= 0 then 1 else -1
		if homeEndSign ~= assistant.EndSign then
			attackingTeamId = "Away"
		end
	end

	local line, frame = resolveOffsideLine(attackingTeamId)

	local lengthOffset
	if line and frame then
		-- Convert the normalized line back into a world offset along the pitch.
		local worldPoint = PitchGeometry.FromNormalized(frame, math.clamp(line, -1, 1), 0)
		lengthOffset = BallControlMath.GetHorizontal(worldPoint - pitchState.Center):Dot(pitchState.LengthAxis)
	elseif ball then
		-- No line available: follow the ball's depth, which is what an assistant
		-- does when there is nothing to hold.
		lengthOffset = BallControlMath.GetHorizontal(ball.Position - pitchState.Center):Dot(pitchState.LengthAxis)
	else
		return nil
	end

	local halfLength = math.max(pitchState.Length * 0.5 - config.GoalLineMargin, 1)
	lengthOffset = math.clamp(lengthOffset, -halfLength, halfLength)
	local widthOffset = (pitchState.Width * 0.5 + config.TouchlineOffset) * assistant.Side

	local target = pitchState.Center
		+ pitchState.LengthAxis * lengthOffset
		+ pitchState.WidthAxis * widthOffset
	return Vector3.new(target.X, pitchState.GroundY, target.Z)
end

--[[
	Shared official locomotion. Ordinary Humanoid movement with acceleration --
	no teleporting and no CFrame stepping, so the feet keep up with the body.
]]
local function moveOfficial(
	officialHumanoid: Humanoid,
	officialRoot: BasePart,
	target: Vector3,
	currentValue: number,
	config,
	deltaTime: number,
	faceTarget: Vector3?
): number
	local toTarget = BallControlMath.GetHorizontal(target - officialRoot.Position)
	local distance = toTarget.Magnitude
	local direction = if distance > 0.05 then toTarget.Unit else Vector3.zero

	local targetSpeed = 0
	if distance > config.ArrivalRadius then
		targetSpeed = if distance >= config.SprintDistance then config.SprintSpeed else config.JogSpeed
	end

	local responseTime = if targetSpeed > currentValue then config.AccelerationTime else config.DecelerationTime
	local maximumDelta = config.SprintSpeed / math.max(responseTime, 0.05) * deltaTime
	local nextSpeed = if currentValue < targetSpeed
		then math.min(targetSpeed, currentValue + maximumDelta)
		else math.max(targetSpeed, currentValue - maximumDelta)

	officialHumanoid.WalkSpeed = nextSpeed
	officialHumanoid:Move(direction, false)

	if faceTarget then
		local toFace = BallControlMath.GetHorizontal(faceTarget - officialRoot.Position)
		if toFace.Magnitude > 1e-3 then
			officialHumanoid.AutoRotate = false
			local current = BallControlMath.GetHorizontal(officialRoot.CFrame.LookVector)
			local blended = if current.Magnitude > 1e-3
				then current.Unit:Lerp(toFace.Unit, math.clamp(6 * deltaTime, 0, 1))
				else toFace.Unit
			if blended.Magnitude > 1e-3 then
				officialRoot.CFrame = CFrame.lookAt(officialRoot.Position, officialRoot.Position + blended.Unit)
			end
		end
	end

	return nextSpeed
end

local function updateAssistants(deltaTime: number)
	if RefereeConfig.Assistants.Enabled ~= true then
		return
	end
	local config = RefereeConfig.Assistants

	assistantAccumulator += deltaTime
	local refresh = assistantAccumulator >= config.UpdateInterval
	if refresh then
		assistantAccumulator = 0
	end

	for _, assistant in assistants do
		if assistant.Character and assistant.Character.Parent and assistant.RootPart.Parent then
			if refresh then
				assistant.Target = resolveAssistantTarget(assistant)
			end
			if not assistant.Tracks then
				assistant.Tracks = loadOfficialTracks(assistant.Humanoid)
			end
			if assistant.Target then
				assistant.CurrentSpeed = moveOfficial(
					assistant.Humanoid,
					assistant.RootPart,
					assistant.Target,
					assistant.CurrentSpeed,
					config,
					deltaTime,
					-- Assistants watch the pitch, not their own run.
					if ball then ball.Position else nil
				)
			end
			updateOfficialAnimation(assistant.Tracks, assistant.RootPart)
		end
	end
end

--[[
	Blow the whistle.

	Count and playback speed carry meaning -- three blasts is full time, two is a
	penalty or the end of a half -- so a decision is recognisable before the HUD
	text is read.
]]
function RefereeService.Whistle(kind: string)
	if RefereeConfig.Whistle.Enabled ~= true then
		return
	end
	local pattern = RefereeConfig.GetWhistlePattern(kind)
	local sound = whistle
	if not pattern then
		-- Informational announcements are deliberately silent.
		return
	end
	if not sound then
		--[[
			A decision arrived with no referee on the pitch to whistle it. That is
			a real fault -- the official is created when the match starts -- so it
			is reported rather than silently swallowed.
		]]
		warn(string.format("%s[Referee] %s announced with no whistle available", GameConfig.LogPrefix, kind))
		return
	end
	log(string.format("whistle %s x%d", kind, math.max(pattern.Count, 1)))

	whistleToken += 1
	local token = whistleToken
	task.spawn(function()
		for index = 1, math.max(pattern.Count, 1) do
			if token ~= whistleToken or not sound.Parent then
				return
			end
			sound.PlaybackSpeed = pattern.Speed or 1
			sound:Play()
			if index < pattern.Count and (pattern.Gap or 0) > 0 then
				task.wait(pattern.Gap)
			end
		end
	end)
end

function RefereeService.SetBall(newBall: BasePart?)
	ball = newBall
end

--[[
	Where the referee should be.

	The diagonal: trail the ball along the pitch and stand off it laterally,
	choosing whichever side has more room so play near a touchline pushes the
	official infield rather than off the pitch.
]]
local function resolveTarget(): Vector3?
	local pitchState = PitchService.GetState()
	if not pitchState or not ball then
		return nil
	end

	local config = RefereeConfig.Positioning

	--[[
		During a stoppage the referee stops trailing play and stands over the
		restart spot. Standing off at a distance while a free kick is set up is
		what tells the players a decision has actually been given.
	]]
	if MatchRulesService.IsRestartActive() then
		local spot = ball.Position
		local away = BallControlMath.GetHorizontal(spot - pitchState.Center)
		local direction = if away.Magnitude > 1e-3 then away.Unit else pitchState.WidthAxis
		local target = spot - direction * RefereeConfig.Stoppage.ApproachDistance
		return Vector3.new(target.X, pitchState.GroundY, target.Z)
	end
	local ballVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	local anticipated = ball.Position + ballVelocity * config.BallLookAhead

	local offset = BallControlMath.GetHorizontal(anticipated - pitchState.Center)
	local lengthOffset = offset:Dot(pitchState.LengthAxis)
	local widthOffset = offset:Dot(pitchState.WidthAxis)

	-- Stand off on whichever side of the ball has more pitch behind it.
	local lateralSign = if widthOffset >= 0 then -1 else 1
	-- Trail toward the middle of the pitch, so the official is behind play
	-- rather than ahead of it wherever the ball happens to be.
	local trailSign = if lengthOffset >= 0 then -1 else 1

	local targetLength = lengthOffset + trailSign * config.TrailDistance
	local targetWidth = widthOffset + lateralSign * config.LateralDistance

	local halfLength = math.max(pitchState.Length * 0.5 - config.BoundaryMargin, 1)
	local halfWidth = math.max(pitchState.Width * 0.5 - config.BoundaryMargin, 1)
	targetLength = math.clamp(targetLength, -halfLength, halfLength)
	targetWidth = math.clamp(targetWidth, -halfWidth, halfWidth)

	local target = pitchState.Center
		+ pitchState.LengthAxis * targetLength
		+ pitchState.WidthAxis * targetWidth

	--[[
		Never crowd the ball. Clamping to the pitch can pull the target back
		toward play, so the minimum separation is enforced afterwards rather than
		assumed from the offsets.
	]]
	local toBall = BallControlMath.GetHorizontal(ball.Position - target)
	if toBall.Magnitude < config.MinimumBallDistance and toBall.Magnitude > 1e-3 then
		target -= toBall.Unit * (config.MinimumBallDistance - toBall.Magnitude)
		local pushed = BallControlMath.GetHorizontal(target - pitchState.Center)
		target = pitchState.Center
			+ pitchState.LengthAxis * math.clamp(pushed:Dot(pitchState.LengthAxis), -halfLength, halfLength)
			+ pitchState.WidthAxis * math.clamp(pushed:Dot(pitchState.WidthAxis), -halfWidth, halfWidth)
	end

	return Vector3.new(target.X, pitchState.GroundY, target.Z)
end

local function moveToward(value: number, target: number, maximumDelta: number): number
	if value < target then
		return math.min(target, value + maximumDelta)
	end
	return math.max(target, value - maximumDelta)
end

local function step(deltaTime: number)
	local model, modelHumanoid, modelRoot = character, humanoid, rootPart

	--[[
		Officials exist for as long as a match does (§23, §88).

		This used to key off MatchService.IsPlaying(), which meant the referee was
		created only AFTER the match started -- so it appeared on the pitch in
		front of the player instead of already being there. The officials are now
		part of field assembly and are torn down only when the match itself ends.
	]]
	--[[
		A mode that does not use officials does not get officials.

		This used to spawn a referee and two assistants for any match state that
		was not Idle, with no notion of which mode was running -- which is why a
		free-practice session had three officials standing on it.
	]]
	local matchState = MatchService.GetState()
	if not GameModeConfig.Uses(MatchService.GetMode(), "UsesOfficials") then
		if model then
			destroyCharacter()
		end
		if #assistants > 0 then
			destroyAssistants()
		end
		return
	end
	if matchState == "Idle" then
		if model then
			destroyCharacter()
		end
		if #assistants > 0 then
			destroyAssistants()
		end
		return
	end

	if not model or not model.Parent then
		if not createCharacter() then
			return
		end
		model, modelHumanoid, modelRoot = character, humanoid, rootPart
	end
	createAssistants()
	if not model or not modelHumanoid or not modelRoot then
		return
	end

	if not refereeTracks then
		refereeTracks = loadOfficialTracks(modelHumanoid)
	end
	updateAssistants(deltaTime)

	--[[
		Before the match is started the officials stand still, exactly like every
		footballer (§25). They are already in position, so the first visible frame
		is complete.
	]]
	if MatchRulesService.IsPreMatch() or not MatchService.IsPlaying() then
		currentSpeed = 0
		modelHumanoid.WalkSpeed = 0
		modelHumanoid:Move(Vector3.zero, false)
		updateOfficialAnimation(refereeTracks, modelRoot)
		return
	end

	sinceUpdate += deltaTime
	if sinceUpdate >= RefereeConfig.Positioning.UpdateInterval then
		sinceUpdate = 0
		holdTarget = resolveTarget()
	end

	local target = holdTarget
	if not target then
		return
	end

	local config = RefereeConfig.Positioning
	local toTarget = BallControlMath.GetHorizontal(target - modelRoot.Position)
	local distance = toTarget.Magnitude
	local direction = if distance > 0.05 then toTarget.Unit else Vector3.zero

	local targetSpeed = 0
	if distance > config.ArrivalRadius then
		if MatchRulesService.IsRestartActive() then
			-- Officials walk to a set piece; sprinting to one reads as panic.
			targetSpeed = RefereeConfig.Stoppage.Speed
		else
			targetSpeed = if distance >= config.SprintDistance then config.SprintSpeed else config.JogSpeed
		end
	end

	local responseTime = if targetSpeed > currentSpeed then config.AccelerationTime else config.DecelerationTime
	currentSpeed = moveToward(
		currentSpeed,
		targetSpeed,
		config.SprintSpeed / math.max(responseTime, 0.05) * deltaTime
	)
	modelHumanoid.WalkSpeed = currentSpeed
	modelHumanoid:Move(direction, false)

	--[[
		An official watches the ball, not their own feet. AutoRotate would turn
		the body along the run, which for a referee jogging backwards into
		position means facing away from the incident they are there to judge.
	]]
	if ball then
		local toBall = BallControlMath.GetHorizontal(ball.Position - modelRoot.Position)
		if toBall.Magnitude > 1e-3 then
			modelHumanoid.AutoRotate = false
			local current = BallControlMath.GetHorizontal(modelRoot.CFrame.LookVector)
			local blended = if current.Magnitude > 1e-3
				then current.Unit:Lerp(toBall.Unit, math.clamp(6 * deltaTime, 0, 1))
				else toBall.Unit
			if blended.Magnitude > 1e-3 then
				modelRoot.CFrame = CFrame.lookAt(modelRoot.Position, modelRoot.Position + blended.Unit)
			end
		end
	end

	--[[
		Feet follow the body (§58). Driven from measured world velocity, so the
		referee can never appear to slide: if the root is moving, a run clip is
		playing at a matching rate.
	]]
	updateOfficialAnimation(refereeTracks, modelRoot)
end

function RefereeService.Initialize()
	if initialized or RefereeConfig.Enabled ~= true then
		return
	end
	initialized = true
	getContainer()

	--[[
		The whistle is driven by the rules, not by this module guessing. Every
		decision MatchRulesService announces produces the matching blast, so the
		referee can never whistle for something that did not happen -- nor stay
		silent for something that did.
	]]
	local announcements = MatchRulesService.GetAnnouncementEvent()
	if announcements then
		announcements.Event:Connect(function(payload)
			if typeof(payload) == "table" and typeof(payload.Kind) == "string" then
				RefereeService.Whistle(payload.Kind)
			end
		end)
	end

	connection = RunService.Heartbeat:Connect(step)
end

--[[
	FIELD ASSEMBLY (§23, §24).

	Create every official NOW, before the pitch is revealed. Returns false with
	the name of what could not be built, so the assembly barrier can report the
	specific missing actor rather than revealing a half-built match.
]]
function RefereeService.EnsureOfficials(): (boolean, string?)
	if RefereeConfig.Enabled ~= true then
		return true, nil
	end
	if not character or not character.Parent then
		if not createCharacter() then
			return false, "Referee"
		end
	end
	if not createAssistants() then
		return false, "AssistantReferee"
	end
	return true, nil
end

-- How many officials are on the pitch. Used by the assembly barrier's report.
function RefereeService.GetOfficialCount(): number
	local count = if character and character.Parent then 1 else 0
	for _, assistant in assistants do
		if assistant.Character and assistant.Character.Parent then
			count += 1
		end
	end
	return count
end

function RefereeService.Destroy()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	destroyAssistants()
	destroyCharacter()
	initialized = false
end

return RefereeService
