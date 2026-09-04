--!strict
--[[
	THE HUMAN GOALKEEPER, CLIENT SIDE.

	Choosing GK now genuinely puts the player in goal, and a goalkeeper is not an
	outfielder with different spawn coordinates -- the actions available are
	different, the assistance is different, and the skill being tested is
	different. This controller is what makes those three things true on the
	client:

	  * It REROUTES the existing football inputs rather than adding new ones.
	    A keeper presses the same key an outfielder presses to tackle, and it
	    dives; the same key they press to pass, and it throws the ball out. No
	    new binding to learn, nothing extra to configure on gamepad or touch, and
	    the HUD only has to relabel what is already there.

	  * It supplies the POSITIONING ASSISTANCE. The server publishes where the
	    keeper should be standing; when the player is not steering, this drifts
	    them toward it. Hold a direction and the assist yields immediately, so
	    coming off the line is always the player's choice.

	  * It gets out of the way during a dive, which is server-driven physical
	    movement. Steering during it would cancel the impulse the player just
	    asked for.

	What it deliberately does NOT do is decide anything. The dive request is a
	request; whether it commits, where it goes and whether it saves the shot are
	all resolved on the server, exactly as for shooting and tackling.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GoalkeeperConfig = require(Shared.Config.GoalkeeperConfig)
local BallControlMath = require(Shared.Football.BallControlMath)

local InputController = require(script.Parent.InputController)
local MovementController = require(script.Parent.MovementController)

local GoalkeeperController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local connections: { RBXScriptConnection } = {}
local character: Model? = nil
local rootPart: BasePart? = nil
local actionRemote: RemoteEvent? = nil
local lastRequestAt = 0

local function log(message: string)
	print(string.format("%s[Client][GK] %s", GameConfig.LogPrefix, message))
end

--[[
	Is the local footballer a goalkeeper right now?

	Read from the character attribute the server writes when it registers the
	keeper, so the client can never believe it is a keeper when the server does
	not agree -- which is what would otherwise let a striker send dive requests.
]]
function GoalkeeperController.IsActive(): boolean
	if GoalkeeperConfig.Human.Enabled ~= true then
		return false
	end
	local model = character
	if not model or not model.Parent then
		return false
	end
	if model:GetAttribute(GoalkeeperConfig.RoleAttributeName) ~= GoalkeeperConfig.Role then
		return false
	end

	--[[
		Keeper controls apply inside the keeper's own area only. Step outside and
		the player gets their ordinary outfield bindings back -- pass, shoot,
		tackle -- because outside the box that is genuinely all a keeper is.

		Absent attribute means yes: a keeper must not lose their controls just
		because the server has not published the flag yet, and the permissive
		failure mode matches IsInsideOwnPenaltyArea on the server.
	]]
	local inside = model:GetAttribute(GoalkeeperConfig.Attributes.InsideOwnArea)
	return inside ~= false
end

-- Is this player the keeper at all, regardless of where they are standing?
function GoalkeeperController.IsGoalkeeperRole(): boolean
	local model = character
	return model ~= nil
		and model.Parent ~= nil
		and model:GetAttribute(GoalkeeperConfig.RoleAttributeName) == GoalkeeperConfig.Role
end

function GoalkeeperController.IsDiving(): boolean
	local model = character
	return model ~= nil and model:GetAttribute(GoalkeeperConfig.Attributes.Diving) == true
end

function GoalkeeperController.IsHolding(): boolean
	local model = character
	return model ~= nil and model:GetAttribute(GoalkeeperConfig.Attributes.Holding) == true
end

--[[
	Is a shot on its way in, and how long until it arrives?

	Published by the server so the HUD can prompt the dive. It is information,
	not a decision: nothing here reacts to it automatically.
]]
function GoalkeeperController.GetThreat(): (boolean, number)
	local model = character
	if not model or model:GetAttribute(GoalkeeperConfig.Attributes.ThreatActive) ~= true then
		return false, 0
	end
	local seconds = model:GetAttribute(GoalkeeperConfig.Attributes.ThreatSeconds)
	return true, if typeof(seconds) == "number" then seconds else 0
end

--[[
	The aim for a dive or a throw.

	The player's own movement input first -- that is them explicitly choosing a
	side -- and the direction they are facing when they are not holding one, so
	a keeper who simply presses dive still goes somewhere sensible rather than
	nowhere.
]]
local function getAimDirection(): Vector3
	local state = InputController.GetInputState()
	if state.MoveMagnitude > 0.15 then
		local flat = BallControlMath.GetHorizontal(state.MoveDirection)
		if flat.Magnitude > 0.05 then
			return flat.Unit
		end
	end
	local part = rootPart
	if part then
		local facing = BallControlMath.GetHorizontal(part.CFrame.LookVector)
		if facing.Magnitude > 0.05 then
			return facing.Unit
		end
	end
	return Vector3.zAxis
end

--[[
	THE VERTICAL PART OF THE LAUNCH.

	The horizontal travel is driven by MovementController for the whole dive --
	see the comment there for why an impulse alone could not survive the
	character controller. What is left here is the lift: a one-off upward
	impulse so the keeper leaves the ground rather than sliding along it.

	The attribute is NOT consumed, because the movement driver reads it every
	frame of the dive. Repeat application is prevented by the dive's own
	timestamp instead, so each approved dive lifts exactly once.
]]
local lastDiveLiftAt = 0

local function onDiveVelocityChanged()
	local model = localPlayer.Character
	if not model then
		return
	end
	local velocity = model:GetAttribute(GoalkeeperConfig.Attributes.DiveVelocity)
	if typeof(velocity) ~= "Vector3" or velocity.Y <= 0.01 then
		return
	end
	local startedAt = model:GetAttribute("Beyond90GoalkeeperDiveAt")
	if typeof(startedAt) == "number" then
		if startedAt == lastDiveLiftAt then
			return
		end
		lastDiveLiftAt = startedAt
	end
	local part = model:FindFirstChild("HumanoidRootPart")
	if part and part:IsA("BasePart") then
		part.AssemblyLinearVelocity = Vector3.new(
			part.AssemblyLinearVelocity.X,
			velocity.Y,
			part.AssemblyLinearVelocity.Z
		)
	end
end

local function send(action: string, aimOverride: Vector3?)
	local remote = actionRemote
	if not remote then
		return
	end
	--[[
		A floor between requests. The server validates and rate-limits properly;
		this only stops a held key or a mashed touch button from filling the
		remote queue with requests the server will reject anyway.
	]]
	local now = os.clock()
	if now - lastRequestAt < 0.08 then
		return
	end
	lastRequestAt = now
	remote:FireServer(action, aimOverride or getAimDirection())
end

--[[
	The input reroute.

	Tackle -> dive, Pass -> throw. Both are the actions those keys already mean
	in football terms for the role the player is actually playing, which is why
	no new binding is introduced: an outfielder's "win the ball back" and a
	keeper's "go and get it" are the same intent.
]]
--[[
	THE DIVE IS A CLICK, THEN A SIDE.

	Requested directly: left mouse click dives, and the direction comes from the
	movement key pressed immediately after. That ordering is what a keeper
	actually does -- the decision to go is made before the side is chosen, and
	forcing the player to hold a direction BEFORE committing would make every
	dive late by however long it took them to pick.

	So a click with a direction already held goes that way at once. A click with
	no direction held waits DiveAimGraceSeconds for one, and dives centrally if
	none arrives. The wait is short enough that it never reads as lag and long
	enough to catch a genuine click-then-press.
]]
local diveAimPoll: thread? = nil

--[[
	CAPTURING THE SIDE, NOT RE-READING IT LATER.

	The direction used to be read from the input state at the moment the request
	was SENT, which is up to DiveAimGraceSeconds after the click. A player who
	taps A and lets go -- which is what "click, then a direction" actually feels
	like -- has already released it by then, so the read returned nothing and the
	aim fell back to the keeper's facing. Facing is forward, so forward dives
	worked and side dives silently became forward dives.

	The window is now polled every frame and the FIRST direction seen is captured
	and sent. A tap of a single frame is enough, and the direction cannot be lost
	between choosing it and using it.
]]
local function cancelDivePoll()
	if diveAimPoll then
		task.cancel(diveAimPoll)
		diveAimPoll = nil
	end
end

--[[
	A CLICK WITH NO SIDE IS STILL A DIVE TO A SIDE.

	Diving straight ahead is removed: it is the one direction a keeper never
	dives, because anything straight at them is caught standing up (that is what
	the assisted save radius is for). So a bare click has to mean something else,
	and the useful meaning is "go where the danger is".

	Where that is, in order of what is actually known:

	  1. The threat point the server has published -- the place it has worked out
	     the ball is heading. This is the real answer whenever a shot is live.
	  2. Failing that, the ball's own position: the keeper commits to the side
	     the attack is on.

	Both are read ACROSS THE GOAL and nothing else. A dive has one meaningful
	axis -- along the goal line -- so the direction is the goalward component
	only, and a threat dead centre resolves to whichever side the ball sits on
	rather than to a forward dive.

	This does not choose the player's football decision (section 2). The player
	decided to dive, and decided not to name a side; this resolves an
	under-specified input rather than substituting for one the player made.
]]
local function getUncommittedDiveDirection(): Vector3?
	local part = rootPart
	local model = localPlayer.Character
	if not part or not model then
		return nil
	end

	local across = model:GetAttribute(GoalkeeperConfig.Attributes.Pitchward)
	if typeof(across) ~= "Vector3" then
		return nil
	end
	-- The goal line axis: perpendicular to facing out of the goal.
	local lineAxis = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(across):Cross(Vector3.yAxis),
		Vector3.xAxis
	)

	local target: Vector3? = nil
	if model:GetAttribute(GoalkeeperConfig.Attributes.ThreatActive) == true then
		local point = model:GetAttribute(GoalkeeperConfig.Attributes.ThreatPoint)
		if typeof(point) == "Vector3" then
			target = point
		end
	end
	if not target then
		local container = workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
		local ballFolder = container and container:FindFirstChild("Ball")
		local ball = ballFolder and ballFolder:FindFirstChildWhichIsA("BasePart")
		target = if ball then ball.Position else nil
	end
	if not target then
		return nil
	end

	local offset = BallControlMath.GetHorizontal(target - part.Position)
	local along = offset:Dot(lineAxis)
	if math.abs(along) < 0.05 then
		-- Dead centre with nothing to separate the sides: refuse rather than
		-- invent one. The caller falls back to the keeper's own facing.
		return nil
	end
	return lineAxis * math.sign(along)
end

local function onDiveClicked()
	if not GoalkeeperController.IsActive() then
		return
	end
	cancelDivePoll()

	local state = InputController.GetInputState()
	if state.MoveMagnitude > 0.15 then
		-- A side is already being held; nothing to wait for.
		send("Dive")
		return
	end

	local deadline = os.clock() + (GoalkeeperConfig.Human.DiveAimGraceSeconds or 0.2)
	diveAimPoll = task.spawn(function()
		while os.clock() < deadline do
			local polled = InputController.GetInputState()
			if polled.MoveMagnitude > 0.15 then
				local flat = BallControlMath.GetHorizontal(polled.MoveDirection)
				diveAimPoll = nil
				send("Dive", if flat.Magnitude > 0.05 then flat.Unit else nil)
				return
			end
			task.wait()
		end
		-- No side chosen: read the danger instead of diving forward.
		diveAimPoll = nil
		send("Dive", getUncommittedDiveDirection())
	end)
end

local function onFootballAction(payload)
	if not GoalkeeperController.IsActive() or payload.Phase ~= "Pressed" then
		return
	end
	local actionType = payload.ActionType
	if actionType == "Tackle" then
		--[[
			THE SAME DIVE AS THE CLICK, INCLUDING THE AIM.

			This used to send a bare `send("Dive")` with no direction, which was
			survivable while it was only a secondary keyboard binding. It is not
			survivable on touch: the HUD's DIVE button is the ONLY way a phone
			player dives, and a dive with no side is refused outright by the
			server as `no-lateral-component`.

			Routing through `onDiveClicked` gives every entry point the same
			behaviour -- stick already held, dive that way at once; nothing held,
			a short grace for a side and then read which way the danger is.
		]]
		onDiveClicked()
	elseif actionType == "Shoot" then
		--[[
			The HUD has advertised a keeper "kick long" on this key for some time
			while nothing was bound to it. This is that control: a drop kick,
			available only with the ball in hand, which is when a keeper can
			actually take one.
		]]
		if GoalkeeperController.IsHolding() then
			send("DropKick")
		end
	elseif actionType == "GroundPass" or actionType == "LobPass" or actionType == "ThroughPass" then
		if GoalkeeperController.IsHolding() then
			send("Distribute")
		end
	end
end

--[[
	Goalkeeper movement state, for the locomotion pipeline.

	NO POSITIONING ASSISTANCE. A HUMAN KEEPER STEERS THEMSELVES.

	This used to drift the player toward the server's published resting position
	whenever they were not actively steering. It was bounded and overridable, but
	a player standing still on purpose is making a goalkeeping decision -- angle,
	depth, whether to hold the line for a cross -- and quietly walking them
	somewhere else overrules the one thing the role is about. Removed at the
	player's request, and it is the right call: positioning IS goalkeeping, so
	assisting it is assisting the skill rather than the execution (AGENTS.md
	§2, §23).

	`RestingPosition` is still published by the server and still used by the AI
	keeper, which genuinely needs somewhere to stand.

	A DIVE IS STILL FROZEN. HOLDING IS NOT.

	A dive is committed movement the server launched; steering it would fight the
	server for the same character. Holding was frozen too, on the grounds that it
	is "stationary by definition" -- which is simply not football. A keeper who
	has caught the ball walks out of their six-yard box, carries it to the edge
	and then throws or kicks. Being unable to move at all while holding is the
	bug the player reported, and this is its whole cause: `Frozen` here becomes
	`Vector3.zero` in MovementController's assist, so every input was discarded.

	`GoalkeeperService.updateHeldBall` pins the football to the keeper's own root
	every frame, so it travels with them correctly while they walk.
]]
function GoalkeeperController.GetAssistState()
	if not GoalkeeperController.IsActive() then
		return nil
	end
	if not character then
		return nil
	end
	if GoalkeeperController.IsDiving() then
		return { Frozen = true }
	end
	--[[
		Deliberately a table with no target: a keeper neither presses nor chases
		loose balls like an outfielder, and MovementController uses the presence
		of this state to suppress both. Returning nil would hand the keeper the
		outfield press assist instead of removing assistance altogether.
	]]
	return {}
end

local diveVelocityConnection: RBXScriptConnection? = nil

local function bindCharacter(model: Model)
	character = model
	rootPart = model:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if diveVelocityConnection then
		diveVelocityConnection:Disconnect()
	end
	diveVelocityConnection = model
		:GetAttributeChangedSignal(GoalkeeperConfig.Attributes.DiveVelocity)
		:Connect(onDiveVelocityChanged)
	-- A launch published before this connected still has to land.
	onDiveVelocityChanged()
end

function GoalkeeperController.Initialize()
	if initialized then
		return
	end
	initialized = true

	local remotes = ReplicatedStorage:WaitForChild(FootballActionConfig.RemotesFolderName, 20)
	if remotes then
		local remote = remotes:WaitForChild(GoalkeeperConfig.ActionRemoteName, 20)
		if remote and remote:IsA("RemoteEvent") then
			actionRemote = remote
		end
	end
	if not actionRemote then
		warn(string.format(
			"%s[Client][GK] %s remote unavailable; goalkeeper actions are disabled",
			GameConfig.LogPrefix,
			GoalkeeperConfig.ActionRemoteName
		))
	end

	if localPlayer.Character then
		bindCharacter(localPlayer.Character)
	end
	table.insert(connections, localPlayer.CharacterAdded:Connect(bindCharacter))
	table.insert(connections, InputController.GetFootballActionEvent().Event:Connect(onFootballAction))

	--[[
		Left mouse click dives. Bound here rather than through the football-action
		layer because it belongs to one role only: an outfielder's left click is
		not a dive, and routing it through the shared action set would mean every
		player carrying a binding that does nothing for them.

		`GameProcessed` is respected so clicking a HUD button never dives.
	]]
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onDiveClicked()
			return
		end
		--[[
			R: HANDS ON, HANDS OFF.

			A keeper holding the ball has only one way to continue -- throw or
			kick it away -- and no way to simply put it down and play it with
			their feet, which is an ordinary thing to want: carrying it to the
			edge of the box and passing short, or dropping it to take a kick
			rather than a throw.

			So R is the toggle. With the ball in hand it drops it at the
			keeper's feet; with a loose ball within gathering range it picks it
			up. One key, because it is one decision -- whether this is a
			hands ball or a feet ball -- and the answer is always the opposite
			of what is currently true.

			The server owns both halves: `Release` refuses if this keeper is not
			the holder, and `Hold` refuses outside the penalty area, so the
			handling law still decides whether a pickup is legal.
		]]
		if input.KeyCode == Enum.KeyCode.R then
			send(if GoalkeeperController.IsHolding() then "DropBall" else "PickUpBall")
		end
	end))

	MovementController.SetGoalkeeperStateProvider(GoalkeeperController.GetAssistState)
	log("human goalkeeper controls ready (dive = tackle input, throw = pass input)")
end

function GoalkeeperController.Stop()
	if not initialized then
		return
	end
	initialized = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	MovementController.SetGoalkeeperStateProvider(nil)
	character = nil
	rootPart = nil
end

return GoalkeeperController
