--!strict
--[[
	CAMERA SHAKE.

	A small, decaying additive offset applied to whichever camera is running.

	Three rules govern everything here, and they are the reason this is a
	separate module rather than a few lines inside each camera:

	  PRESENTATION ONLY.
	      Shake never changes where the camera IS, only how the final frame is
	      presented. It is applied after the camera has finished composing, as a
	      rotation and a small translation on the result, and it is never fed
	      back into the smoothing state. Nothing about the game's geometry,
	      framing, dead zones or aim can be affected by it, so it cannot make a
	      shot harder to line up or a pass harder to judge.

	  BOUNDED AND SHORT.
	      Football is not an explosion. The strongest impulse here is a fraction
	      of a degree over a fifth of a second -- enough to register as impact
	      and gone before it can interfere with reading the next moment of play.
	      A camera that is still shaking when the ball reaches the net has taken
	      something away from the player rather than added to it.

	  THE PLAYER CAN SWITCH IT OFF, AND MAY ALREADY HAVE.
	      Roblox exposes an accessibility preference for reduced motion, and
	      screen shake is exactly the effect that preference exists for. It is
	      honoured automatically -- a player who has asked their whole device for
	      less motion should not have to find a setting in this game as well.

	The offset is a decaying sum of sine waves at incommensurate frequencies
	rather than random noise per frame. Random noise reads as a glitch or a
	dropped frame; a decaying oscillation reads as an impact, because that is
	what an impact does to a real camera operator.
]]
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraConfig = require(Shared.Config.CameraConfig)

local CameraShake = {}

local config = CameraConfig.Shake

-- One live impulse. Several may overlap; a shot that hits the post is two.
type Impulse = {
	Magnitude: number,
	Duration: number,
	Frequency: number,
	Elapsed: number,
	Seed: number,
}

local impulses: { Impulse } = {}
local reducedMotionOverride: boolean? = nil

--[[
	Has the player asked for less motion?

	Read through a pcall because ReducedMotionEnabled is a relatively recent
	property and an older client must not error out of the camera path over an
	accessibility preference it cannot express. When it cannot be read the answer
	is "no preference expressed", which leaves the effect on.
]]
local function reducedMotion(): boolean
	if reducedMotionOverride ~= nil then
		return reducedMotionOverride
	end
	local ok, enabled = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and enabled == true
end

--[[
	Add an impulse.

	`preset` names an entry in CameraConfig.Shake.Presets; `scale` lets a caller
	express how hard the thing that happened was -- a tap-in and a thirty-yard
	drive are both shots, and should not shake the camera equally.
]]
function CameraShake.Trigger(preset: string, scale: number?)
	if config.Enabled ~= true or reducedMotion() then
		return
	end
	local definition = config.Presets[preset]
	if not definition then
		return
	end
	--[[
		A cap on concurrent impulses. Without one, a scramble in the six-yard
		box -- several tackles and a shot inside a second -- sums into a shake
		far larger than any single event was ever configured to produce.
	]]
	if #impulses >= config.MaximumConcurrent then
		table.remove(impulses, 1)
	end
	table.insert(impulses, {
		Magnitude = definition.Magnitude * math.clamp(scale or 1, 0, config.MaximumScale),
		Duration = definition.Duration,
		Frequency = definition.Frequency,
		Elapsed = 0,
		Seed = math.random() * 100,
	})
end

--[[
	Advance every live impulse and return the combined offset.

	Called once per rendered frame by whichever camera is active. Returns an
	identity CFrame when nothing is shaking, so the caller can apply it
	unconditionally and there is no branch in the camera to get wrong.
]]
function CameraShake.Step(deltaTime: number): CFrame
	if #impulses == 0 then
		return CFrame.identity
	end

	--[[
		Iterated BACKWARDS, and the index steps every pass.

		The first version only decremented on the branch that kept an impulse, so
		removing one left the index parked past the new end of the list and the
		next read was nil:

			CameraShake:124: attempt to index nil with 'Elapsed'

		which fired on every shot and every tackle. Walking backwards is what
		makes removal safe here -- removing element i never moves anything at an
		index below i -- but only if the walk actually advances in both cases.
	]]
	local pitch, yaw, roll = 0, 0, 0
	for index = #impulses, 1, -1 do
		local impulse = impulses[index]
		impulse.Elapsed += deltaTime
		if impulse.Elapsed >= impulse.Duration then
			table.remove(impulses, index)
		else
			--[[
				Decay squared, so the tail is quiet.

				A linear decay spends half its life at more than half strength,
				which is what makes shake outstay its welcome. Squared, most of
				the visible movement happens in the first third of the duration
				and the rest settles out.
			]]
			local remaining = 1 - impulse.Elapsed / impulse.Duration
			local amplitude = impulse.Magnitude * remaining * remaining
			local t = impulse.Elapsed * impulse.Frequency + impulse.Seed
			-- Incommensurate multipliers: the three axes never resynchronise,
			-- so the movement does not read as a single repeating wobble.
			pitch += math.sin(t * 6.283) * amplitude
			yaw += math.sin(t * 4.271 + 1.7) * amplitude
			roll += math.sin(t * 5.113 + 3.1) * amplitude * config.RollScale
		end
	end

	return CFrame.Angles(
		math.rad(pitch),
		math.rad(yaw),
		math.rad(roll)
	)
end

-- Drop everything immediately. Used when a camera is disabled or a mode
-- changes, so a shake started under one camera cannot leak into the next.
function CameraShake.Clear()
	table.clear(impulses)
end

-- Testing seam: force the reduced-motion answer regardless of the platform
-- preference, so the disabled path can be exercised. Pass nil to hand control
-- back to the player's actual setting.
function CameraShake.SetReducedMotionOverride(value: boolean?)
	reducedMotionOverride = value
	if value == true then
		CameraShake.Clear()
	end
end

function CameraShake.IsReducedMotion(): boolean
	return reducedMotion()
end

return CameraShake
