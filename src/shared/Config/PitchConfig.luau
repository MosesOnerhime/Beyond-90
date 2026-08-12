local length = 180
local width = 110
local surfaceThickness = 1
local lineThickness = 0.35
local lineHeight = 0.08
local goalWidth = 28
local goalDepth = 10
local goalHeight = 8
local developmentSpawnLengthOffset = -12
local maxPitchBoundsReferenceThickness = 2

local PitchConfig = {
	Length = length,
	Width = width,
	UseWorkspacePitchBounds = true,
	WorkspacePitchBoundsPath = { "StadiumDevelopment", "PitchBounds" },
	MaxPitchBoundsReferenceThickness = maxPitchBoundsReferenceThickness,
	SurfaceThickness = surfaceThickness,
	SurfaceSize = Vector3.new(width, surfaceThickness, length),
	SurfacePosition = Vector3.new(0, -surfaceThickness / 2, 0),

	LineThickness = lineThickness,
	LineHeight = lineHeight,
	LineY = 0.04,

	GoalWidth = goalWidth,
	GoalDepth = goalDepth,
	GoalHeight = goalHeight,

	DevelopmentSpawnLengthOffset = developmentSpawnLengthOffset,
	BallCenterPosition = Vector3.new(0, 4, 0),
}

return PitchConfig
