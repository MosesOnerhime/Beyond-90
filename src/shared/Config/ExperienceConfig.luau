local ExperienceConfig = {
	States = {
		Boot = "Boot",
		MenuLoading = "MenuLoading",
		Menu = "Menu",
		ModeLoading = "ModeLoading",
		Gameplay = "Gameplay",
	},
	--[[
		INTRO TIMING (§9).

		The branding sequence used to run about 20 seconds: a 5-second asset
		preload the Drixil stage did not need, ~6.2s of Drixil, ~7.4s of
		Beyond 90, and only then a serial menu preload. None of that was
		presentation -- it was waiting, dressed as a title sequence.

		These are the visible durations. Everything that can be loaded during
		them now is, so cold loading overlaps the branding rather than
		preceding it.
	]]
	Intro = {
		-- Drixil: type on, settle, leave. ~1.25s total.
		DrixilRevealDuration = 0.55,
		DrixilLetterStagger = 0.028,
		DrixilHold = 0.3,
		DrixilFadeDuration = 0.4,
		-- Beyond 90: emerge, present, recede. ~2.0s total.
		BeyondFadeInDuration = 0.7,
		BeyondHold = 0.55,
		BeyondFadeOutDuration = 0.75,
		--[[
			The logo has had the whole Drixil stage to decode by now, so on a
			warm client this costs nothing. On a genuinely cold first join the
			asset takes several seconds to fetch, and 1.5s was tight enough that
			the wordmark fallback appeared on roughly half of cold starts --
			which is a worse outcome than a slightly longer ident.
		]]
		LogoDecodeTimeout = 3,
		-- Beat of black between the two stages, so they read as separate.
		StageGap = 0.12,
	},

	StartupMinimumDisplayTime = 5.6,
	ModeMinimumDisplayTime = 3.5,
	ReturnToMenuMinimumDisplayTime = 1.5,
	PreloadTimeout = 12,
	--[[
		How long StartupLoading may go without a heartbeat before StartupFallback
		concludes it has stalled and takes over. This is a STALL timeout, not a
		budget for the branded sequence -- the intro may run as long as it likes.
	]]
	StartupStallTimeout = 10,
	CharacterReadyTimeout = 15,
	FadeDuration = 0.35,
	MenuRevealDuration = 2.25,
	StartupHandoffDuration = 0.5,
}

return ExperienceConfig
