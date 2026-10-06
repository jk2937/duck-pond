--[[
	Landmarks builder
	The buildings round the Duck Pond and the furniture along its paths, from
	TerrainData.Landmarks (tools/make_landmarks.py: OSM footprints, lidar
	heights, OSM furniture, and guessed benches and lamps by the water).

		require(game.ServerStorage.Builders.Landmarks).build()

	Buildings are massing for now -- walls and a flat roof, at their measured
	height -- in Hokie Stone for the university's. Solitude is modelled from
	the photos: white clapboard, a green metal gable roof, red brick chimneys.
	Furniture follows the photos: slatted wooden benches, concrete picnic
	tables, black lamp posts with lanterns.
]]

local ServerStorage = game:GetService("ServerStorage")

local Landmarks = {}

local HOKIE_STONE = Color3.fromRGB(150, 142, 130)
local CONCRETE = Color3.fromRGB(176, 172, 164)
local WHITE_BOARD = Color3.fromRGB(236, 234, 226)
local GREEN_ROOF = Color3.fromRGB(62, 92, 74)
local BRICK = Color3.fromRGB(150, 62, 48)
local IRON = Color3.fromRGB(30, 32, 34)
local SLAT = Color3.fromRGB(120, 88, 58)
local BIN_GREEN = Color3.fromRGB(40, 64, 48)

local function part(parent, name, size, cframe, colour, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

-- The terrain's surface under a point, or the fallback.
local function groundY(x, z, fallback)
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), groundParams)
	return if hit then hit.Position.Y else fallback
end

-- A flat triangle a, b, c (all at the same height), `thick` deep, from two
-- wedges: the usual Roblox trick.
local function triangle(parent, a, b, c, thick, colour, material)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.05 then
		return
	end
	local w1 = Instance.new("WedgePart")
	local w2 = Instance.new("WedgePart")
	for _, w in ipairs({ w1, w2 }) do
		w.Anchored = true
		w.Color = colour
		w.Material = material
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
	end
	w1.Size = Vector3.new(thick, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(thick, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	w1.Parent = parent
	w2.Parent = parent
end

-- A wall from a to b (ground points), `height` tall, down into the ground.
local function wall(parent, a, b, bottom, top, thick, colour, material)
	local flatA, flatB = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	local length = (flatB - flatA).Magnitude
	if length < 0.1 then
		return
	end
	local mid = (flatA + flatB) / 2
	part(parent, "Wall", Vector3.new(thick, top - bottom, length + thick),
		CFrame.lookAt(Vector3.new(mid.X, (top + bottom) / 2, mid.Z), Vector3.new(flatB.X, (top + bottom) / 2, flatB.Z)),
		colour, material)
end

-- The massing: walls round the footprint, a roof over it, a coping on top.
local function building(parent, spec)
	local model = Instance.new("Model")
	model.Name = if spec.name ~= "" then spec.name else "Building"
	model.Parent = parent
	local university = spec.kind == "university" or spec.kind == "college" or spec.kind == "dormitory"
	local colour = if university then HOKIE_STONE else Color3.fromRGB(196, 190, 180)
	local material = if university then Enum.Material.Slate else Enum.Material.Brick
	local bottom, top = spec.base - 6, spec.base + spec.height
	local pts = {}
	for _, p in ipairs(spec.points) do
		table.insert(pts, Vector3.new(p[1], top, p[2]))
	end
	for i = 1, #pts do
		wall(model, pts[i], pts[i % #pts + 1], bottom, top, 1.2, colour, material)
	end
	for _, t in ipairs(spec.triangles) do
		triangle(model, pts[t[1]], pts[t[2]], pts[t[3]], 1, Color3.fromRGB(90, 90, 94), Enum.Material.Concrete)
	end
	return model
end

-- Solitude, from the photos: a white clapboard house, two storeys, a
-- pitched green metal roof, red brick chimneys at the gable ends. Built as
-- a clean rectangle along the footprint's long axis (the mapped outline has
-- wings and porches that a simple roof can't sit on), no wider than a house.
local function solitude(parent, spec)
	local model = Instance.new("Model")
	model.Name = "Solitude"
	model.Parent = parent

	-- The footprint's middle and long axis.
	local cx, cz = 0, 0
	for _, p in ipairs(spec.points) do
		cx += p[1]
		cz += p[2]
	end
	cx /= #spec.points
	cz /= #spec.points
	local sxx, szz, sxz = 0, 0, 0
	for _, p in ipairs(spec.points) do
		local dx, dz = p[1] - cx, p[2] - cz
		sxx += dx * dx
		szz += dz * dz
		sxz += dx * dz
	end
	local angle = 0.5 * math.atan2(2 * sxz, sxx - szz)
	local along = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local across = Vector3.new(-along.Z, 0, along.X)
	local minA, maxA, minC, maxC = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(spec.points) do
		local d = Vector3.new(p[1] - cx, 0, p[2] - cz)
		minA, maxA = math.min(minA, d:Dot(along)), math.max(maxA, d:Dot(along))
		minC, maxC = math.min(minC, d:Dot(across)), math.max(maxC, d:Dot(across))
	end
	local length = math.min(maxA - minA, 16 / 0.28) -- at most 16 m long
	local width = math.min(maxC - minC, 8.5 / 0.28) -- and 8.5 m deep
	local centre = Vector3.new(cx, 0, cz) + along * (minA + maxA) / 2 + across * (minC + maxC) / 2
	local ground = groundY(centre.X, centre.Z, spec.base)
	-- Lowest ground under the corners, so the walls never float.
	for _, sa in ipairs({ -1, 1 }) do
		for _, sc in ipairs({ -1, 1 }) do
			local q = centre + along * sa * length / 2 + across * sc * width / 2
			ground = math.min(ground, groundY(q.X, q.Z, ground))
		end
	end
	local eaves = ground + 6.2 / 0.28
	-- X along the ridge, Z across it (fromMatrix takes X and Y; Z follows).
	local basis = CFrame.fromMatrix(Vector3.zero, along, Vector3.yAxis).Rotation
	local function at(a, y, c)
		return centre + along * a + across * c + Vector3.new(0, y, 0)
	end

	-- The walls: one block, clapboard white.
	local bottom = ground - 3
	part(model, "Walls", Vector3.new(length, eaves - bottom, width),
		CFrame.new(centre.X, (eaves + bottom) / 2, centre.Z) * basis, WHITE_BOARD, Enum.Material.WoodPlanks)

	-- The roof: two slabs from the eaves (with a little overhang) up to the
	-- ridge, meeting exactly along it.
	local pitch = math.rad(35)
	local rise = (width / 2) * math.tan(pitch)
	local ridgeY = eaves + rise
	local overhang = 1.5
	for _, sc in ipairs({ -1, 1 }) do
		local ridge = at(0, eaves + rise, 0)
		local eave = at(0, eaves, sc * width / 2)
		local down = (eave - ridge).Unit
		local lower = eave + down * overhang
		local mid = (ridge + lower) / 2
		local slope = (lower - ridge).Magnitude
		local normal = along:Cross(down).Unit
		if normal.Y < 0 then
			normal = -normal
		end
		local cf = CFrame.fromMatrix(mid + normal * 0.3, along, normal)
		part(model, "Roof", Vector3.new(length + overhang * 2, 0.6, slope), cf, GREEN_ROOF, Enum.Material.SmoothPlastic)
	end
	-- The gable ends: triangles of clapboard, flush with the end walls.
	for _, sa in ipairs({ -1, 1 }) do
		triangle(model, at(sa * length / 2, eaves, -width / 2), at(sa * length / 2, eaves, width / 2),
			at(sa * length / 2, ridgeY, 0), 1, WHITE_BOARD, Enum.Material.WoodPlanks)
	end
	-- A chimney in each gable wall, up through the roof past the ridge.
	for _, sa in ipairs({ -1, 1 }) do
		local base = at(sa * (length / 2 - 1.2), 0, 0)
		local top = ridgeY + 4
		part(model, "Chimney", Vector3.new(3.4, top - bottom, 5), CFrame.new(base.X, (top + bottom) / 2, base.Z) * basis,
			BRICK, Enum.Material.Brick)
	end
	return model
end

-- Furniture ------------------------------------------------------------------

local function bench(parent, at)
	-- 1.8 m of wooden slats on an iron frame, facing the water.
	local m = Instance.new("Model")
	m.Name = "Bench"
	for i = 0, 2 do
		part(m, "Seat", Vector3.new(6.4, 0.25, 0.45), at * CFrame.new(0, 1.6, -0.2 + i * 0.55), SLAT, Enum.Material.Wood)
	end
	for i = 0, 1 do
		part(m, "Back", Vector3.new(6.4, 0.45, 0.2), at * CFrame.new(0, 2.4 + i * 0.6, 1.05) * CFrame.Angles(math.rad(-12), 0, 0),
			SLAT, Enum.Material.Wood)
	end
	-- A seat, so a player can sit and look at the water.
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Anchored = true
	seat.Transparency = 1
	seat.Size = Vector3.new(5, 0.3, 1.4)
	seat.CFrame = at * CFrame.new(0, 1.75, 0.35)
	seat.Parent = m
	for _, x in ipairs({ -2.8, 2.8 }) do
		part(m, "Leg", Vector3.new(0.25, 1.6, 1.6), at * CFrame.new(x, 0.8, 0.3), IRON, Enum.Material.Metal)
		part(m, "Arm", Vector3.new(0.25, 1.5, 0.25), at * CFrame.new(x, 2.4, 1.05), IRON, Enum.Material.Metal)
	end
	m.Parent = parent
end

local function picnic(parent, at)
	-- The photos: all concrete, a slab top and slab seats on pedestals.
	local m = Instance.new("Model")
	m.Name = "PicnicTable"
	part(m, "Top", Vector3.new(6.4, 0.5, 3), at * CFrame.new(0, 2.6, 0), CONCRETE, Enum.Material.Concrete)
	part(m, "Pedestal", Vector3.new(1.2, 2.4, 1.6), at * CFrame.new(0, 1.3, 0), CONCRETE, Enum.Material.Concrete)
	for _, z in ipairs({ -2.8, 2.8 }) do
		part(m, "Seat", Vector3.new(6.4, 0.4, 1.2), at * CFrame.new(0, 1.55, z), CONCRETE, Enum.Material.Concrete)
		part(m, "SeatFoot", Vector3.new(1, 1.4, 1), at * CFrame.new(0, 0.7, z), CONCRETE, Enum.Material.Concrete)
	end
	m.Parent = parent
end

local function lamp(parent, at)
	-- A black post with a lantern: a warm glow, bright enough to see at night.
	local m = Instance.new("Model")
	m.Name = "Lamp"
	part(m, "Post", Vector3.new(0.45, 12.5, 0.45), at * CFrame.new(0, 6.25, 0), IRON, Enum.Material.Metal)
	part(m, "Base", Vector3.new(0.9, 1.2, 0.9), at * CFrame.new(0, 0.6, 0), IRON, Enum.Material.Metal)
	local glass = part(m, "Lantern", Vector3.new(1.3, 1.8, 1.3), at * CFrame.new(0, 13.3, 0),
		Color3.fromRGB(255, 220, 160), Enum.Material.Neon, { Transparency = 0.2 })
	part(m, "Cap", Vector3.new(1.7, 0.4, 1.7), at * CFrame.new(0, 14.4, 0), IRON, Enum.Material.Metal)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 206, 140)
	light.Range = 26
	light.Brightness = 1.2
	light.Parent = glass
	m.Parent = parent
end

local function bin(parent, at)
	local m = Instance.new("Model")
	m.Name = "Bin"
	part(m, "Body", Vector3.new(3, 2, 2), at * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)), BIN_GREEN,
		Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	m.Parent = parent
end

local function fountain(parent, at)
	local m = Instance.new("Model")
	m.Name = "DrinkingFountain"
	part(m, "Pedestal", Vector3.new(1.4, 3, 1.4), at * CFrame.new(0, 1.5, 0), CONCRETE, Enum.Material.Concrete)
	part(m, "Bowl", Vector3.new(2, 0.5, 2), at * CFrame.new(0, 3.2, 0), Color3.fromRGB(140, 144, 150), Enum.Material.Metal)
	m.Parent = parent
end

local function shelter(parent, at)
	-- A picnic shelter: four posts and a hipped roof.
	local m = Instance.new("Model")
	m.Name = "Shelter"
	local half = 8
	for _, x in ipairs({ -half, half }) do
		for _, z in ipairs({ -half, half }) do
			part(m, "Post", Vector3.new(0.9, 10, 0.9), at * CFrame.new(x, 5, z), SLAT, Enum.Material.Wood)
		end
	end
	part(m, "Beam", Vector3.new(half * 2 + 2, 0.8, half * 2 + 2), at * CFrame.new(0, 10.2, 0), SLAT, Enum.Material.Wood)
	for k = 0, 3 do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.Color = GREEN_ROOF
		w.Material = Enum.Material.Metal
		w.Size = Vector3.new(half * 2 + 3, 3.5, half + 1.5)
		w.CFrame = at * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 12.3, (half + 1.5) / 2)
		w.Parent = m
	end
	picnic(m, at)
	m.Parent = parent
end

-- The sign by the spawn: where you are, and whose data made it (OSM's
-- licence asks for the credit).
local CREDIT = "THE DUCK POND\nVirginia Tech · Blacksburg, Virginia\n\n"
	.. "Map data © OpenStreetMap contributors\nGround and trees: USGS 3DEP elevation and lidar\n"
	.. "Tree species: Virginia Tech Campus Tree Inventory\n"
	.. "Maple models: TreeML-Data (CC BY 4.0), Yazdi et al.\n"
	.. "Reference photos: Wikimedia Commons contributors"

local function sign(parent, at, textOverride, name)
	local m = Instance.new("Model")
	m.Name = name or "Sign"
	-- Posts at the board's ends, clear of its face, so they never cover the text.
	for _, x in ipairs({ -3.5, 3.5 }) do
		part(m, "Post", Vector3.new(0.5, 6.4, 0.5), at * CFrame.new(x, 3.2, 0), SLAT, Enum.Material.Wood)
	end
	local board = part(m, "Board", Vector3.new(6.4, 3.8, 0.3), at * CFrame.new(0, 4.4, 0), Color3.fromRGB(96, 70, 46),
		Enum.Material.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(244, 236, 214)
	text.Font = Enum.Font.GothamMedium
	text.TextScaled = true
	text.Text = textOverride or CREDIT
	text.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = text
	m.Parent = parent
end

local FURNITURE = { bench = bench, picnic = picnic, lamp = lamp, bin = bin, fountain = fountain, shelter = shelter }

function Landmarks.build()
	-- A fresh copy each run: require caches, and the data changes between runs.
	local data = require(ServerStorage:WaitForChild("TerrainData"):WaitForChild("Landmarks"):Clone())
	local root = workspace:FindFirstChild("DuckPond") or Instance.new("Folder")
	root.Name = "DuckPond"
	root.Parent = workspace
	for _, name in ipairs({ "Buildings", "Furniture" }) do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = root
	local furniture = Instance.new("Folder")
	furniture.Name = "Furniture"
	furniture.Parent = root

	for _, spec in ipairs(data.buildings) do
		if spec.name == "Solitude" then
			solitude(buildings, spec)
		else
			building(buildings, spec)
		end
	end
	local counts = {}
	for _, f in ipairs(data.furniture) do
		local build = FURNITURE[f.kind]
		if build then
			local y = groundY(f.x, f.z, f.y)
			-- yaw: 0 is north (-Z), turning clockwise. Each piece is built
			-- facing -Z (a bench's back is at +Z), so this faces it the water.
			local at = CFrame.new(f.x, y, f.z) * CFrame.Angles(0, -f.yaw, 0)
			build(furniture, at)
			counts[f.kind] = (counts[f.kind] or 0) + 1
		end
	end
	-- The credits sign, beside the spawn, facing the player as they arrive.
	local spawn = workspace:FindFirstChild("SpawnLocation")
	if spawn then
		local beside = spawn.CFrame * CFrame.new(7, 0, -2)
		local y = groundY(beside.X, beside.Z, beside.Y)
		sign(furniture, CFrame.new(beside.X, y, beside.Z) * spawn.CFrame.Rotation * CFrame.Angles(0, math.rad(200), 0))
		-- And its neighbour: where the trees came from.
		local statsModule = ServerStorage.TerrainData:FindFirstChild("TreeStats")
		if statsModule then
			local st = require(statsModule:Clone())
			-- Lidar trees are found, and matched to the inventory, by estimate:
			-- those counts are approximate. The photos are counted exactly.
			local text = string.format("THE TREES: about %d (approximate)\n\n~%d  lidar, named by VT's inventory\n"
				.. "~%d  VT inventory only (newer, or hidden)\n~%d  lidar only, estimated (no species)\n"
				.. "~%d  removed since the 2017 scan\n\nVT photos: %d, of %d trees",
				st.total, st.both, st.inventoryOnly, st.lidarOnly, st.removed, st.photos, st.photoTrees)
			local other = spawn.CFrame * CFrame.new(-7, 0, -2)
			local oy = groundY(other.X, other.Z, other.Y)
			sign(furniture, CFrame.new(other.X, oy, other.Z) * spawn.CFrame.Rotation * CFrame.Angles(0, math.rad(160), 0),
				text, "TreeSign")
		end
	end
	local parts = {}
	for kind, n in pairs(counts) do
		table.insert(parts, n .. " " .. kind)
	end
	return string.format("%d buildings; %s", #data.buildings, table.concat(parts, ", "))
end

return Landmarks
