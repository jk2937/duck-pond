"""Download the USGS lidar points over the model's box, into data/raw/lidar/.

    python3 tools/fetch_lidar.py     # needs: pip install --user "laspy[lazrs]"

The survey is VA_South_Central_B1_2017 (USGS 3DEP, public domain), served as
an Entwine Point Tile octree on AWS's open data: only the nodes that overlap
the box are fetched. Points are in Web Mercator (EPSG:3857) metres, heights
in metres; classification 2 is ground, 3-5 vegetation, 6 buildings.

Then tools/make_trees.py turns them into trees.
"""

import json
import math
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "raw" / "lidar"
EPT = "https://s3-us-west-2.amazonaws.com/usgs-lidar-public/VA_South_Central_B1_2017"
BBOX = (-80.4330, 37.2235, -80.4245, 37.2290)  # as fetch_data.py


def mercator(lon, lat):
    r = 6378137.0
    return r * math.radians(lon), r * math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))


def get_json(url):
    out = subprocess.run(["curl", "-sS", "-m", "120", url], check=True, capture_output=True).stdout
    return json.loads(out)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    ept = get_json(f"{EPT}/ept.json")
    b = ept["bounds"]
    x0, y0 = mercator(BBOX[0], BBOX[1])
    x1, y1 = mercator(BBOX[2], BBOX[3])

    def node_bounds(d, x, y):
        size = (b[3] - b[0]) / 2 ** d
        return b[0] + x * size, b[1] + y * size, b[0] + (x + 1) * size, b[1] + (y + 1) * size

    def overlaps(key):
        d, x, y, _ = map(int, key.split("-"))
        nx0, ny0, nx1, ny1 = node_bounds(d, x, y)
        return nx0 < x1 and x0 < nx1 and ny0 < y1 and y0 < ny1

    # Walk the hierarchy, only down overlapping branches.
    wanted = []
    pending = ["0-0-0-0"]
    while pending:
        root = pending.pop()
        hierarchy = get_json(f"{EPT}/ept-hierarchy/{root}.json")
        frontier = [root]
        while frontier:
            key = frontier.pop()
            count = hierarchy.get(key)
            if count is None or not overlaps(key):
                continue
            if count == -1:
                pending.append(key)
                continue
            if count > 0:
                wanted.append(key)
            d, x, y, z = map(int, key.split("-"))
            for dx in (0, 1):
                for dy in (0, 1):
                    for dz in (0, 1):
                        frontier.append(f"{d + 1}-{2 * x + dx}-{2 * y + dy}-{2 * z + dz}")
    print(len(wanted), "nodes overlap the box")

    import laspy
    xs, ys, zs, cls, ret, nret = [], [], [], [], [], []
    for i, key in enumerate(sorted(wanted)):
        path = OUT / f"{key}.laz"
        if not path.exists():
            subprocess.run(["curl", "-sS", "-m", "300", "-o", str(path), f"{EPT}/ept-data/{key}.laz"], check=True)
        las = laspy.read(path)
        keep = (las.x >= x0) & (las.x <= x1) & (las.y >= y0) & (las.y <= y1)
        xs.append(np.asarray(las.x)[keep]); ys.append(np.asarray(las.y)[keep]); zs.append(np.asarray(las.z)[keep])
        cls.append(np.asarray(las.classification)[keep])
        ret.append(np.asarray(las.return_number)[keep]); nret.append(np.asarray(las.number_of_returns)[keep])
        if i % 20 == 0:
            print(f"  {i + 1}/{len(wanted)}")
    np.savez_compressed(OUT.parent / "lidar_points.npz", x=np.concatenate(xs), y=np.concatenate(ys),
                        z=np.concatenate(zs), cls=np.concatenate(cls), ret=np.concatenate(ret),
                        nret=np.concatenate(nret))
    print("points:", sum(len(a) for a in xs))


if __name__ == "__main__":
    main()
