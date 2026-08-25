local AudioConfig = {
	FadeSeconds = 0.75,
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
			Volume = 0.48,
		},
	},
	Gameplay = {
		DribbleTouch = {
			AssetId = "4458219865",
			Volume = 0.32,
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
