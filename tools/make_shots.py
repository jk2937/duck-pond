"""The places the cinematic camera films, from the same data as the model.

    python3 tools/make_shots.py   # after make_terrain.py and make_landmarks.py

Writes src/ReplicatedStorage/Shots.lua (the client can't see ServerStorage):
the pond's middle and water level, each island's middle and size, the weir,
Solitude, paths along the water (with ground heights), and benches.
"""

import json
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
TD = ROOT / "src" / "ServerStorage" / "TerrainData"
OUT = ROOT / "src" / "ReplicatedStorage" / "Shots.lua"

BBOX = (-80.4330, 37.2235, -80.4245, 37.2290)
ORIGIN = (37.2261281, -80.4285877)
M_PER_STUD = 0.28
BASE_M = 611.0
M_LAT = 111_132.0
M_LON = 111_320.0 * math.cos(math.radians(ORIGIN[0]))
MAIN_LEVEL = 615.49  # the Duck Pond's surface (make_terrain.py, from the lidar)


def studs(p):
    return ((p["lon"] - ORIGIN[1]) * M_LON / M_PER_STUD, -(p["lat"] - ORIGIN[0]) * M_LAT / M_PER_STUD)


def main():
    osm = json.load(open(RAW / "osm.json"))["elements"]
    dem = np.array(Image.open(RAW / "dem.tif")).astype(np.float64)
    w, s, e, n = BBOX

    def ground(x, z):
        lon = ORIGIN[1] + x * M_PER_STUD / M_LON
        lat = ORIGIN[0] - z * M_PER_STUD / M_LAT
        j = int(np.clip((lon - w) / (e - w) * dem.shape[1], 0, dem.shape[1] - 1))
        i = int(np.clip((n - lat) / (n - s) * dem.shape[0], 0, dem.shape[0] - 1))
        return (dem[i, j] - BASE_M) / M_PER_STUD

    pond = next(el for el in osm if el["type"] == "relation" and el.get("tags", {}).get("name") == "Duck Pond")
    outer = [studs(p) for m in pond["members"] if m["role"] == "outer" for p in m["geometry"]]
    cx, cz = np.mean([p[0] for p in outer]), np.mean([p[1] for p in outer])
    islands = []
    for m in pond["members"]:
        if m["role"] == "inner":
            pts = [studs(p) for p in m["geometry"]]
            ix, iz = np.mean([p[0] for p in pts]), np.mean([p[1] for p in pts])
            r = max(math.hypot(x - ix, z - iz) for x, z in pts)
            islands.append((ix, iz, r))
    water = (MAIN_LEVEL - BASE_M) / M_PER_STUD

    # Paths within 40 m of the pond's shore, as ground-hugging polylines.
    shore = np.array(outer)
    paths = []
    for el in osm:
        t = el.get("tags", {})
        if t.get("highway") in ("footway", "path", "cycleway", "pedestrian") and el.get("geometry") \
                and not t.get("tunnel") and not t.get("bridge"):
            pts = [studs(p) for p in el["geometry"]]
            near = min(np.min(np.hypot(shore[:, 0] - x, shore[:, 1] - z)) for x, z in pts)
            length = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:]))
            if near * M_PER_STUD < 40 and length > 80:
                paths.append([(x, ground(x, z), z) for x, z in pts])

    weir = next(el for el in osm if el.get("tags", {}).get("waterway") == "weir" and el["type"] == "way")
    wpts = [studs(p) for p in weir["geometry"]]
    wx, wz = np.mean([p[0] for p in wpts]), np.mean([p[1] for p in wpts])

    solitude = next(el for el in osm if el.get("tags", {}).get("name") == "Solitude" and el.get("geometry"))
    spts = [studs(p) for p in solitude["geometry"]]
    sx, sz = np.mean([p[0] for p in spts]), np.mean([p[1] for p in spts])

    landmarks = (TD / "Landmarks.lua").read_text()
    benches = [(float(x), float(y), float(z)) for kind, x, z, y in re.findall(
        r'kind = "(bench)",\s*x = ([-\d.]+),\s*z = ([-\d.]+),\s*y = ([-\d.]+)', landmarks)]
    near_benches = [b for b in benches if math.hypot(b[0] - cx, b[2] - cz) < 500][:12]

    def v(x, y, z):
        return f"Vector3.new({x:.1f}, {y:.1f}, {z:.1f})"

    lines = ["-- Written by tools/make_shots.py; don't edit by hand.", "return {",
             f"\tpond = {v(cx, water, cz)},",
             f"\twater = {water:.2f},",
             "\tislands = {"]
    lines += [f"\t\t{{ centre = {v(x, water, z)}, radius = {r:.1f} }}," for x, z, r in islands]
    lines += ["\t},", f"\tweir = {v(wx, ground(wx, wz), wz)},", f"\tsolitude = {v(sx, ground(sx, sz), sz)},",
              "\tpaths = {"]
    for p in paths:
        lines.append("\t\t{ " + ", ".join(v(*q) for q in p) + " },")
    lines += ["\t},", "\tbenches = {"]
    lines += [f"\t\t{v(*b)}," for b in near_benches]
    lines += ["\t},", "}", ""]
    OUT.write_text("\n".join(lines))
    print(f"{len(islands)} islands, {len(paths)} pond paths, {len(near_benches)} benches")


if __name__ == "__main__":
    main()
