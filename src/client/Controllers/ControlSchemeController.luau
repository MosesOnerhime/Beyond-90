--!strict
--[[
	Owns the player's chosen control scheme.

	The choice is mirrored onto the LocalPlayer as an attribute so any UI can read
	it without depending on this module, and a BindableEvent lets the HUD and menu
	re-render the moment it changes.

	Touch devices are not asked: a touch device is touch, and the on-screen
	controls are the only ones it has.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ControlSchemeConfig = require(Shared.Config.ControlSchemeConfig)
local GameConfig = require(Shared.Config.GameConfig)

local ControlSchemeController = {}

local Schemes = ControlSchemeConfig.Schemes

local localPlayer = Players.LocalPlayer
local initialized = false
local scheme = Schemes.Keyboard
local chosen = false
local changedEvent = Instance.new("BindableEvent")

local function log(message: string)
	print(string.format("%s[Client][Controls] %s", GameConfig.LogPrefix, message))
end

local function publish()
	localPlayer:SetAttribute(ControlSchemeConfig.AttributeName, scheme)
	localPlayer:SetAttribute(ControlSchemeConfig.ChosenAttributeName, chosen)
	changedEvent:Fire(scheme)
end

function ControlSchemeController.Get(): string
	return scheme
end

function ControlSchemeController.IsGamepad(): boolean
	return scheme == Schemes.Gamepad
end

function ControlSchemeController.IsTouch(): boolean
	return scheme == Schemes.Touch
end

function ControlSchemeController.HasChosen(): boolean
	return chosen
end

function ControlSchemeController.GetChangedEvent(): BindableEvent
	return changedEvent
end

--[[
	Set the scheme. `explicit` marks it as the player's own answer, which is what
	stops the prompt being asked again.
]]
function ControlSchemeController.Set(nextScheme: string, explicit: boolean?)
	local normalized = ControlSchemeConfig.Normalize(nextScheme)
	local changed = normalized ~= scheme
	scheme = normalized
	if explicit then
		chosen = true
	end
	publish()
	if changed then
		log(string.format("Scheme -> %s%s", scheme, if explicit then " (chosen)" else ""))
	end
end

--[[
	Should the one-time prompt be shown?

	Touch never asks. Desktop always asks once, whether or not a controller is
	plugged in -- a player with a controller connected may well be on the keyboard,
	and guessing that wrong is exactly the problem this replaces.
]]
function ControlSchemeController.ShouldPrompt(): boolean
	if ControlSchemeConfig.Prompt.Enabled ~= true then
		return false
	end
	if scheme == Schemes.Touch then
		return false
	end
	return not chosen
end

-- The prompt table for the current scheme, e.g. { Select = "A", Back = "B" }.
function ControlSchemeController.GetMenuPrompt()
	return ControlSchemeConfig.MenuPrompts[scheme] or ControlSchemeConfig.MenuPrompts.Keyboard
end

function ControlSchemeController.Initialize()
	if initialized then
		return
	end
	initialized = true

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		scheme = Schemes.Touch
		-- A touch device has made its own choice by existing.
		chosen = true
	else
		scheme = Schemes.Keyboard
		chosen = false
	end
	publish()
	log(string.format("Initial scheme %s chosen=%s", scheme, tostring(chosen)))
end

function ControlSchemeController.Destroy()
	initialized = false
end

return ControlSchemeController
