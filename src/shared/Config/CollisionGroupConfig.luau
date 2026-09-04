--!strict
--[[
	Collision groups.

	Beyond 90 used none until the referee arrived, and the referee is the reason
	it needs them: a purely presentational official must not be able to affect a
	competitive outcome (section 17), and `CanCollide = false` cannot express that.
	Roblox's Humanoid re-forces collision on R15 torso parts at the engine level,
	so a script clearing the flag is simply overridden -- and the torso collision
	is also what holds a Humanoid up, so clearing it would drop the referee
	through the pitch even if it did stick.

	Collision groups are the mechanism that says what should actually be true:

		Official  x  Footballer   ->  never collide
		Official  x  Ball         ->  never collide
		Official  x  everything   ->  collide (so the referee stands on the pitch)
		Footballer x everything   ->  unchanged
		Ball       x everything   ->  unchanged

	Nothing about how footballers collide with the world, the ball or each other
	changes. The only pairs switched off are the referee against a footballer and
	the referee against the football -- an official who can body-check a striker
	or deflect a shot is a presentational system changing a competitive outcome.
]]
local CollisionGroupConfig = {}

CollisionGroupConfig.Footballer = "Beyond90Footballer"
CollisionGroupConfig.Official = "Beyond90Official"
CollisionGroupConfig.Ball = "Beyond90Ball"

--[[
	Pairs to disable, as { groupA, groupB }. Every pair not listed keeps Roblox's
	default of colliding, which is what preserves existing behaviour.
]]
CollisionGroupConfig.NonCollidingPairs = {
	{ CollisionGroupConfig.Official, CollisionGroupConfig.Footballer },
	{ CollisionGroupConfig.Official, CollisionGroupConfig.Ball },

	--[[
		FOOTBALLERS DO STILL COLLIDE WITH FOOTBALLERS.

		This pair was briefly removed to stop players climbing over each other,
		and that cure was worse than the disease: footballers passed straight
		THROUGH one another, which is not football at any price. Reverted.

		Climbing is now addressed where it actually comes from -- bodies reaching
		contact at all. FootballerSeparation steers them apart before they touch,
		and it is tuned to hold roughly a body's width of daylight, so the
		collision is still there for the cases steering cannot prevent (two
		players committed to the same ball) without being the routine state.

		If climbing survives that, the next step is a single smooth collision
		capsule per footballer rather than the separate torso parts -- a Humanoid
		climbs LEDGES, and separate parts are what make ledges. Do not reach for
		removing the pair again.
	]]
}

return CollisionGroupConfig
