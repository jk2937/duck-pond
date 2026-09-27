"""Buildings and street furniture, for the Landmarks builder.

    python3 tools/make_landmarks.py   # after make_terrain.py and fetch_lidar.py

Buildings: every OSM footprint, its height measured from the lidar (the 90th
percentile of returns inside it, over the ground), its roof triangulated so
the builder can cap any shape.

Furniture: the OSM benches, picnic tables, shelters, lamps, bins and water
fountains where they are; then, since OSM maps few at the pond and the
photos show plenty, benches and lamps along the paths near the water, every
so often, marked guess = true -- to be put right on visits.

Writes src/ServerStorage/TerrainData/Landmarks.lua.
"""

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "src" / "ServerStorage" / "TerrainData"

BBOX = (-80.4330, 37.2235, -80.4245, 37.2290)
ORIGIN = (37.2261281, -80.4285877)
M_PER_STUD = 0.28
BASE_M = 611.0
M_PER_DEG_LAT = 111_132.0
M_PER_DEG_LON = 111_320.0 * math.cos(math.radians(ORIGIN[0]))

POND_REACH = 70.0  # m: paths this close to the water get guessed furniture
BENCH_EVERY = 45.0  # m along a path
LAMP_EVERY = 35.0
FURNITURE = {"bench": "bench", "picnic_table": "picnic", "shelter": "shelter", "street_lamp": "lamp",
             "waste_basket": "bin", "drinking_water": "fountain"}


def metres(p):
    return (p["lon"] - ORIGIN[1]) * M_PER_DEG_LON, -(p["lat"] - ORIGIN[0]) * M_PER_DEG_LAT


def main():
    osm = json.load(open(RAW / "osm.json"))["elements"]
    dem = np.array(Image.open(RAW / "dem.tif")).astype(np.float64)
    w, s, e, n = BBOX

    def ground(mx, mz):
        lon = ORIGIN[1] + mx / M_PER_DEG_LON
        lat = ORIGIN[0] - mz / M_PER_DEG_LAT
        x = int(np.clip((lon - w) / (e - w) * dem.shape[1], 0, dem.shape[1] - 1))
        y = int(np.clip((n - lat) / (n - s) * dem.shape[0], 0, dem.shape[0] - 1))
        return dem[y, x]

    # Lidar, in local metres, for building heights.
    pts = np.load(RAW / "lidar_points.npz")
    r = 6378137.0
    lon = np.degrees(pts["x"] / r)
    lat = np.degrees(2 * np.arctan(np.exp(pts["y"] / r)) - math.pi / 2)
    lx = (lon - ORIGIN[1]) * M_PER_DEG_LON
    lz = -(lat - ORIGIN[0]) * M_PER_DEG_LAT
    lzv, lcls = pts["z"], pts["cls"]

    out = {"buildings": [], "furniture": []}

    # --- buildings ---
    for el in osm:
        t = el.get("tags", {})
        if "building" not in t:
            continue
        rings = ([el["geometry"]] if el.get("geometry")
                 else [m["geometry"] for m in el.get("members", []) if m.get("role") == "outer" and m.get("geometry")])
        for ring in rings:
            poly = [metres(p) for p in ring]
            if poly[0] == poly[-1]:
                poly = poly[:-1]
            if len(poly) < 3:
                continue
            if area(poly) < 0:
                poly = poly[::-1]
            xs, zs = [p[0] for p in poly], [p[1] for p in poly]
            box = (lx >= min(xs)) & (lx <= max(xs)) & (lz >= min(zs)) & (lz <= max(zs)) & (lcls == 1)
            inside = np.array([contains(poly, x, z) for x, z in zip(lx[box], lz[box])], dtype=bool)
            base = min(ground(x, z) for x, z in poly)
            roofs = lzv[box][inside] if inside.any() else np.array([])
            height = float(np.percentile(roofs, 90) - base) if len(roofs) > 20 else None
            if height is None or not (2.5 < height < 60):
                levels = t.get("building:levels")
                height = float(t.get("height") or (float(levels) * 3.5 + 1 if levels else 8))
            tris = triangulate(poly)
            out["buildings"].append({
                "name": t.get("name", ""),
                "kind": t["building"],
                "base": (base - BASE_M) / M_PER_STUD,
                "height": height / M_PER_STUD,
                "points": [(x / M_PER_STUD, z / M_PER_STUD) for x, z in poly],
                "triangles": [list(tri) for tri in tris],
            })

    # Path segments, for squaring benches to the path beside them.
    segments = []
    for el in osm:
        t = el.get("tags", {})
        if t.get("highway") in ("footway", "path", "cycleway", "pedestrian", "tertiary", "service", "unclassified",
                                "residential") and el.get("geometry") and not t.get("tunnel"):
            line_ = [metres(p) for p in el["geometry"]]
            segments += list(zip(line_, line_[1:]))

    def square_to_path(mx, mz, yaw, reach=8.0):
        """The yaw, turned to the nearer of the two directions square to the
        nearest path segment (within reach), so a bench faces across it."""
        best, bd = None, reach
        for (ax, az), (bx, bz) in segments:
            vx, vz = bx - ax, bz - az
            ll = vx * vx + vz * vz
            if ll < 1e-6:
                continue
            f = max(0.0, min(1.0, ((mx - ax) * vx + (mz - az) * vz) / ll))
            d = math.hypot(mx - (ax + f * vx), mz - (az + f * vz))
            if d < bd:
                best, bd = (vx, vz), d
        if not best:
            return yaw
        along = math.atan2(best[0], -best[1])  # the path's own yaw
        options = [along + math.pi / 2, along - math.pi / 2]
        return min(options, key=lambda o: abs((o - yaw + math.pi) % (2 * math.pi) - math.pi))

    # --- furniture, from OSM ---
    def add(kind, mx, mz, yaw, guess):
        if kind in ("bench", "picnic", "bin"):
            yaw = square_to_path(mx, mz, yaw)
        out["furniture"].append({"kind": kind, "x": mx / M_PER_STUD, "z": mz / M_PER_STUD,
                                 "y": (ground(mx, mz) - BASE_M) / M_PER_STUD, "yaw": yaw, "guess": guess})

    water = []  # sample points on the pond shores, for "which way is the water"
    for el in osm:
        t = el.get("tags", {})
        if t.get("natural") == "water":
            for m in (el.get("members") or [{"geometry": el.get("geometry")}]):
                for p in (m.get("geometry") or [])[::2]:
                    water.append(metres(p))
    water = np.array(water)

    def facing_water(mx, mz):
        d = water - (mx, mz)
        k = np.argmin((d ** 2).sum(1))
        return math.atan2(d[k][0], -d[k][1]), math.sqrt((d[k] ** 2).sum())

    for el in osm:
        t = el.get("tags", {})
        kind = FURNITURE.get(t.get("amenity")) or FURNITURE.get(t.get("leisure")) or FURNITURE.get(t.get("highway"))
        if el["type"] == "node" and kind:
            mx, mz = metres(el)
            yaw, _ = facing_water(mx, mz)
            add(kind, mx, mz, yaw, False)

    # --- furniture, guessed along the paths by the water ---
    placed = [(f["x"] * M_PER_STUD, f["z"] * M_PER_STUD) for f in out["furniture"]]
    for el in osm:
        t = el.get("tags", {})
        if t.get("highway") not in ("footway", "path", "cycleway", "pedestrian") or t.get("tunnel") or t.get("bridge"):
            continue
        line = [metres(p) for p in el["geometry"]]
        walked, next_bench, next_lamp = 0.0, BENCH_EVERY / 2, LAMP_EVERY / 3
        for (ax, az), (bx, bz) in zip(line, line[1:]):
            leg = math.hypot(bx - ax, bz - az)
            if leg < 0.01:
                continue
            ux, uz = (bx - ax) / leg, (bz - az) / leg
            for kind, every in (("bench", BENCH_EVERY), ("lamp", LAMP_EVERY)):
                at = next_bench if kind == "bench" else next_lamp
                while at <= walked + leg:
                    f = at - walked
                    px, pz = ax + ux * f, az + uz * f
                    yaw, dist = facing_water(px, pz)
                    if dist < POND_REACH and all(math.hypot(px - qx, pz - qz) > 12 for qx, qz in placed):
                        # Beside the path: a bench on the water side, a lamp opposite.
                        # The path's left is (-uz, ux); the water is (sin yaw, -cos yaw).
                        side = 1 if math.sin(yaw) * -uz + -math.cos(yaw) * ux > 0 else -1
                        off = 2.2 * (side if kind == "bench" else -side)
                        qx, qz = px - uz * off, pz + ux * off
                        add(kind, qx, qz, yaw, True)
                        placed.append((qx, qz))
                        if kind == "bench" and len(placed) % 3 == 0:
                            add("bin", qx + ux * 1.6, qz + uz * 1.6, yaw, True)
                    at += every
                if kind == "bench":
                    next_bench = at
                else:
                    next_lamp = at
            walked += leg

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Landmarks.lua").write_text("-- Written by tools/make_landmarks.py; don't edit by hand.\nreturn "
                                       + lua(out) + "\n")
    kinds = {}
    for f in out["furniture"]:
        kinds[f["kind"]] = kinds.get(f["kind"], 0) + 1
    print(len(out["buildings"]), "buildings;", "furniture", kinds,
          f"({sum(1 for f in out['furniture'] if f['guess'])} guessed)")
    for b in out["buildings"]:
        if b["name"]:
            print(f"  {b['name']}: {b['height'] * M_PER_STUD:.1f} m")


def area(poly):
    return sum(x0 * z1 - x1 * z0 for (x0, z0), (x1, z1) in zip(poly, poly[1:] + poly[:1])) / 2


def contains(poly, x, z):
    c = False
    for (x0, z0), (x1, z1) in zip(poly, poly[-1:] + poly[:-1]):
        if (z0 > z) != (z1 > z) and x < (x1 - x0) * (z - z0) / (z1 - z0) + x0:
            c = not c
    return c


def triangulate(poly):
    """Ear clipping, for a simple polygon wound positively (in x, z)."""
    idx = list(range(len(poly)))
    tris = []
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if cross(a, b, c) <= 0:
                continue
            if any(cross(a, b, poly[j]) > 0 and cross(b, c, poly[j]) > 0 and cross(c, a, poly[j]) > 0
                   for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0 + 1, i1 + 1, i2 + 1))  # Lua indices
            idx.pop(k)
            break
        else:
            break
    if len(idx) == 3:
        tris.append(tuple(i + 1 for i in idx))
    return tris


def lua(v, indent=0):
    pad = "\t" * (indent + 1)
    if isinstance(v, dict):
        return "{\n" + "".join(f"{pad}{k} = {lua(x, indent + 1)},\n" for k, x in v.items()) + "\t" * indent + "}"
    if isinstance(v, (list, tuple)):
        if all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v):
            return "{ " + ", ".join(lua(x) for x in v) + " }"
        return "{\n" + "".join(f"{pad}{lua(x, indent + 1)},\n" for x in v) + "\t" * indent + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return f"{v:.2f}"
    return '"' + str(v).replace('"', '\\"') + '"'


if __name__ == "__main__":
    main()
