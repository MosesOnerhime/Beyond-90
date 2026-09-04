--!strict
--[[
	BODIES DO NOT SHARE A STUD.

	Two footballers walking into each other were climbing over one another: a
	Roblox Humanoid steps up onto anything within its step height, and another
	footballer's torso is exactly that. The result was players and AI riding up
	each other's shoulders, which is neither football nor recoverable -- the
	one on top is airborne and the one underneath is pinned.

	The climb itself is stopped by collision groups (see CollisionGroupConfig:
	a footballer no longer collides with a footballer, so there is nothing left
	to climb). That alone would let two bodies occupy the same space, which
	looks worse than the climb did. This is the other half: a steering push that
	holds them apart before they ever touch.

	WHY STEERING RATHER THAN A PHYSICS PUSH. A push is a force applied after the
	overlap has happened, and it fights whatever the footballer is trying to do.
	A steering offset is applied to the direction they are ALREADY moving, so a
	defender closing down a carrier still closes down the carrier -- they simply
	arrive alongside instead of inside. Nothing here changes anyone's football
	decision, which is the line AGENTS.md section 2 draws; it is the
	"body-overlap avoidance" section 33 explicitly allows.

	It is deliberately weak and short-ranged. Football is a contact sport and
	players get close; this only refuses to let them get closer than a body.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local FootballerSeparation = {}

--[[
	The push away from `neighbours`, as a horizontal vector no longer than 1.

	`neighbours` is any list of things with a `.Position`; the caller supplies
	whichever set it already has to hand rather than this module searching the
	Workspace, because both callers are inside a per-frame loop that has the
	list already (section 10, section 53: no repeated Workspace searches).
]]
function FootballerSeparation.GetPush(
	position: Vector3,
	neighbours: { { Id: number, Position: Vector3 } },
	selfId: number?,
	config
): Vector3
	local settings = config or PlayerConfig.Separation
	if not settings or settings.Enabled ~= true then
		return Vector3.zero
	end

	local radius = settings.Radius
	local push = Vector3.zero
	for _, neighbour in neighbours do
		if selfId and neighbour.Id == selfId then
			continue
		end
		local offset = BallControlMath.GetHorizontal(position - neighbour.Position)
		local distance = offset.Magnitude
		if distance > 1e-3 and distance < radius then
			--[[
				Weighted by how far INSIDE the radius they are, so the push is
				nothing at the edge and strongest at contact. Linear rather than
				inverse-square: an inverse law spikes without bound as the
				distance closes and turns a brush past into a shove.
			]]
			push += offset.Unit * (1 - distance / radius)
		end
	end

	if push.Magnitude < 1e-3 then
		return Vector3.zero
	end
	--[[
		Clamped as a whole. Three opponents arriving at once must not produce
		three times the push -- being surrounded is a football situation, not a
		reason to be fired out of the group.
	]]
	return push.Unit * math.min(push.Magnitude, settings.MaximumPush)
end

--[[
	`direction` steered away from `neighbours`, renormalised.

	A footballer standing still is left standing still: separation nudges
	movement, it does not start it. Someone deliberately holding their ground --
	a keeper on their line, a defender holding a position -- stays where they
	chose to be.
]]
function FootballerSeparation.Steer(
	direction: Vector3,
	position: Vector3,
	neighbours: { { Id: number, Position: Vector3 } },
	selfId: number?,
	config
): Vector3
	if direction.Magnitude < 1e-3 then
		return direction
	end
	local push = FootballerSeparation.GetPush(position, neighbours, selfId, config)
	if push.Magnitude < 1e-3 then
		return direction
	end
	local settings = config or PlayerConfig.Separation
	local steered = direction + push * settings.SteeringWeight
	return BallControlMath.SafeUnit(steered, direction) * math.min(direction.Magnitude, 1)
end

return FootballerSeparation
