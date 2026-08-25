local ExperienceConfig = {
	States = {
		Boot = "Boot",
		MenuLoading = "MenuLoading",
		Menu = "Menu",
		ModeLoading = "ModeLoading",
		Gameplay = "Gameplay",
	},
	StartupMinimumDisplayTime = 5.6,
	ModeMinimumDisplayTime = 3.5,
	ReturnToMenuMinimumDisplayTime = 1.5,
	PreloadTimeout = 12,
	CharacterReadyTimeout = 15,
	FadeDuration = 0.35,
	MenuRevealDuration = 2.25,
	StartupHandoffDuration = 1.75,
}

return ExperienceConfig
