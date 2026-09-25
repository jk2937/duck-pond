"""Turn data/raw/ into the terrain the builder writes into Studio.

    python3 tools/make_terrain.py

Writes src/ServerStorage/TerrainData/:
  Meta.lua      the grid: size, cell, origin, scale
  Height.txt    ground height per cell   } 2 chars a cell, base-64,
  Water.txt     water surface per cell   } in quarter studs above BASE_M
  Material.txt  a letter a cell (see MATERIALS)
Rojo syncs a .txt as a StringValue, so no giant Lua literals.

Also writes data/terrain_preview.png, the grid as the builder will see it.

Scale: 1 stud = 0.28 m (a Roblox avatar is about a person's height), so the
model is real size. North is -Z, east is +X, and the origin is the Duck Pond.
"""

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "src" / "ServerStorage" / "TerrainData"

BBOX = (-80.4330, 37.2235, -80.4245, 37.2290)  # as fetch_data.py
ORIGIN = (37.2261281, -80.4285877)  # the Duck Pond, lat/lon
M_PER_STUD = 0.28
CELL = 4  # studs: Roblox terrain's voxel
BASE_M = 611.0  # elevation at Y = 0

M_PER_DEG_LAT = 111_132.0
M_PER_DEG_LON = 111_320.0 * np.cos(np.radians(ORIGIN[0]))

# Terrain materials by letter; the builder has the same table.
MATERIALS = {
    "g": "Grass", "l": "LeafyGrass", "s": "Sand", "m": "Mud", "a": "Asphalt",
    "p": "Pavement", "r": "Rock", "b": "Ground",
}

POND_MAX_DEPTH = 2.0  # m
CREEK_WIDTH = 3.0  # m
CREEK_CUT = 0.6  # m below the ground the bed goes
ROAD_WIDTH = {"tertiary": 8, "secondary": 9, "unclassified": 6, "residential": 6, "service": 4}
PATH_WIDTH = 3.2  # m: a touch wide, so a 1.1 m voxel grid draws it unbroken
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def main():
    w, s, e, n = BBOX
    dem = np.array(Image.open(RAW / "dem.tif")).astype(np.float64)
    dh, dw = dem.shape
    osm = json.load(open(RAW / "osm.json"))["elements"]

    # The grid, in studs, aligned to the voxel grid.
    def to_m(lat, lon):
        return (lon - ORIGIN[1]) * M_PER_DEG_LON, -(lat - ORIGIN[0]) * M_PER_DEG_LAT
    x_min, z_min = to_m(n, w)
    x_max, z_max = to_m(s, e)
    x0 = int(np.ceil(x_min / M_PER_STUD / CELL)) * CELL
    z0 = int(np.ceil(z_min / M_PER_STUD / CELL)) * CELL
    nx = int((x_max / M_PER_STUD - x0) // CELL)
    nz = int((z_max / M_PER_STUD - z0) // CELL)
    cell_m = CELL * M_PER_STUD

    # Every cell's centre, in lon/lat and so in DEM pixels.
    xs = (x0 + (np.arange(nx) + 0.5) * CELL) * M_PER_STUD
    zs = (z0 + (np.arange(nz) + 0.5) * CELL) * M_PER_STUD
    lon = ORIGIN[1] + xs / M_PER_DEG_LON
    lat = ORIGIN[0] - zs / M_PER_DEG_LAT
    px = (lon - w) / (e - w) * dw - 0.5
    py = (n - lat) / (n - s) * dh - 0.5
    PX, PY = np.meshgrid(px, py)
    ground = bilinear(dem, PX, PY)  # metres, [nz, nx]

    def grid_xy(lat_, lon_):
        mx, mz = to_m(lat_, lon_)
        return (mx / M_PER_STUD - x0) / CELL, (mz / M_PER_STUD - z0) / CELL

    def mask():
        return Image.new("L", (nx, nz), 0)

    def pts(geom):
        return [grid_xy(p["lat"], p["lon"]) for p in geom]

    # --- pond water: every natural=water area, islands cut out ---
    water_img, island_img = mask(), mask()
    wd, idr = ImageDraw.Draw(water_img), ImageDraw.Draw(island_img)
    wood_img, sand_img, park_img = mask(), mask(), mask()
    road_img, path_img, creek_img = mask(), mask(), mask()
    weir_img = mask()
    for el in osm:
        t = el.get("tags", {})
        is_water = t.get("natural") == "water" or t.get("water") in ("pond", "basin")
        if el["type"] == "relation" and is_water:
            for m in el.get("members", []):
                if "geometry" in m and len(m["geometry"]) > 2:
                    (idr if m.get("role") == "inner" else wd).polygon(pts(m["geometry"]), fill=255)
        elif el["type"] == "way" and "geometry" in el:
            g = pts(el["geometry"])
            if len(g) < 2:
                continue
            if is_water and len(g) > 2:
                wd.polygon(g, fill=255)
            elif t.get("natural") in ("wood", "scrub") and len(g) > 2:
                ImageDraw.Draw(wood_img).polygon(g, fill=255)
            elif t.get("natural") in ("sand", "beach") and len(g) > 2:
                ImageDraw.Draw(sand_img).polygon(g, fill=255)
            elif t.get("amenity") == "parking" and len(g) > 2:
                ImageDraw.Draw(road_img).polygon(g, fill=255)
            elif t.get("waterway") in ("weir", "dam"):
                line(weir_img, g, 1.5)
            elif t.get("waterway") in ("stream", "river", "ditch") and t.get("tunnel") is None:
                line(creek_img, g, CREEK_WIDTH / cell_m)
            elif "highway" in t and t.get("bridge") is None and t.get("tunnel") is None:
                hw = t["highway"]
                if hw in ROAD_WIDTH:
                    line(road_img, g, ROAD_WIDTH[hw] / cell_m)
                elif hw in ("footway", "path", "cycleway", "pedestrian", "steps", "track"):
                    line(path_img, g, PATH_WIDTH / cell_m)

    pond = (np.array(water_img) > 127) & ~(np.array(island_img) > 127)
    creek = (np.array(creek_img) > 127) & ~pond
    # A weir splits a pond in two: the Duck Pond's upper end sits ~1.6 m above
    # the rest, behind the weir across its neck.
    weir = (np.array(weir_img) > 127) & pond

    # Each pond's level: the middle of the lidar's water surface.
    water_top = np.full(ground.shape, np.nan)
    labels, count = label(pond & ~weir)
    sizes = {k: int((labels == k).sum()) for k in range(1, count + 1)}
    for k, size in sizes.items():
        if size >= 40:
            water_top[labels == k] = np.median(ground[labels == k])
    # Slivers the weir cut off take the level of the pond they touch.
    for k, size in sizes.items():
        if size < 40:
            cells = labels == k
            ring = dilate(cells, 3) & ~cells
            water_top[cells] = np.nanmax(water_top[ring]) if np.isfinite(water_top[ring]).any() else np.median(ground[cells])
    count = sum(1 for size in sizes.values() if size >= 40)
    # The bed shelves down from the shore.
    shore = distance(pond) * cell_m
    bed = water_top - np.minimum(POND_MAX_DEPTH, 0.3 + 0.35 * shore)
    ground = np.where(pond & ~weir, bed, ground)
    # The weir: a stone lip level with the upper pond, the water just over it.
    upper = np.nanmax(np.where(dilate(weir, 2), water_top, np.nan)) if weir.any() else np.nan
    ground = np.where(weir, upper - 0.1, ground)
    water_top = np.where(weir, upper, water_top)
    # The creek: a channel cut into the ground, not quite brim-full.
    creek_top = ground - 0.15
    ground = np.where(creek, ground - CREEK_CUT, ground)
    water_top = np.where(creek, creek_top, water_top)

    # Materials.
    mat = np.full(ground.shape, "g", dtype="<U1")
    mat[np.array(wood_img) > 127] = "l"
    mat[np.array(sand_img) > 127] = "s"
    mat[np.array(path_img) > 127] = "p"
    mat[np.array(road_img) > 127] = "a"
    near_water = (distance(~(pond | creek)) * cell_m < 1.6) & ~(pond | creek)
    mat[near_water & (mat == "g")] = "m"
    mat[pond] = "m"
    mat[creek] = "r"
    mat[weir] = "r"

    # Where a player starts: on the path nearest the pond's middle, facing it.
    paths = np.argwhere((mat == "p") & np.isnan(water_top))
    oz, ox = (-z0 / CELL), (-x0 / CELL)
    sz_, sx_ = paths[np.argmin((paths[:, 0] - oz) ** 2 + (paths[:, 1] - ox) ** 2)]
    spawn = (x0 + (sx_ + 0.5) * CELL, (ground[sz_, sx_] - BASE_M) / M_PER_STUD + 3, z0 + (sz_ + 0.5) * CELL)

    # Encode.
    OUT.mkdir(parents=True, exist_ok=True)
    def enc(metres):
        q = np.where(np.isnan(metres), 0, np.clip(np.round((metres - BASE_M) / M_PER_STUD * 4) + 1, 1, 4095))
        q = q.astype(int).ravel()
        return "".join(B64[v >> 6] + B64[v & 63] for v in q)
    (OUT / "Height.txt").write_text(enc(ground))
    (OUT / "Water.txt").write_text(enc(water_top))
    (OUT / "Material.txt").write_text("".join(mat.ravel()))
    (OUT / "Meta.lua").write_text(f"""-- Written by tools/make_terrain.py; don't edit by hand.
return {{
	nx = {nx}, -- cells east
	nz = {nz}, -- cells south
	cell = {CELL}, -- studs
	x0 = {x0}, -- the grid's north-west corner, studs
	z0 = {z0},
	baseMetres = {BASE_M}, -- elevation at Y = 0
	metresPerStud = {M_PER_STUD},
	spawn = {{ {spawn[0]:.1f}, {spawn[1]:.1f}, {spawn[2]:.1f} }}, -- on a path by the water
	materials = {{ {", ".join(f'{k} = "{v}"' for k, v in MATERIALS.items())} }},
	source = "USGS 3DEP elevation; (c) OpenStreetMap contributors",
}}
""")

    # A look at it.
    shade = np.clip((ground - ground.min()) / (ground.max() - ground.min()), 0, 1)
    colours = {"g": (110, 170, 80), "l": (70, 130, 60), "s": (220, 200, 150), "m": (120, 100, 70),
               "a": (70, 70, 74), "p": (190, 186, 176), "r": (130, 130, 130)}
    rgb = np.zeros(ground.shape + (3,))
    for k, c in colours.items():
        rgb[mat == k] = c
    rgb *= (0.6 + 0.4 * shade)[..., None]
    wet = ~np.isnan(water_top)
    rgb[wet] = rgb[wet] * 0.3 + np.array([40, 110, 200]) * 0.7
    Image.fromarray(rgb.astype(np.uint8)).save(ROOT / "data" / "terrain_preview.png")
    print(f"grid {nx} x {nz} cells ({nx * CELL} x {nz * CELL} studs), "
          f"ground {ground.min():.1f}-{ground.max():.1f} m, {count} ponds, "
          f"levels {sorted(set(np.round(water_top[pond], 2)))}")


def bilinear(img, x, y):
    x = np.clip(x, 0, img.shape[1] - 1.001)
    y = np.clip(y, 0, img.shape[0] - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    a, b = img[y0, x0], img[y0, x0 + 1]
    c, d = img[y0 + 1, x0], img[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def line(img, points, width_cells):
    ImageDraw.Draw(img).line(points, fill=255, width=max(1, int(round(width_cells))), joint="curve")


def dilate(m, n):
    out = m.copy()
    for _ in range(n):
        grown = out.copy()
        grown[1:] |= out[:-1]
        grown[:-1] |= out[1:]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        out = grown
    return out


def label(m):
    """Connected regions of a mask (4-neighbour), by flood fill."""
    labels = np.zeros(m.shape, dtype=int)
    count = 0
    for sy, sx in zip(*np.nonzero(m)):
        if labels[sy, sx]:
            continue
        count += 1
        stack = [(sy, sx)]
        labels[sy, sx] = count
        while stack:
            y, x = stack.pop()
            for ny, nx_ in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < m.shape[0] and 0 <= nx_ < m.shape[1] and m[ny, nx_] and not labels[ny, nx_]:
                    labels[ny, nx_] = count
                    stack.append((ny, nx_))
    return labels, count


def distance(m):
    """For cells in the mask, cells to the nearest cell outside it (chamfer)."""
    big = 1e9
    d = np.where(m, big, 0.0)
    h, w = d.shape
    for y in range(h):
        row = d[y]
        if y > 0:
            row[:] = np.minimum(row, d[y - 1] + 1)
        for x in range(1, w):
            if row[x] > row[x - 1] + 1:
                row[x] = row[x - 1] + 1
    for y in range(h - 1, -1, -1):
        row = d[y]
        if y < h - 1:
            row[:] = np.minimum(row, d[y + 1] + 1)
        for x in range(w - 2, -1, -1):
            if row[x] > row[x + 1] + 1:
                row[x] = row[x + 1] + 1
    return d


if __name__ == "__main__":
    main()
