--[[
	Terrain builder
	Writes the Duck Pond's terrain into workspace.Terrain from TerrainData,
	which tools/make_terrain.py makes from USGS elevation and OpenStreetMap.

	Run it in Studio, in Edit mode (the command bar, or the MCP), then save the
	place: terrain lives in the place file, not in the repo.

		require(game.ServerStorage.Builders.Terrain).build()

	It works in chunks and yields between them, so Studio stays responsive;
	workspace's "TerrainBuild" attribute says how far along it is.
]]

local ServerStorage = game:GetService("ServerStorage")

local Terrain = {}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHUNK = 32 -- cells a side per WriteVoxels call

local function decoder()
	local value = {}
	for i = 1, #B64 do
		value[string.byte(B64, i)] = i - 1
	end
	return value
end

-- A cell's height in studs above Y = 0, or nil for none. 2 chars a cell,
-- quarter studs, 0 meaning none.
local function reader(data, value)
	return function(index)
		local a, b = string.byte(data, index * 2 - 1, index * 2)
		local q = value[a] * 64 + value[b]
		if q == 0 then
			return nil
		end
		return (q - 1) / 4
	end
end

function Terrain.build()
	local folder = ServerStorage:WaitForChild("TerrainData")
	local meta = require(folder:WaitForChild("Meta"))
	local value = decoder()
	local height = reader(folder:WaitForChild("Height").Value, value)
	local water = reader(folder:WaitForChild("Water").Value, value)
	local materialCodes = folder:WaitForChild("Material").Value
	local materials = {}
	for code, name in pairs(meta.materials) do
		materials[string.byte(code)] = Enum.Material[name]
	end

	local nx, nz, cell = meta.nx, meta.nz, meta.cell
	local terrain = workspace.Terrain
	terrain:Clear()

	-- The floor everything stands on: a little below the lowest ground.
	local lowest = math.huge
	for i = 1, nx * nz do
		lowest = math.min(lowest, height(i))
	end
	local floorY = math.floor((lowest - 12) / 4) * 4

	local chunksX, chunksZ = math.ceil(nx / CHUNK), math.ceil(nz / CHUNK)
	local done, total = 0, chunksX * chunksZ
	for cz = 0, chunksZ - 1 do
		for cx = 0, chunksX - 1 do
			local ix0, iz0 = cx * CHUNK, cz * CHUNK
			local w, d = math.min(CHUNK, nx - ix0), math.min(CHUNK, nz - iz0)
			-- This chunk's columns, and how high it reaches.
			local top = floorY + 4
			local columns = {}
			for dz = 0, d - 1 do
				for dx = 0, w - 1 do
					local index = (iz0 + dz) * nx + (ix0 + dx) + 1
					local g, wt = height(index), water(index)
					columns[dz * w + dx] = { g, wt, materials[string.byte(materialCodes, index)] or Enum.Material.Grass }
					top = math.max(top, g, wt or 0)
				end
			end
			local layers = math.ceil((top - floorY) / 4) + 1

			local mats, occs = {}, {}
			for x = 1, w do
				local mx, ox = {}, {}
				mats[x], occs[x] = mx, ox
				for y = 1, layers do
					mx[y], ox[y] = {}, {}
				end
			end
			for dz = 0, d - 1 do
				for dx = 0, w - 1 do
					local c = columns[dz * w + dx]
					local g, wt, m = c[1], c[2], c[3]
					for y = 1, layers do
						local y0 = floorY + (y - 1) * 4
						local solid = math.clamp((g - y0) / 4, 0, 1)
						local wet = if wt then math.clamp((wt - y0) / 4, 0, 1) else 0
						local mat, occ = Enum.Material.Air, 0
						if solid >= 0.5 or (solid > 0 and wet == 0) then
							mat, occ = m, solid
						elseif wet > 0 then
							mat, occ = Enum.Material.Water, wet
						end
						mats[dx + 1][y][dz + 1] = mat
						occs[dx + 1][y][dz + 1] = occ
					end
				end
			end
			local origin = Vector3.new(meta.x0 + ix0 * cell, floorY, meta.z0 + iz0 * cell)
			local region = Region3.new(origin, origin + Vector3.new(w * cell, layers * 4, d * cell))
			terrain:WriteVoxels(region, 4, mats, occs)

			done += 1
			workspace:SetAttribute("TerrainBuild", string.format("%d / %d chunks", done, total))
			task.wait()
		end
	end

	-- A pond, not a swimming pool: murky, still, a little green.
	terrain.WaterColor = Color3.fromRGB(62, 84, 58)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.04
	terrain.WaterWaveSpeed = 4
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(96, 140, 64))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(78, 118, 56))
	terrain:SetMaterialColor(Enum.Material.Pavement, Color3.fromRGB(156, 150, 140))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(96, 80, 58))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(196, 174, 128))

	-- Where players arrive: a path by the water.
	local spawn = workspace:FindFirstChild("SpawnLocation") or Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn:ClearAllChildren()
	spawn.Position = Vector3.new(meta.spawn[1], meta.spawn[2], meta.spawn[3])
	spawn.Parent = workspace
	local base = workspace:FindFirstChild("Baseplate")
	if base then
		base:Destroy()
	end

	workspace:SetAttribute("TerrainBuild", "done")
	return string.format("built %d x %d cells", nx, nz)
end

return Terrain
