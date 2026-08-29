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
	return model:GetAttribute(GoalkeeperConfig.RoleAttributeName) == GoalkeeperConfig.Role
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

local function send(action: string)
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
	remote:FireServer(action, getAimDirection())
end

--[[
	The input reroute.

	Tackle -> dive, Pass -> throw. Both are the actions those keys already mean
	in football terms for the role the player is actually playing, which is why
	no new binding is introduced: an outfielder's "win the ball back" and a
	keeper's "go and get it" are the same intent.
]]
local function onFootballAction(payload)
	if not GoalkeeperController.IsActive() or payload.Phase ~= "Pressed" then
		return
	end
	local actionType = payload.ActionType
	if actionType == "Tackle" then
		send("Dive")
	elseif actionType == "GroundPass" or actionType == "LobPass" or actionType == "ThroughPass" then
		if GoalkeeperController.IsHolding() then
			send("Distribute")
		end
	end
end

--[[
	Positioning assistance.

	Returned in the same shape MovementController's press assist uses, so the
	locomotion pipeline treats it as one more source of assisted intent rather
	than as a special goalkeeper movement mode.

	Three rules make this assistance rather than automation:

	  * It only acts when the player is NOT steering. Any real input wins
	    outright, so coming for a cross or narrowing the angle yourself is always
	    available.
	  * It stops inside a deadzone, so the keeper settles instead of jittering on
	    the spot around a target that moves with the ball.
	  * It gives up beyond a distance. A keeper who has run to the halfway line
	    has made a decision, and dragging them home would be the game overruling
	    it.
]]
function GoalkeeperController.GetAssistState()
	if not GoalkeeperController.IsActive() then
		return nil
	end
	local model = character
	if not model then
		return nil
	end
	if GoalkeeperController.IsDiving() or GoalkeeperController.IsHolding() then
		-- Diving is server-driven; holding is stationary by definition.
		return { Frozen = true }
	end
	local resting = model:GetAttribute(GoalkeeperConfig.Attributes.RestingPosition)
	if typeof(resting) ~= "Vector3" then
		return nil
	end
	return { TargetPosition = resting, Config = GoalkeeperConfig.Human }
end

local function bindCharacter(model: Model)
	character = model
	rootPart = model:WaitForChild("HumanoidRootPart", 5) :: BasePart?
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
