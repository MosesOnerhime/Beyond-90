local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared.Config.AnimationConfig)
local AnimationRootMotion = require(Shared.Football.AnimationRootMotion)

local AIAnimationService = {}

local tracksByActor = {}
local rootMotionByActor = {}

local function loadTrack(animator: Animator, assetId: string, priority: Enum.AnimationPriority, looped: boolean)
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
	track.Looped = looped
	return track
end

function AIAnimationService.Register(actor)
	local animator = actor.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = actor.Humanoid
	end
	local assets = AnimationConfig.Assets
	local tracks = {
		Idle = loadTrack(animator, assets.Locomotion.OffBall.Idle, Enum.AnimationPriority.Idle, true),
		Jog = loadTrack(animator, assets.Locomotion.OffBall.Jog.Forward, Enum.AnimationPriority.Movement, true),
		Sprint = loadTrack(animator, assets.Locomotion.OffBall.Sprint.Forward, Enum.AnimationPriority.Movement, true),
		Receive = loadTrack(animator, assets.Actions.ReceivePass, Enum.AnimationPriority.Action, false),
		Pass = loadTrack(animator, assets.Actions.Pass, Enum.AnimationPriority.Action, false),
		Shoot = loadTrack(animator, assets.Actions.Shoot, Enum.AnimationPriority.Action, false),
		Heading = loadTrack(animator, assets.Actions.HeadingBall, AnimationConfig.Heading.Priority, false),
		-- The tackler's own clips. Empty ids load nothing and play nothing; see
		-- AnimationConfig.Actions.
		StandingTackle = loadTrack(animator, assets.Actions.StandingTackle, Enum.AnimationPriority.Action, false),
		SlideTackle = loadTrack(animator, assets.Actions.SlideTackle, Enum.AnimationPriority.Action, false),
		InjuredWalk = loadTrack(animator, assets.InjuredWalk, AnimationConfig.InjuredWalk.Priority, true),
		-- Tackle reactions.
		TackledNormal = loadTrack(animator, assets.Tackled.Normal, AnimationConfig.Tackled.Priority, false),
		TackledSlideFront = loadTrack(animator, assets.Tackled.SlideFromFront, AnimationConfig.Tackled.Priority, false),
		TackledSlideBack = loadTrack(animator, assets.Tackled.SlideFromBack, AnimationConfig.Tackled.Priority, false),
		Current = "",
	}

	-- Goalkeepers use their own idle/step vocabulary on top of the shared set.
	if actor.Position == "Goalkeeper" then
		local gk = assets.Goalkeeper
		local gkConfig = AnimationConfig.Goalkeeper
		tracks.KeeperIdle = loadTrack(animator, gk.Idle, gkConfig.IdlePriority, true)
		tracks.KeeperIdleWithBall = loadTrack(animator, gk.IdleWithBall, gkConfig.IdlePriority, true)
		tracks.KeeperCatchStanding = loadTrack(animator, gk.CatchStanding, gkConfig.ActionPriority, false)
		tracks.KeeperThrowPass = loadTrack(animator, gk.ThrowPass, gkConfig.ActionPriority, false)
		tracks.KeeperSideStep = loadTrack(animator, gk.SideStep, gkConfig.MovementPriority, true)
	end
	tracksByActor[actor] = tracks
	AIAnimationService.Update(actor, true)
end

local function playLocomotion(tracks, name: string, speed: number)
	if tracks.Current == name then
		local active = tracks[name]
		if active and name ~= "Idle" then
			active:AdjustSpeed(speed)
		end
		return
	end
	for _, trackName in { "Idle", "Jog", "Sprint" } do
		local track = tracks[trackName]
		if track and track.IsPlaying then
			track:Stop(0.12)
		end
	end
	local nextTrack = tracks[name]
	if nextTrack then
		nextTrack:Play(0.12, 1, speed)
	end
	tracks.Current = name
end

function AIAnimationService.Update(actor, force: boolean?)
	local tracks = tracksByActor[actor]
	if not tracks or not actor.RootPart or not actor.RootPart.Parent then
		return
	end
	local speed = Vector3.new(actor.RootPart.AssemblyLinearVelocity.X, 0, actor.RootPart.AssemblyLinearVelocity.Z).Magnitude
	local name = if speed < 1 then "Idle" else if speed >= 19 then "Sprint" else "Jog"
	if force then
		tracks.Current = ""
	end
	local playback = if name == "Sprint"
		then math.clamp(speed / 28, 0.55, 1.25)
		elseif name == "Jog"
		then math.clamp(speed / 14, 0.55, 1.6)
		else 1
	playLocomotion(tracks, name, playback)
end

local ROOT_MOTION_CLIPS = {
	TackledNormal = "NormalTackled",
	TackledSlideFront = "SlideTackledFromFront",
	TackledSlideBack = "SlideTackledFromBack",
	KeeperCatchStanding = "KeeperCatchStanding",
	KeeperThrowPass = "KeeperThrowPass",
	KeeperSideStep = "KeeperSideStep",
}

--[[
	Play an action clip and, where the clip implies bodily travel the animation
	cannot produce itself, start the matching root-motion compensation.
	`mirrored` flips a mirrorable clip (the keeper side-step moves right).
]]
function AIAnimationService.PlayAction(actor, actionName: string, mirrored: boolean?)
	local tracks = tracksByActor[actor]
	local track = tracks and tracks[actionName]
	if not track then
		return
	end
	local fadeIn = 0.05
	local rate = 1
	if actionName == "Heading" then
		fadeIn = AnimationConfig.Heading.FadeInTime
		rate = AnimationConfig.Heading.PlaybackRate
	elseif string.find(actionName, "Tackled", 1, true) then
		fadeIn = AnimationConfig.Tackled.FadeInTime
		rate = AnimationConfig.Tackled.PlaybackRate
	elseif string.find(actionName, "Keeper", 1, true) then
		fadeIn = AnimationConfig.Goalkeeper.FadeInTime
		rate = AnimationConfig.Goalkeeper.PlaybackRate
	end
	track:Play(fadeIn, 1, rate)

	local clipKey = ROOT_MOTION_CLIPS[actionName]
	if clipKey and AnimationConfig.RootMotion.Enabled == true then
		local spec = AnimationConfig.RootMotion.Clips[clipKey]
		local playback = AnimationRootMotion.Begin(spec, mirrored)
		if playback then
			rootMotionByActor[actor] = playback
		end
	end
end

-- Advance root-motion compensation. Called from the same bounded movement tick
-- as everything else, never its own loop.
function AIAnimationService.StepRootMotion(actor, deltaTime: number)
	local playback = rootMotionByActor[actor]
	if not playback then
		return
	end
	if not actor.RootPart or not actor.RootPart.Parent then
		rootMotionByActor[actor] = nil
		return
	end
	local offset = AnimationRootMotion.Step(playback, deltaTime, AnimationConfig.RootMotion)
	if not offset then
		rootMotionByActor[actor] = nil
		return
	end
	local world = AnimationRootMotion.ToWorldOffset(actor.RootPart, offset)
	actor.RootPart.CFrame = actor.RootPart.CFrame + world - (playback.AppliedWorld or Vector3.zero)
	playback.AppliedWorld = world
end

--[[
	Goalkeeper locomotion. Idle / idle-with-ball / lateral guard step, chosen from
	the keeper's actual movement rather than from input.
]]
function AIAnimationService.UpdateGoalkeeper(actor, holdingBall: boolean, deltaTime: number)
	local tracks = tracksByActor[actor]
	if not tracks or not tracks.KeeperIdle or not actor.RootPart or not actor.RootPart.Parent then
		return
	end
	local gkConfig = AnimationConfig.Goalkeeper
	local velocity = actor.RootPart.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local lateralSpeed = horizontal:Dot(actor.RootPart.CFrame.RightVector)

	local desired
	if math.abs(lateralSpeed) >= gkConfig.SideStepMinimumSpeed and tracks.KeeperSideStep then
		desired = "KeeperSideStep"
	elseif holdingBall and tracks.KeeperIdleWithBall then
		desired = "KeeperIdleWithBall"
	else
		desired = "KeeperIdle"
	end

	if tracks.CurrentKeeper ~= desired then
		for _, name in { "KeeperIdle", "KeeperIdleWithBall", "KeeperSideStep" } do
			local track = tracks[name]
			if track and track.IsPlaying then
				track:Stop(gkConfig.FadeOutTime)
			end
		end
		local nextTrack = tracks[desired]
		if nextTrack then
			nextTrack:Play(gkConfig.FadeInTime, 1, gkConfig.PlaybackRate)
		end
		tracks.CurrentKeeper = desired
	end

	-- The source side-step travels left; mirror it when moving right so the
	-- footwork matches the direction the keeper is actually going.
	if desired == "KeeperSideStep" then
		local shouldMirror = lateralSpeed > 0
		local playback = rootMotionByActor[actor]
		if not playback or playback.Mirrored ~= shouldMirror then
			local spec = AnimationConfig.RootMotion.Clips.KeeperSideStep
			rootMotionByActor[actor] = AnimationRootMotion.Begin(spec, shouldMirror)
		end
	end

	AIAnimationService.StepRootMotion(actor, deltaTime)
end

function AIAnimationService.Unregister(actor)
	local tracks = tracksByActor[actor]
	if not tracks then
		return
	end
	for _, value in tracks do
		if typeof(value) == "Instance" and value:IsA("AnimationTrack") then
			value:Stop(0)
			value:Destroy()
		end
	end
	tracksByActor[actor] = nil
	rootMotionByActor[actor] = nil
end

function AIAnimationService.Clear()
	local actors = {}
	for actor in tracksByActor do
		table.insert(actors, actor)
	end
	for _, actor in actors do
		AIAnimationService.Unregister(actor)
	end
end

return AIAnimationService
