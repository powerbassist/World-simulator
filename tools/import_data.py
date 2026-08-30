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
import zipfile
from math import floor, log10
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "sources"
NATIONS_DIR = ROOT / "data" / "nations"
GEO_OUT = ROOT / "data" / "geo" / "europe.geojson"
WORLD_OUT = ROOT / "data" / "geo" / "world.geojson"


def confined(path, root=ROOT):
    """Every path this importer writes is proven to resolve inside the repo
    before it is opened -- ids off the wire (Eurostat NUTS codes, GeoNames
    names) reach several of them, and a write target is not the place to
    discover one carries a traversal."""
    resolved = Path(path).resolve()
    base = Path(root).resolve()
    if resolved != base and base not in resolved.parents:
        raise RuntimeError("write path '%s' escapes '%s'" % (path, root))
    return resolved


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

# V1.1e. Rule of law, docs/tiers/v1.md section 5's statistic handed to section 1's
# judiciary bullet at V1.5's decomposition -- and the third row in a row whose "cannot
# be derived" premise turned out to be about the model rather than about the world.
# V1.5b found age structure published, V1.5c found the Gini published, and the World
# Bank publishes this one too: all ten nations, all ten years of the window every
# indicator above already uses, no gaps at all, so it needs neither
# load_wb_indicator_nearest_year() nor a provenance year of its own.
#
# TWO THINGS ABOUT THE CODE, BOTH FOUND BY FETCHING IT RATHER THAN BY ASSUMING IT.
# The Worldwide Governance Indicators were re-coded: the `RL.EST` every citation of
# this series still names returns *"The indicator was not found. It may have been
# deleted or archived."* The live code is `GOV_WGI_RL.SC`, and it lives on WGI's own
# database rather than on the default one -- so this is the FIRST indicator in this
# file whose download line carries `&source=3`, which is why it sits on its own line in
# docs/data-sources.md the way V1.6a's different WINDOW does.
#
# The SCORE (0-100) rather than the ESTIMATE (-2.5..+2.5), and that is a units decision
# rather than a preference: every stock this project reads on a nation is already on a
# 0-100 scale -- approval, service_quality, unrest_pct, gini_index -- so the estimate
# would be the one quantity in the game needing a conversion nobody could check.
INSTITUTIONS_INDICATOR = "GOV_WGI_RL.SC"

# V1.6a. The business cycle's per-nation amplitude, and the FIRST indicator in this
# file read over a different window from everything above it -- which is the honest
# cost of the block and is recorded rather than absorbed.
#
# V1.5b's ageing slope cost "one extra read of a series already on disk and no extra
# download". This one cannot: measuring how volatile a country's growth is needs
# several cycles, and 2015-2024 contains one. The download line in docs/data-sources.md
# fetches this code alone over date=1990:2024.
#
# THE EXCLUSION IS THE BLOCK'S ONE EDITORIAL ACT AND IT IS LOAD-BEARING. On the window
# the rest of the file already uses, France's real-growth standard deviation is 3.333
# -- and 0.579 with 2020 and 2021 removed, a factor of 5.8. Every nation collapses the
# same way. A session that had reused the existing window would have shipped a
# "business cycle" whose entire amplitude was one pandemic, and it would have looked
# measured. A pandemic is an exogenous disaster, which docs/tiers/v1.md section 8 owns;
# a business cycle is "booms and recessions that arrive whether or not the player
# deserves them", which is section 6's. 2008-09 is NOT excluded, because a financial
# crisis IS a business cycle.
#
# The result is measured and it does not cluster: 1.262 (France) to 2.704
# (Luxembourg), a 2.14x spread whose ordering holds across five different windows.
CYCLE_INDICATOR = "NY.GDP.MKTP.KD.ZG"
CYCLE_FROM_YEAR = 1990
CYCLE_EXCLUDE_YEARS = [2020, 2021]

# V1.6b. Inflation: the per-nation anchor, and the two roster-wide constants
# src/sim/inflation_constants.gd needs. Reuses V1.6a's WINDOW but is still its own
# DOWNLOAD -- load_wb_indicator_series() reads sources/wb/{code}.json, one file per
# indicator code, so V1.5b's "one extra read of a series already on disk" does not
# transfer and docs/data-sources.md gains a second date=1990:2024 line.
#
# THE EXCLUSION LIST IS EMPTY AND THAT IS AN EDITORIAL ACT, not an omission. V1.6a
# drops 2020-21 from the growth series because a pandemic is an exogenous OUTPUT
# shock in a series measuring output, which docs/tiers/v1.md section 8 owns. The
# 2022-23 energy spike is a PRICE shock in a series measuring prices -- it is the
# thing this indicator exists to record, and dropping it would leave an inflation
# model calibrated on the thirty years in which nothing happened. So `_excludes` is
# written into every nation file as [] rather than left out, for the reason
# `inequality._year` is written: a provenance record that hides its own editorial
# act is worse than none.
#
# Keeping it costs what it should. Spain's mean over 1990-2024 is 2.90 against 2.62
# with 2022-23 removed, and Germany's 2.09 against 1.83.
PRICES_INDICATOR = "FP.CPI.TOTL.ZG"
PRICES_FROM_YEAR = 1990
PRICES_EXCLUDE_YEARS = []

# V1.6b. The Phillips regression needs unemployment over the SAME window as prices,
# not over the 2015-2024 one everything else reads it at. The wide download is a
# strict superset -- verified row by row, 100 overlapping rows, zero differing values
# -- and every other caller reaches this series through load_wb_indicator_for_year(),
# which matches an exact year. So the download was widened rather than duplicated,
# and this constant records that the widening is deliberate.
PRICES_UNEMPLOYMENT_INDICATOR = "SL.UEM.TOTL.ZS"


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


def load_wb_indicator_series(code, lo, hi, exclude):
    """V1.6a. The whole series per nation over [lo, hi], with `exclude` years dropped.

    A third loader rather than a third use of one of the two above, and the reason is
    the same one that kept load_wb_indicator_nearest_year() separate: those two answer
    "what was the value at a year", which is what every block but this one needs. This
    answers "what did the series DO", and folding it in would give the other callers a
    silent way to read a window when they meant to read a year.
    """
    path = SOURCES / "wb" / f"{code}.json"
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    out = {}
    for row in (data[1] or []):
        if row["value"] is None:
            continue
        y = int(row["date"])
        if y < lo or y > hi or y in exclude:
            continue
        out.setdefault(row["countryiso3code"], {})[y] = row["value"]
    return out


def build_cycle_blocks(series):
    """V1.6a. Per-nation growth volatility, and each nation's ratio to the roster mean.

    THE ONLY BLOCK IN THIS FILE THAT NEEDS THE WHOLE ROSTER AT ONCE, which is why it is
    a function over all ten and returns a dict, where build_cohorts_block() and
    build_inequality_block() each take one nation. The denominator is the mean of the
    ten standard deviations, so `amplitude_rel` says "how volatile is this country
    compared with a European average" and src/sim/cycle_constants.gd's
    CYCLE_AMPLITUDE_PCT is then the amplitude OF that average.

    Anchored on the roster mean rather than on France, and that is
    docs/media-model.md's correction inherited rather than rediscovered: V1.5d
    anchored a deviation on the player's own nation and needed a constant near 250 for
    it. A mean anchor makes the swept constant mean the same thing for all ten.

    Population-weighting the mean was considered and dropped. It would put the anchor
    within a rounding error of Germany-plus-France and make Luxembourg's ratio a
    statement about Germany, where the unweighted mean makes it a statement about
    "a European economy" -- which is what the constant it scales claims to be.
    """
    sd = {}
    for nid in NATIONS:
        values = list(series.get(nid, {}).values())
        # Five is the fewest a standard deviation says anything about, and the roster
        # has 33 each. A window this short is a broken download, not a quiet country.
        if len(values) < 5:
            sys.exit(
                f"{nid}: only {len(values)} usable years of {CYCLE_INDICATOR} in "
                f"[{CYCLE_FROM_YEAR}, {YEAR}] excluding {CYCLE_EXCLUDE_YEARS} -- "
                f"a growth volatility cannot be measured from that"
            )
        mean = sum(values) / len(values)
        sd[nid] = (sum((v - mean) ** 2 for v in values) / len(values)) ** 0.5

    roster_mean = sum(sd.values()) / len(sd)
    if roster_mean <= 0.0:
        sys.exit("every nation's growth volatility is zero -- the series is empty")

    # V1.6a. src/sim/cycle_constants.gd's CYCLE_COMMON_SHARE, printed rather than
    # written into a nation file, because it is ONE number for the whole roster and a
    # per-nation copy of it would be one quantity written ten times.
    #
    # It is why that constant is measured rather than swept. Two different statistics
    # of the same series are printed and they agree: the variance share of the common
    # factor, and the mean pairwise correlation. Two methods agreeing is what makes
    # this a measurement instead of a plausible number -- V1.5c's two-harness rule,
    # applied to data rather than to a probe.
    years = sorted(set.intersection(*[set(series[nid]) for nid in NATIONS]))
    dev = {
        nid: [series[nid][y] - sum(series[nid][z] for z in years) / len(years) for y in years]
        for nid in NATIONS
    }
    common = [sum(dev[nid][i] for nid in NATIONS) / len(NATIONS) for i in range(len(years))]

    def pvar(xs):
        m = sum(xs) / len(xs)
        return sum((x - m) ** 2 for x in xs) / len(xs)

    var_share = pvar(common) / (sum(pvar(dev[nid]) for nid in NATIONS) / len(NATIONS))
    cors = []
    for i, a in enumerate(NATIONS):
        for b in NATIONS[i + 1:]:
            cov = sum(dev[a][k] * dev[b][k] for k in range(len(years))) / len(years)
            cors.append(cov / (pvar(dev[a]) * pvar(dev[b])) ** 0.5)
    print(
        f"cycle: common variance share {var_share:.4f} over {len(years)} years "
        f"(mean pairwise correlation {sum(cors) / len(cors):.4f}) "
        f"-- src/sim/cycle_constants.gd CYCLE_COMMON_SHARE"
    )

    return {
        nid: {
            "amplitude_rel": round(sd[nid] / roster_mean, 3),
            "growth_sd_pct": round(sd[nid], 3),
            "_from_year": CYCLE_FROM_YEAR,
            "_to_year": YEAR,
            "_excludes": list(CYCLE_EXCLUDE_YEARS),
        }
        for nid in NATIONS
    }


def _ols(xs, ys):
    """Slope and Pearson r of a simple regression. Returns (slope, r, n)."""
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    sxy = sum((a - mx) * (b - my) for a, b in zip(xs, ys))
    sxx = sum((a - mx) ** 2 for a in xs)
    syy = sum((b - my) ** 2 for b in ys)
    if sxx <= 0.0 or syy <= 0.0:
        sys.exit("prices: a regression input has zero variance -- the series is flat")
    return sxy / sxx, sxy / (sxx * syy) ** 0.5, n


def build_prices_blocks(series, unemployment):
    """V1.6b. The per-nation inflation anchor, and the two constants measured off it.

    The second block in this file that needs the whole roster at once, and for a
    different reason from build_cycle_blocks(): that one needs the roster to form a
    RATIO, this one needs it to pool a REGRESSION. The anchor itself is per nation and
    could have been built one at a time; the two printed constants could not.

    WHAT IS MEASURED HERE IS NOT WHAT docs/tiers/v1.md section 6 ASKED FOR, and the
    refutation is the session's finding rather than an inconvenience. The ROADMAP row
    specifies "a price pressure from the gap, the impulse and (a)'s shock". Regressed
    against an output gap built the way src/sim/economy.gd builds one -- the running
    sum of (growth - own-mean growth), per nation, demeaned -- the output gap carries
    NO SIGNAL and its sign FLIPS between sub-samples: +0.204 pre-euro, +0.098 in the
    euro era, -0.140 pooled. The UNEMPLOYMENT gap carries a stable, correctly-signed
    Phillips relation in both disjoint halves. So the model reads unemployment, which
    is docs/economy-model.md's own treatment of Okun -- the honest textbook
    relationship rather than a bespoke one -- and it dissolves the row's other defect
    for free, because the gap and the impulses that fill it were one quantity written
    three times.

    Both sub-sample slopes are printed, not just the pooled one. Two disjoint windows
    agreeing on sign is V1.6a's cross-check discipline, and the pooled figure is
    attenuated by pooling two regimes with different means -- so it is the WEAKEST of
    the three and would be the wrong one to ship.
    """
    anchors = {}
    for nid in NATIONS:
        values = list(series.get(nid, {}).values())
        if len(values) < 5:
            sys.exit(
                f"{nid}: only {len(values)} usable years of {PRICES_INDICATOR} in "
                f"[{PRICES_FROM_YEAR}, {YEAR}] -- an anchor cannot be measured "
                f"from that"
            )
        anchors[nid] = sum(values) / len(values)

    # Persistence, as an AR(1) on each nation's own deviation from its own anchor.
    # Demeaned per nation so the pooled fit measures how sticky inflation IS, not how
    # different the ten countries are from each other.
    lag_x, lag_y = [], []
    for nid in NATIONS:
        years = sorted(series[nid])
        for i, y in enumerate(years):
            dev = series[nid][y] - anchors[nid]
            if i > 0 and years[i - 1] == y - 1:
                lag_x.append(series[nid][years[i - 1]] - anchors[nid])
                lag_y.append(dev)

    rho, rho_r, rho_n = _ols(lag_x, lag_y)

    # The Phillips slope, on three windows. `u_mean` is the nation's own average
    # unemployment over the same window -- a stand-in for the structural rate, which
    # is exactly what src/sim/economy.gd's `structural_unemployment_pct` is.
    def slope(lo, hi):
        xs, ys = [], []
        for nid in NATIONS:
            years = [
                y for y in sorted(series[nid])
                if lo <= y <= hi and y in unemployment.get(nid, {})
            ]
            if len(years) < 5:
                continue
            us = [unemployment[nid][y] for y in years]
            ps = [series[nid][y] for y in years]
            um = sum(us) / len(us)
            pm = sum(ps) / len(ps)
            for i in range(len(years)):
                xs.append(us[i] - um)
                ys.append(ps[i] - pm)
        return _ols(xs, ys)

    pre = slope(PRICES_FROM_YEAR, 1998)
    euro = slope(1999, YEAR)
    pooled = slope(PRICES_FROM_YEAR, YEAR)

    print(
        f"prices: persistence rho {rho:.4f} (r {rho_r:.3f}, n {rho_n}) "
        f"-- src/sim/inflation_constants.gd INFLATION_PERSISTENCE"
    )
    # Sign flip is deliberate. The regression is pi on (u - u_mean) and so comes back
    # negative; the model writes target = anchor + BETA * (structural - u), so BETA is
    # the same slope with the argument the other way round and is POSITIVE.
    print(
        f"prices: Phillips slope on the unemployment gap -- "
        f"pre-euro {-pre[0]:.4f} (r {pre[1]:.3f}, n {pre[2]}), "
        f"euro era {-euro[0]:.4f} (r {euro[1]:.3f}, n {euro[2]}), "
        f"pooled {-pooled[0]:.4f} (r {pooled[1]:.3f}, n {pooled[2]}) "
        f"-- src/sim/inflation_constants.gd INFLATION_UNEMP_BETA"
    )

    return {
        nid: {
            "inflation_pct": round(anchors[nid], 3),
            "_from_year": PRICES_FROM_YEAR,
            "_to_year": YEAR,
            "_excludes": list(PRICES_EXCLUDE_YEARS),
        }
        for nid in NATIONS
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

    # V1.1e. Complete at `year` for all ten, so the exact-year loader every complete
    # series uses -- a missing value here is a broken download and should stop the
    # import, which is load_wb_indicator_nearest_year()'s own docstring reason for not
    # being the default.
    institutions = load_wb_indicator_for_year(INSTITUTIONS_INDICATOR, year)

    # V1.6a. Computed once for all ten before the loop, because `amplitude_rel` is a
    # ratio against the roster mean and so cannot be built one nation at a time --
    # the only block here with that shape. See build_cycle_blocks().
    cycle_blocks = build_cycle_blocks(
        load_wb_indicator_series(
            CYCLE_INDICATOR, CYCLE_FROM_YEAR, year, CYCLE_EXCLUDE_YEARS
        )
    )

    # V1.6b. Same shape and the same reason as the line above, one session on. See
    # build_prices_blocks() for why the regression it prints reads unemployment
    # rather than the output gap docs/tiers/v1.md section 6 names.
    prices_blocks = build_prices_blocks(
        load_wb_indicator_series(
            PRICES_INDICATOR, PRICES_FROM_YEAR, year, PRICES_EXCLUDE_YEARS
        ),
        load_wb_indicator_series(
            PRICES_UNEMPLOYMENT_INDICATOR, PRICES_FROM_YEAR, year, []
        ),
    )

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

        if institutions.get(nid) is None:
            sys.exit(
                f"{nid}: missing {year} data for {INSTITUTIONS_INDICATOR} -- rule of "
                f"law is complete for all ten on this window, so an absent value is a "
                f"broken download rather than a gap to fall back from"
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
            "cycle": cycle_blocks[nid],
            "prices": prices_blocks[nid],
            # V1.1e. One decimal, `unemployment_pct`'s and `gini_index`'s treatment.
            # No provenance keys and no slope: the series is read at the block's own
            # `_year` on the block's own window, so `_year` above already describes it.
            # The measured slope EXISTS -- nine of the ten fall over 2015-2024 and only
            # Italy rises -- and it is deliberately not imported, because a court that
            # weakens every year on its own is the permanent monotone charge
            # docs/defence-model.md names, and V1.5c's Gini drift is a stopgap standing
            # in for levers that do not exist where this one has a lever from day one.
            # See docs/judiciary-model.md.
            "institutions": {
                "rule_of_law_score": round(institutions[nid], 1),
            },
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
    confined(path).write_text(compact_scalar_arrays(text) + "\n", encoding="utf-8", newline="\n")


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



# ---------------------------------------------------------------------------
# V2.2a. The geographic register: regions from Eurostat + GISCO, cities from
# GeoNames. See docs/geography-model.md.
# ---------------------------------------------------------------------------

REGIONS_DIR = ROOT / "data" / "regions"
REGION_GEO_OUT = ROOT / "data" / "geo" / "regions.geojson"

# THE LEVEL IS PER NATION, AND THAT IS A MEASUREMENT RATHER THAN A TASTE.
# docs/tiers/v2.md section 2 says "Content from Eurostat NUTS 2", and for the nation
# this game is about NUTS 2 is the PRE-2016 regions: Eurostat's own labels return
# `FRC1 Bourgogne`, `FRE1 Nord-Pas de Calais`, `FRE2 Picardie`, units abolished in
# 2016. A French player reading "Picardie" in a game set in 2026 reads a bug, and
# docs/fictionalization.md names *Occitanie* as its example of a real region -- which
# is NUTS 1 (`FRJ`). Germany is the same shape: NUTS 1 is the 16 Laender, NUTS 2 the
# Regierungsbezirke. And the inverse holds elsewhere, which is why one level cannot
# serve the roster: Italy's NUTS 1 is 5 statistical macro-areas and Switzerland's is
# ONE, so neither could use it.
#
# The level never reaches src/. data/regions/ holds regions and the loader does not
# learn that a level exists; this table plus each file's `_source` line is the whole
# of it, on `imported._year`'s provenance idiom.
#
# CHE could be NUTS 3 -- the 26 cantons are the politically real unit where the 7
# grandes regions are statistical. Not taken: 26 units for 8.7 M people is finer than
# every other nation on the roster, and a register whose grain varies by an order of
# magnitude is one V2.5 has to special-case. Recorded rather than left silent.
REGION_LEVEL = {
    "FRA": 1,  # 13 regions
    "DEU": 1,  # 16 Laender
    "GBR": 1,  # 9 English regions + Wales, Scotland, Northern Ireland
    "BEL": 1,  # Flanders, Wallonia, Brussels -- Belgium's actual political division
    "ITA": 2,  # 20 regioni, Trentino split into its two autonomous provinces
    "ESP": 2,  # 17 comunidades + Ceuta + Melilla
    "NLD": 2,  # 12 provinces
    "AUT": 2,  # 9 Bundeslaender
    "CHE": 2,  # 7 grandes regions
    "LUX": 2,  # one region at every level
}

REGION_NUTS_VINTAGE = 2021
REGION_YEAR = 2022

# ISO3 -> the two-letter code Eurostat and GISCO use. `UK` rather than `GB`, which is
# the one place the two disagree with GeoNames -- see CITY_COUNTRY below.
NUTS_COUNTRY = {
    "FRA": "FR", "DEU": "DE", "ITA": "IT", "ESP": "ES", "BEL": "BE",
    "NLD": "NL", "LUX": "LU", "CHE": "CH", "GBR": "UK", "AUT": "AT",
}

# GeoNames uses the ISO 3166 code, so Britain is `GB` where NUTS says `UK`.
CITY_COUNTRY = dict(NUTS_COUNTRY, GBR="GB")

# Years fetched for demo_r_pjangrp3, newest first. Britain is the reason there is more
# than one: Eurostat dropped UK regions after withdrawal, so the 2022 response carries
# 41 UK NUTS 2 codes and 12 NUTS 1 codes with NO values, while 2019 carries all of them
# and they sum to the UK national figure exactly. That is V1.5c's nearest-year fallback
# on a second series, and it is scoped the same way -- per nation, with the year it
# used written into the file, because a provenance record that names a year the number
# does not come from is worse than none.
#
# WHAT IS *NOT* RESCUED THIS WAY IS THE HALF docs/tiers/v2.md GOT WRONG.
# `nama_10r_2gdp` -- regional GDP -- carries ZERO geo codes beginning `UK` at EVERY
# year, 2018 included, because the codes were removed from the dimension rather than
# left empty. So the fallback genuinely has nothing to fall back to there. Regional
# population is measured for all ten; only regional GDP is short, and regional GDP is
# what docs/tiers/v2.md section 5 makes load-bearing. It is not imported here.
REGION_YEARS = [2022, 2019]

# THE POPULATION CUT, and the one measured constant this session ships.
#
# Named cities are a partition of their region the way a firm is of its sector, so the
# question the sweep answers is how much of a nation the named half covers. Two clauses
# were fixed before it ran:
#   (ii) the roster's MEAN named share of national population is at least 0.30, so the
#        register describes the country rather than a rounding error in it;
#   (iii) at most 600 named cities across the ten, written from the drawing side --
#        V2.2b draws by rank and the whole roster at the opening fit is about 1000 px
#        wide, so a bigger register ships content the map can never separate.
# Swept 15 000 to 200 000 and refined to 1 000, the two cross at [69 000, 73 000]:
# 69 000 is the first row at or under 600 cities (596) and 73 000 the last at or over
# 0.30 mean coverage (0.3006). BOTH EDGES ARE SMOOTH CROSSINGS rather than plateaux, so
# neither selects and the interior governs (V1.5d's rule): the midpoint, 71 000. It is
# the same answer at a grid of 2 000 and at one of 1 000, which is V1.5b's refinement
# diagnostic -- a value that moves when the grid does is the grid's answer, not the
# model's -- and it is interior to the swept range rather than sitting on its edge.
# The register is identical for any cut in 70 915..71 010, the gap between the two
# adjacent city populations that bracket it.
#
# MEASURED THREE TIMES, AND THE FIRST ANSWER WAS WRONG BY 29 %. The first sweep landed
# on a feasible [82 000, 101 000] and a midpoint of 91 500, and it was measuring
# GeoNames rather than Europe: 607 city DISTRICTS counted as cities, a London naming
# twenty of its own boroughs, and thirty-six Paris and Marseille arrondissements. All
# three corrections came from READING THE GENERATED FILE, not from a check -- which is
# why what each of them fixed is now an assertion in tests/test_geography.gd rather
# than a paragraph here.
#
# A THIRD CLAUSE WAS WRITTEN AND DELETED, and the reason is structural rather than a
# retune. "The WORST nation names at least 0.20 of its population" fails at every
# candidate on the grid and its two failing nations do not move with the threshold at
# all: Luxembourg has ONE city and it is 11.9 % of the country, and Swiss communes are
# administratively small (Zuerich is 341 k of 8.7 M), so both are held at the floor by
# the top-up rule below rather than by this constant. A band an observable cannot reach
# is a bound and not a selector -- V1.5a's finding, and V1.5c's -- so it is recorded
# here instead of being met by shipping 4 691 cities.
CITY_MIN_POP = 71000

# ...PLUS EACH REGION'S LARGEST, whatever it is. docs/tiers/v2.md section 2 says a
# region is "a main city plus the sum of the smaller cities under it", and a region
# with no city is not that object. It costs nothing today -- every one of the 112
# regions has a GeoNames place above 15 000 -- but it is what stops a future level
# change or a higher cut producing a region the register cannot name.
CITY_TOPUP_LARGEST = True

# How far outside its region a city may sit and still be assigned to it. The GISCO
# 10M coastline cuts coastal communes -- Birkenhead, Portsmouth, A Coruna, Santander,
# Cadiz, Antibes, Marsala all fall in the sea at this resolution -- so a strict
# point-in-polygon drops 85 real cities. Anything beyond this is an error rather than a
# silent drop, and at the shipped value nothing is: 4 606 land inside, 85 snap, 41 are
# genuinely overseas, 0 fail.
CITY_SNAP_DEG = 0.25

# GeoNames feature codes that are NOT a city, and leaving them in is the bug this
# session found by reading its own output rather than by a check.
#
# `PPLX` is "section of populated place" -- 607 rows across the ten, 76 of them above
# the cut -- and every one DOUBLE-COUNTS the city it is part of: Hamburg-Nord,
# Hamburg-Mitte, Altona and Wandsbek are Hamburg; Carabanchel, Latina and Fuencarral
# are Madrid; Eixample and Nou Barris are Barcelona; Favoriten and Donaustadt are
# Vienna; `Paris 13e Arrondissement` is Paris. Left in, a region's named city shares
# do not partition it -- Madrid's districts plus Madrid is roughly twice Madrid -- and
# the residual goes NEGATIVE, which is why tests/test_geography.gd asserts a
# non-negative residual rather than only a sum.
#
# `PPLQ` is an abandoned place, which is not a population at all.
CITY_EXCLUDED_FEATURE_CODES = {"PPLX", "PPLQ"}


def load_eurostat_region_population():
    """{year: {geo code: population}} over REGION_YEARS, newest first.

    JSON-stat keeps the values in a flat dict keyed by the geo dimension's own INDEX,
    so the index has to be inverted before anything can be read by code.
    """
    out = {}
    for year in REGION_YEARS:
        path = SOURCES / "eurostat" / f"demo_r_pjangrp3_{year}.json"
        if not path.exists():
            sys.exit(f"missing {path.relative_to(ROOT)} -- see docs/data-sources.md")
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        index = data["dimension"]["geo"]["category"]["index"]
        inverse = {v: k for k, v in index.items()}
        out[year] = {inverse[int(k)]: v for k, v in data["value"].items()}
    return out


def load_gisco_nuts():
    """{level: {NUTS code: feature}} for the two levels REGION_LEVEL uses."""
    out = {}
    for level in sorted(set(REGION_LEVEL.values())):
        name = f"NUTS_RG_10M_{REGION_NUTS_VINTAGE}_4326_LEVL_{level}.geojson"
        path = SOURCES / "gisco" / name
        if not path.exists():
            sys.exit(f"missing {path.relative_to(ROOT)} -- see docs/data-sources.md")
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        out[level] = {f["properties"]["NUTS_ID"]: f for f in data["features"]}
    return out


def _polygons_of(feature):
    geom = feature["geometry"]
    if geom["type"] == "MultiPolygon":
        return geom["coordinates"]
    return [geom["coordinates"]]


def _point_in_ring(lon, lat, ring):
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _point_in_polygon(lon, lat, polygon):
    """Outer ring minus its holes. Enclaves matter here in a way they do not for the
    national outlines: Berlin is a hole in Brandenburg and Vienna one in
    Niederoesterreich, so ignoring holes would file every Brandenburg city under
    Berlin and both partitions would still sum to 1.0."""
    if not _point_in_ring(lon, lat, polygon[0]):
        return False
    return not any(_point_in_ring(lon, lat, hole) for hole in polygon[1:])


def _distance_to_polygons(lon, lat, polygons):
    return min(
        ((px - lon) ** 2 + (py - lat) ** 2) ** 0.5
        for polygon in polygons
        for ring in polygon
        for px, py in ring
    )


def build_region_index(populations, nuts):
    """Per nation: the regions that survive, the ones dropped, and the year used.

    THE GEOMETRY IS THE AUTHORITY ON THE ROSTER, and that single rule resolves three
    separate problems rather than one. A region with no polygon cannot be drawn, and
    this tier exists to locate things, so:

    * `<CC>ZZ` -- Extra-Regio NUTS 2, the output that belongs to no region: offshore,
      embassies, ships -- carries a figure and has no geometry, so it falls into the
      residual with no filter of its own.
    * The Eurostat response holds TWO NUTS VINTAGES AT ONCE. `NL35` and `NL36` are the
      2024 codes for Utrecht and Zuid-Holland and `NL31`/`NL33` the 2021 ones; the
      values are equal to the person, so summing all fourteen Dutch codes overstates
      the Netherlands by 5.1 M. Filtering to the codes the 2021 geometry knows leaves
      exactly twelve and the sum is the national figure to the digit.
    * `FRY` and `ES70` are the overseas regions, and the bounding-box filter that has
      dropped them from the map since S8 drops them here for free.
    """
    out = {}
    for nid in NATIONS:
        cc = NUTS_COUNTRY[nid]
        level = REGION_LEVEL[nid]

        year = None
        for candidate in REGION_YEARS:
            if any(code.startswith(cc) and len(code) == level + 2
                   for code in populations[candidate]):
                year = candidate
                break
        if year is None:
            sys.exit(f"{nid}: no regional population in any of {REGION_YEARS}")
        values = populations[year]

        national = values.get(cc)
        if not national:
            sys.exit(f"{nid}: no national population at {year}")

        kept, dropped = [], []
        for code in sorted(c for c in nuts[level] if c.startswith(cc)):
            if code not in values:
                continue
            feature = nuts[level][code]
            polygons = _polygons_of(feature)
            onshore = [p for p in polygons if not bbox_outside(p[0])]
            props = feature["properties"]
            record = {
                "id": code,
                "name": props.get("NAME_LATN") or props.get("NUTS_NAME"),
                "population": values[code],
                "polygons": onshore,
                "all_polygons": polygons,
            }
            (kept if onshore else dropped).append(record)

        if not kept:
            sys.exit(f"{nid}: every region was dropped by the bounding-box filter")

        out[nid] = {"year": year, "level": level, "national": national,
                    "kept": kept, "dropped": dropped}
    return out


def assign_cities(index):
    """GeoNames places, filed under the region whose polygon contains them.

    THE JOIN CANNOT GO THROUGH GEONAMES' OWN `admin1`, and that is why the geometry is
    downloaded rather than only a code table: for France `admin1` is the 13 modern
    regions, which is NUTS 1 and therefore COARSER than the NUTS 2 the row asked for.
    A code join would be silently wrong for at least one nation and unverifiable for
    the rest. A point in a polygon is exact, uniform across the ten, needs no lookup
    table, and checks the geometry against the register while it works.

    Three outcomes and each says something true: inside, snapped (a coastal commune the
    10M coastline cuts), or overseas -- a place inside a region the bounding box
    dropped, which belongs in the residual. Anything else stops the import.
    """
    path = SOURCES / "geonames" / "cities15000.zip"
    if not path.exists():
        sys.exit(f"missing {path.relative_to(ROOT)} -- see docs/data-sources.md")
    with zipfile.ZipFile(path) as archive:
        raw = archive.read("cities15000.txt").decode("utf-8")

    by_country = {}
    for line in raw.splitlines():
        fields = line.split("\t")
        if len(fields) < 15:
            continue
        if fields[7] in CITY_EXCLUDED_FEATURE_CODES:
            continue
        by_country.setdefault(fields[8], []).append({
            "name": fields[1],
            "ascii": fields[2],
            "lat": float(fields[4]),
            "lon": float(fields[5]),
            "population": int(fields[14]),
        })

    counts = {"inside": 0, "snapped": 0, "overseas": 0, "subdivisions": 0}
    for nid in NATIONS:
        entry = index[nid]
        boxes = []
        for region in entry["kept"]:
            lons = [p[0] for poly in region["polygons"] for p in poly[0]]
            lats = [p[1] for poly in region["polygons"] for p in poly[0]]
            region["cities"] = []
            boxes.append((region, min(lons), min(lats), max(lons), max(lats)))

        for city in by_country.get(CITY_COUNTRY[nid], []):
            lon, lat = city["lon"], city["lat"]
            home = None
            for region, x0, y0, x1, y1 in boxes:
                if not (x0 <= lon <= x1 and y0 <= lat <= y1):
                    continue
                if any(_point_in_polygon(lon, lat, p) for p in region["polygons"]):
                    home = region
                    break
            if home is not None:
                counts["inside"] += 1
                home["cities"].append(city)
                continue

            if any(any(_point_in_polygon(lon, lat, p) for p in region["all_polygons"])
                   for region in entry["dropped"]):
                counts["overseas"] += 1
                continue

            nearest = min(entry["kept"],
                          key=lambda r: _distance_to_polygons(lon, lat, r["polygons"]))
            near_kept = _distance_to_polygons(lon, lat, nearest["polygons"])
            near_dropped = min(
                (_distance_to_polygons(lon, lat, r["all_polygons"])
                 for r in entry["dropped"]),
                default=float("inf"))
            # An island off a region the bbox dropped is overseas even when it falls
            # outside that region's own coarse polygon -- La Palma and Lanzarote are
            # ten degrees from mainland Spain and would otherwise snap to Andalucia.
            if near_dropped < near_kept:
                counts["overseas"] += 1
            elif near_kept <= CITY_SNAP_DEG:
                counts["snapped"] += 1
                nearest["cities"].append(city)
            else:
                sys.exit("%s: '%s' at %.4f,%.4f is %.2f deg from any region"
                         % (nid, city["name"], lon, lat, near_kept))

        counts["subdivisions"] += drop_numbered_subdivisions(entry["kept"])
    return counts


NUMBERED_SUBDIVISION = re.compile(r"^(.+?) \d")


def drop_numbered_subdivisions(regions):
    """`Paris 15 Vaugirard` is not a city and CITY_EXCLUDED_FEATURE_CODES cannot see
    it, because GeoNames codes some Paris arrondissements `PPLX` and others plain
    `PPL` -- `Paris 13e Arrondissement` is one, `Paris 15 Vaugirard` at 229 713 is the
    other. Twenty Paris arrondissements and sixteen Marseille ones come through the
    feature filter, and select_cities()' fit rule does not stop them either, because
    Ile-de-France is large enough to hold Paris and its own districts.

    The discriminator is a NUMBER, and that is what makes this a rule rather than a
    list. A plain name-prefix test also eats `Mansfield Woodhouse`, `Newport Pagnell`,
    `Amersham on the Hill`, `Ischia Porto` and `Kronberg Tal`, which are five real
    places; requiring a digit immediately after the parent's name catches all
    thirty-six subdivisions and none of the five. Scoped to a parent in the SAME
    region and larger than the child, so a genuine `Frankfurt 1` somewhere else could
    not remove a city it has nothing to do with.
    """
    dropped = 0
    for region in regions:
        names = {c["ascii"]: c["population"] for c in region["cities"]}
        keep = []
        for city in region["cities"]:
            match = NUMBERED_SUBDIVISION.match(city["ascii"])
            parent = match.group(1) if match else None
            if parent and names.get(parent, 0) > city["population"]:
                dropped += 1
                continue
            keep.append(city)
        region["cities"] = keep
    return dropped


def floor_share(value, places=6):
    """Round a share DOWN, so the residual absorbs the rounding rather than losing to
    it. Rounding to nearest put Germany's sixteen Laender at 1.000003 of Germany and
    the Netherlands' twelve provinces at 1.000001 -- a residual of minus three parts in
    a million, which is arithmetically nothing and is still a partition that does not
    hold. Flooring guarantees the sum is at or under the true sum and therefore at or
    under 1.0, at a cost bounded by 112 x 1e-6 across the whole roster."""
    scale = 10 ** places
    return int(value * scale) / scale


def _city_slug(city):
    ascii_name = city["ascii"] or city["name"]
    slug = re.sub(r"[^a-z0-9]+", "_", ascii_name.lower()).strip("_")
    return slug or "city"


def select_cities(region):
    """The named half of a region, in descending order, taken only while it FITS.

    A city's share is of its region, so the named cities cannot add up to more than
    the region -- and the raw data says they do, for two unrelated reasons the same
    rule settles:

    * GEONAMES MIXES ADMINISTRATIVE LEVELS, and the feature-code filter above does not
      catch it because these are not `PPLX`. `UKI London` carries London at 8.96 M and
      then Islington, Westminster, Bexley, Croydon and fifteen more BOROUGHS OF IT,
      summing to 1.325 of the region; Brussels carries Anderlecht, Schaerbeek,
      Molenbeek, Ixelles and Uccle, which are communes of the same region, summing to
      1.285. Taken in descending order the agglomeration is named first and its own
      parts no longer fit, which is the right answer and needs no list of exceptions.
    * THE TWO SOURCES DISAGREE ABOUT CITY-STATES. Eurostat puts Hamburg at 1.854 M and
      GeoNames at 1.974 M, a 6 % difference of definition and vintage; Ceuta and
      Melilla are the same case at 1.5 % and 0.1 %. Here the largest city IS the
      region, so it is admitted at a share of exactly 1.0 and the residual is zero,
      which is true of a city-state and false of nobody.

    Stopping at the first city that does not fit rather than skipping it: the list is
    descending, so skipping would admit Uccle while refusing Schaerbeek, and a rule
    whose output depends on which of two arbitrary neighbours is larger is not a rule.
    """
    ordered = sorted(region["cities"], key=lambda c: (-c["population"], c["ascii"]))
    above = [c for c in ordered if c["population"] >= CITY_MIN_POP]
    if not above and CITY_TOPUP_LARGEST and ordered:
        above = ordered[:1]

    named, room = [], region["population"]
    for city in above:
        if city["population"] <= room:
            named.append((city, city["population"] / region["population"]))
            room -= city["population"]
        elif not named:
            named.append((city, 1.0))
            room = 0
            break
        else:
            break
    return named


def build_regions():
    """{nation id: the file to write}, plus the index and the join's own counts."""
    populations = load_eurostat_region_population()
    nuts = load_gisco_nuts()
    index = build_region_index(populations, nuts)
    counts = assign_cities(index)

    files = {}
    for nid in NATIONS:
        entry = index[nid]
        national = entry["national"]
        regions = []
        for region in entry["kept"]:
            cities = []
            used = set()
            for city, share in select_cities(region):
                slug = _city_slug(city)
                if slug in used:
                    n = 2
                    while f"{slug}_{n}" in used:
                        n += 1
                    slug = f"{slug}_{n}"
                used.add(slug)
                cities.append({
                    "id": f"{region['id']}_{slug}",
                    "name": city["name"],
                    "share": floor_share(share),
                    "lonlat": [round(city["lon"], 4), round(city["lat"], 4)],
                })
            regions.append({
                "id": region["id"],
                "name": region["name"],
                "share": floor_share(region["population"] / national),
                "cities": cities,
            })

        files[nid] = {
            "_source": ("Eurostat demo_r_pjangrp3 NUTS %d (%d); "
                        "GISCO NUTS_RG_10M_%d; GeoNames cities15000"
                        % (entry["level"], entry["year"], REGION_NUTS_VINTAGE)),
            "_year": entry["year"],
            "_note": ("Generated by tools/import_data.py -- every field here is "
                      "dataset-derived and a re-import overwrites the file whole. "
                      "`share` is of the NATION for a region and of its own REGION "
                      "for a city; both sums are below 1.0 and the remainder is the "
                      "unnamed residual -- extra-regio and overseas at the national "
                      "level, rural and small towns at the regional one. See "
                      "docs/geography-model.md."),
            "regions": regions,
        }
    return files, index, counts


def build_region_geo(index):
    """One feature per region that survived, at the roster's own 4-decimal precision.

    Not merged into europe.geojson: that file is one feature per NATION and map_view.gd
    hit-tests it, so a second kind of feature in it would make `_nation_at_lonlat()`
    answer for two things -- which is exactly the property U6c refused to give up for
    project markers.
    """
    features = []
    for nid in NATIONS:
        for region in index[nid]["kept"]:
            kept = [[clean_ring(ring) for ring in polygon]
                    for polygon in region["polygons"]]
            features.append({
                "type": "Feature",
                "properties": {"id": region["id"], "nation": nid, "name": region["name"]},
                "geometry": {"type": "MultiPolygon", "coordinates": kept},
            })
    features.sort(key=lambda f: f["properties"]["id"])
    return {"type": "FeatureCollection", "features": features}


def write_region_file(nid, payload):
    REGIONS_DIR.mkdir(parents=True, exist_ok=True)
    path = REGIONS_DIR / f"{nid}.json"
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    confined(path).write_text(compact_scalar_arrays(text) + "\n", encoding="utf-8", newline="\n")

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

    # V2.2a. The region geometry is written from the SAME index the register is
    # built from, rather than re-read, so the two cannot describe different rosters.
    region_files, region_index, join = build_regions()
    for nid in NATIONS:
        write_region_file(nid, region_files[nid])
    region_geo = build_region_geo(region_index)
    write_geojson(REGION_GEO_OUT, region_geo, indent=None)

    print(f"Imported {len(NATIONS)} nations for {args.year}.")
    print(f"Wrote {GEO_OUT.relative_to(ROOT)}")
    print(f"Wrote {WORLD_OUT.relative_to(ROOT)} ({len(world['features'])} features)")
    regions = sum(len(f["regions"]) for f in region_files.values())
    cities = sum(len(r["cities"]) for f in region_files.values() for r in f["regions"])
    print(f"Wrote data/regions/ ({regions} regions, {cities} cities)")
    print(f"Wrote {REGION_GEO_OUT.relative_to(ROOT)} ({len(region_geo['features'])} features)")
    print("  city join: %d inside, %d snapped, %d overseas, %d numbered subdivisions dropped"
          % (join["inside"], join["snapped"], join["overseas"], join["subdivisions"]))


def write_geojson(path, collection, indent):
    separators = None if indent else (",", ":")
    text = json.dumps(collection, ensure_ascii=False, indent=indent, separators=separators)
    confined(path).write_text(text + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
