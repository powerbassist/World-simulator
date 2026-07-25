#!/usr/bin/env python3
"""Regenerate data/nations/*.json (imported block only) and data/geo/europe.geojson
from the raw datasets in sources/. See docs/data-sources.md and
docs/data-architecture.md for the pipeline this implements.
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

NATIONS = ["FRA", "DEU", "ITA", "ESP", "BEL", "NLD", "LUX", "CHE", "GBR", "AUT"]

YEAR = 2024
USD_TO_EUR = 0.92

# Drops overseas territories (e.g. French Guiana, Réunion) that bloat S8's map bounds.
LON_MIN, LON_MAX = -11, 32
LAT_MIN, LAT_MAX = 34, 72

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


def clean_ring(ring):
    rounded = [[round(pt[0], 4), round(pt[1], 4)] for pt in ring]
    cleaned = [rounded[0]]
    for pt in rounded[1:]:
        if pt != cleaned[-1]:
            cleaned.append(pt)
    return cleaned


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

        features_by_id[adm0] = {
            "type": "Feature",
            "properties": {"id": adm0},
            "geometry": {"type": "MultiPolygon", "coordinates": kept},
        }

    missing = [n for n in NATIONS if n not in features_by_id]
    if missing:
        sys.exit(f"missing geometry for: {missing}")

    features = [features_by_id[nid] for nid in sorted(features_by_id)]
    return {"type": "FeatureCollection", "features": features}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--year", type=int, default=YEAR)
    args = parser.parse_args()

    imported = build_imported_block(args.year)
    for nid in NATIONS:
        write_nation_file(nid, imported[nid])

    geo = build_geo()
    GEO_OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(GEO_OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(geo, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Imported {len(NATIONS)} nations for {args.year}.")
    print(f"Wrote {GEO_OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
