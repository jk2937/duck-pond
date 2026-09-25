"""Download the real-world data the model is built from, into data/raw/.

    python3 tools/fetch_data.py

  osm.json    OpenStreetMap features in the box (Overpass API)
              (c) OpenStreetMap contributors, ODbL: credit it in the game
  dem.tif     USGS 3DEP bare-earth elevation, ~1 m, float32 metres (public domain)
  aerial.png  USGS imagery, for reference (public domain)

All three cover BBOX, in lon/lat, and share its pixel frame.
"""

import subprocess
from pathlib import Path

RAW = Path(__file__).resolve().parent.parent / "data" / "raw"

# West, south, east, north. The Duck Pond, its upper ponds, Stroubles Creek in
# and out, and the buildings round about.
BBOX = (-80.4330, 37.2235, -80.4245, 37.2290)
DEM_SIZE = (760, 612)  # about a metre a pixel
AERIAL_SIZE = (1520, 1224)
AGENT = "duck-pond-roblox-model/1.0 (personal hobby project)"


def curl(out, url, params):
    cmd = ["curl", "-sS", "-m", "180", "-G", url, "-H", f"User-Agent: {AGENT}", "-o", str(out)]
    for k, v in params.items():
        cmd += ["--data-urlencode", f"{k}={v}"]
    subprocess.run(cmd, check=True)


def main():
    RAW.mkdir(parents=True, exist_ok=True)
    w, s, e, n = BBOX
    box = f"{w},{s},{e},{n}"
    curl(RAW / "osm.json", "https://overpass-api.de/api/interpreter",
         {"data": f"[out:json][timeout:60];(nwr({s},{w},{n},{e}););out geom;"})
    curl(RAW / "dem.tif", "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage",
         {"bbox": box, "bboxSR": 4326, "imageSR": 4326, "size": f"{DEM_SIZE[0]},{DEM_SIZE[1]}",
          "format": "tiff", "pixelType": "F32", "interpolation": "RSP_BilinearInterpolation", "f": "image"})
    curl(RAW / "aerial.png", "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/export",
         {"bbox": box, "bboxSR": 4326, "imageSR": 4326, "size": f"{AERIAL_SIZE[0]},{AERIAL_SIZE[1]}",
          "format": "png", "f": "image"})
    print("fetched into", RAW)


if __name__ == "__main__":
    main()
