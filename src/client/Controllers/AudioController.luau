local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local FootballActionConfig = require(ReplicatedStorage.Shared.Config.FootballActionConfig)
local GoalConfig = require(ReplicatedStorage.Shared.Config.GoalConfig)
local ControlledBallController = require(script.Parent.ControlledBallController)

local AudioController = {}
local initialized = false
local selectedTrackIndex = 2
--[[
	Background music on/off.

	Kept separate from track selection: turning music off must survive changing
	tracks, and choosing a track must not silently switch music back on.
]]
local musicEnabled = true
local musicChangedEvent = Instance.new("BindableEvent")
local menuSound: Sound? = nil
local crowdSound: Sound? = nil
local clickSound: Sound? = nil
local dribbleTouchSound: Sound? = nil
local passSound: Sound? = nil
local shootSound: Sound? = nil
local goalNetSound: Sound? = nil
local matchWhistleSound: Sound? = nil
local goalCommentarySound: Sound? = nil
local dribbleConnection: RBXScriptConnection? = nil
local goalConnection: RBXScriptConnection? = nil

local function validAssetId(value): boolean
	return AudioConfig.NormalizeAssetId(value) ~= ""
end

local function createSound(name: string, assetId: string, looped: boolean): Sound?
	if not validAssetId(assetId) then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = AudioConfig.NormalizeAssetId(assetId)
	sound.Looped = looped
	sound.Volume = 0
	sound.Parent = SoundService
	task.spawn(function()
		local ok, failure = pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ sound })
		end)
		if not ok then
			warn(string.format("[Beyond90][Client][Audio] Failed to load %s (%s): %s", name, sound.SoundId, tostring(failure)))
		else
			print(string.format("[Beyond90][Client][Audio] Loaded %s asset=%s", name, sound.SoundId))
		end
	end)
	return sound
end

local function configureEffect(sound: Sound?, definition)
	if not sound then return end
	sound.Volume = definition.Volume or 0.5
	sound.PlaybackSpeed = definition.PlaybackSpeed or 1
end

local function playEffect(sound: Sound?)
	if not sound then return end
	sound.TimePosition = 0
	sound:Play()
end

local function fade(sound: Sound?, target: number, stopAfter: boolean?)
	if not sound then return end
	if target > 0 and not sound.IsPlaying then sound:Play() end
	local tween = TweenService:Create(sound, TweenInfo.new(AudioConfig.FadeSeconds), { Volume = target })
	tween:Play()
	if stopAfter then
		task.delay(AudioConfig.FadeSeconds + 0.05, function()
			if sound and sound.Parent and sound.Volume <= 0.01 then sound:Stop() end
		end)
	end
end

local function rebuildMenuSound(playAfter: boolean)
	if menuSound then menuSound:Destroy() end
	local track = AudioConfig.MenuTracks[selectedTrackIndex]
	menuSound = track and createSound("Beyond90MenuMusic", track.AssetId, true) or nil
	if playAfter and musicEnabled then fade(menuSound, AudioController.GetMusicVolume()) end
end

function AudioController.Initialize()
	if initialized then return end
	initialized = true
	rebuildMenuSound(false)
	local crowd = AudioConfig.Crowd.Base
	crowdSound = createSound("Beyond90CrowdAmbience", crowd.AssetId, true)
	clickSound = createSound("Beyond90UIClick", AudioConfig.UI.Click.AssetId, false)
	if clickSound then clickSound.Volume = AudioConfig.UI.Click.Volume end
	dribbleTouchSound = createSound("Beyond90DribbleTouch", AudioConfig.Gameplay.DribbleTouch.AssetId, false)
	passSound = createSound("Beyond90PassKick", AudioConfig.Gameplay.Pass.AssetId, false)
	shootSound = createSound("Beyond90ShotKick", AudioConfig.Gameplay.Shoot.AssetId, false)
	goalNetSound = createSound("Beyond90GoalNet", AudioConfig.Gameplay.GoalNet.AssetId, false)
	goalCommentarySound = createSound("Beyond90GoalCommentary", AudioConfig.Gameplay.GoalCommentary.AssetId, false)
	matchWhistleSound = createSound("Beyond90MatchStartWhistle", AudioConfig.Match.StartWhistle.AssetId, false)
	configureEffect(matchWhistleSound, AudioConfig.Match.StartWhistle)
	configureEffect(dribbleTouchSound, AudioConfig.Gameplay.DribbleTouch)
	configureEffect(passSound, AudioConfig.Gameplay.Pass)
	configureEffect(shootSound, AudioConfig.Gameplay.Shoot)
	configureEffect(goalNetSound, AudioConfig.Gameplay.GoalNet)
	configureEffect(goalCommentarySound, AudioConfig.Gameplay.GoalCommentary)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild(FootballActionConfig.RemotesFolderName, 10)
		local goalRemote = remotes and remotes:WaitForChild(GoalConfig.GoalScoredRemoteName, 10)
		if initialized and goalRemote and goalRemote:IsA("RemoteEvent") then
			goalConnection = goalRemote.OnClientEvent:Connect(function()
				playEffect(goalNetSound)
				playEffect(goalCommentarySound)
			end)
		end
	end)
end

function AudioController.EnterMenu()
	fade(crowdSound, 0, true)
	if musicEnabled then
		fade(menuSound, AudioController.GetMusicVolume())
	else
		fade(menuSound, 0, true)
	end
end

function AudioController.EnterGameplay()
	fade(menuSound, 0, true)
	fade(crowdSound, AudioConfig.Crowd.Base.Volume)
	if not dribbleConnection then
		dribbleConnection = ControlledBallController.GetDribbleTouchEvent().Event:Connect(function()
			playEffect(dribbleTouchSound)
		end)
	end
end

function AudioController.BeginTransition()
	fade(menuSound, 0, true)
	fade(crowdSound, 0, true)
	if dribbleConnection then
		dribbleConnection:Disconnect()
		dribbleConnection = nil
	end
end

function AudioController.SetMenuTrack(index: number)
	selectedTrackIndex = math.clamp(math.floor(index), 1, #AudioConfig.MenuTracks)
	rebuildMenuSound(true)
end

function AudioController.GetMenuTrackIndex(): number
	return selectedTrackIndex
end

--[[
	Background music toggle.

	Only the menu music is affected. Crowd ambience, the whistle and every
	gameplay SFX are match audio, not background music, and stay as they are.
]]
--[[
	The player's chosen menu-music level, 0-1.

	Read through one accessor so nothing takes the raw attribute and forgets to
	clamp it, and so the default lives in config rather than being repeated as a
	literal at each call site -- which is how the old hardcoded 0.5 ended up
	being the de facto mix.
]]
function AudioController.GetMusicVolume(): number
	local stored = Players.LocalPlayer:GetAttribute(AudioConfig.Music.AttributeName)
	if typeof(stored) ~= "number" then
		return AudioConfig.Music.DefaultVolume
	end
	return math.clamp(stored, AudioConfig.Music.Minimum, AudioConfig.Music.Maximum)
end

--[[
	Set the level, and hear it immediately.

	A volume slider that only takes effect on the next track is not a volume
	slider, so this applies straight to the live sound rather than waiting for
	the next fade -- but only while the menu music should actually be audible,
	so it can never resurrect music the player turned off or override the
	fade-out on the way into a match.
]]
function AudioController.SetMusicVolume(volume: number)
	if typeof(volume) ~= "number" then
		return
	end
	local clamped = math.clamp(volume, AudioConfig.Music.Minimum, AudioConfig.Music.Maximum)
	Players.LocalPlayer:SetAttribute(AudioConfig.Music.AttributeName, clamped)
	if musicEnabled
		and menuSound
		and Players.LocalPlayer:GetAttribute("Beyond90ClientExperienceState") ~= "Gameplay"
	then
		menuSound.Volume = clamped
		if clamped > 0 and not menuSound.IsPlaying then
			menuSound:Play()
		end
	end
	musicChangedEvent:Fire(musicEnabled)
end

function AudioController.SetMusicEnabled(enabled: boolean)
	enabled = enabled == true
	if musicEnabled == enabled then
		return
	end
	musicEnabled = enabled
	if enabled then
		-- Only resume if we are actually on a menu screen; entering gameplay
		-- fades this out again on its own.
		if Players.LocalPlayer:GetAttribute("Beyond90ClientExperienceState") ~= "Gameplay" then
			fade(menuSound, AudioController.GetMusicVolume())
		end
	else
		fade(menuSound, 0, true)
	end
	musicChangedEvent:Fire(enabled)
end

function AudioController.IsMusicEnabled(): boolean
	return musicEnabled
end

function AudioController.GetMusicChangedEvent(): BindableEvent
	return musicChangedEvent
end

-- Only MatchPresentationController calls this, so the whistle can never be
-- doubled by a second system reacting to the same match-start event.
function AudioController.PlayMatchStartWhistle()
	playEffect(matchWhistleSound)
end

function AudioController.PlayClick()
	playEffect(clickSound)
end

function AudioController.PlayFootballKick(actionType: string)
	if actionType == "Shoot" or actionType == "Clearance" then
		playEffect(shootSound)
	elseif actionType == "GroundPass" or actionType == "ThroughPass" or actionType == "LobPass" then
		playEffect(passSound)
	end
end

function AudioController.Destroy()
	if dribbleConnection then dribbleConnection:Disconnect() end
	dribbleConnection = nil
	if goalConnection then goalConnection:Disconnect() end
	goalConnection = nil
	for _, sound in { menuSound, crowdSound, clickSound, dribbleTouchSound, passSound, shootSound, goalNetSound, goalCommentarySound } do
		if sound then sound:Destroy() end
	end
	menuSound, crowdSound, clickSound = nil, nil, nil
	dribbleTouchSound, passSound, shootSound = nil, nil, nil
	goalNetSound, goalCommentarySound = nil, nil
	initialized = false
end

return AudioController
