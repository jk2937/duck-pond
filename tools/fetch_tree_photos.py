"""Download the Campus Tree Inventory's photos of the trees near the pond.

    python3 tools/fetch_tree_photos.py [metres]   # default: within 250 m

VT's inventory (see fetch_data.py) has photos attached to most trees, taken
by the survey team: a ground-level record of much of the park. They're for
reference only, not used in the game. Each is shrunk to 1024 px on its long
side and saved as data/photos/vt_trees/<treeid>_<n>.jpg, with index.json
listing each tree's species, position and photos. Already-downloaded photos
are skipped, so it can be re-run to pick up new ones. (Not in git: large,
and re-fetchable.)
"""

import io
import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "photos" / "vt_trees"
LAYER = "https://arcgis-central-prod.aws.gis.cloud.vt.edu/arcgis/rest/services/facilities/Campus_Trees/FeatureServer/0"
ORIGIN = (37.2261281, -80.4285877)  # the pond
AGENT = "duck-pond-roblox-model/1.0 (personal hobby project)"


def get(url, params=None, binary=False):
    cmd = ["curl", "-sS", "-m", "120", "-G", url, "-H", f"User-Agent: {AGENT}"]
    for k, v in (params or {}).items():
        cmd += ["--data-urlencode", f"{k}={v}"]
    out = subprocess.run(cmd, check=True, capture_output=True).stdout
    return out if binary else json.loads(out)


def main():
    reach = float(sys.argv[1]) if len(sys.argv) > 1 else 250.0
    OUT.mkdir(parents=True, exist_ok=True)
    for leftover in OUT.glob("*.part"):
        leftover.unlink()
    dlat = reach / 111_132.0
    dlon = reach / (111_320.0 * math.cos(math.radians(ORIGIN[0])))
    box = f"{ORIGIN[1] - dlon},{ORIGIN[0] - dlat},{ORIGIN[1] + dlon},{ORIGIN[0] + dlat}"
    found = get(f"{LAYER}/query", {
        "where": "status='Alive'", "geometry": box, "geometryType": "esriGeometryEnvelope", "inSR": 4326,
        "outSR": 4326, "outFields": "objectid,treeid,commonname,scientificname,height,latitude,longitude",
        "resultRecordCount": 2000, "f": "json"})["features"]
    trees = {f["attributes"]["objectid"]: f["attributes"] for f in found}
    print(len(trees), "trees within", reach, "m")

    index_path = OUT / "index.json"
    index = json.load(open(index_path)) if index_path.exists() else {}
    ids = sorted(trees)
    got = 0
    for start in range(0, len(ids), 50):
        batch = ids[start:start + 50]
        groups = get(f"{LAYER}/queryAttachments", {"objectIds": ",".join(map(str, batch)), "f": "json"})
        for group in groups.get("attachmentGroups", []):
            a = trees[group["parentObjectId"]]
            treeid = (a.get("treeid") or str(group["parentObjectId"])).strip()
            entry = index.setdefault(treeid, {
                "species": a.get("commonname"), "scientific": a.get("scientificname"),
                "height_ft": a.get("height"), "lat": a.get("latitude"), "lon": a.get("longitude"), "photos": []})
            for n, info in enumerate(group["attachmentInfos"], 1):
                if not info.get("contentType", "").startswith("image"):
                    continue
                name = f"{treeid}_{n}.jpg"
                if (OUT / name).exists():
                    if name not in entry["photos"]:
                        entry["photos"].append(name)  # saved before an interruption, not yet indexed
                    continue
                raw = get(f"{LAYER}/{group['parentObjectId']}/attachments/{info['id']}", binary=True)
                try:
                    img = Image.open(io.BytesIO(raw)).convert("RGB")
                except Exception:
                    continue
                img.thumbnail((1024, 1024))
                # Via a temporary name, so an interruption never leaves half a photo.
                tmp = OUT / (name + ".part")
                img.save(tmp, "JPEG", quality=85)
                tmp.replace(OUT / name)
                if name not in entry["photos"]:
                    entry["photos"].append(name)
                got += 1
        json.dump(index, open(index_path, "w"), indent=1)
        print(f"  {min(start + 50, len(ids))}/{len(ids)} trees, {got} new photos")
    print("done:", got, "new photos;", sum(len(e["photos"]) for e in index.values()), "in all")


if __name__ == "__main__":
    main()
