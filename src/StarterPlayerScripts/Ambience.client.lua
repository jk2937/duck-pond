--[[
	Ambience
	What the Duck Pond sounds like, played on each player's own client:
	birdsong everywhere, and the weir's water tumbling down its steps, louder
	the nearer you are. Sounds are Pro Sound Effects, free on the Creator
	Store.
]]

local SoundService = game:GetService("SoundService")

local BIRDS = "rbxassetid://9112831284" -- Morning Birds 1 (SFX): chirping, a loop
local WEIR = "rbxassetid://9120552550" -- Waterfall Steady Stream 1 (SFX)

local birds = Instance.new("Sound")
birds.Name = "Birdsong"
birds.SoundId = BIRDS
birds.Looped = true
birds.Volume = 0.25
birds.Parent = SoundService
birds:Play()

-- The weir: a sound on the model itself, so it's positional.
task.spawn(function()
	-- With streaming on, the weir only arrives once you're near: wait for it.
	local step
	repeat
		local weir = workspace:FindFirstChild("DuckPond") and workspace.DuckPond:FindFirstChild("Bridges")
			and workspace.DuckPond.Bridges:FindFirstChild("Weir")
		step = weir and weir:FindFirstChild("Step")
		if not step then
			task.wait(2)
		end
	until step
	local water = Instance.new("Sound")
	water.Name = "WeirWater"
	water.SoundId = WEIR
	water.Looped = true
	water.Volume = 0.8
	water.RollOffMode = Enum.RollOffMode.InverseTapered
	water.RollOffMinDistance = 12
	water.RollOffMaxDistance = 220
	water.Parent = step
	water:Play()
end)
