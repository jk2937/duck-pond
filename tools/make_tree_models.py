"""Where each realistic tree model belongs, from the models' own CSV.

    python3 tools/make_tree_models.py

Reads assets/trees/*/*_trees.csv (one per species set, written by whoever made
the models: file, tree ID, lat/lon, inventory height) and writes
src/ServerStorage/TerrainData/TreeModels.lua: for each model, its stud
position on our map, so the builder can swap the block-built tree standing
there for the real model. Positions are in the same frame as Trees.txt.
"""

import csv
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "ServerStorage" / "TerrainData" / "TreeModels.lua"
ORIGIN = (37.2261281, -80.4285877)  # the pond (as make_terrain.py)
M_PER_STUD = 0.28
M_LAT = 111_132.0
M_LON = 111_320.0 * math.cos(math.radians(ORIGIN[0]))


def main():
    models = []
    for path in sorted((ROOT / "assets" / "trees").glob("*/*_trees.csv")):
        species = path.parent.name  # sugar_maple
        for r in csv.DictReader(open(path)):
            if r["tier"] != "standard":
                continue
            x = (float(r["longitude"]) - ORIGIN[1]) * M_LON / M_PER_STUD
            z = -(float(r["latitude"]) - ORIGIN[0]) * M_LAT / M_PER_STUD
            models.append((species, r["file"], r["tree_id"], x, z, float(r["inventory_height_studs"]),
                           float(r["model_height_studs"])))
    lines = ["-- Written by tools/make_tree_models.py; don't edit by hand.", "return {"]
    for species, file, tid, x, z, inv_h, model_h in models:
        lines.append(f'\t{{ species = "{species}", file = "{file}", id = "{tid}", x = {x:.1f}, z = {z:.1f}, '
                     f"height = {inv_h:.1f}, modelHeight = {model_h:.1f} }},")
    lines += ["}", ""]
    OUT.write_text("\n".join(lines))
    print(len(models), "tree models placed in", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
