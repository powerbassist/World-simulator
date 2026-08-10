#!/usr/bin/env python3
"""Regenerate data/nations/*.json (imported block only), data/geo/europe.geojson
and data/geo/world.geojson from the raw datasets in sources/. See
docs/data-sources.md and docs/data-architecture.md for the pipeline this
implements.
"""
import argparse
import json
import re
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

# V1.5b. The year the demographic trend is measured FROM. Every indicator is already
# fetched over date=2015:2024 (docs/data-sources.md), so a per-nation ageing slope
# costs one extra read of a series already on disk and no extra download.
#
# Measured rather than modelled, and that is the session's central call: a cohort
# machine driven by fertility and life expectancy re-derives, badly, a number the
# World Bank already publishes. A uniform 15-64 bucket predicts Luxembourg ages
# fastest of the ten; measured, it ages slowest (+0.142 pt/yr against France's
# +0.366). See docs/demography-model.md.
TREND_FROM_YEAR = 2015

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

# V1.5b, read at TREND_FROM_YEAR as well as at YEAR. Split from INDICATORS above
# rather than merged into it because only these three are read twice, and a reader
# who cannot see which are which has to go and find out.
#
# Participation is the 15-64 rate, which is what makes it multiply the working share
# cleanly. It is also what lets companies_constants.LABOUR_FORCE_SHARE be DELETED
# rather than re-derived: that constant's own comment called 0.45 "the measured
# participation-times-working-age figure for the roster, not a dial", and the claim
# checks out for France (74.07 x 61.34 = 0.4543) and fails for Germany (79.94 x
# 62.89 = 0.5027). One constant right for one nation becomes two measured facts for
# all ten.
COHORT_INDICATORS = {
    "young": "SP.POP.0014.TO.ZS",
    "old": "SP.POP.65UP.TO.ZS",
    "participation": "SL.TLF.ACTI.ZS",
}

# V1.5c. The inequality statistic docs/tiers/v1.md section 5 books to this session as a
# "declared stopgap read" -- on the premise, stated at section 6, that the index CANNOT
# BE DERIVED because the model has no brackets, deciles or capital/labour split. That
# premise is right and it does not matter: the index does not have to be derived,
# because the World Bank publishes it. All ten nations, 7-9 years each, on the same
# provider, the same licence and the same download loop as everything above.
#
# Held apart from COHORT_INDICATORS for one reason: coverage is EU-SILC-based and
# SPARSE. Nothing is published at YEAR for any of the ten -- the latest is 2021 (GBR,
# NLD), 2022 (CHE, DEU) or 2023 (the other six) -- so this series alone needs a
# nearest-year fallback, and load_wb_indicator_for_year()'s exact-year match plus
# build_imported_block()'s sys.exit would refuse the whole import. Which year was
# actually used is written into the block, per nation, for the reason
# `_trend_from_year` is: a provenance record that names a year the number does not come
# from is worse than no record.
SPARSE_INDICATORS = {
    "gini": "SI.POV.GINI",
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


def load_wb_indicator_nearest_year(code, year):
    """V1.5c. Value and the year it came from, per nation, for a series with gaps.

    Returns {iso3: (value, year_used)}. Nearest by absolute distance, ties broken
    toward the year ASKED FOR being the later one -- i.e. prefer a value from before
    the target over one from after it, because a Gini published after `YEAR` would
    describe a country the rest of the block does not.

    Deliberately not folded into load_wb_indicator_for_year(). Every other indicator
    is complete at both years, and a silent fallback on those would turn a missing
    2024 GDP -- which is a broken download and should stop the import -- into a
    quietly stale figure nobody notices.
    """
    path = SOURCES / "wb" / f"{code}.json"
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    by_nation = {}
    for row in (data[1] or []):
        if row["value"] is None:
            continue
        by_nation.setdefault(row["countryiso3code"], {})[int(row["date"])] = row["value"]

    out = {}
    for nid, series in by_nation.items():
        best = min(series, key=lambda y: (abs(y - year), y > year))
        out[nid] = (series[best], best)
    return out


def round_sig(value, sig):
    if value == 0:
        return 0.0
    digits = sig - int(floor(log10(abs(value)))) - 1
    return round(value, digits)


def round_to_nearest(value, step):
    return int(round(value / step) * step)


def build_cohorts_block(nid, now, base, years):
    """V1.5b. Two age shares, their measured slopes, and the participation rate.

    The 15-64 share is deliberately NOT emitted: src/sim/demography.gd derives it as
    the residual 1 - young - old, so there is exactly one answer and a conservation
    bug is structurally impossible. That is _apply_growth_to_sectors()'s discipline,
    which keeps sector output summing to GDP with no reconciliation.

    Shares carry a LINEAR slope in points per year, because a share cannot compound;
    population carries a compound rate, because it does. The pair replaces
    economy_constants.POP_GROWTH_PCT, one flat 0.15 shared by all ten.
    """
    return {
        "young_pct": round(now["young"], 2),
        "old_pct": round(now["old"], 2),
        "young_pct_per_yr": round((now["young"] - base["young"]) / years, 3),
        "old_pct_per_yr": round((now["old"] - base["old"]) / years, 3),
        "participation_pct": round(now["participation"], 2),
        "pop_growth_pct": round(
            100.0 * ((now["population"] / base["population"]) ** (1.0 / years) - 1.0), 3
        ),
    }


def build_inequality_block(nid, now, base):
    """V1.5c. The Gini index and its measured slope, with the years both came from.

    `now` and `base` are (value, year_used) pairs from
    load_wb_indicator_nearest_year(). The slope divides by the ACTUAL span between the
    two years used, not by trend_years -- GBR's latest is 2021 and Austria's is 2023,
    so a shared denominator would understate one and overstate the other by two years
    of drift each.

    Same shape as the cohort slopes and for the same reason: an index cannot compound.
    The spread is real and the SIGNS DIFFER -- Spain 36.2 -> 33.4 falling against
    Germany 31.4 -> 33.7 rising -- which is what makes this a measured fact rather
    than the clustered `coalition_position` failure a stopgap would risk.
    """
    value, year_used = now
    base_value, base_year = base
    span = float(year_used - base_year)
    if span <= 0.0:
        sys.exit(
            f"{nid}: Gini is published for only one year ({year_used}) in the "
            f"downloaded window -- a slope cannot be measured from one point"
        )
    return {
        "gini_index": round(value, 2),
        "gini_index_per_yr": round((value - base_value) / span, 3),
        "_year": year_used,
        "_from_year": base_year,
    }


def build_imported_block(year):
    every = dict(INDICATORS)
    every.update(COHORT_INDICATORS)
    wb = {name: load_wb_indicator_for_year(code, year) for name, code in every.items()}
    # The trend year needs the cohort indicators and population; reading the whole
    # set is one dict comprehension over files already open and keeps the two passes
    # symmetrical, which is worth more than the four values it discards.
    wb_base = {
        name: load_wb_indicator_for_year(code, TREND_FROM_YEAR)
        for name, code in every.items()
    }
    trend_years = float(year - TREND_FROM_YEAR)
    if trend_years <= 0.0:
        sys.exit(f"--year {year} is not after TREND_FROM_YEAR {TREND_FROM_YEAR}")

    # V1.5c, read through the nearest-year loader rather than the exact-year one --
    # see SPARSE_INDICATORS.
    sparse = {
        name: load_wb_indicator_nearest_year(code, year)
        for name, code in SPARSE_INDICATORS.items()
    }
    sparse_base = {
        name: load_wb_indicator_nearest_year(code, TREND_FROM_YEAR)
        for name, code in SPARSE_INDICATORS.items()
    }

    imported = {}
    for nid in NATIONS:
        values = {name: wb[name].get(nid) for name in every}
        missing = [name for name, v in values.items() if v is None]
        if missing:
            sys.exit(f"{nid}: missing {year} data for indicators {missing}")

        base = {name: wb_base[name].get(nid) for name in COHORT_INDICATORS}
        base["population"] = wb_base["population"].get(nid)
        missing_base = [name for name, v in base.items() if v is None]
        if missing_base:
            sys.exit(
                f"{nid}: missing {TREND_FROM_YEAR} data for indicators {missing_base} "
                f"-- the demographic slope cannot be measured without both years"
            )

        missing_sparse = [name for name in SPARSE_INDICATORS if nid not in sparse[name]]
        if missing_sparse:
            sys.exit(
                f"{nid}: no {missing_sparse} value at ANY year in the downloaded "
                f"window -- the nearest-year fallback had nothing to fall back to"
            )

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
            # V1.5b. Without this the provenance record lies: `_year` alone claims the
            # block describes one year, and the cohort slopes describe two.
            "_trend_from_year": TREND_FROM_YEAR,
            "_usd_eur": USD_TO_EUR,
            "population": population,
            "gdp_eur_bn": gdp_eur_bn,
            "unemployment_pct": unemployment_pct,
            "sectors": sectors,
            "cohorts": build_cohorts_block(nid, values, base, trend_years),
            "inequality": build_inequality_block(
                nid, sparse["gini"][nid], sparse_base["gini"][nid]
            ),
        }
    return imported


def write_nation_file(nid, imported_block):
    """Refreshes ONLY the `imported` block, preserving every other key and its order.

    It used to enumerate the keys it kept -- id, name, geo_id, capital, playable,
    government, fiscal, imported -- and rebuild the file from that list. Which meant
    that every top-level field a later session added was SILENTLY DELETED the next
    time anyone ran the import, and two already had been: U6b's `leader` block and
    the `flag` block. Found at V1.5b by diffing the ten files after an import and
    asking why the change was larger than the block it added.

    Rebuilding from the file's own key order preserves whatever is there, so this
    cannot happen again -- there is no list to forget to update. The docstring at the
    top of this function's error message already claimed this was the behaviour; now
    it is.
    """
    path = NATIONS_DIR / f"{nid}.json"
    if not path.exists():
        sys.exit(f"{nid}: {path} does not exist. The import script never creates "
                  f"nation files, only refreshes the 'imported' block of an existing one.")

    with open(path, encoding="utf-8") as f:
        nation = json.load(f)

    if "imported" not in nation:
        sys.exit(f"{nid}: {path} has no 'imported' block to refresh")

    ordered = {key: nation[key] for key in nation}
    ordered["imported"] = imported_block

    text = json.dumps(ordered, ensure_ascii=False, indent=2)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(compact_scalar_arrays(text) + "\n")


# A flat array of scalars, exploded by indent=2 over one line per element.
FLAT_ARRAY = re.compile(r"\[\s*\n\s*([^\[\]{}]*?)\s*\n\s*\]", re.DOTALL)


def compact_scalar_arrays(text):
    """Puts `["BEL", "CHE"]` back on one line, the way the nation files are written.

    json.dumps(indent=2) explodes every array, so without this an import rewrites
    `neighbours` and `flag.bands` in all ten files and the demographic block arrives
    buried in twenty lines of formatting churn. That matters beyond tidiness: the
    check that an import added ONLY what it claims to add is only readable if the
    script's output already matches what is committed.

    Scalars only -- an array holding an object or another array keeps its indented
    form, which is what leaves data/geo/ untouched (it uses write_geojson, not this).
    """
    return FLAT_ARRAY.sub(lambda m: "[" + " ".join(m.group(1).split()) + "]", text)


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
