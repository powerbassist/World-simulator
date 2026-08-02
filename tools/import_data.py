#!/usr/bin/env python3
"""Regenerate data/nations/*.json (imported block only), data/geo/europe.geojson
and data/geo/world.geojson from the raw datasets in sources/. See
docs/data-sources.md and docs/data-architecture.md for the pipeline this
implements.
"""
import argparse
import json
import sys
from math import floor, log10
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "sources"
NATIONS_DIR = ROOT / "data" / "nations"
GEO_OUT = ROOT / "data" / "geo" / "europe.geojson"
WORLD_OUT = ROOT / "data" / "geo" / "world.geojson"

NATIONS = ["FRA", "DEU", "ITA", "ESP", "BEL", "NLD", "LUX", "CHE", "GBR", "AUT"]

YEAR = 2024
USD_TO_EUR = 0.92

# Drops overseas territories (e.g. French Guiana, Réunion) that bloat S8's map bounds.
LON_MIN, LON_MAX = -11, 32
LAT_MIN, LAT_MAX = 34, 72

# U5b, the world backdrop. Deliberately the 1:110m file rather than the 1:50m one
# the roster uses: 242 countries at 1:50m is several megabytes of JSON parsed at
# every launch, larger than the satellite raster it would be drawn over, to gain
# detail nothing in the game can click on. Coordinates are rounded harder for the
# same reason -- 2 decimals is ~1 km, which is below one screen pixel at every
# zoom map_view.gd offers.
WORLD_SOURCE = "ne_110m_admin_0_countries.geojson"
WORLD_PRECISION = 2

# Square degrees of bounding box below which a world ring is dropped. At the
# furthest zoom out (~6 px per degree on a 1080p screen) a 1 deg² island is about
# 2.5 px across; the raster underneath still shows it, and a border polyline that
# small is a smudge rather than a coastline.
MIN_WORLD_RING_DEG2 = 1.0

INDICATORS = {
    "gdp": "NY.GDP.MKTP.CD",
    "population": "SP.POP.TOTL",
    "unemployment": "SL.UEM.TOTL.ZS",
    "agriculture": "NV.AGR.TOTL.ZS",
    "industry": "NV.IND.TOTL.ZS",
    "services": "NV.SRV.TOTL.ZS",
}


def load_wb_indicator_for_year(code, year):
    path = SOURCES / "wb" / f"{code}.json"
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return {
        row["countryiso3code"]: row["value"]
        for row in (data[1] or [])
        if row["date"] == str(year)
    }


def round_sig(value, sig):
    if value == 0:
        return 0.0
    digits = sig - int(floor(log10(abs(value)))) - 1
    return round(value, digits)


def round_to_nearest(value, step):
    return int(round(value / step) * step)


def build_imported_block(year):
    wb = {name: load_wb_indicator_for_year(code, year) for name, code in INDICATORS.items()}

    imported = {}
    for nid in NATIONS:
        values = {name: wb[name].get(nid) for name in INDICATORS}
        missing = [name for name, v in values.items() if v is None]
        if missing:
            sys.exit(f"{nid}: missing {year} data for indicators {missing}")

        gdp_eur_bn = round_sig(values["gdp"] * USD_TO_EUR / 1e9, 3)
        population = round_to_nearest(values["population"], 100_000)
        unemployment_pct = round(values["unemployment"], 1)

        sector_sum = values["agriculture"] + values["industry"] + values["services"]
        sectors = {
            "agriculture": round(values["agriculture"] / sector_sum, 3),
            "industry": round(values["industry"] / sector_sum, 3),
            "services": round(values["services"] / sector_sum, 3),
        }
        residue = round(1.0 - sum(sectors.values()), 3)
        if residue != 0:
            largest = max(sectors, key=sectors.get)
            sectors[largest] = round(sectors[largest] + residue, 3)

        imported[nid] = {
            "_source": "worldbank",
            "_year": year,
            "_usd_eur": USD_TO_EUR,
            "population": population,
            "gdp_eur_bn": gdp_eur_bn,
            "unemployment_pct": unemployment_pct,
            "sectors": sectors,
        }
    return imported


def write_nation_file(nid, imported_block):
    path = NATIONS_DIR / f"{nid}.json"
    if not path.exists():
        sys.exit(f"{nid}: {path} does not exist. The import script never creates "
                  f"nation files, only refreshes the 'imported' block of an existing one.")

    with open(path, encoding="utf-8") as f:
        nation = json.load(f)

    ordered = {
        "id": nation["id"],
        "name": nation["name"],
        "geo_id": nation["geo_id"],
        "capital": nation["capital"],
        "playable": nation["playable"],
        "government": nation["government"],
        "fiscal": nation["fiscal"],
        "imported": imported_block,
    }
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(ordered, f, ensure_ascii=False, indent=2)
        f.write("\n")


def bbox_outside(ring):
    lons = [pt[0] for pt in ring]
    lats = [pt[1] for pt in ring]
    return (max(lons) < LON_MIN or min(lons) > LON_MAX
            or max(lats) < LAT_MIN or min(lats) > LAT_MAX)


def clean_ring(ring, precision=4):
    rounded = [[round(pt[0], precision), round(pt[1], precision)] for pt in ring]
    cleaned = [rounded[0]]
    for pt in rounded[1:]:
        if pt != cleaned[-1]:
            cleaned.append(pt)
    return cleaned


def bbox_area(ring):
    lons = [pt[0] for pt in ring]
    lats = [pt[1] for pt in ring]
    return (max(lons) - min(lons)) * (max(lats) - min(lats))


def label_point(props):
    """Natural Earth's own label anchor, which is placed by hand and is a better
    anchor than a polygon centroid -- France's centroid is fine, Norway's is in
    Sweden. Falls back to nothing rather than guessing; map_view.gd skips a nation
    with no label point instead of drawing one in the wrong country."""
    lon = props.get("LABEL_X")
    lat = props.get("LABEL_Y")
    if lon is None or lat is None:
        return {}
    return {"label_lon": round(float(lon), 4), "label_lat": round(float(lat), 4)}


def build_geo():
    path = SOURCES / "ne_50m_admin_0_countries.geojson"
    with open(path, encoding="utf-8") as f:
        ne = json.load(f)

    features_by_id = {}
    for feature in ne["features"]:
        # Never ISO_A3 — it is "-99" for France in this dataset.
        adm0 = feature["properties"].get("ADM0_A3")
        if adm0 not in NATIONS:
            continue

        geom = feature["geometry"]
        polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        kept = [[clean_ring(ring) for ring in poly]
                for poly in polys if not bbox_outside(poly[0])]
        if not kept:
            sys.exit(f"{adm0}: bounding-box filter dropped every polygon")

        props = {"id": adm0}
        props.update(label_point(feature["properties"]))
        features_by_id[adm0] = {
            "type": "Feature",
            "properties": props,
            "geometry": {"type": "MultiPolygon", "coordinates": kept},
        }

    missing = [n for n in NATIONS if n not in features_by_id]
    if missing:
        sys.exit(f"missing geometry for: {missing}")

    features = [features_by_id[nid] for nid in sorted(features_by_id)]
    return {"type": "FeatureCollection", "features": features}


def build_world():
    """The backdrop beyond the roster: every country the game does not simulate,
    as outlines only.

    Excludes the ten in NATIONS on purpose. They come from europe.geojson, which
    is a finer source, and map_view.gd tints them -- drawn from both files they
    would be outlined twice and tinted over their own coastline.
    """
    path = SOURCES / WORLD_SOURCE
    with open(path, encoding="utf-8") as f:
        ne = json.load(f)

    features = []
    seen = set()
    for feature in ne["features"]:
        props = feature["properties"]
        adm0 = props.get("ADM0_A3")
        if adm0 in NATIONS:
            continue

        # ADM0_A3 is "-99" for a handful of disputed entries in this file, and
        # the loader keys features by id, so a collision would silently drop one.
        fid = adm0 if adm0 and adm0 != "-99" else str(props.get("NAME", "")).upper()
        if not fid or fid in seen:
            continue
        seen.add(fid)

        geom = feature["geometry"]
        polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        kept = [[clean_ring(poly[0], WORLD_PRECISION)]
                for poly in polys if bbox_area(poly[0]) >= MIN_WORLD_RING_DEG2]
        if not kept:
            continue

        out_props = {"id": fid}
        out_props.update(label_point(props))
        features.append({
            "type": "Feature",
            "properties": out_props,
            "geometry": {"type": "MultiPolygon", "coordinates": kept},
        })

    features.sort(key=lambda f: f["properties"]["id"])
    return {"type": "FeatureCollection", "features": features}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--year", type=int, default=YEAR)
    args = parser.parse_args()

    imported = build_imported_block(args.year)
    for nid in NATIONS:
        write_nation_file(nid, imported[nid])

    GEO_OUT.parent.mkdir(parents=True, exist_ok=True)
    write_geojson(GEO_OUT, build_geo(), indent=2)
    world = build_world()
    # Compact rather than indent=2: the world file is one long list of coordinate
    # pairs nobody reads by hand, and pretty-printing it roughly triples a file
    # that is already the largest thing in data/.
    write_geojson(WORLD_OUT, world, indent=None)

    print(f"Imported {len(NATIONS)} nations for {args.year}.")
    print(f"Wrote {GEO_OUT.relative_to(ROOT)}")
    print(f"Wrote {WORLD_OUT.relative_to(ROOT)} ({len(world['features'])} features)")


def write_geojson(path, collection, indent):
    separators = None if indent else (",", ":")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(collection, f, ensure_ascii=False, indent=indent, separators=separators)
        f.write("\n")


if __name__ == "__main__":
    main()
