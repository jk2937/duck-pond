--[[
	Everything, in order: the terrain first (the rest sit on it), then the
	paths and bridges, trees, plants, and the buildings and furniture (the
	credits sign stands by the spawn the terrain places).

		require(game.ServerStorage.Builders.All).build()

	Takes a minute or so; save the place afterwards.
]]

local All = {}

function All.build()
	local results = {}
	for _, name in ipairs({ "Terrain", "Paths", "Trees", "Plants", "Landmarks" }) do
		-- A fresh copy of each: require caches, and the builders change.
		local builder = require(game:GetService("ServerStorage").Builders:WaitForChild(name):Clone())
		table.insert(results, name .. ": " .. tostring(builder.build()))
	end
	return table.concat(results, "\n")
end

return All
