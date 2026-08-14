local studsPerMeter = 3.3333333333
local metersPerStud = 0.3

local WorldScaleConfig = {
	CanonicalPlayerHeightMeters = 1.8,
	CanonicalPlayerHeightStuds = 6,
	PlayerHeightTestStuds = 6,
	PlayerHeightTestOptionsStuds = { 6, 6.25, 6.5 },
	StudsPerMeter = studsPerMeter,
	MetersPerStud = metersPerStud,

	CanonicalPitchLengthMeters = 105,
	CanonicalPitchWidthMeters = 68,
	CanonicalPitchLengthStuds = 105 * studsPerMeter,
	CanonicalPitchWidthStuds = 68 * studsPerMeter,

	CanonicalGoalWidthMeters = 7.32,
	CanonicalGoalHeightMeters = 2.44,
	CanonicalGoalWidthStuds = 7.32 * studsPerMeter,
	CanonicalGoalHeightStuds = 2.44 * studsPerMeter,

	CurrentStadiumPitchBoundsLengthStuds = 343,
	CurrentStadiumPitchBoundsWidthStuds = 241,
	CurrentStadiumPitchBoundsLengthMeters = 343 * metersPerStud,
	CurrentStadiumPitchBoundsWidthMeters = 241 * metersPerStud,
}

function WorldScaleConfig.MetersToStuds(meters: number): number
	return meters * studsPerMeter
end

function WorldScaleConfig.StudsToMeters(studs: number): number
	return studs * metersPerStud
end

return WorldScaleConfig
