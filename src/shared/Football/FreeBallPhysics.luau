local FreeBallPhysics = {}

local EPSILON = 1e-5

local function tangent(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end

local function clampMagnitude(vector: Vector3, maximum: number): Vector3
	local magnitude = vector.Magnitude
	if magnitude <= maximum or magnitude <= EPSILON then
		return vector
	end

	return vector * (maximum / magnitude)
end

-- Roblox owns collision detection; this preserves GameplayFootball's useful
-- football relationships while producing a Roblox-native contact response.
function FreeBallPhysics.ComputeBounce(
	incomingVelocity: Vector3,
	angularVelocity: Vector3,
	normal: Vector3,
	radius: number,
	config
)
	local impactSpeed = math.max(0, -incomingVelocity:Dot(normal))
	local reboundSpeed = math.max(0, impactSpeed * config.Restitution - config.LinearBounceLoss)
	if reboundSpeed < config.SettleReboundSpeed then
		reboundSpeed = 0
	end
	reboundSpeed = math.min(reboundSpeed, config.MaximumReboundSpeed)

	local frictionRange = math.max(
		config.ImpactFrictionFullSpeed - config.ImpactFrictionStartSpeed,
		EPSILON
	)
	local impactFactor = math.clamp(
		(impactSpeed - config.ImpactFrictionStartSpeed) / frictionRange,
		0,
		1
	)
	local incomingTangent = tangent(incomingVelocity, normal)
	local rollingVelocity = tangent(angularVelocity:Cross(normal) * radius, normal)
	local maximumRollingSpeed = incomingTangent.Magnitude * config.MaximumSpinSurfaceSpeedRatio
	if maximumRollingSpeed > EPSILON then
		rollingVelocity = clampMagnitude(rollingVelocity, maximumRollingSpeed)
	else
		rollingVelocity = Vector3.zero
	end

	local spinCoupling = math.clamp(config.ImpactSpinCoupling * impactFactor, 0, 1)
	local outgoingTangent = incomingTangent:Lerp(rollingVelocity, spinCoupling)
	outgoingTangent *= 1 - config.ImpactTangentLoss * impactFactor

	local normalSpin = normal * angularVelocity:Dot(normal) * config.NormalSpinRetention
	local rollingAngularVelocity = normal:Cross(outgoingTangent) / math.max(radius, EPSILON)
	local angularCoupling = math.clamp(config.ImpactAngularCoupling * impactFactor, 0, 1)
	local outgoingAngularVelocity = angularVelocity:Lerp(
		rollingAngularVelocity + normalSpin,
		angularCoupling
	)

	return {
		Velocity = outgoingTangent + normal * reboundSpeed,
		AngularVelocity = outgoingAngularVelocity,
		ImpactSpeed = impactSpeed,
		ReboundSpeed = reboundSpeed,
		ImpactFactor = impactFactor,
		IncomingTangentSpeed = incomingTangent.Magnitude,
		OutgoingTangentSpeed = outgoingTangent.Magnitude,
	}
end

function FreeBallPhysics.StepGround(
	velocity: Vector3,
	angularVelocity: Vector3,
	normal: Vector3,
	radius: number,
	grassInfluence: number,
	deltaTime: number,
	metersPerStud: number,
	config
)
	local influence = math.clamp(grassInfluence, 0, 1)
	local normalSpeed = velocity:Dot(normal)
	local horizontalVelocity = tangent(velocity, normal)
	local rollingVelocity = tangent(angularVelocity:Cross(normal) * radius, normal)
	local rollingAlpha = 1 - math.exp(-config.RollingVelocityCoupling * influence * deltaTime)
	horizontalVelocity = horizontalVelocity:Lerp(rollingVelocity, rollingAlpha)

	local speedStuds = horizontalVelocity.Magnitude
	local speedMeters = speedStuds * metersPerStud
	if speedMeters > EPSILON then
		local speedLossMeters = (
			config.QuadraticFriction * speedMeters * speedMeters
			+ config.LinearFriction
		) * influence * deltaTime
		local newSpeedMeters = math.max(0, speedMeters - speedLossMeters)
		horizontalVelocity *= newSpeedMeters / speedMeters
	end

	local normalSpin = normal * angularVelocity:Dot(normal)
	local normalSpinRetention = math.exp(-config.NormalSpinDamping * influence * deltaTime)
	local targetAngularVelocity = normal:Cross(horizontalVelocity) / math.max(radius, EPSILON)
		+ normalSpin * normalSpinRetention
	local spinAlpha = 1 - math.exp(-config.RollingSpinResponse * influence * deltaTime)
	angularVelocity = angularVelocity:Lerp(targetAngularVelocity, spinAlpha)

	if horizontalVelocity.Magnitude < config.StopSpeed then
		horizontalVelocity = Vector3.zero
		angularVelocity = normal * angularVelocity:Dot(normal) * normalSpinRetention
	end

	return {
		Velocity = horizontalVelocity + normal * math.max(0, normalSpeed),
		AngularVelocity = angularVelocity,
		Stopped = horizontalVelocity.Magnitude <= EPSILON and normalSpeed <= EPSILON,
	}
end

return FreeBallPhysics
