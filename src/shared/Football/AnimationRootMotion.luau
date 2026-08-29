--!strict
--[[
	Root motion compensation for animation clips.

	Roblox animations never translate the HumanoidRootPart, so a clip that reads
	as falling, stumbling or side-stepping looks wrong on its own. This applies
	the offset a clip implies, in the character's local frame, easing in over the
	clip's own curve and easing back out on release.

	It is presentation only. It never teleports, never changes possession, and
	never decides whether an action was valid.
]]
local AnimationRootMotion = {}

export type Playback = {
	Spec: any,
	StartedAt: number,
	Mirrored: boolean,
	Offset: Vector3,
	Released: boolean,
	ReleasedAt: number,
}

-- Piecewise-linear lookup across the clip's normalized time.
local function sampleCurve(curve, alpha: number): number
	if not curve or #curve == 0 then
		return alpha
	end
	if alpha <= curve[1][1] then
		return curve[1][2]
	end
	for index = 1, #curve - 1 do
		local a = curve[index]
		local b = curve[index + 1]
		if alpha <= b[1] then
			local span = math.max(b[1] - a[1], 1e-5)
			local t = (alpha - a[1]) / span
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return curve[#curve][2]
end

function AnimationRootMotion.Begin(spec, mirrored: boolean?): Playback?
	if not spec then
		return nil
	end
	return {
		Spec = spec,
		StartedAt = os.clock(),
		Mirrored = mirrored == true,
		Offset = Vector3.zero,
		Released = false,
		ReleasedAt = 0,
	}
end

--[[
	Advance one playback and return the local-space offset to apply this frame.
	Returns nil once the playback has fully eased out and can be discarded.
]]
function AnimationRootMotion.Step(playback: Playback, deltaTime: number, config): Vector3?
	local spec = playback.Spec
	local now = os.clock()
	local duration = math.max(spec.Duration or 1, 1e-3)
	local elapsed = now - playback.StartedAt

	local target: Vector3
	if playback.Released or elapsed >= duration then
		-- Ease the offset away rather than snapping the body back.
		playback.Released = true
		if playback.ReleasedAt == 0 then
			playback.ReleasedAt = now
		end
		target = Vector3.zero
	else
		local alpha = math.clamp(elapsed / duration, 0, 1)
		local scale = sampleCurve(spec.Curve, alpha)
		local right = (spec.Right or 0) * scale
		if playback.Mirrored and spec.MirrorRight then
			right = -right
		end
		target = Vector3.new(right, (spec.Up or 0) * scale, -(spec.Forward or 0) * scale)
	end

	local responsiveness = if playback.Released
		then (config.ReleaseResponsiveness or 9)
		else (config.Responsiveness or 16)
	local blend = 1 - math.exp(-responsiveness * math.max(deltaTime, 0))
	playback.Offset = playback.Offset:Lerp(target, blend)

	if playback.Released and playback.Offset.Magnitude < 0.01 then
		return nil
	end
	return playback.Offset
end

function AnimationRootMotion.Release(playback: Playback)
	if playback and not playback.Released then
		playback.Released = true
		playback.ReleasedAt = os.clock()
	end
end

-- Convert a local-space offset into a world CFrame offset for a given root.
function AnimationRootMotion.ToWorldOffset(rootPart: BasePart, localOffset: Vector3): Vector3
	local cf = rootPart.CFrame
	return cf.RightVector * localOffset.X
		+ Vector3.yAxis * localOffset.Y
		+ cf.LookVector * (-localOffset.Z)
end

return AnimationRootMotion
