#!/usr/bin/env python3
"""How far do Europe's real regional population shares actually drift?

WHY THIS EXISTS. src/sim/migration_constants.gd's clause (ii) was originally written
against SHARE_DRIFT_MAX -- one number with two names, evaluated on exactly the quantity
the bound guards, so the upper crossing restated the guard rail instead of measuring the
model. This project names that failure repeatedly: a band whose ceiling is the clamp
measures the clamp. The replacement ceiling is MEASURED, from the same data family the
register itself came from -- V1.6a's rule, that a band edge moves under widening or
refinement while a fit converges.

THE CEILING. The model's regional population shares may not drift further over 168
months than real European regional population shares actually drift over a comparable
span. It is the LARGEST per-region drift observed across the roster, not a mean: the
model must be able to reproduce Europe's most mobile real region without exceeding the
ceiling, and a mean would forbid the interesting case.

METHOD, and every rule here is the register's own rather than this file's:
  * THE REGISTER IS THE AUTHORITY ON THE ROSTER. Exactly the NUTS codes
    data/regions/<ID>.json names -- no more, no fewer -- so the shares compared are
    shares of the same partition the model runs. A raw sum over every returned code
    would re-introduce extra-regio, the overseas regions and the duplicated NUTS
    vintage that docs/geography-model.md sections 1 and 3 record dropping, and the
    drift would be an artefact of the roster rather than of migration.
  * SHARE IS OF THE NATION, not of the register sum -- import_data.py's own
    `floor_share(region["population"] / national)`, so the unnamed residual is inside
    the denominator exactly as it is in the shipped file.
  * THE WINDOW IS THE WIDEST THAT KEEPS THE ROSTER STABLE, per nation, and where it
    stops is a finding rather than a limit. Britain's series ends at 2019 (Eurostat
    dropped UK regions after withdrawal, docs/region-economy-model.md section 8) and
    the Netherlands' NL31/NL33 vanish at 2024, replaced by the 2024 codes NL35/NL36 --
    equal to the person in every overlapping year, so a window crossing that boundary
    measures a RE-CODING and not a migration. Detected by name and excluded by taking
    the window that stops before it.

Run: python tools/region_drift.py
Reads sources/eurostat/demo_r_pjangrp3_<year>.json, fetched by the loop in
docs/data-sources.md. tools/ is dev-only and never ships.
"""

import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "sources", "eurostat")

# 2014 is where the NUTS 2021 back-cast begins: 2011-2013 return an EMPTY value dict
# for this request, not a short one. 2025 is the newest published.
YEARS = list(range(2014, 2026))

# The model's horizon, and the span every drift below is scaled to.
HORIZON_YEARS = 14.0

NUTS_COUNTRY = {
    "FRA": "FR", "DEU": "DE", "ITA": "IT", "ESP": "ES", "BEL": "BE",
    "NLD": "NL", "LUX": "LU", "CHE": "CH", "GBR": "UK", "AUT": "AT",
}


def load_year(year):
    """{geo code: population} for one cached response, or None if it is empty."""
    path = os.path.join(SOURCES, "demo_r_pjangrp3_%d.json" % year)
    if not os.path.exists(path):
        sys.exit("missing %s -- see docs/data-sources.md" % path)
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    values = data.get("value") or {}
    if not values:
        return None
    index = data["dimension"]["geo"]["category"]["index"]
    inverse = {v: k for k, v in index.items()}
    return {inverse[int(k)]: v for k, v in values.items()}


def load_register():
    """{nation id: [NUTS code]} exactly as data/regions/ names them."""
    out = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "regions", "*.json"))):
        nid = os.path.basename(path)[:3]
        with open(path, encoding="utf-8") as handle:
            out[nid] = [r["id"] for r in json.load(handle)["regions"]]
    return out


def main():
    data = {}
    for year in YEARS:
        values = load_year(year)
        if values is not None:
            data[year] = values
    years = sorted(data)
    register = load_register()

    print("=== (a) roster stability: years in which EVERY register code carries a "
          "value ===")
    windows = {}
    for nid, codes in sorted(register.items()):
        cc = NUTS_COUNTRY[nid]
        good = [y for y in years
                if data[y].get(cc) and all(c in data[y] for c in codes)]
        windows[nid] = good
        gaps = [y for y in years if y not in good]
        print("  %s  %d codes | usable %s | dropped %s"
              % (nid, len(codes),
                 ("%d-%d" % (good[0], good[-1])) if good else "NONE",
                 ", ".join(str(y) for y in gaps) if gaps else "none"))

    print()
    print("=== (b) the vintage collision, by name ===")
    for year in years:
        row = data[year]
        print("  %d  NL31 %-9s NL33 %-9s | NL35 %-9s NL36 %-9s"
              % (year,
                 row.get("NL31", "absent"), row.get("NL33", "absent"),
                 row.get("NL35", "absent"), row.get("NL36", "absent")))
    print("  NL31/NL33 are the 2021 codes and NL35/NL36 the 2024 ones, equal to the")
    print("  person in every overlapping year. The register names NL31/NL33, so the")
    print("  Dutch window STOPS before the re-coding rather than measuring it.")

    print()
    print("=== (c) per-nation drift in share of the NATION, scaled to %g years ==="
          % HORIZON_YEARS)
    print("  nation  window      span  worst region                       "
          "drift    /yr       @168m")
    worst = None
    rows = []
    for nid in sorted(register):
        good = windows[nid]
        if len(good) < 2:
            print("  %s  no usable window -- EXCLUDED" % nid)
            continue
        y0, y1 = good[0], good[-1]
        span = float(y1 - y0)
        cc = NUTS_COUNTRY[nid]
        best = None
        for code in register[nid]:
            s0 = data[y0][code] / float(data[y0][cc])
            s1 = data[y1][code] / float(data[y1][cc])
            drift = abs(s1 - s0)
            if best is None or drift > best[1]:
                best = (code, drift)
        code, drift = best
        scaled = drift / span * HORIZON_YEARS
        rows.append((nid, y0, y1, span, code, drift, scaled))
        if worst is None or scaled > worst[6]:
            worst = rows[-1]
        print("  %s     %d-%d   %4.0f  %-34s %.4f   %.5f   %.4f"
              % (nid, y0, y1, span, code, drift, drift / span, scaled))

    print()
    print("=== (d) THE CEILING ===")
    nid, y0, y1, span, code, drift, scaled = worst
    print("  largest per-region drift across the roster: %s in %s" % (code, nid))
    print("  %d-%d (%g years), %.6f share points raw, %.6f per year"
          % (y0, y1, span, drift, drift / span))
    print("  scaled to %g years / 168 months: %.6f" % (HORIZON_YEARS, scaled))
    print("  CEILING = %.4f" % round(scaled, 4))


if __name__ == "__main__":
    main()
