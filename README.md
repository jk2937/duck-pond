# Duck Pond

A faithful, real-scale model of the Duck Pond at Virginia Tech, Blacksburg, in
Roblox. A long-term hobby project.

## How it's made

The ground, water and paths come from real data:

- **Elevation:** USGS 3DEP, about 1 m resolution (public domain)
- **Map features:** OpenStreetMap: the ponds, islands, Stroubles Creek, weirs,
  paths, roads, trees, benches, buildings. © OpenStreetMap contributors, ODbL:
  the game must credit it.
- **Aerial imagery:** USGS, for reference (public domain)

```bash
python3 tools/fetch_data.py     # re-download into data/raw/ (already there)
python3 tools/make_terrain.py   # data/raw -> src/ServerStorage/TerrainData
```

Then in Studio (Edit mode), with Rojo connected:

```lua
require(game.ServerStorage.Builders.Terrain).build()
```

and save the place. Terrain lives in the place file, not the repo.

Scale: 1 stud = 0.28 m. North is -Z, east is +X, and the origin is the pond.

## Development

```bash
rojo serve
```

Serves on port 34876.

See `docs/PLAN.md` for the stages.
