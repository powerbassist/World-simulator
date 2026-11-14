#!/usr/bin/env python3
"""The tax library's checks (docs/design/finance-bill.md section 9), stdlib only.

  python tools/tax_library_check.py               # report; exit 1 on a structural refusal
  python tools/tax_library_check.py --band 0.30   # also fail a nation whose modelled yield is
                                                  # more than 30 % off its real one

Reads data/taxes/*.json (one file per kind) and the four playable nations' rows in
data/nations/: fiscal.tax_rates_pct (the kinds in force) and fiscal.tax_base_share (a
nation's override of a kind's base_share). src/core/loaders/taxes_loader.gd is the loader
these checks restate; this script adds the yield report the loader does not make.

STRUCTURE (exit 1), the loader's refusals restated: an id outside [a-z0-9_]{2,24}, a
duplicate id, an id that is a computed revenue line, a who_pays bloc with no bloc_salience
weight, a salience weight outside (0, 1], a rate_range_pct with no room, a nation rate outside
its kind's range, a kind a nation lists that the library lacks, and a nation whose kinds in
force explain more revenue than its tax_revenue_pct_gdp (9.3's negative residual).

YIELD (report; --band makes it a gate): for every kind a nation has in force with a real yield
in its reference, the effective base_share x rate against the real yield in % of GDP. The
effective base_share is the nation's override for that kind where it has one (the parent's
ruling, 2026-11-14: a nation may override a kind's base_share for a kind in force), else the
library's; the `src` column says which. The ratio is the
finding: one base_share per kind has to serve every nation, and where the ratios spread the
kind needs a per-nation base or a different rate unit (Systems' call, finance-bill.md 9.1).
Nothing here models erosion: at the start rate the erosion term is 1, which is the state the
check describes.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TAXES = ROOT / "data" / "taxes"
NATIONS = ROOT / "data" / "nations"
PLAYABLE = ["FRA", "DEU", "GBR", "POL"]
ID_RE = re.compile(r"^[a-z0-9_]{2,24}$")
# Budget.COMPUTED_REVENUE_LINES: revenue lines that are not tax kinds.
COMPUTED = {"other", "tariffs", "dividends"}
# The five keep today's order first (finance-bill.md 9.1, "order is data too").
FIVE = ["income", "corporate", "vat", "capital_gains", "wealth"]
BLOCS = {"workers", "pensioners", "urban", "rural", "business", "students"}


def load_library(fails):
    kinds = {}
    for path in sorted(TAXES.glob("*.json")):
        k = json.loads(path.read_text(encoding="utf-8"))
        kid = k.get("id", "")
        if kid != path.stem:
            fails.append("%s: id '%s' differs from the file name" % (path.name, kid))
        if not ID_RE.match(kid):
            fails.append("%s: id '%s' is outside [a-z0-9_]{2,24}" % (path.name, kid))
        if kid in COMPUTED:
            fails.append("%s: id '%s' is a computed revenue line" % (path.name, kid))
        if kid in kinds:
            fails.append("%s: duplicate id '%s'" % (path.name, kid))
        sal = k.get("bloc_salience", {})
        for bloc in k.get("who_pays", []):
            if bloc not in BLOCS:
                fails.append("%s: who_pays names an unknown bloc '%s'" % (kid, bloc))
            if bloc not in sal:
                fails.append("%s: who_pays bloc '%s' has no bloc_salience weight" % (kid, bloc))
        for bloc, w in sal.items():
            if bloc not in BLOCS or not (0.0 < float(w) <= 1.0):
                fails.append("%s: salience %s=%s is not a bloc weight in (0, 1]" % (kid, bloc, w))
        lo, hi = k.get("rate_range_pct", [0.0, 0.0])
        if not hi > lo:
            fails.append("%s: rate_range_pct %s has no room" % (kid, k.get("rate_range_pct")))
        if not float(k.get("base_share", 0.0)) > 0.0:
            fails.append("%s: base_share must be above 0" % kid)
        kinds[kid] = k
    order = FIVE + sorted(k for k in kinds if k not in FIVE)
    return kinds, order


def load_nations(fails):
    out = {}
    for n in PLAYABLE:
        d = json.loads((NATIONS / ("%s.json" % n)).read_text(encoding="utf-8"))
        rates = d["fiscal"]["tax_rates_pct"]
        out[n] = {"rates": rates, "gdp": float(d["imported"]["gdp_eur_bn"]),
                  "revenue": float(d["fiscal"]["tax_revenue_pct_gdp"]),
                  "overrides": d["fiscal"].get("tax_base_share", {})}
        for kid, share in out[n]["overrides"].items():
            if kid not in rates:
                fails.append("%s overrides the base_share of '%s', which it does not have in force" % (n, kid))
            elif not float(share) > 0.0:
                fails.append("%s: base_share override for %s must be above 0" % (n, kid))
    return out


def share(kinds, nd, kid):
    """The effective base_share of `kid` in a nation, and where it came from."""
    if kid in nd["overrides"]:
        return float(nd["overrides"][kid]), "nation"
    return float(kinds[kid]["base_share"]), "library"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--band", type=float, default=None,
                    help="fail a modelled yield more than this fraction off the real one")
    args = ap.parse_args()
    fails = []
    kinds, order = load_library(fails)
    nations = load_nations(fails)

    print("%-22s %-4s %10s %-7s %10s %10s %7s  %s" % ("kind", "nat", "rate", "src", "model%GDP", "real%GDP", "ratio", "provenance"))
    off_band = []
    for n, nd in nations.items():
        for kid, rate in nd["rates"].items():
            if kid not in kinds:
                fails.append("%s lists '%s', which the library lacks" % (n, kid))
                continue
            lo, hi = kinds[kid]["rate_range_pct"]
            if not lo <= float(rate) <= hi:
                fails.append("%s: %s rate %s is outside %s" % (n, kid, rate, kinds[kid]["rate_range_pct"]))
    for kid in order:
        k = kinds[kid]
        ref = k.get("reference", {})
        real = ref.get("yield_pct_gdp", {})
        prov = ref.get("provenance", {})
        for n in PLAYABLE:
            rate = nations[n]["rates"].get(kid)
            if rate is None:
                continue
            used, src = share(kinds, nations[n], kid)
            modelled = used * float(rate)
            if n in real:
                ratio = modelled / real[n] if real[n] else float("inf")
                print("%-22s %-4s %10.4g %-7s %10.4f %10.4f %7.2f  %s" % (kid, n, rate, src, modelled, real[n], ratio, prov.get(n, "")))
                if args.band is not None and abs(ratio - 1.0) > args.band:
                    off_band.append("%s %s: modelled %.4f vs real %.4f %% of GDP (ratio %.2f)" % (kid, n, modelled, real[n], ratio))
            else:
                print("%-22s %-4s %10.4g %-7s %10.4f %10s %7s  %s" % (kid, n, rate, src, modelled, "-", "-", prov.get(n, "no real yield in the reference")))

    print("")
    print("revenue explained by the kinds in force (9.3's guard: must not exceed tax_revenue_pct_gdp):")
    for n, nd in nations.items():
        total = sum(share(kinds, nd, k)[0] * float(r) for k, r in nd["rates"].items() if k in kinds)
        print("  %s  %6.2f %% of GDP of %5.1f" % (n, total, nd["revenue"]))
        if total > nd["revenue"]:
            fails.append("%s: kinds in force explain %.2f %% of GDP, above its %.1f (negative residual)" % (n, total, nd["revenue"]))

    for f in fails + off_band:
        print("FAIL %s" % f, file=sys.stderr)
    if fails or off_band:
        print("tax_library_check: %d failure(s)" % (len(fails) + len(off_band)), file=sys.stderr)
        return 1
    print("tax_library_check: %d kinds, %d nations, structure holds%s" % (len(kinds), len(nations), "" if args.band is None else ", every yield within the band"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
