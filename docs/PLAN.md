# Plan

1. **Terrain** -- real ground shape at real scale, grass, the ponds and creek
   as water, the islands, the weir. Paths and roads painted on.
2. **Paths and bridges** (first pass done: the five bridges and 13 flights of steps from OSM, smoothed path ground; looks guessed) -- proper path surfaces, steps, the Duck Pond Drive
   bridge and the footbridges.
3. **Trees and plantings** (first pass done: 865 real trees from USGS lidar -- broadleaf, willow, conifer) -- the mapped trees, plus the canopy seen in the
   aerial photo (the south and east banks are dense and mostly unmapped).
4. **Landmarks** (buildings DEFERRED: the base massing needs work before any detail pass; first pass done: 27 buildings at lidar heights, Solitude from photos, OSM + guessed benches, lamps, bins, picnic tables, shelter, fountain) -- benches, shelters, weirs, the gazebo, lamps; then the
   buildings around it (Solitude, The Grove, Hahn Hall, the Alumni Center)
   as simple massing.
5. **Life** (done: 40 ducks and geese that come to the edge and chase bread, birdsong, the weir's water, iris and reeds, seats on the benches, a credits sign). No day/night cycle: it stays afternoon.
6. **Detail** -- close work from ground photos.

Open questions: the gazebo's exact spot and style, the footbridges' look, how
deep the pond really is (the model guesses 2 m at most).

## Deferred

- **Buildings**: the base massing needs rework first (shapes, roofs, how they
  meet the ground), then a detail pass (windows, doors, Hokie Stone texture).
- **A real willow model**, if the part-built ones don't hold up.

## Rebuilding

After changing data or builders, in Studio (Edit mode):

```lua
require(game.ServerStorage.Builders.All).build()
```

then save the place. Visit notes go in `docs/VISIT_CHECKLIST.md`.

## Backlog

- **Paths look bad.** (First pass done: 239 paths and roads as ribbons of parts at
  real widths, grass under them; to refine: fewer parts on flat runs, curbs, surfaces
  checked on a visit.)
- **Path junctions.** Where two paths cross, each sits at its own fitted height, so one's
  edge shows as a thin ledge over the other. Fix: build junctions as one shared pad, and
  snap the paths meeting there to its height. They're painted into the terrain, whose voxels are 4
  studs (~1.1 m) -- Roblox's finest -- so a 3 m path is only ~3 voxels wide:
  jagged, stair-stepped edges, and the pavement blends into the grass.
  Terrain can't go finer. Proposed fix: draw paths as their own surface -- a
  smooth ribbon of thin parts along each OSM line, sitting just on the
  ground, with round joints at bends, real widths and a proper paving
  material -- and leave the terrain under them as ground.

## Where things stand (2026-09-27)

Done since the stages above: VT Campus Tree Inventory merged into the trees
(species, sizes; 152 misplaced trees moved off water and paths); paths as
ground-hugging ribbons; real-time sun; cinematic camera (11 shots, studded
button); ducks flock in rafts (boids, after Duck Duck Drift); Solitude
rebuilt as a clean gabled house; tower buildings fixed.

Next, in order:
1. Go through data/photos/vt_trees (1,081 VT photos of 890 trees, indexed by
   tree in index.json) and correct tree shapes and the scene from them.
2. Path junctions: one shared pad per crossing (see Backlog).
3. The deferred building rework.
4. Visit notes (docs/VISIT_CHECKLIST.md).
