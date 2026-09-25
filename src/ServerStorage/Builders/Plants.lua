--[[
	Plants builder
	Iris and reeds along the edges of the ponds and the creek, as the photos
	show them: clumps of sword-shaped iris leaves, fanning out, and taller,
	thinner reeds. From TerrainData.Plants (tools/make_terrain.py).

		require(game.ServerStorage.Builders.Plants).build()

	Leaves don't collide. Now and then an iris has a yellow flower.
]]

local ServerStorage = game:GetService("ServerStorage")

local Plants = {}

local IRIS = { Color3.fromRGB(88, 136, 64), Color3.fromRGB(104, 148, 72), Color3.fromRGB(78, 124, 60) }
local REED = { Color3.fromRGB(120, 140, 70), Color3.fromRGB(134, 146, 80) }
local FLOWER = Color3.fromRGB(236, 206, 60)

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

local function groundY(x, z, fallback)
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), groundParams)
	return if hit then hit.Position.Y else fallback
end

local function blade(model, base, height, width, tilt, turn, colour)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.new(width, height, 0.12)
	p.Color = colour
	p.Material = Enum.Material.Grass
	-- Standing on its foot, leaning out.
	p.CFrame = CFrame.new(base) * CFrame.Angles(0, turn, 0) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, height / 2, 0)
	p.Parent = model
	return p
end

local function iris(model, base, rng)
	local colour = IRIS[rng:NextInteger(1, #IRIS)]
	for _ = 1, rng:NextInteger(7, 12) do
		blade(model, base + Vector3.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6)),
			rng:NextNumber(2.2, 3.4), rng:NextNumber(0.25, 0.4), math.rad(rng:NextNumber(5, 28)),
			rng:NextNumber(0, math.pi * 2), colour:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.15)))
	end
	if rng:NextNumber() < 0.12 then
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * 0.5
		p.Color = FLOWER
		p.Material = Enum.Material.SmoothPlastic
		p.CFrame = CFrame.new(base + Vector3.new(0, 3.5, 0))
		p.Parent = model
	end
end

local function reed(model, base, rng)
	local colour = REED[rng:NextInteger(1, #REED)]
	for _ = 1, rng:NextInteger(10, 16) do
		blade(model, base + Vector3.new(rng:NextNumber(-0.9, 0.9), 0, rng:NextNumber(-0.9, 0.9)),
			rng:NextNumber(3.5, 6), rng:NextNumber(0.1, 0.18), math.rad(rng:NextNumber(0, 10)),
			rng:NextNumber(0, math.pi * 2), colour:Lerp(Color3.fromRGB(170, 160, 100), rng:NextNumber(0, 0.3)))
	end
end

function Plants.build()
	local data = ServerStorage:WaitForChild("TerrainData"):WaitForChild("Plants").Value
	local root = workspace:FindFirstChild("DuckPond") or Instance.new("Folder")
	root.Name = "DuckPond"
	root.Parent = workspace
	local old = root:FindFirstChild("Plants")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Plants"
	folder.Parent = root
	local n = 0
	for line in string.gmatch(data, "[^\n]+") do
		local x, z, y, kind = string.match(line, "(%S+) (%S+) (%S+) (%S+)")
		x, z, y = tonumber(x), tonumber(z), tonumber(y)
		local model = Instance.new("Model")
		model.Name = kind
		local base = Vector3.new(x, groundY(x, z, y) - 0.2, z)
		local rng = Random.new(math.floor(x * 13 + z * 7))
		if kind == "reed" then
			reed(model, base, rng)
		else
			iris(model, base, rng)
		end
		model.Parent = folder
		n += 1
		if n % 150 == 0 then
			task.wait()
		end
	end
	return n .. " clumps"
end

return Plants
