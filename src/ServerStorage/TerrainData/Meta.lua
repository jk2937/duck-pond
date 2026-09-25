-- Written by tools/make_terrain.py; don't edit by hand.
return {
	nx = 672, -- cells east
	nz = 544, -- cells south
	cell = 4, -- studs
	x0 = -1396, -- the grid's north-west corner, studs
	z0 = -1136,
	baseMetres = 611.0, -- elevation at Y = 0
	metresPerStud = 0.28,
	spawn = { -62.0, 27.0, -122.0 }, -- on a path by the water
	materials = { g = "Grass", l = "LeafyGrass", s = "Sand", m = "Mud", a = "Asphalt", p = "Pavement", r = "Rock", b = "Ground" },
	source = "USGS 3DEP elevation; (c) OpenStreetMap contributors",
}
