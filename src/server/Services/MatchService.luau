local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchConfig = require(Shared.Config.MatchConfig)

--[[
	Server-authoritative match lifecycle.

	Idle → WaitingForPlayers → Starting → Playing

	AI, the match clock and tackling all consult IsPlaying(). Nothing that can
	affect the football is permitted before Playing, so a footballer cannot be
	contested while its controller is still loading.
]]
local MatchService = {}

local initialized = false
local folder: Folder? = nil
local readyRemote: RemoteEvent? = nil
local startRequestRemote: RemoteEvent? = nil
local state = MatchConfig.States.Idle
local currentMode: string? = nil
local participants: { [Player]: boolean } = {}
local readyPlayers: { [Player]: boolean } = {}
local startedAt = 0
local waitingSince = 0
local startToken = 0
local stateChangedEvent = Instance.new("BindableEvent")
local matchStartedEvent = Instance.new("BindableEvent")

local function log(message: string)
	print(string.format("%s[Match] %s", GameConfig.LogPrefix, message))
end

local function publish()
	if not folder then
		return
	end
	folder:SetAttribute(MatchConfig.StateAttributeName, state)
	folder:SetAttribute(MatchConfig.StartedAtAttributeName, startedAt)
	folder:SetAttribute(MatchConfig.ModeAttributeName, currentMode)
end

local function setState(nextState: string)
	if state == nextState then
		return
	end
	state = nextState
	publish()
	stateChangedEvent:Fire(state)
	log(string.format("State -> %s", state))
end

local function countParticipants(): (number, number)
	local total = 0
	local ready = 0
	for player in participants do
		if player.Parent then
			total += 1
			if readyPlayers[player] then
				ready += 1
			end
		end
	end
	return total, ready
end

local function beginPlaying(token: number)
	if token ~= startToken or state ~= MatchConfig.States.Starting then
		return
	end
	startedAt = Workspace:GetServerTimeNow()
	setState(MatchConfig.States.Playing)
end

-- Readiness only moves the match to ReadyToStart. Kick-off is a deliberate
-- player action, so nothing begins on a timer.
local function tryAdvanceToReady()
	if state ~= MatchConfig.States.WaitingForPlayers then
		return
	end
	local total, ready = countParticipants()
	if total == 0 then
		return
	end
	local timedOut = waitingSince > 0 and os.clock() - waitingSince >= MatchConfig.ClientReadyTimeout
	if ready < total and not timedOut then
		return
	end
	if timedOut and ready < total then
		log(string.format("Client readiness timed out; offering start with %d/%d ready", ready, total))
	end
	setState(MatchConfig.States.ReadyToStart)
end

-- Fired when a participant presses START MATCH. The whistle blows here, not
-- when the clients merely finished loading.
local function requestStart(player: Player?): boolean
	if state ~= MatchConfig.States.ReadyToStart then
		return false
	end
	if player and not participants[player] then
		return false
	end

	startToken += 1
	local token = startToken
	setState(MatchConfig.States.Starting)
	log(string.format("Kick-off requested by %s", if player then player.Name else "server"))
	matchStartedEvent:Fire({
		Mode = currentMode,
		PresentationSeconds = MatchConfig.StartPresentationSeconds,
		RequestedBy = player,
	})
	task.delay(MatchConfig.StartPresentationSeconds, function()
		beginPlaying(token)
	end)
	return true
end

function MatchService.Initialize()
	if initialized then
		return
	end
	initialized = true

	folder = ReplicatedStorage:FindFirstChild(MatchConfig.FolderName) :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = MatchConfig.FolderName
		folder.Parent = ReplicatedStorage
	end

	local existing = folder:FindFirstChild(MatchConfig.ReadyRemoteName)
	if existing and existing:IsA("RemoteEvent") then
		readyRemote = existing
	else
		local remote = Instance.new("RemoteEvent")
		remote.Name = MatchConfig.ReadyRemoteName
		remote.Parent = folder
		readyRemote = remote
	end

	local existingStart = folder:FindFirstChild(MatchConfig.StartRequestRemoteName)
	if existingStart and existingStart:IsA("RemoteEvent") then
		startRequestRemote = existingStart
	else
		local remote = Instance.new("RemoteEvent")
		remote.Name = MatchConfig.StartRequestRemoteName
		remote.Parent = folder
		startRequestRemote = remote
	end

	readyRemote.OnServerEvent:Connect(function(player)
		if not participants[player] then
			return
		end
		if readyPlayers[player] then
			return
		end
		readyPlayers[player] = true
		local total, ready = countParticipants()
		log(string.format("Client ready %s (%d/%d)", player.Name, ready, total))
		tryAdvanceToReady()
	end)

	startRequestRemote.OnServerEvent:Connect(function(player)
		requestStart(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		MatchService.RemoveParticipant(player)
	end)

	publish()
end

-- Called when a player commits to a mode. A player joining an already-running
-- match becomes a participant but does not reset the match for everyone.
function MatchService.AddParticipant(player: Player, modeId: string)
	participants[player] = true
	readyPlayers[player] = nil
	currentMode = modeId

	if state == MatchConfig.States.Playing
		or state == MatchConfig.States.Starting
		or state == MatchConfig.States.ReadyToStart
	then
		return
	end
	if state == MatchConfig.States.Idle then
		waitingSince = os.clock()
		setState(MatchConfig.States.WaitingForPlayers)
	end
end

function MatchService.RemoveParticipant(player: Player)
	if not participants[player] then
		return
	end
	participants[player] = nil
	readyPlayers[player] = nil

	local total = countParticipants()
	if total == 0 then
		startToken += 1
		currentMode = nil
		startedAt = 0
		waitingSince = 0
		setState(MatchConfig.States.Idle)
		return
	end
	-- A departing loader must not keep the rest of the match waiting.
	tryAdvanceToReady()
end

function MatchService.Update()
	if state == MatchConfig.States.WaitingForPlayers then
		tryAdvanceToReady()
	end
end

function MatchService.RequestStart(player: Player?): boolean
	return requestStart(player)
end

function MatchService.IsPlaying(): boolean
	return state == MatchConfig.States.Playing
end

-- Which mode the current session is running. Services read this to ask the
-- mode what it uses, rather than hardcoding mode ids of their own.
function MatchService.GetMode(): string?
	return currentMode
end

function MatchService.GetState(): string
	return state
end

function MatchService.GetStartedAt(): number
	return startedAt
end

function MatchService.GetStateChangedEvent(): BindableEvent
	return stateChangedEvent
end

function MatchService.GetMatchStartedEvent(): BindableEvent
	return matchStartedEvent
end

return MatchService
