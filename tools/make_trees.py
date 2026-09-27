"""Find the real trees in the lidar and write them for the Trees builder.

    python3 tools/make_trees.py      # after tools/fetch_lidar.py

1. A canopy height model at 1 m: the highest non-ground return in each cell,
   minus the bare ground (USGS DEM) under it. Buildings (OSM footprints) are
   masked out.
2. Tree tops: local maxima of the smoothed canopy, searched over a window
   that grows with height (tall trees have wide crowns), 3 m and up.
3. Each tree's height, crown radius (how far the canopy stays above half its
   height), and, lacking a species, broadleaf or conifer (conifer where the
   leaf-off survey couldn't see the ground under the crown).
4. Virginia Tech's Campus Tree Inventory (data/raw/vt_trees.json, public, from
   VT Facilities' ArcGIS service), where it covers: a lidar tree with an
   inventory tree within 4 m takes its species and the arborists'
   measurements; one whose match has since been removed is dropped; living
   inventory trees the 2017 survey missed are added. Species decide the
   shape: willow, conifer, cypress (deciduous conifers), ornamental, broadleaf.
Writes src/ServerStorage/TerrainData/Trees.txt: one tree a line,
  x z y height radius kind species   (studs; y is the ground; species is the
  inventory's common name with _ for spaces, or - if unknown)
and data/trees_preview.png.
"""

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "src" / "ServerStorage" / "TerrainData"

BBOX = (-80.4330, 37.2235, -80.4245, 37.2290)
ORIGIN = (37.2261281, -80.4285877)
M_PER_STUD = 0.28
BASE_M = 611.0
M_PER_DEG_LAT = 111_132.0
M_PER_DEG_LON = 111_320.0 * math.cos(math.radians(ORIGIN[0]))
CELL = 1.0  # metres

MIN_HEIGHT = 3.0
WILLOW_REACH = 12.0  # m from water


def main():
    pts = np.load(RAW / "lidar_points.npz")
    # Web Mercator -> lon/lat -> local metres (east, south).
    r = 6378137.0
    lon = np.degrees(pts["x"] / r)
    lat = np.degrees(2 * np.arctan(np.exp(pts["y"] / r)) - math.pi / 2)
    ex = (lon - ORIGIN[1]) * M_PER_DEG_LON
    sz = -(lat - ORIGIN[0]) * M_PER_DEG_LAT
    z = pts["z"]
    cls = pts["cls"]

    w, s, e, n = BBOX
    gx0 = (w - ORIGIN[1]) * M_PER_DEG_LON
    gz0 = -(n - ORIGIN[0]) * M_PER_DEG_LAT
    W = int(((e - ORIGIN[1]) * M_PER_DEG_LON - gx0) / CELL)
    H = int((-(s - ORIGIN[0]) * M_PER_DEG_LAT - gz0) / CELL)
    ci = np.clip(((sz - gz0) / CELL).astype(int), 0, H - 1)
    cj = np.clip(((ex - gx0) / CELL).astype(int), 0, W - 1)

    # Bare ground: the USGS DEM, resampled to this grid.
    dem = np.array(Image.open(RAW / "dem.tif")).astype(np.float64)
    jj, ii = np.meshgrid(np.arange(W) + 0.5, np.arange(H) + 0.5)
    glon = ORIGIN[1] + (gx0 + jj * CELL) / M_PER_DEG_LON
    glat = ORIGIN[0] - (gz0 + ii * CELL) / M_PER_DEG_LAT
    px = (glon - w) / (e - w) * dem.shape[1] - 0.5
    py = (n - glat) / (n - s) * dem.shape[0] - 0.5
    ground = bilinear(dem, px, py)

    # The canopy: highest unclassified (non-ground) return per cell.
    top = np.full((H, W), -np.inf)
    above = cls == 1
    np.maximum.at(top, (ci[above], cj[above]), z[above])
    chm = np.where(np.isfinite(top), top - ground, 0.0)
    chm = np.clip(chm, 0, 45)
    # Ground returns per cell, for telling evergreens from bare broadleaves.
    ground_hits = np.zeros((H, W)); np.add.at(ground_hits, (ci[cls == 2], cj[cls == 2]), 1)
    all_hits = np.zeros((H, W)); np.add.at(all_hits, (ci, cj), 1)

    # Masks from OSM: buildings (no trees), water (for willows).
    osm = json.load(open(RAW / "osm.json"))["elements"]
    def gp(p):
        return (((p["lon"] - ORIGIN[1]) * M_PER_DEG_LON - gx0) / CELL,
                (-(p["lat"] - ORIGIN[0]) * M_PER_DEG_LAT - gz0) / CELL)
    build_img = Image.new("L", (W, H), 0)
    water_img = Image.new("L", (W, H), 0)
    holes_img = Image.new("L", (W, H), 0)
    for el in osm:
        t = el.get("tags", {})
        geoms = ([(None, el["geometry"])] if el.get("geometry")
                 else [(m.get("role"), m["geometry"]) for m in el.get("members", []) if m.get("geometry")])
        for role, g in geoms:
            p = [gp(q) for q in g]
            if len(p) < 2:
                continue
            if "building" in t and len(p) > 2:
                ImageDraw.Draw(build_img).polygon(p, fill=255)
            elif t.get("natural") == "water" and len(p) > 2:
                ImageDraw.Draw(holes_img if role == "inner" else water_img).polygon(p, fill=255)
            elif t.get("waterway") in ("stream", "river") and t.get("tunnel") is None:
                ImageDraw.Draw(water_img).line(p, fill=255, width=3)
    buildings = np.asarray(build_img.filter(ImageFilter.MaxFilter(5))) > 127
    water = (np.asarray(water_img) > 127) & ~(np.asarray(holes_img) > 127)
    chm[buildings] = 0

    # Smooth a little, then find tops.
    smooth = blur(chm, 1.2)
    near_water = distance(~water) <= WILLOW_REACH / CELL
    trees = []
    cand = np.argwhere(smooth >= MIN_HEIGHT)
    order = np.argsort(-smooth[cand[:, 0], cand[:, 1]])
    taken = np.zeros((H, W), bool)
    for k in order:
        i, j = cand[k]
        h = smooth[i, j]
        if taken[i, j]:
            continue
        rad = max(1.5, min(7.0, 1.0 + 0.18 * h))  # search window ~ crown
        r0 = int(math.ceil(rad))
        i0, i1, j0, j1 = max(0, i - r0), min(H, i + r0 + 1), max(0, j - r0), min(W, j + r0 + 1)
        if smooth[i0:i1, j0:j1].max() > h + 1e-6:
            continue
        # Crown: how far out the canopy stays above half the height.
        crown = 1.5
        for rr in range(1, 12):
            ring = []
            for a in range(0, 360, 30):
                y = int(i + rr * math.sin(math.radians(a))); x = int(j + rr * math.cos(math.radians(a)))
                if 0 <= y < H and 0 <= x < W:
                    ring.append(chm[y, x])
            if not ring or np.mean(np.array(ring) > h * 0.5) < 0.5:
                break
            crown = rr + 0.5
        yy, xx = np.ogrid[i0:i1, j0:j1]
        disk = (yy - i) ** 2 + (xx - j) ** 2 <= (crown * CELL) ** 2
        taken[i0:i1, j0:j1] |= disk
        g_frac = ground_hits[i0:i1, j0:j1][disk].sum() / max(1, all_hits[i0:i1, j0:j1][disk].sum())
        # No species here: just broadleaf or conifer. (The VT inventory,
        # below, names the ones it knows -- willows included.)
        if g_frac < 0.12 and h > 5:
            kind = "conifer"
        else:
            kind = "broadleaf"
        x_st = (gx0 + (j + 0.5) * CELL) / M_PER_STUD
        z_st = (gz0 + (i + 0.5) * CELL) / M_PER_STUD
        y_st = (ground[i, j] - BASE_M) / M_PER_STUD
        trees.append((x_st, z_st, y_st, h / M_PER_STUD, crown / M_PER_STUD, kind, "-"))

    # Virginia Tech's campus tree inventory, where it covers: each tree's
    # species and the arborists' measurements. A lidar tree with an
    # inventory tree within MATCH metres becomes that tree; one whose match
    # has been removed since is dropped; inventory trees the 2017 survey
    # didn't see (planted since) are added.
    trees, matched, added, dropped = merge_inventory(trees, gx0, gz0, ground, W, H)

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Trees.txt").write_text("\n".join(f"{x:.1f} {z_:.1f} {y:.1f} {h:.1f} {c:.1f} {k} {sp}"
                                             for x, z_, y, h, c, k, sp in trees))
    print(f"inventory: {matched} lidar trees named, {added} added, {dropped} removed since 2017")
    # For the tree sign by the spawn (Builders/Landmarks).
    lidar_only = sum(1 for t in trees if t[6] == "-")
    photos = ROOT / "data" / "photos" / "vt_trees" / "index.json"
    pics = json.load(open(photos)) if photos.exists() else {}
    (OUT / "TreeStats.lua").write_text(
        "-- Written by tools/make_trees.py; don't edit by hand.\nreturn {\n"
        f"\ttotal = {len(trees)},\n\tboth = {matched},\n\tinventoryOnly = {added},\n"
        f"\tlidarOnly = {lidar_only},\n\tremoved = {dropped},\n"
        f"\tphotoTrees = {len(pics)},\n\tphotos = {sum(len(e['photos']) for e in pics.values())},\n}}\n")
    counts = {}
    for t in trees:
        counts[t[5]] = counts.get(t[5], 0) + 1
    print(len(trees), "trees", counts, "heights %.0f-%.0f m" % (min(t[3] for t in trees) * M_PER_STUD,
                                                              max(t[3] for t in trees) * M_PER_STUD))

    # Preview over the aerial.
    aerial = Image.open(RAW / "aerial.png").convert("RGB").resize((W, H))
    d = ImageDraw.Draw(aerial)
    colour = {"broadleaf": (255, 220, 0), "willow": (0, 230, 255), "conifer": (255, 60, 200),
              "cypress": (120, 255, 120), "ornamental": (255, 140, 200)}
    for x, z_, _, h, c, k, _sp in trees:
        j = x * M_PER_STUD - gx0; i = z_ * M_PER_STUD - gz0
        rr = c * M_PER_STUD
        d.ellipse([j - rr, i - rr, j + rr, i + rr], outline=colour[k])
    aerial.save(ROOT / "data" / "trees_preview.png")


INVENTORY_MATCH = 4.0  # metres
FT = 0.3048
DEFAULT_HEIGHT = {"L": 18.0, "M": 11.0, "S": 6.0}  # m, by the inventory's size class
ORNAMENTAL = ("cherry", "crabapple", "dogwood", "serviceberry", "redbud", "magnolia", "plum", "pear")


def tree_kind(name, code):
    """The model's shape for an inventory species."""
    name = (name or "").lower()
    code = code or ""
    if "willow" in name and "oak" not in name and "black willow" not in name:
        return "willow"
    if code.startswith("CD") or "cypress" in name and "leyland" not in name or "redwood" in name or "larch" in name:
        return "cypress"
    if code.startswith("CE") or any(w in name for w in ("pine", "spruce", "hemlock", "cedar", "fir", "yew", "juniper")):
        return "conifer"
    if code.endswith("S") or any(w in name for w in ORNAMENTAL):
        return "ornamental"
    return "broadleaf"


def merge_inventory(trees, gx0, gz0, ground, W, H):
    path = RAW / "vt_trees.json"
    if not path.exists():
        return trees, 0, 0, 0
    inv = []
    for f in json.load(open(path))["features"]:
        a = f["attributes"]
        lon, lat = f["geometry"]["x"], f["geometry"]["y"]
        mx = (lon - ORIGIN[1]) * M_PER_DEG_LON
        mz = -(lat - ORIGIN[0]) * M_PER_DEG_LAT
        inv.append((mx, mz, a))
    inv_xy = np.array([(x, z) for x, z, _ in inv])
    used = np.zeros(len(inv), bool)
    out, matched, dropped = [], 0, 0

    def spec(a, lidar_h=None, lidar_r=None):
        code = a.get("treetype") or ""
        h = (a.get("totalheight") or a.get("height") or 0) * FT
        if h <= 0:
            h = lidar_h or DEFAULT_HEIGHT.get(code[-1:], 10.0)
        h = max(h, 2.0)  # a few entries are saplings, or zero
        r = (a.get("crownradius") or 0) * FT
        if r <= 0:
            r = lidar_r or max(1.5, h * 0.3)
        species = (a.get("commonname") or "tree").strip().replace(" ", "_") or "tree"
        return h, r, tree_kind(a.get("commonname"), code), species

    for t in trees:
        x_m, z_m = t[0] * M_PER_STUD, t[1] * M_PER_STUD
        d = np.hypot(inv_xy[:, 0] - x_m, inv_xy[:, 1] - z_m)
        d[used] = np.inf
        k = int(np.argmin(d))
        if d[k] > INVENTORY_MATCH:
            out.append(t)
            continue
        used[k] = True
        a = inv[k][2]
        if a.get("status") in ("Removed", "Stump"):
            dropped += 1
            continue
        h, r, kind, species = spec(a, t[3] * M_PER_STUD, t[4] * M_PER_STUD)
        out.append((t[0], t[1], t[2], h / M_PER_STUD, r / M_PER_STUD, kind, species))
        matched += 1
    added = 0
    for k, (mx, mz, a) in enumerate(inv):
        if used[k] or a.get("status") != "Alive":
            continue
        i, j = int((mz - gz0) / CELL), int((mx - gx0) / CELL)
        if not (0 <= i < H and 0 <= j < W):
            continue
        h, r, kind, species = spec(a)
        out.append((mx / M_PER_STUD, mz / M_PER_STUD, (ground[i, j] - BASE_M) / M_PER_STUD, h / M_PER_STUD,
                    r / M_PER_STUD, kind, species))
        added += 1
    return out, matched, added, dropped


def blur(a, sigma):
    """A Gaussian blur, separable, in numpy."""
    r = int(math.ceil(sigma * 3))
    k = np.exp(-np.arange(-r, r + 1) ** 2 / (2 * sigma * sigma))
    k /= k.sum()
    pad = np.pad(a, r, mode="edge")
    rows = sum(k[t] * pad[:, t:t + a.shape[1]] for t in range(2 * r + 1))
    return sum(k[t] * rows[t:t + a.shape[0], :] for t in range(2 * r + 1))


def bilinear(img, x, y):
    x = np.clip(x, 0, img.shape[1] - 1.001)
    y = np.clip(y, 0, img.shape[0] - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    a, b = img[y0, x0], img[y0, x0 + 1]
    c, d = img[y0 + 1, x0], img[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def distance(m):
    """For cells in the mask, cells to the nearest cell outside it (chamfer)."""
    d = np.where(m, 1e9, 0.0)
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
