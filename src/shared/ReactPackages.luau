local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local packages = ReplicatedStorage:FindFirstChild("Packages") or Shared:FindFirstChild("Packages")

assert(packages, "Beyond 90 React packages are missing; run 'wally install' before Rojo sync/build")

return {
	React = require(packages:WaitForChild("React")),
	ReactRoblox = require(packages:WaitForChild("ReactRoblox")),
}
