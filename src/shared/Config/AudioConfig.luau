local AudioConfig = {
	FadeSeconds = 0.75,

	--[[
		MENU MUSIC VOLUME.

		The menu track used to come in at 0.5 and it sat far too loud over the
		menu -- loud enough that it competed with the branding sting rather than
		sitting under it. The default is now 0.3, which is where the mix wants it.

		It is also a SETTING now, so a player can put it where they like without
		having to choose between "as loud as this" and "off". Session scoped and
		stored on the player: persistence is a later milestone, and a value that
		only lasts the session is much better than no control at all.

		Only the menu music reads this. Crowd ambience, the whistle and every
		gameplay SFX are match audio, not background music, and are untouched.
	]]
	Music = {
		DefaultVolume = 0.3,
		Minimum = 0,
		Maximum = 1,
		AttributeName = "Beyond90MusicVolume",
		-- Granularity of the slider, so dragging lands on tidy percentages.
		Step = 0.05,
	},
	Startup = {
		AssetId = "115017291331516",
		LocalSource = "assets/audio/sfx/B90_Startup_Logo_Sting.mp3",
		Volume = 1,
	},
	MenuTracks = {
		{
			Name = "Danza Kuduro",
			AssetId = "80210594606101",
			LocalSource = "assets/audio/music/main - Danza Kuduro.mp3",
		},
		{
			Name = "The Football Freestyler",
			AssetId = "136774397148813",
			LocalSource = "assets/audio/music/secondary 1 - Ramenez la coupe à la maison.mp3",
		},
		{
			Name = "C'est pour la vie",
			AssetId = "126238364412134",
			LocalSource = "assets/audio/music/secondary 2 - C’est la vie.mp3",
		},
	},
	UI = {
		Click = {
			AssetId = "117649901456711",
			LocalSource = "assets/audio/sfx/button click.mp3",
			Volume = 0.45,
		},
	},
	Crowd = {
		Base = {
			AssetId = "7378338223",
			LocalSource = "assets/audio/sfx/stadium crowd.mp3",
			-- Raised so the stadium reads as occupied. Kept below the whistle
			-- (0.85) and goal audio so match events still cut through.
			Volume = 0.6,
		},
	},
	Match = {
		StartWhistle = {
			AssetId = "9125967307",
			Volume = 0.85,
			PlaybackSpeed = 1,
		},
	},
	Gameplay = {
		DribbleTouch = {
			AssetId = "4458219865",
			Volume = 0.2,
			PlaybackSpeed = 1.04,
		},
		Pass = {
			AssetId = "4458219865",
			Volume = 0.58,
			PlaybackSpeed = 0.96,
		},
		Shoot = {
			AssetId = "4458219865",
			Volume = 0.68,
			PlaybackSpeed = 0.9,
		},
		GoalNet = {
			AssetId = "5568887127",
			Volume = 1,
			PlaybackSpeed = 1,
		},
		GoalCommentary = {
			AssetId = "132952369664787",
			Volume = 0.82,
			PlaybackSpeed = 1,
		},
	},
}

function AudioConfig.NormalizeAssetId(value): string
	if typeof(value) ~= "string" then
		return ""
	end
	if string.match(value, "^rbxassetid://%d+$") then
		return value
	end
	local numericId = string.match(value, "^%s*(%d+)%s*$")
	return if numericId then "rbxassetid://" .. numericId else ""
end

return AudioConfig
