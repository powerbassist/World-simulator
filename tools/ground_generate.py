#!/usr/bin/env python3
"""The ground at depth -- V4.10a. Dev-only, never ships, never in the gate.

    python tools/ground_generate.py --download     # once: fetch the DEM into sources/
    python tools/ground_generate.py                # bake assets/map/ground_europe.*
    python tools/ground_generate.py --check        # sidecar and image agree with the geometry

Bakes ONE plate-carree texture the map draws at depth in place of the satellite:
land is a paper tone times a multiply hillshade, sea is the map's own flat sea
lightened over the shelves, and alpha feathers to 0 at the extent's edge so the
satellite shows through past it without a seam. Writes the image and a sidecar
JSON with its lon/lat bounds; src/ui/map_ground.gd reads both, and nothing
authors the bounds a second time.

Why baked colour and not channels: without a shader (V4.10c is the first), a
draw's modulate colour cannot tell land from sea inside one texture, so the
palette lives here and re-tuning it means re-running this script -- seconds,
against the cached DEM.

Why the coast comes from data/geo/ and not from the DEM: the land mask is
rasterised from the same rings map_view strokes (outer rings only, the
`_outer_ring()` rule), so the paper coast and the stroked coast agree by
construction -- and the Dutch polders, below sea level in any DEM, stay land.
The DEM only shades.

Source: NOAA NCEI ETOPO 2022, 60 arc-second, ice surface -- a US federal work,
public domain; provenance in docs/data-sources.md. Fetched ONCE through NOAA's
ERDDAP griddap subset into the gitignored sources/etopo/ (the tier doc refuses a
streamed tile source by name; this is a one-time download, not a stream).

Dependencies beyond the gate's plain python: numpy, scipy (NetCDF-3 reading and
resampling), Pillow (polygon raster, WebP). This script is run by hand when the
asset is re-baked and by nothing else.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import time
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.io import netcdf_file
from scipy.ndimage import binary_opening, map_coordinates

ROOT = Path(__file__).resolve().parent.parent
GEO = ROOT / "data" / "geo"
CACHE = ROOT / "sources" / "etopo"
OUT_IMAGE = ROOT / "assets" / "map" / "ground_europe.webp"
OUT_SIDECAR = ROOT / "assets" / "map" / "ground_europe.json"

ERDDAP = "https://oceanwatch.pifsc.noaa.gov/erddap/griddap/ETOPO_2022_v1_60s.nc"
SOURCE_NAME = "ETOPO 2022 v1 60s surface"

# The extent is the bbox of every roster ring (europe.geojson: the 41 simulated
# nations) grown by this margin and snapped OUT to whole degrees. Six degrees is
# a little over half a screen at the band's top edge (zoom 2.5, 30 px/deg on a
# 1920 px map), so the feather below sits off-screen while the player looks at
# any roster nation's coast.
EXTENT_MARGIN_DEG = 6.0

# Alpha ramps 255 -> 0 across the last FEATHER_DEG inside each edge. Wide enough
# that the hand-off from paper to photograph reads as a fade, not a line, at max
# zoom (3 deg = 288 px at 96 px/deg); narrow enough to stay inside the margin.
FEATHER_DEG = 3.0

# Output density. 60 is the DEM's native grid (one sample per arc-minute), so at
# the default every output pixel centre IS a DEM cell centre and the resample is
# an identity. At MAX_ZOOM (8 x BASE_SCALE 12 = 96 screen px/deg) that is a 1.6x
# upscale -- soft, not blocky, for a hillshade. The plan's fallback (45) applies
# if the asset breaks 6 MB or 300 ms decode.
DEFAULT_PX_PER_DEG = 60

# Land mask supersampling: polygons rasterised at 4x and box-filtered down, so the
# coast is anti-aliased rather than stair-stepped at 1.6x upscale.
MASK_SUPERSAMPLE = 4

# The three vintages do not tile: world.geojson's 1:110m outlines and the roster's
# 1:50m / 1:10m rings leave thin gaps along every shared land border (Russia's
# with Finland, Belarus, Ukraine), and over paper a gap reads as a sea-coloured
# crack -- over the photograph it never showed. A crack is "sea" narrower than
# this radius that the DEM says is LAND (z > 0); it is filled. Real narrow water
# -- the Bosporus, the Sound, a fjord -- is below sea level in the DEM and stays
# sea, so the fill cannot close a strait. 4 px = ~7 km at 60 px/deg, wider than
# the widest crack measured on the preview.
SLIVER_RADIUS_PX = 4

# Hillshade: Horn's method, the cartographic convention (light from the north-west
# at 45 degrees -- a light from the south reads as inverted relief to most eyes).
SUN_AZIMUTH_DEG = 315.0
SUN_ALTITUDE_DEG = 45.0
# Vertical exaggeration. At ~1.8 km cells real slopes are shallow; 3x is what
# makes the Massif Central and the Apennines read at all without turning the Alps
# into a black-and-white woodcut. Chosen on the preview, which is the instrument.
Z_EXAGGERATION = 3.0
# How dark the fully-shadowed slope gets relative to the paper: 0 would be flat
# paper, 1 would let a north-facing cliff go to black under the fills.
SHADE_STRENGTH = 0.55
# High ground darkens a touch on top of the shading (full effect at 3000 m), the
# hypsometric hint a paper map gives -- small, because the fills sit over it.
HYPSO_STRENGTH = 0.12
HYPSO_TOP_M = 3000.0

# Palette, linear 0..1. PAPER is a muted parchment chosen against the navy-and-brass
# chrome: mid-tone, so both the near-white labels (which carry a dark outline) and
# the dark political strokes read over it. SEA is map_view.SEA exactly, so the
# ground's open ocean and the no-raster fallback are the same colour; SHELF
# lightens shallow water so the coast keeps an edge where the stroke is thin.
PAPER = (0.70, 0.66, 0.57)
SEA = (0.043, 0.075, 0.129)
SHELF = (0.10, 0.155, 0.23)
SHELF_DEPTH_M = 1500.0


def _outer_rings(path: Path):
    """Yield (feature_id, outer ring as [(lon, lat)...]) -- outer rings only, the
    rule map_view's `_outer_ring()` draws by."""
    data = json.loads(path.read_text(encoding="utf-8"))
    for feat in data["features"]:
        geom = feat["geometry"]
        polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        for poly in polys:
            if poly:
                yield feat["properties"].get("id", ""), poly[0]


def derive_extent() -> tuple[float, float, float, float]:
    xs: list[float] = []
    ys: list[float] = []
    for _id, ring in _outer_rings(GEO / "europe.geojson"):
        for lon, lat in ring:
            xs.append(lon)
            ys.append(lat)
    return (
        math.floor(min(xs) - EXTENT_MARGIN_DEG),
        math.ceil(max(xs) + EXTENT_MARGIN_DEG),
        math.floor(min(ys) - EXTENT_MARGIN_DEG),
        math.ceil(max(ys) + EXTENT_MARGIN_DEG),
    )


def _cache_paths() -> list[Path]:
    return [CACHE / "etopo_west.nc", CACHE / "etopo_east.nc"]


def download(extent) -> None:
    """ERDDAP serves longitudes 0..360, so an extent straddling Greenwich is two
    requests. Each is a NetCDF-3 file scipy reads without netCDF4."""
    lon_min, lon_max, lat_min, lat_max = extent
    CACHE.mkdir(parents=True, exist_ok=True)
    pad = 1.0  # one degree past each edge, so resampling never reads off the grid
    spans = [(lon_min - pad + 360.0, 359.9917), (0.0083, lon_max + pad)]
    for path, (a, b) in zip(_cache_paths(), spans):
        query = "z%5B({:.4f}):1:({:.4f})%5D%5B({:.4f}):1:({:.4f})%5D".format(
            lat_min - pad, lat_max + pad, a, b)
        url = ERDDAP + "?" + query
        print("fetching", url)
        with urllib.request.urlopen(url, timeout=600) as resp:
            path.write_bytes(resp.read())
        print("  ->", path, path.stat().st_size, "bytes")


def load_dem():
    """Return (lons ascending in -180..180, lats ascending, z[lat, lon] float32)."""
    parts = []
    for path in _cache_paths():
        if not path.exists():
            sys.exit("DEM cache missing at %s -- run: python tools/ground_generate.py --download" % path)
        f = netcdf_file(str(path), mmap=False)
        lon = np.array(f.variables["longitude"][:], dtype=np.float64)
        lat = np.array(f.variables["latitude"][:], dtype=np.float64)
        z = np.array(f.variables["z"][:], dtype=np.float32)
        f.close()
        lon = np.where(lon > 180.0, lon - 360.0, lon)
        parts.append((lon, lat, z))
    (lw, latw, zw), (le, late, ze) = parts
    if not np.allclose(latw, late):
        sys.exit("the two DEM halves disagree on latitude -- re-download")
    lons = np.concatenate([lw, le])
    z = np.concatenate([zw, ze], axis=1)
    order = np.argsort(lons)
    return lons[order], latw, z[:, order]


def resample(lons, lats, z, extent, ppd):
    lon_min, lon_max, lat_min, lat_max = extent
    w = int(round((lon_max - lon_min) * ppd))
    h = int(round((lat_max - lat_min) * ppd))
    # Pixel centres, top row first (image rows run north to south).
    px_lon = lon_min + (np.arange(w) + 0.5) / ppd
    px_lat = lat_max - (np.arange(h) + 0.5) / ppd
    # Fractional indices into the DEM's evenly spaced axes.
    fi = (px_lon - lons[0]) / (lons[1] - lons[0])
    fj = (px_lat - lats[0]) / (lats[1] - lats[0])
    jj, ii = np.meshgrid(fj, fi, indexing="ij")
    out = map_coordinates(z, [jj, ii], order=1, mode="nearest").astype(np.float32)
    return out, px_lat


def hillshade(z, px_lat, ppd):
    """Multiply-form hillshade: 1.0 on flat ground, darker on slopes facing away
    from the sun, never brighter than the paper."""
    land_z = np.maximum(z, 0.0) * Z_EXAGGERATION
    p = np.pad(land_z, 1, mode="edge")
    a, b, c = p[:-2, :-2], p[:-2, 1:-1], p[:-2, 2:]
    d, f = p[1:-1, :-2], p[1:-1, 2:]
    g, h, i = p[2:, :-2], p[2:, 1:-1], p[2:, 2:]
    # Plate carree: a degree of longitude shrinks with cos(lat), a degree of
    # latitude does not -- the cell is not square in metres.
    dy = 110_574.0 / ppd
    dx = (111_320.0 / ppd) * np.cos(np.radians(px_lat))[:, None]
    dzdx = ((c + 2 * f + i) - (a + 2 * d + g)) / (8.0 * dx)
    dzdy = ((g + 2 * h + i) - (a + 2 * b + c)) / (8.0 * dy)
    slope = np.arctan(np.hypot(dzdx, dzdy))
    aspect = np.arctan2(dzdy, -dzdx)
    zen = math.radians(90.0 - SUN_ALTITUDE_DEG)
    az = math.radians((360.0 - SUN_AZIMUTH_DEG + 90.0) % 360.0)
    hs = math.cos(zen) * np.cos(slope) + math.sin(zen) * np.sin(slope) * np.cos(az - aspect)
    shade = np.clip(hs / math.cos(zen), 0.0, 1.0)
    factor = 1.0 - SHADE_STRENGTH * (1.0 - shade)
    factor *= 1.0 - HYPSO_STRENGTH * np.clip(z / HYPSO_TOP_M, 0.0, 1.0)
    return factor.astype(np.float32)


def land_mask(extent, w, h, ppd):
    lon_min, _lon_max, _lat_min, lat_max = extent
    ss = MASK_SUPERSAMPLE
    big = Image.new("L", (w * ss, h * ss), 0)
    draw = ImageDraw.Draw(big)
    k = ppd * ss
    for name in ("world.geojson", "europe.geojson", "regions.geojson"):
        for _id, ring in _outer_rings(GEO / name):
            if len(ring) < 3:
                continue
            draw.polygon([((lon - lon_min) * k, (lat_max - lat) * k) for lon, lat in ring], fill=255)
    small = big.resize((w, h), Image.BOX)
    return np.asarray(small, dtype=np.float32) / 255.0


def feather(w, h, ppd):
    f = FEATHER_DEG * ppd
    x = np.minimum(np.arange(w) + 0.5, w - np.arange(w) - 0.5) / f
    y = np.minimum(np.arange(h) + 0.5, h - np.arange(h) - 0.5) / f
    return np.clip(np.minimum(y[:, None], x[None, :]), 0.0, 1.0)


def bake(ppd: int) -> None:
    t0 = time.time()
    extent = derive_extent()
    lons, lats, z = load_dem()
    zr, px_lat = resample(lons, lats, z, extent, ppd)
    h, w = zr.shape
    shade = hillshade(zr, px_lat, ppd)
    mask = land_mask(extent, w, h, ppd)
    # Not "< 0.5": a 1 px crack is never fully sea after the 4x box filter, and a
    # half-covered crack pixel still prints as a grey hairline over the paper.
    sea = mask < 0.999
    r = SLIVER_RADIUS_PX
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    narrow = sea & ~binary_opening(sea, structure=(xx * xx + yy * yy) <= r * r)
    mask = np.where(narrow & (zr > 0.0), 1.0, mask).astype(np.float32)
    depth = np.sqrt(np.clip(-zr / SHELF_DEPTH_M, 0.0, 1.0))
    rgb = np.empty((h, w, 3), dtype=np.float32)
    for ch in range(3):
        sea = SHELF[ch] + (SEA[ch] - SHELF[ch]) * depth
        land = PAPER[ch] * shade
        rgb[:, :, ch] = sea + (land - sea) * mask
    alpha = feather(w, h, ppd)
    rgba = np.dstack([rgb, alpha])
    img = Image.fromarray(np.clip(rgba * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    OUT_IMAGE.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_IMAGE, "WEBP", quality=90, method=6)
    sidecar = _sidecar(extent, ppd, w, h)
    OUT_SIDECAR.write_text(json.dumps(sidecar, indent=2) + "\n", encoding="utf-8")
    print("extent lon %s..%s lat %s..%s" % extent)
    print("image %dx%d at %d px/deg, %d bytes, %.1f s"
          % (w, h, ppd, OUT_IMAGE.stat().st_size, time.time() - t0))


def _sidecar(extent, ppd, w, h) -> dict:
    lon_min, lon_max, lat_min, lat_max = extent
    return {
        "lon_min": float(lon_min), "lon_max": float(lon_max),
        "lat_min": float(lat_min), "lat_max": float(lat_max),
        "px_per_deg": float(ppd), "width": w, "height": h,
        "source": SOURCE_NAME, "generator": "tools/ground_generate.py",
    }


def check() -> int:
    side = json.loads(OUT_SIDECAR.read_text(encoding="utf-8"))
    extent = derive_extent()
    ppd = side["px_per_deg"]
    want = _sidecar(extent, int(ppd), int(round((extent[1] - extent[0]) * ppd)),
                    int(round((extent[3] - extent[2]) * ppd)))
    bad = [k for k in want if want[k] != side.get(k)]
    with Image.open(OUT_IMAGE) as img:
        if img.size != (side["width"], side["height"]):
            bad.append("image size %s" % (img.size,))
        if img.mode != "RGBA":
            bad.append("image mode %s" % img.mode)
    if bad:
        print("ground asset out of step with the geometry:", ", ".join(bad))
        return 1
    print("ground asset OK: %dx%d, extent %s" % (side["width"], side["height"], extent))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--download", action="store_true")
    ap.add_argument("--px-per-deg", type=int, default=DEFAULT_PX_PER_DEG)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if args.check:
        return check()
    if args.download:
        download(derive_extent())
    bake(args.px_per_deg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
