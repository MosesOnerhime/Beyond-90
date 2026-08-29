--!strict
--[[
	Client side of position selection.

	Asks the server for a slot and reads back who holds what. The client never
	decides anything -- PositionService validates and may refuse, and the UI
	simply shows the authoritative occupancy.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PositionConfig = require(Shared.Config.PositionConfig)

local PositionController = {}

local FOLDER_NAME = "Beyond90Positions"
local REQUEST_REMOTE = "PositionRequest"

local localPlayer = Players.LocalPlayer
local folder: Folder? = nil
local requestRemote: RemoteEvent? = nil

local function resolve()
	if folder and folder.Parent then
		return
	end
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder?
	requestRemote = folder and folder:FindFirstChild(REQUEST_REMOTE) :: RemoteEvent?
end

function PositionController.SelectPosition(teamId: string, slotId: string)
	resolve()
	if requestRemote then
		requestRemote:FireServer({ TeamId = teamId, SlotId = slotId })
		print(string.format("%s[Client][Positions] requested %s %s", GameConfig.LogPrefix, teamId, slotId))
	end
end

--[[
	Which positions on `teamId` are already held by another human.

	Returns slotId -> { Taken, OccupiedBy }. A slot the local player holds is not
	reported as taken, so re-opening the screen still shows their own choice as
	selectable.
]]
function PositionController.GetOccupancy(teamId: string, modeId: string?)
	resolve()
	local occupancy = {}
	if not folder then
		return occupancy
	end

	local encoded = folder:GetAttribute(teamId .. "Reservations")
	if typeof(encoded) ~= "string" or encoded == "" then
		return occupancy
	end

	for entry in string.gmatch(encoded, "[^,]+") do
		local slotKey, holderName = string.match(entry, "^(.-)=(.*)$")
		if slotKey and holderName then
			local slotId = string.match(slotKey, "^(.-)#") or slotKey
			if holderName ~= localPlayer.Name then
				occupancy[slotId] = { Taken = true, OccupiedBy = holderName }
			end
		end
	end

	return occupancy
end

function PositionController.GetLocalSlotId(): string?
	local slotId = localPlayer:GetAttribute(PositionConfig.SlotAttributeName)
	return if typeof(slotId) == "string" then slotId else nil
end

return PositionController
