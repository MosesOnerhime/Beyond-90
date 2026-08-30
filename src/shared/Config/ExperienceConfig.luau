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
		--[[
			PACE: LUXURIOUS, NOT LEISURELY.

			The previous pass over-corrected. Cutting a bloated 20-second sequence
			down to ~3.9s removed the waiting, but it also removed the ident: a
			publisher card that types on and leaves inside two seconds reads as a
			transition, not as a title.

			A studio ident earns its length by HOLDING. The reference shape --
			Konami, EA SPORTS, the broadcast idents this game is presented like --
			is roughly a beat to arrive, a beat to sit, a beat to leave, per stage.
			Around seven seconds across two stages is where that lands: long enough
			to feel deliberate and owned, short enough that a returning player is
			not tapping to skip it.

			The stage totals below are therefore weighted toward the HOLDS and the
			fades rather than the reveal. Time spent watching something arrive is
			time spent waiting; time spent looking at it is presentation.
		]]
		--[[
			The Drixil card SETTLES on -- it rises a few pixels into place while
			the letters fade up -- rather than growing.

			The distinction is not stylistic, it is a performance one, and
			getting it wrong is what made this ident stutter.

			Scaling was tried and had to be withdrawn. The wordmark is ~18
			TextLabels with AutomaticSize.X inside a UIListLayout, so changing a
			UIScale on the row forces Roblox to re-measure every label, re-run
			the whole row's layout, and re-rasterise every glyph at the new size
			-- ON EVERY FRAME OF THE TWEEN. The Beyond 90 stage gets away with
			exactly this motion because it is a single ImageLabel, where a scale
			is a GPU transform of one already-rasterised texture and costs
			nothing. Text is not an image, and that is the whole difference.

			It landed on the worst possible stretch of the timeline: the client
			measured 15.0 FPS while this stage was running, because the React
			menu and the audio bank are still being built behind the cover. Two
			and a half seconds of continuous re-layout there reads as stutter.

			A POSITION tween has none of that cost. Nothing is re-measured, no
			layout is re-run, no glyph is re-rasterised -- the same quads are
			composited at a different offset -- so it stays smooth even on a
			frame that arrives late. It still reads as the card arriving and
			coming to rest, which is what was actually wanted.

			In pixels at a 1280-wide reference viewport; scaled with the rest of
			the ident so it is proportionate on a 780x360 phone.
		]]
		DrixilSettleOffset = 14,
		-- Drixil: type on, settle, leave. ~3.15s total.
		DrixilRevealDuration = 0.8,
		DrixilLetterStagger = 0.045,
		DrixilHold = 0.9,
		DrixilFadeDuration = 0.65,
		-- Beyond 90: emerge, present, recede. ~3.25s total.
		BeyondFadeInDuration = 1.15,
		BeyondHold = 1.15,
		--[[
			The recede is the longest beat of the whole ident.

			It was reading as a CUT rather than a fade. A logo that leaves faster
			than it arrived always will -- the eye is already tracking it, so the
			exit needs more time than the entrance, not less. This is now
			comfortably the longest of the three, and the black beat below gives
			it somewhere to land instead of running straight into the menu.
		]]
		BeyondFadeOutDuration = 1.3,
		--[[
			A beat of black AFTER the logo has gone, before the menu is revealed.

			Without it the handoff begins the instant the logo hits zero, so the
			end of the fade and the start of the reveal overlap and the ident
			appears to be interrupted rather than finished.
		]]
		PostBeyondHold = 0.4,
		--[[
			The logo has had the whole Drixil stage to decode by now, so on a
			warm client this costs nothing. On a genuinely cold first join the
			asset takes several seconds to fetch, and 1.5s was tight enough that
			the wordmark fallback appeared on roughly half of cold starts --
			which is a worse outcome than a slightly longer ident.
		]]
		LogoDecodeTimeout = 3,
		-- Beat of black between the two stages, so they read as separate. Long
		-- enough now to register as a deliberate cut rather than a dropped frame.
		StageGap = 0.4,
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
	-- The cover's own fade off the finished ident. Longer than it was: a
	-- half-second cross-fade out of a seven-second title sequence reads as a cut.
	StartupHandoffDuration = 0.85,
}

return ExperienceConfig
