local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

--[[
	SURFACES ARE CHARCOAL-NAVY, NOT BLUE.

	The dark surfaces were strongly blue-dominant -- measured as a blue-to-red
	ratio, the canvas sat at 6.0 and the panels between 3.0 and 3.4. At those
	ratios the blue stops being the colour of the room and becomes the colour of
	the interface, which is the failure docs/ui/UI_AGENT_DECISION_RULES.md section
	2 warns about: the identity should come from the football, not from tinting
	everything the accent colour.

	Pulled back to roughly 1.7-2.5. That is still unmistakably a night-stadium
	navy -- it has not gone grey, and the mockup direction is intact -- but the
	blue now reads as atmosphere rather than as a wash over every panel, and the
	interaction blue below stands out against it instead of blending into it.

	The ACCENTS are deliberately untouched. Beyond 90's interaction colour is
	blue and should stay blue; the problem was never the accent, it was that the
	surfaces were competing with it.
]]
local Theme = {
	Background = Color3.fromRGB(6, 8, 15),
	BackgroundRaised = Color3.fromRGB(13, 16, 26),
	Panel = Color3.fromRGB(18, 23, 38),
	PanelHover = Color3.fromRGB(28, 34, 52),
	PanelSelected = Color3.fromRGB(30, 36, 56),
	Text = Color3.fromRGB(246, 248, 255),
	MutedText = Color3.fromRGB(156, 169, 201),
	FaintText = Color3.fromRGB(102, 116, 151),
	Accent = Color3.fromRGB(40, 181, 255),
	AccentCyan = Color3.fromRGB(44, 226, 255),

	--[[
		THE COLOUR OF SELECTED TEXT.

		Selected labels used AccentCyan directly. At RGB(44, 226, 255) that is a
		near-maximum-saturation cyan, and against the dark navy panels it reads as
		a glow around the letters rather than as a colour -- which is what it was
		reported as.

		Selection is already carried by the panel: a selected option gets
		PanelSelected behind it and a brighter stroke around it. The text does not
		also need to shout, and docs/ui/UI_ACCESSIBILITY_LOCALIZATION.md section 5
		asks that state not rest on colour alone in any case.

		So selected text is plain bright white. AccentCyan stays for what it is
		good at -- thin accents, rules, small captions and focus rings -- where a
		saturated line is the point rather than an artefact.
	]]
	SelectedText = Color3.fromRGB(255, 255, 255),
	AccentViolet = Color3.fromRGB(130, 76, 255),
	AccentDark = Color3.fromRGB(19, 83, 164),
	Good = Color3.fromRGB(74, 224, 144),
	Warning = Color3.fromRGB(255, 190, 74),
	Poor = Color3.fromRGB(255, 91, 110),
	-- Borders were the other place the blue accumulated: an outline on every
	-- panel at a 1.9 ratio tints the whole screen even though no single one looks
	-- blue. "Do not make every border blue" is the rule this was breaking.
	Stroke = Color3.fromRGB(74, 83, 105),
	StrokeBright = Color3.fromRGB(118, 191, 255),
	CornerRadius = UDim.new(0, 6),

	--[[
		THE SMALLEST A CONTROL MAY BE, IN PIXELS.

		docs/ui/UI_AGENT_DECISION_RULES.md section 8 asks for an effective touch
		target around 48x48 device-independent pixels. Most Beyond 90 controls are
		sized proportionally, which is right -- they should grow with the screen --
		but proportional sizing has no floor, so the same button that is
		comfortable on a desktop becomes untappable on a short viewport. Measured
		on an 1170x484 surface, the control-scheme Confirm button came out 234x33.

		This is that floor. Paired with ReactUI.MinimumSize it keeps the
		proportional design intact wherever there is room and stops it collapsing
		where there is not.
	]]
	MinimumTouchTarget = 48,

	--[[
		HOW TEXT GROWS WITH THE SCREEN.

		Beyond 90's menus size almost everything with UDim2.fromScale, so panels
		grow and shrink with the viewport. TextSize does not: it is a pixel value.
		Measured on the live menu, 132 elements are scale-sized and there was not
		a single UIScale or UITextSizeConstraint anywhere in the tree.

		The consequence is that the ratio between text and the panel holding it
		changes by roughly 2.2x between a 484-tall surface and a 1080-tall one.
		The cards grow; an 11px caption stays 11px. That is the failure
		docs/ui/UI_AGENT_DECISION_RULES.md section 6 describes -- one layout
		scaled rather than adapted.

		ReferenceHeight is derived, not picked: section 8 asks for body text
		readable at about 18px at 1080p, and Theme.TextSizes.Body is 14, so the
		scale wanted at 1080p is 18/14 and the reference height that produces it
		is 1080 / (18/14) = 840.

		The floor is deliberately 1. Text never gets SMALLER than it is authored,
		so no existing screen regresses and short viewports keep proportionally
		large text -- which is what a phone held close actually wants. Only
		larger displays gain, which is where the readability gap was.
	]]
	TextSizeReferenceHeight = 840,
	TextScaleMinimum = 1,
	TextScaleMaximum = 1.5,
	Fonts = {
		Display = Enum.Font.GothamBold,
		Heading = Enum.Font.GothamBold,
		Subheading = Enum.Font.GothamSemibold,
		Navigation = Enum.Font.GothamSemibold,
		Statistics = Enum.Font.GothamSemibold,
		HUDNumber = Enum.Font.GothamBold,
		HUDLabel = Enum.Font.GothamMedium,
		Body = Enum.Font.Gotham,
		Caption = Enum.Font.Gotham,
	},
	TextSizes = {
		Display = 32,
		Heading = 24,
		Subheading = 18,
		Navigation = 16,
		Body = 14,
		Caption = 11,
		HUDNumber = 26,
		HUDLabel = 14,
	},
}

--[[
	THE RESPONSIVE TYPE SCALE LIVES WITH THE TOKENS IT READS.

	These three were on MenuKit, which is where the menu family uses them -- but
	MenuKit requires MenuFooter, so MenuFooter and BackButton could not call back
	into it without a require cycle, and both were left hardcoding their own
	`if mobile then 9 else 12` pairs as a result. Theme is a leaf that everything
	already imports, and it is where ReferenceHeight, the clamps and
	MinimumTouchTarget are defined, so the derivation belongs beside them.

	MenuKit still re-exports all three, so existing callers are unaffected.
]]

local COMPACT_MAXIMUM_HEIGHT = 500
local COMPACT_MAXIMUM_WIDTH = 900
local COMPACT_TEXT_FACTOR = 0.85
local COMPACT_MINIMUM_TEXT = 11
-- Published so MenuKit can floor its fit-to-box constraint at the same number
-- rather than repeating it. See Theme.Size for where it comes from.
local COMPACT_OVERRIDE_ATTRIBUTE = "Beyond90ForceCompactLayout"

--[[
	Is this a phone-landscape screen?

	Every menu screen used to answer this with `UserInputService.TouchEnabled`,
	which answers a DIFFERENT question: "can this device receive touch input?"
	The two come apart badly in both directions.

		touchscreen laptop, 1920x1080 -> compact layout, 7px captions
		tablet landscape,   1024x768  -> compact layout, 7px captions
		desktop window dragged small  -> full layout, nothing adapts
		console at low resolution     -> full layout, nothing adapts

	docs/ui/UI_RESPONSIVE_INPUT.md section 1 defines the target classes by
	SCREEN -- large landscape, medium landscape, phone landscape -- and the
	distinguishing feature it names for phone landscape is "limited vertical
	space". So the question is about the viewport, and height is the axis.

	The threshold sits between the two clusters of real device heights rather
	than at a round number picked by eye:

		phone landscape   ~360-430   <- compact
		------------------ 500 ------------------
		tablet landscape  ~768-834
		laptop 1366x768    768
		desktop 1080p     1080

	Touch is still the right question for TOUCH TARGETS and for whether to draw
	on-screen sticks, and it is still asked separately for those. What it must
	not decide is how dense the layout is.

	THE OVERRIDE. Studio's viewport cannot be resized from a script and
	Camera.ViewportSize is read-only, so without an override the compact branch
	is unreachable from a desktop session -- which is how it drifted to 7px type
	in the first place: nobody could see it. AGENTS.md section 49 asks for
	reproducible test scenarios for exactly this reason.

		game.Players.LocalPlayer:SetAttribute("Beyond90ForceCompactLayout", true)

	The menu re-renders on that attribute (see UIController), so forcing it
	behaves like resizing the window. It is read only when present, so a normal
	session never touches it.
]]
Theme.MinimumCompactTextSize = COMPACT_MINIMUM_TEXT

function Theme.Compact(): boolean
	local player = Players.LocalPlayer
	local override = if player then player:GetAttribute(COMPACT_OVERRIDE_ATTRIBUTE) else nil
	if type(override) == "boolean" then
		return override
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	local viewport = camera.ViewportSize
	return viewport.Y <= COMPACT_MAXIMUM_HEIGHT or viewport.X <= COMPACT_MAXIMUM_WIDTH
end

--[[
	How much larger text should be on this display than as authored.

	See TextSizeReferenceHeight above for the derivation and for why the floor is
	1. Read from the live viewport so a resize or a device rotation is picked up;
	the menu re-renders on viewport change (see UIController) so this is
	re-evaluated when it matters.
]]
function Theme.TextScale(): number
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else Theme.TextSizeReferenceHeight
	if height <= 0 then
		return 1
	end
	return math.clamp(height / Theme.TextSizeReferenceHeight, Theme.TextScaleMinimum, Theme.TextScaleMaximum)
end

--[[
	Scale an authored desktop size for the current display.

	One helper rather than `if mobile then a else b` scattered through every
	label, so the whole family shrinks by the same ratio and the hierarchy
	between heading, body and caption survives the change of screen.

	THE COMPACT FLOOR IS A READABILITY FLOOR, NOT A ROUNDING GUARD.

	The compact factor and floor used to be 0.66 and 7. Those two numbers meet on
	exactly the screen that can least afford it: TextScale is clamped at 1 on the
	way down, so a 780x360 phone does not scale text at all and simply takes two
	thirds of the authored size. Measured across HomeScreen, that put ten of its
	fifteen labels under 10px and one at 7px.

	7px is below every platform's own minimum for body text -- iOS Human
	Interface Guidelines say 11pt, Material Design's caption style is 12sp -- and
	Roblox reports mobile viewports in points-like units, so those minima
	transfer directly. docs/ui/UI_ACCESSIBILITY_LOCALIZATION.md section 1 also
	lists "tiny stat labels" among the things to avoid.

	docs/ui/UI_RESPONSIVE_INPUT.md section 2 ranks readable text ABOVE reducing
	secondary content when space runs out, so the reduction a phone needs is in
	how much is shown, not in how small the glyphs are -- and the layout branches
	already do that part. Hence a gentler factor and a floor at the platform
	minimum.

	The floor does compress the bottom of the type scale: captions, body and
	labels all arrive at 11 on a phone. That is deliberate. A 360px-tall screen
	cannot carry five distinguishable legible sizes, and the headings keep their
	spread, so the hierarchy that survives is the one that matters.
]]
function Theme.Size(compact: boolean, desktop: number): number
	local scaled = desktop * Theme.TextScale()
	return if compact
		then math.max(math.floor(scaled * COMPACT_TEXT_FACTOR), COMPACT_MINIMUM_TEXT)
		else math.max(math.floor(scaled + 0.5), 7)
end

return Theme
