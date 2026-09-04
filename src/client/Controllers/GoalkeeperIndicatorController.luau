--[[
	THE GOALKEEPER'S INDICATORS.

	Rebuilt from what `ref/EA FC 26 Pro Clubs goalkeeper pov.mp4` actually shows.
	Three marks:

	  1. A HOOP standing up around the keeper -- from the grass on one side, over
	     his head, back down to the grass on the other. Grey while he guards,
	     and the half he is diving toward lights blue when he commits.

	  2. A RING on the ground WHERE HE SHOULD BE. Not under his feet: the whole
	     point of it is to be somewhere else, and it disappears when he is
	     standing in it.

	  3. An ARROW from the keeper to that ring.

	Two previous versions of this file were wrong in the same way -- they drew a
	ring at the keeper's feet, which is the "double circle underneath him" the
	player reported, because a footprint ring and a position ring overlap
	whenever the keeper is anywhere near where the game wants him. The reference
	has no ring under the keeper at all. The grass beneath his feet is bare.

	WHY PARTS. A ring drawn as one texture cannot light one side of itself, and
	the hoop's whole job is to light one side. Built from small parts, colouring
	a side is just colouring the parts whose angle matches.

	Presentation only. Nothing here decides or reports anything: the dive is
	requested by GoalkeeperController and resolved on the server.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GoalkeeperConfig = require(Shared.Config.GoalkeeperConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local InputController = require(script.Parent.InputController)

local GoalkeeperIndicatorController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local renderStepName = "Beyond90GoalkeeperIndicators"
local folder: Folder? = nil
local hoopSegments: { BasePart } = {}
local targetSegments: { BasePart } = {}
local arrowSegments: { BasePart } = {}

local config = GoalkeeperConfig.Indicators

--[[
	THE PITCH SURFACE THE KEEPER IS ACTUALLY STANDING ON.

	Found by raycasting down, not read from a config or an attribute. Two earlier
	attempts got this wrong and the markers were buried both times:

	  * A hardcoded 0.28 -- guessed, and the grass is at 0.5.
	  * `PitchBounds.PitchGroundY`, which reads 0.20 on this stadium. That
	    attribute describes the pitch BOUNDS reference, not the rendered grass,
	    which sits 0.3 studs higher. PlayerService already raycasts for exactly
	    this reason and reports groundY=0.5.

	A ray is the only source that cannot disagree with what the player sees, and
	it stays correct on any stadium.
]]
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function getGroundY(root: BasePart, at: Vector3): number
	groundParams.FilterDescendantsInstances = {
		root.Parent :: Instance,
		folder :: Instance,
	}
	local origin = Vector3.new(at.X, root.Position.Y + 2, at.Z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -40, 0), groundParams)
	if hit then
		return hit.Position.Y + config.GroundOffset
	end
	--[[
		No surface under that point. Rather than guess a height -- guessing is
		what buried these markers twice -- fall back to the keeper's own feet,
		which is the one height that is certainly not underground.
	]]
	return root.Position.Y - root.Size.Y * 0.5 + config.GroundOffset
end

local function isKeeper(): (Model?, BasePart?)
	local character = localPlayer.Character
	if not character or not character.Parent then
		return nil, nil
	end
	if character:GetAttribute(GoalkeeperConfig.RoleAttributeName) ~= GoalkeeperConfig.Role then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return character, if root and root:IsA("BasePart") then root else nil
end

local function makeMarker(name: string, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

--[[
	Where each hoop segment sits, in the keeper's lateral plane.

	Built once. Segments are shared out between the arcs IN PROPORTION TO ARC
	LENGTH, so a 60-degree side arc gets nearly three times as many pieces as the
	22-degree cap and every stroke is drawn at the same density. Splitting them
	evenly would make the short cap look heavy and the long sides look sparse.
]]
local hoopAngles: { number } = {}

local function buildHoopAngles()
	table.clear(hoopAngles)
	local arcs = config.HoopArcs
	local total = 0
	for _, arc in arcs do
		total += arc.Finish - arc.Start
	end
	if total <= 0 then
		return
	end

	local assigned = 0
	for index, arc in arcs do
		local span = arc.Finish - arc.Start
		--[[
			The last arc takes whatever is left rather than its own rounded
			share, so rounding can never leave a segment unplaced (it would sit
			at angle 0, drawing a stray mark on the grass).
		]]
		local count = if index == #arcs
			then config.HoopSegmentCount - assigned
			else math.max(1, math.round(config.HoopSegmentCount * span / total))
		for piece = 1, count do
			local alpha = (piece - 0.5) / count
			table.insert(hoopAngles, math.rad(arc.Start + span * alpha))
		end
		assigned += count
	end
end

local function build()
	if folder then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "Beyond90GoalkeeperIndicators"
	folder.Parent = Workspace

	buildHoopAngles()

	--[[
		The hoop. A HALF circle -- legs to head and back down to legs -- so the
		segments span pi rather than a full turn. Each piece is sized a little
		over its own slice so the joins close and it reads as one line.
	]]
	local hoopPiece = math.pi * config.HoopRadius / config.HoopSegmentCount
	local hoopSize = Vector3.new(config.HoopWidth, config.Thickness, hoopPiece * 1.1)
	for index = 1, config.HoopSegmentCount do
		hoopSegments[index] = makeMarker("Hoop" .. index, hoopSize, config.HoopColor)
	end

	-- The target ring: a full circle, flat on the grass.
	local ringPiece = 2 * math.pi * config.TargetRadius / config.TargetSegmentCount
	local ringSize = Vector3.new(ringPiece * 1.1, config.Thickness, config.TargetWidth)
	for index = 1, config.TargetSegmentCount do
		targetSegments[index] = makeMarker("Target" .. index, ringSize, config.TargetColor)
	end

	--[[
		The arrows. Two bars per chevron, so each one has an actual point rather
		than being a dash that happens to lie along the line.
	]]
	local arrowSize = Vector3.new(config.ArrowWidth, config.Thickness, config.ArrowBarLength)
	for index = 1, config.ArrowCount * 2 do
		arrowSegments[index] = makeMarker("Arrow" .. index, arrowSize, config.TargetColor)
	end
end

local function teardown()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(hoopSegments)
	table.clear(targetSegments)
	table.clear(arrowSegments)
end

local function hideAll()
	for _, part in hoopSegments do
		part.Transparency = 1
	end
	for _, part in targetSegments do
		part.Transparency = 1
	end
	for _, part in arrowSegments do
		part.Transparency = 1
	end
end

--[[
	Which way the keeper is committing, in world space.

	ONLY WHILE ACTUALLY DIVING.

	This used to fall back to whatever direction the player was holding, so the
	hoop lit up during ordinary side-to-side movement and the blue stopped
	meaning anything -- it was on most of the time. In the reference the coloured
	arcs appear only at the moment of a save and are absent while the keeper
	stands, which is what earns them their brightness.

	So the answer is the diving body's own velocity, or nothing. A keeper merely
	shuffling along their line lights no side at all.
]]
local function getCommitDirection(character: Model, root: BasePart): Vector3?
	if character:GetAttribute(GoalkeeperConfig.Attributes.Diving) ~= true then
		return nil
	end
	local velocity = BallControlMath.GetHorizontal(root.AssemblyLinearVelocity)
	if velocity.Magnitude > 1 then
		return velocity.Unit
	end
	--[[
		A dive that has been approved but has not built up speed yet still has a
		side -- the server published it. Without this the first frames of every
		dive light nothing, which reads as the indicator lagging the action.
	]]
	local launch = character:GetAttribute(GoalkeeperConfig.Attributes.DiveVelocity)
	if typeof(launch) == "Vector3" then
		local flat = BallControlMath.GetHorizontal(launch)
		if flat.Magnitude > 0.05 then
			return flat.Unit
		end
	end
	return nil
end

--[[
	Draw the hoop around the keeper.

	The plane it stands in is the keeper's LATERAL one -- the plane containing
	world up and the keeper's own left-right axis. That is the plane a keeper
	dives in, which is what lets one half of it mean "this way": the left half
	is genuinely where a leftward dive goes.
]]
local function drawHoop(root: BasePart, groundY: number, commit: Vector3?)
	local centre = Vector3.new(root.Position.X, groundY, root.Position.Z)
	local right = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(root.CFrame.RightVector),
		Vector3.xAxis
	)
	-- Which side of the hoop the commitment falls on, if there is one.
	local commitSign = 0
	if commit then
		local alongRight = commit:Dot(right)
		if math.abs(alongRight) > 0.15 then
			commitSign = if alongRight > 0 then 1 else -1
		end
	end

	for index, part in hoopSegments do
		--[[
			Angle measured from the grass on the keeper's left (0) through
			straight up (pi/2) to the grass on their right (pi). A half turn --
			legs, head, legs.

			BROKEN INTO THREE UNEQUAL ARCS, per `Indicators.HoopArcs`: two long
			side arcs and a short cap over the head, as the reference draws it.
			The angles are precomputed once by `buildHoopAngles` rather than
			derived here, because distributing a fixed number of segments across
			arcs of DIFFERENT lengths -- so the stroke density matches -- is not
			something to redo per segment per frame.
		]]
		local angle = hoopAngles[index]
		local lateral = -math.cos(angle)
		local offset = right * (lateral * config.HoopRadius)
			+ Vector3.yAxis * (math.sin(angle) * config.HoopRadius)
		local position = centre + offset

		--[[
			Each segment lies along the tangent at its own angle, which is what
			makes the run of straight pieces read as a curve.
		]]
		local tangent = right * math.sin(angle) + Vector3.yAxis * math.cos(angle)
		part.CFrame = CFrame.lookAt(position, position + tangent, Vector3.yAxis)

		local lit = commitSign ~= 0 and (lateral * commitSign) > 0
		part.Color = if lit then config.CommitColor else config.HoopColor
		part.Transparency = if lit then config.CommitTransparency else config.HoopTransparency
	end
end

--[[
	Draw the ground ring where the keeper SHOULD be, and the arrow to it.

	Faded by how far away it is: nothing at all while the keeper is standing in
	it, arriving gradually as they drift off it. A mark that is always on is a
	mark nobody reads, and one drawn on top of the keeper is the double circle
	this file has produced twice before.
]]
local function drawTarget(root: BasePart, resting: Vector3)
	local toTarget = BallControlMath.GetHorizontal(resting - root.Position)
	local distance = toTarget.Magnitude
	if distance <= config.TargetHideDistance then
		for _, part in targetSegments do
			part.Transparency = 1
		end
		for _, part in arrowSegments do
			part.Transparency = 1
		end
		return
	end

	local reveal = math.clamp(
		(distance - config.TargetHideDistance)
			/ math.max(config.TargetFullDistance - config.TargetHideDistance, 0.01),
		0,
		1
	)
	local ringTransparency = 1 - (1 - config.TargetTransparency) * reveal
	local groundY = getGroundY(root, resting)
	local centre = Vector3.new(resting.X, groundY, resting.Z)

	for index, part in targetSegments do
		local angle = (index - 1) / config.TargetSegmentCount * math.pi * 2
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = centre + outward * config.TargetRadius
		part.CFrame = CFrame.lookAt(position, position + outward) * CFrame.Angles(0, math.pi / 2, 0)
		part.Transparency = ringTransparency
	end

	--[[
		THE ARROWS. Chevrons pointing at the ring.

		Each is two bars meeting at a tip, angled back from the direction of
		travel -- the same mark the reference lays on the grass between the
		keeper and where they should be. Stacked along the line and brightening
		toward the ring, so the run reads as "that way" rather than as a dashed
		path.
	]]
	local direction = toTarget.Unit
	local start = config.ArrowStartGap
	local finish = math.max(distance - config.ArrowEndGap, start)
	local span = finish - start
	local half = math.rad(config.ArrowHalfAngleDegrees)
	--[[
		Fit as many chevrons as the gap allows, so a keeper barely off their spot
		gets one mark rather than three overlapping ones.
	]]
	local fit = math.clamp(math.floor(span / config.ArrowSpacing), 0, config.ArrowCount)

	for index = 1, config.ArrowCount do
		local tipBar = arrowSegments[index * 2 - 1]
		local tailBar = arrowSegments[index * 2]
		if not tipBar or not tailBar then
			continue
		end
		if index > fit then
			tipBar.Transparency = 1
			tailBar.Transparency = 1
			continue
		end

		--[[
			Placed from the RING end backwards, so the chevron nearest the target
			is always drawn and the ones behind it drop off as the gap closes.
		]]
		local along = finish - (fit - index) * config.ArrowSpacing
		local point = root.Position + direction * along
		--[[
			Sharing the ring's ground height rather than raycasting per bar.
			This runs every rendered frame, and a pitch is flat over the handful
			of studs between the keeper and their own resting spot -- extra rays
			a frame to confirm that is the sort of cost section 10 says not to
			pay.
		]]
		local tip = Vector3.new(point.X, groundY, point.Z)

		-- Brightest at the ring end, so the run points even before it is read.
		local t = index / config.ArrowCount
		local transparency = 1 - (1 - config.TargetTransparency) * reveal * (0.4 + 0.6 * t)

		for side, bar in { tipBar, tailBar } do
			--[[
				Each bar runs from the tip BACKWARDS at the chevron half-angle.
				The bar's own centre therefore sits half a bar-length back along
				that heading, which is what makes the two meet at a point rather
				than crossing.
			]]
			local sign = if side == 1 then 1 else -1
			local heading = (CFrame.fromAxisAngle(Vector3.yAxis, half * sign) * direction).Unit
			local centre = tip - heading * (config.ArrowBarLength * 0.5)
			bar.CFrame = CFrame.lookAt(centre, centre + heading)
			bar.Transparency = transparency
		end
	end
end

local function update()
	local character, root = isKeeper()
	if not character or not root then
		if folder then
			hideAll()
		end
		return
	end
	build()

	local groundY = getGroundY(root, root.Position)
	drawHoop(root, groundY, getCommitDirection(character, root))

	local resting = character:GetAttribute(GoalkeeperConfig.Attributes.RestingPosition)
	if typeof(resting) == "Vector3" then
		drawTarget(root, resting)
	else
		-- No published resting position: draw nothing rather than guess one.
		for _, part in targetSegments do
			part.Transparency = 1
		end
		for _, part in arrowSegments do
			part.Transparency = 1
		end
	end
end

function GoalkeeperIndicatorController.Initialize()
	if initialized or not config or config.Enabled ~= true then
		return
	end
	initialized = true
	RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Camera.Value - 2, update)
end

function GoalkeeperIndicatorController.Destroy()
	if not initialized then
		return
	end
	initialized = false
	RunService:UnbindFromRenderStep(renderStepName)
	teardown()
end

return GoalkeeperIndicatorController
