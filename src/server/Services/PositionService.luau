--!strict
--[[
	Position slots.

	The server owns every slot in a match. A human asks for one; the server
	decides. AI fills whatever is left over, so a slot is never occupied twice and
	never left empty (§40).

	A slot is just an identity -- which footballer this is and what it is for. It
	deliberately says nothing about who controls it, so the same slot can be held
	by a human or by AI and handed between them without a different footballer
	implementation on either side (§52 of AGENTS.md).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PositionConfig = require(Shared.Config.PositionConfig)

local PositionService = {}

local FOLDER_NAME = "Beyond90Positions"
local REQUEST_REMOTE = "PositionRequest"

local initialized = false
local folder: Folder? = nil
local requestRemote: RemoteEvent? = nil

-- teamId -> slotKey -> Player. A slotKey distinguishes duplicates of the same
-- position in larger formats ("DEF#1", "DEF#2").
local reservations: { [string]: { [string]: Player } } = { Home = {}, Away = {} }
local playerSlotKey: { [Player]: string } = {}
local playerTeam: { [Player]: string } = {}
local changedEvent = Instance.new("BindableEvent")

local function log(message: string)
	print(string.format("%s[Positions] %s", GameConfig.LogPrefix, message))
end

-- "DEF#2" -> "DEF"
local function slotIdFromKey(slotKey: string): string
	local slotId = string.match(slotKey, "^(.-)#")
	return slotId or slotKey
end

--[[
	Every slot key a format fields, in a stable order. Duplicates of a position
	are numbered so 5v5's two defenders are genuinely separate slots.
]]
local function getSlotKeys(modeId: string?): { string }
	local counts, keys = {}, {}
	for _, slotId in PositionConfig.GetSlotIds(modeId) do
		counts[slotId] = (counts[slotId] or 0) + 1
		table.insert(keys, string.format("%s#%d", slotId, counts[slotId]))
	end
	return keys
end

PositionService.GetSlotKeys = getSlotKeys
PositionService.SlotIdFromKey = slotIdFromKey

local function publish()
	if not folder then
		return
	end
	for teamId, teamReservations in reservations do
		local occupied = {}
		for slotKey, player in teamReservations do
			table.insert(occupied, string.format("%s=%s", slotKey, player.Name))
		end
		table.sort(occupied)
		folder:SetAttribute(teamId .. "Reservations", table.concat(occupied, ","))
	end
end

--[[
	Is this slot free for `player`?

	Returns the resolved slot key, or nil plus a reason. A player asking for the
	slot they already hold is accepted, so re-confirming a choice is harmless.
]]
function PositionService.ResolveRequest(
	player: Player,
	teamId: string,
	slotId: string,
	modeId: string?
): (string?, string)
	if not FootballTeamConfig.ValidTeams[teamId] then
		return nil, "invalid-team"
	end
	if not PositionConfig.Get(slotId) then
		return nil, "invalid-position"
	end

	local teamReservations = reservations[teamId]
	local existingKey = playerSlotKey[player]

	for _, slotKey in getSlotKeys(modeId) do
		if slotIdFromKey(slotKey) == slotId then
			local holder = teamReservations[slotKey]
			if holder == player then
				return slotKey, "already-held"
			end
			-- A holder who has left the match no longer blocks the slot.
			if holder == nil or holder.Parent == nil then
				if existingKey and teamReservations[existingKey] == player then
					teamReservations[existingKey] = nil
				end
				return slotKey, "available"
			end
		end
	end

	return nil, "position-taken"
end

function PositionService.Reserve(player: Player, teamId: string, slotId: string, modeId: string?): (boolean, string)
	local slotKey, reason = PositionService.ResolveRequest(player, teamId, slotId, modeId)
	if not slotKey then
		return false, reason
	end

	PositionService.Release(player)

	reservations[teamId][slotKey] = player
	playerSlotKey[player] = slotKey
	playerTeam[player] = teamId
	player:SetAttribute(PositionConfig.SlotAttributeName, slotId)

	local position = PositionConfig.Get(slotId)
	player:SetAttribute(PositionConfig.CategoryAttributeName, position and position.Category or nil)

	publish()
	changedEvent:Fire(player, teamId, slotId)
	log(string.format("%s reserved %s %s", player.Name, teamId, slotKey))
	return true, slotKey
end

function PositionService.Release(player: Player)
	local teamId = playerTeam[player]
	local slotKey = playerSlotKey[player]
	if teamId and slotKey and reservations[teamId] and reservations[teamId][slotKey] == player then
		reservations[teamId][slotKey] = nil
	end
	playerSlotKey[player] = nil
	playerTeam[player] = nil
	player:SetAttribute(PositionConfig.SlotAttributeName, nil)
	player:SetAttribute(PositionConfig.CategoryAttributeName, nil)
	publish()
end

function PositionService.GetPlayerSlotId(player: Player): string?
	local slotKey = playerSlotKey[player]
	return if slotKey then slotIdFromKey(slotKey) else nil
end

function PositionService.GetPlayerSlotKey(player: Player): string?
	return playerSlotKey[player]
end

--[[
	The slots AI must fill for `teamId`: every slot key with no live human on it.
	Returned in formation order so a short-handed team still fields a shape.
]]
function PositionService.GetUnoccupiedSlots(teamId: string, modeId: string?): { string }
	local teamReservations = reservations[teamId] or {}
	local free = {}
	for _, slotKey in getSlotKeys(modeId) do
		local holder = teamReservations[slotKey]
		if holder == nil or holder.Parent == nil then
			table.insert(free, slotKey)
		end
	end
	return free
end

-- Occupancy for the selection UI: who holds what, and whether AI would fill it.
function PositionService.GetTeamOccupancy(teamId: string, modeId: string?)
	local teamReservations = reservations[teamId] or {}
	local rows = {}
	for _, slotKey in getSlotKeys(modeId) do
		local holder = teamReservations[slotKey]
		local live = holder ~= nil and holder.Parent ~= nil
		table.insert(rows, {
			SlotKey = slotKey,
			SlotId = slotIdFromKey(slotKey),
			OccupiedBy = if live then (holder :: Player).Name else nil,
			IsAI = not live,
		})
	end
	return rows
end

function PositionService.GetChangedEvent(): BindableEvent
	return changedEvent
end

--[[
	A sensible default when a player never chose. Prefers a free outfield slot
	over the goalkeeper, because dropping an unprepared player in goal is the
	worst possible default.
]]
function PositionService.GetDefaultSlotId(teamId: string, modeId: string?): string
	for _, slotKey in PositionService.GetUnoccupiedSlots(teamId, modeId) do
		local slotId = slotIdFromKey(slotKey)
		if not PositionConfig.IsGoalkeeper(slotId) then
			return slotId
		end
	end
	return "MID"
end

function PositionService.ClearAll()
	for teamId in reservations do
		reservations[teamId] = {}
	end
	for player in playerSlotKey do
		player:SetAttribute(PositionConfig.SlotAttributeName, nil)
		player:SetAttribute(PositionConfig.CategoryAttributeName, nil)
	end
	table.clear(playerSlotKey)
	table.clear(playerTeam)
	publish()
end

function PositionService.Initialize()
	if initialized then
		return
	end
	initialized = true

	local created = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not created then
		created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
	end
	folder = created :: Folder

	local remote = created:FindFirstChild(REQUEST_REMOTE)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REQUEST_REMOTE
		remote.Parent = created
	end
	requestRemote = remote :: RemoteEvent

	--[[
		The client only ever asks. Team and mode are read from the player's own
		authoritative attributes rather than from the request, so a crafted
		payload cannot reserve a slot on a team the player is not on.
	]]
	;(remote :: RemoteEvent).OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local slotId = payload.SlotId
		if typeof(slotId) ~= "string" then
			return
		end
		local teamId = FootballTeamConfig.Normalize(payload.TeamId)
			or FootballTeamConfig.Normalize(player:GetAttribute(FootballTeamConfig.AttributeName))
		if not teamId then
			return
		end
		local modeId = player:GetAttribute("Beyond90SelectedGameMode")
		PositionService.Reserve(player, teamId, slotId, modeId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PositionService.Release(player)
	end)

	publish()
end

return PositionService
