--!strict
--[[
	Stamina.

	Real gameplay state, not a HUD decoration (§44). One model covers humans and
	AI, because a footballer's lungs should not depend on who is controlling it.

	The design intent (§46) is that fatigue takes away SUSTAINED SPRINTING and
	leaves everything else alone. A tired footballer still jogs, still passes,
	still defends and can still play well -- they simply cannot keep running at
	top speed. Making low stamina broadly punishing would remove skill expression
	rather than reward game management.

	Drain is driven by MEASURED horizontal speed rather than by a client-reported
	sprint flag, so a client cannot claim to be jogging while travelling at 28
	studs/s (§47).
]]
local PlayerConfig = require(script.Parent.PlayerConfig)

local StaminaConfig = {
	Enabled = true,

	Maximum = 100,
	-- Everyone starts a match fresh.
	StartingValue = 100,

	Attributes = {
		-- Published on the CHARACTER so the local HUD and the client's own
		-- locomotion both read the same authoritative number.
		Value = "Beyond90Stamina",
		-- The sprint ceiling this stamina currently allows, in studs/s. Published
		-- rather than recomputed so server and client can never disagree.
		SprintCeiling = "Beyond90StaminaSprintCeiling",
	},

	--[[
		Above this measured speed a footballer is considered to be sprinting.
		Sits comfortably between jog (14) and sprint (28) so neither a jog with a
		following wind nor a decelerating sprint is misclassified.
	]]
	SprintSpeedThreshold = (PlayerConfig.Movement.BaseSpeed + PlayerConfig.Movement.SprintSpeed) * 0.5,
	-- Below this, a footballer is recovering rather than working.
	RestSpeedThreshold = PlayerConfig.Movement.BaseSpeed * 0.45,

	Drain = {
		--[[
			Stamina per second at full sprint.

			At 3.6/s it took 15 seconds of unbroken sprinting just to reach the
			fatigue threshold and 28 to empty, which is longer than most players
			ever sprint in one go -- so in practice the bar barely moved and
			sprint had no cost. At 8/s the threshold arrives in about 7 seconds
			and the bar empties in 12: holding sprint across a whole attack is now
			a real decision, while a normal 2-3 second burst is still cheap.

			Recovery is unchanged, so the cost is felt in sustained running rather
			than in being permanently tired.
		]]
		SprintPerSecond = 8,
		-- Scales in between the sprint threshold and full sprint, so a three-quarter
		-- pace run is cheaper than a flat-out one.
		PartialSprintScale = 0.55,
		--[[
			Sustained pressing is high-intensity work even below sprint speed:
			short accelerations, turns and jockeying. Charged only while press
			assistance or an AI press is actually active.
		]]
		PressPerSecond = 1.4,
		-- Chasing a knock-on is a deliberate flat-out effort.
		ChasePerSecond = 0.9,
	},

	Recovery = {
		-- Standing still.
		IdlePerSecond = 6.5,
		-- Walking or jogging: the normal way stamina comes back during a match.
		JoggingPerSecond = 3.2,
		-- Any stoppage -- restart, injury, celebration. Players get a breather.
		StoppagePerSecond = 11,
		-- Half time is a genuine rest.
		HalfTimeRecoveryFraction = 0.75,
	},

	--[[
		The gameplay consequence (§46).

		Above FatigueThreshold nothing changes at all, so ordinary play is never
		degraded. Below it the sprint ceiling falls linearly toward
		ExhaustedSprintSpeed -- which is still meaningfully faster than a jog, so
		an exhausted footballer is slowed rather than disabled.
	]]
	Effect = {
		FatigueThreshold = 45,
		ExhaustedSprintSpeed = PlayerConfig.Movement.BaseSpeed + 3,
		--[[
			Acceleration suffers before top speed does, which is what actually
			reads as tiredness: the footballer still gets there, just later.
		]]
		MinimumAccelerationScale = 0.7,
	},

	--[[
		AI decision-making (§48).

		An AI will not START a sprint below ReserveForSprint, so it keeps
		something back for a genuinely important run instead of arriving at every
		situation exhausted. It never refuses to sprint when the situation is
		urgent, which is what stops "AI looks slow" being caused by its own
		caution.
	]]
	AI = {
		ReserveForSprint = 18,
		-- Urgency above which the reserve is spent anyway: a loose ball, a
		-- recovery run, a clear chance.
		UrgentReserve = 4,
	},

	-- Bounded update rate. Stamina does not need per-frame precision.
	UpdateInterval = 0.2,

	Debug = {
		Enabled = false,
		LogInterval = 5,
	},
}

--[[
	The fastest this footballer may currently run.

	Returns the full sprint speed while fresh, tapering to ExhaustedSprintSpeed
	as stamina empties. Shared by the server, the client's own locomotion and the
	AI, so all three agree without restating the curve.
]]
function StaminaConfig.GetSprintCeiling(stamina: number): number
	local effect = StaminaConfig.Effect
	local full = PlayerConfig.Movement.SprintSpeed
	if stamina >= effect.FatigueThreshold then
		return full
	end
	local alpha = math.clamp(stamina / math.max(effect.FatigueThreshold, 1e-3), 0, 1)
	return effect.ExhaustedSprintSpeed + (full - effect.ExhaustedSprintSpeed) * alpha
end

-- How much slower a tired footballer builds speed. 1 while fresh.
function StaminaConfig.GetAccelerationScale(stamina: number): number
	local effect = StaminaConfig.Effect
	if stamina >= effect.FatigueThreshold then
		return 1
	end
	local alpha = math.clamp(stamina / math.max(effect.FatigueThreshold, 1e-3), 0, 1)
	return effect.MinimumAccelerationScale + (1 - effect.MinimumAccelerationScale) * alpha
end

return StaminaConfig
