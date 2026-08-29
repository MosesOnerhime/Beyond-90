local UIAssetConfig = {
	Logo = "rbxassetid://95120414425732",
	MenuStadium = "rbxassetid://126626380889858",
	Navigation = {
		Play = "rbxassetid://100294171234846",
		Training = "rbxassetid://71903961755034",
		Clubs = "rbxassetid://96914356938207",
		Profile = "rbxassetid://130860898349158",
		Settings = "rbxassetid://137603747676714",
	},
	Currency = {
		B90 = "rbxassetid://103242075983113",
		Premium = "rbxassetid://102150102530893",
	},
	DivisionBadge = "rbxassetid://96822520991612",
	FeaturedPlayerFrame = "rbxassetid://127622546712149",
	Highlights = {
		Trophy = "rbxassetid://79810444313222",
		Goal = "rbxassetid://101370728719623",
		MOTM = "rbxassetid://99076658869335",
	},
	Menu = {
		OpenMenu = "rbxassetid://114126400220548",
		Time = "rbxassetid://92588773446277",
		Select = "rbxassetid://102699736820051",
		NigeriaFlag = "rbxassetid://71158226611997",
		--[[
			KEYBOARD FOOTER PROMPTS (§9).

			The keyboard profile previously reused the controller "A" glyph or a
			drawn text chip, neither of which is what a keyboard player actually
			presses. These are the supplied production icons.

			Every consumer must fall back gracefully if an image does not resolve
			(§57): see MenuFooter, which keeps the text chip as its fallback.
		]]
		LeftMouseClick = "rbxassetid://94149095251371",
		EscKey = "rbxassetid://127883114740769",
	},

	--[[
		CONTROL-SCHEME SELECTION (§10).

		Presentation only. The control-scheme system itself is unchanged -- these
		simply make each profile recognisable at a glance instead of being
		represented by drawn shapes.
	]]
	ControlScheme = {
		Keyboard = "rbxassetid://137187938500810",
		Gamepad = "rbxassetid://74060318259206",
	},

	--[[
		POSITION PREVIEWS (§11).

		Supplied pitch diagrams, one per position group. These replace the
		procedurally drawn pitch that existed only because the images were not
		available at the time.

		PositionSelectionScreen falls back to that drawn pitch if an image fails
		to resolve, so a moderation problem degrades the preview rather than
		leaving an empty frame.
	]]
	PitchPositions = {
		GK = "rbxassetid://71723106340650",
		DEF = "rbxassetid://132671397428450",
		MID = "rbxassetid://82318616333884",
		FWD = "rbxassetid://111013468900915",
	},
	Social = {
		Friends = "rbxassetid://106677884507356",
		Chat = "rbxassetid://138586242100664",
		Network = "rbxassetid://115790652812240",
	},
	XboxGlyphSheet = "rbxassetid://110161316257210",
	ClubBadgeSheet = "rbxassetid://139686032960693",
	HUD = {
		Logo = "rbxassetid://123091895810787",
		HomeBadge = "rbxassetid://113175743744467",
		AwayBadge = "rbxassetid://111967538963872",
		PlayerBadge = "rbxassetid://81668252360329",
		Glyphs = {
			RT = "rbxassetid://118891276729528",
			RB = "rbxassetid://104970858363532",
			Y = "rbxassetid://95291107724239",
			X = "rbxassetid://107395329048567",
			B = "rbxassetid://121923521436023",
		},
		Network = "rbxassetid://96628096969714",
		Locks = {
			"rbxassetid://98839632808068",
			"rbxassetid://114283576261352",
			"rbxassetid://113771960818328",
		},
		Minimap = {
			Ball = "rbxassetid://83221022961938",
			Friendly = "rbxassetid://131612878086300",
			Opponent = "rbxassetid://126163821187806",
		},
	},
	TypographyReference = "rbxassetid://88005646695090",
	--[[
		Local source map, for traceability (§57). Not a runtime loader -- Roblox
		cannot read a local file at runtime -- but it is what lets a moderation
		notice be traced back to the exact file that produced an asset.
		See docs/assets/roblox-asset-manifest.md.
	]]
	LocalSources = {
		LeftMouseClick = "assets/UI_assets/left_mouse_click.png",
		EscKey = "assets/UI_assets/esc_key.png",
		ControlSchemeKeyboard = "assets/UI_assets/keyboard_image.png",
		ControlSchemeGamepad = "assets/UI_assets/gamepad_image.png",
		PitchPositionGK = "assets/UI_assets/pitch_position_gk.png",
		PitchPositionDEF = "assets/UI_assets/pitch_position_def.png",
		PitchPositionMID = "assets/UI_assets/pitch_position_mid.png",
		PitchPositionFWD = "assets/UI_assets/pitch_position_fwd.png",
		Logo = "assets/UI_assets/Beyond 90 transparent logo.png",
		MenuStadium = "assets/UI_assets/Menu stadium background.png",
		XboxGlyphSheet = "assets/UI_assets/Xbox controller glyph set.png",
		ClubBadgeSheet = "assets/UI_assets/Club team badge placeholders.png",
		OpenMenu = "assets/UI_assets/open menu icon.png",
		Time = "assets/UI_assets/time icon.png",
		Select = "assets/UI_assets/A select icon.png",
		NigeriaFlag = "assets/UI_assets/nigerian flag icon.png",
	},
}

--[[
	The pitch preview for a position slot id (GK / DEF#n / MID#n / FWD#n).

	Returns "" when there is no image for the group, which callers treat as
	"draw the pitch instead" rather than as an error (§57).
]]
function UIAssetConfig.GetPitchPositionImage(slotId: string?): string
	if typeof(slotId) ~= "string" then
		return ""
	end
	-- Slot ids carry an index ("DEF#2"); the artwork is per GROUP.
	local group = string.match(slotId, "^(%a+)") or slotId
	return UIAssetConfig.PitchPositions[string.upper(group)] or ""
end

return UIAssetConfig
