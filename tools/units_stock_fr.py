#!/usr/bin/env python3
"""Rebuild data/units/stock/FRA.json's `stock` and `levels` from the published sources.

Dev-only, not run by CI (it needs the network and openpyxl). A dataset is read once, by
a script (docs/data-sources.md), so the figures can be re-read and audited. DEU, GBR and
POL have their own build with the same shape: stock rows {region, type, units, capacity}
and level rows {region, figure, level}, every number a raw cell.

  python tools/units_stock_fr.py            # prints the table and the self-checks
  python tools/units_stock_fr.py --check    # also fails if data/units/stock/FRA.json differs
  python tools/units_stock_fr.py --write    # rewrites its `stock` and `figures`, keeping `_source`

The file's shape (Systems' loader): stock rows {region, type, units, capacity}, and per type
`figures[type] = {figure, national, levels: [{region, level}]}`, the national value and the levels from
ONE table and one scope. The catalogue's per-nation `capacity` is printed, not written here:
a school = the mean enrolment per lycee; a hospital = the mean MCO beds (medicine, surgery, obstetrics, full
hospitalisation) of the establishments with an authorised emergency department, DREES ARES 2021.

Sources (read 2026-11-17), all in the file's `_source`:
  lycees      data.education.gouv.fr, fr-en-lycee_gt-effectifs-niveau-sexe-lv and
              fr-en-lycee_pro-effectifs-niveau-sexe-lv (pupils per lycee, rentree 2024)
  teachers    data.education.gouv.fr, fr-en-indicateurs_personnels_etablissements2d (FTE)
  hospitals   DREES base ARES, NB_ET sheet (establishments per region, 2021)
  beds, pop   Eurostat hlth_rs_bdsrg2 (2021, NR) and demo_r_d2jan (2021, T, TOTAL)
"""
import collections
import gzip
import io
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "units" / "stock" / "FRA.json"
YEAR = "2024"
PORTAL = "https://data.education.gouv.fr/api/explore/v2.1/catalog/datasets/"
DREES = ("https://data.drees.solidarites-sante.gouv.fr/api/explore/v2.1/catalog/datasets/bases-ares/"
         "attachments/nombre_d_etablissements_de_sante_en_france_2013_2021_xlsx")
DREES_URG = ("https://data.drees.solidarites-sante.gouv.fr/api/explore/v2.1/catalog/datasets/bases-ares/"
             "attachments/nombre_d_etablissements_de_sante_en_france_2013_2021_xlsx")  # sheet NB_URG, same workbook as NB_ET
# INSEE region code -> game region. The game's regions are the 2016 regions.
REGION = {"11": "FR1", "24": "FRB", "27": "FRC", "28": "FRD", "32": "FRE", "44": "FRF", "52": "FRG",
          "53": "FRH", "75": "FRI", "76": "FRJ", "84": "FRK", "93": "FRL", "94": "FRM"}
# Eurostat NUTS 2 parts of each game region (summed).
NUTS = {"FR1": ["FR10"], "FRB": ["FRB0"], "FRC": ["FRC1", "FRC2"], "FRD": ["FRD1", "FRD2"],
        "FRE": ["FRE1", "FRE2"], "FRF": ["FRF1", "FRF2", "FRF3"], "FRG": ["FRG0"], "FRH": ["FRH0"],
        "FRI": ["FRI1", "FRI2", "FRI3"], "FRJ": ["FRJ1", "FRJ2"], "FRK": ["FRK1", "FRK2"], "FRL": ["FRL0"],
        "FRM": ["FRM0"]}
OVERSEAS = ["FRY1", "FRY2", "FRY3", "FRY4", "FRY5"]
FIGURES = {"upper_secondary_school": "upper_secondary_pupils_per_teacher", "hospital": "hospital_beds_per_1000"}
MCO = ("https://data.drees.solidarites-sante.gouv.fr/api/explore/v2.1/catalog/datasets/bases-ares/"
       "attachments/capacites_et_activite_en_mco_en_france_2013_2021_xlsx")


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept-Encoding": "gzip"})
    body = urllib.request.urlopen(req, timeout=180).read()
    return gzip.decompress(body) if body[:2] == b"\x1f\x8b" else body


def export(dataset: str, where: str) -> list:
    q = urllib.parse.urlencode({"where": where, "timezone": "UTC"})
    return json.loads(get(f"{PORTAL}{dataset}/exports/json?{q}"))


def eurostat(code: str, **kw) -> dict:
    q = "&".join(f"{k}={v}" for k, v in kw.items())
    d = json.loads(get(f"https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/{code}?format=JSON&lang=EN&{q}"))
    geo = d["dimension"]["geo"]["category"]["index"]
    # every other dimension is a single value here, so the position is the geo index
    return {g: d["value"][str(i)] for g, i in geo.items() if str(i) in d["value"]}


def number(cell) -> int:
    return int(str(cell).replace(" ", "").replace(" ", "").replace(" ", ""))


def mco_means(count: dict) -> tuple:
    """Mainland MCO beds in full hospitalisation (2021) and mainland establishments with an authorised
    emergency department (2021), both DREES ARES, for the 13 regions."""
    import openpyxl
    import openpyxl.reader.excel as ex
    ex.find_images = lambda a, p: ([], [])
    beds = 0
    for row in openpyxl.load_workbook(io.BytesIO(get(MCO)), data_only=True)["MCO_LIT"].iter_rows(values_only=True):
        if row and isinstance(row[0], str) and row[0][:2] in REGION and row[0][2:5] == " - ":
            beds += number([c for c in row if c is not None][-1])  # the last column is Total MCO 2021
    emergency = 0
    for row in openpyxl.load_workbook(io.BytesIO(get(DREES_URG)), data_only=True)["NB_URG"].iter_rows(values_only=True):
        if row and isinstance(row[0], str) and row[0][:2] in REGION and row[0][2:5] == " - ":
            emergency += number([c for c in row if c is not None][-1])  # 2021
    return beds, emergency


def build() -> dict:
    pupils: dict = collections.defaultdict(int)
    where: dict = {}
    for ds in ("fr-en-lycee_gt-effectifs-niveau-sexe-lv", "fr-en-lycee_pro-effectifs-niveau-sexe-lv"):
        for r in export(ds, f'year(rentree_scolaire)={YEAR}'):
            if r["nombre_d_eleves"] is None:
                continue
            pupils[r["numero_lycee"]] += r["nombre_d_eleves"]
            where[r["numero_lycee"]] = str(r["code_region_insee"])
    etp = {r["uai"]: (r["etp_enseignants_hommes_et_femmes"] or 0)
           for r in export("fr-en-indicateurs_personnels_etablissements2d", f'annee_de_la_rentree_scolaire="{YEAR}"')}
    school = {g: {"units": 0, "capacity": 0, "pupils_taught": 0, "fte": 0.0} for g in NUTS}
    left_out = collections.Counter()
    for uai, n in pupils.items():
        g = REGION.get(where[uai])
        if g is None or n <= 0:
            continue
        s = school[g]
        s["units"] += 1
        s["capacity"] += n
        if etp.get(uai, 0) > 0:
            s["pupils_taught"] += n
            s["fte"] += etp[uai]
        else:
            left_out[g] += 1  # no teacher row, or a zero or null FTE: left out of the level only
    import openpyxl
    import openpyxl.reader.excel as ex
    ex.find_images = lambda a, p: ([], [])  # the workbook carries images openpyxl cannot read
    ws = openpyxl.load_workbook(io.BytesIO(get(DREES)), data_only=True)["NB_ET"]
    count: dict = {}
    national = None
    for row in ws.iter_rows(values_only=True):
        if row and isinstance(row[0], str):
            vals = [c for c in row if c is not None]
            if row[0][:2].isdigit() and row[0][2:5] == " - ":
                count[row[0][:2]] = vals[-1]
            if row[0] == "France entière":
                national = vals[-1]
    beds = eurostat("hlth_rs_bdsrg2", time="2021", unit="NR")
    pop = eurostat("demo_r_d2jan", time="2021", sex="T", age="TOTAL")
    stock, levels = [], {"upper_secondary_school": [], "hospital": []}
    mainland_beds = mainland_pop = 0
    for g in NUTS:
        b = int(sum(beds[n] for n in NUTS[g]))
        p = int(sum(pop[n] for n in NUTS[g]))
        mainland_beds += b
        mainland_pop += p
        code = next(c for c, gg in REGION.items() if gg == g)
        s = school[g]
        stock.append({"region": g, "type": "upper_secondary_school", "units": s["units"], "capacity": s["capacity"]})
        stock.append({"region": g, "type": "hospital", "units": count[code], "capacity": b})
        levels["upper_secondary_school"].append({"region": g, "level": round(s["pupils_taught"] / s["fte"], 2)})
        levels["hospital"].append({"region": g, "level": round(b / p * 1000, 2)})
    overseas_beds = sum(beds[x] for x in OVERSEAS)
    assert mainland_beds + overseas_beds == beds["FR"], "beds do not add up to Eurostat's national figure"
    overseas_est = sum(count[c] for c in ("01", "02", "03", "04", "06"))
    mainland_est = sum(count[c] for c in REGION)
    assert mainland_est + overseas_est == national, "establishments do not add up to DREES's France entiere"
    taught = sum(a["pupils_taught"] for a in school.values())
    fte = sum(a["fte"] for a in school.values())
    mco_beds, emergency = mco_means(count)
    figures = {
        "upper_secondary_school": {"figure": FIGURES["upper_secondary_school"], "national": round(taught / fte, 2),
                                   "levels": levels["upper_secondary_school"]},
        "hospital": {"figure": FIGURES["hospital"], "national": round(mainland_beds / mainland_pop * 1000, 2),
                     "levels": levels["hospital"]}}
    capacity = {"upper_secondary_school": round(sum(a["capacity"] for a in school.values()) / sum(a["units"] for a in school.values())),
                "hospital": round(mco_beds / emergency)}
    print("catalogue capacity per new unit:", capacity, "(MCO beds", mco_beds, "over", emergency, "establishments with emergency)")
    print("teachers left out of the level:", sum(left_out.values()), dict(left_out))
    print("beds", mainland_beds, "+", overseas_beds, "= Eurostat", beds["FR"],
          "| establishments", mainland_est, "+", overseas_est, "= DREES", national)
    return {"stock": stock, "figures": figures, "capacity": capacity}


def render(source: str, built: dict) -> str:
    """The file's text: one row a line, the `_source` kept as it stands."""
    rows = ",\n".join("    " + json.dumps(r, ensure_ascii=False) for r in built["stock"])
    figures = []
    for t, f in built["figures"].items():
        levels = ",\n".join("      " + json.dumps(r) for r in f["levels"])
        figures.append('    "%s": {"figure": "%s", "national": %s, "levels": [\n%s\n    ]}' % (t, f["figure"], f["national"], levels))
    return ('{\n  "_source": ' + json.dumps(source, ensure_ascii=False) + ',\n  "stock": [\n' + rows
            + '\n  ],\n  "figures": {\n' + ",\n".join(figures) + "\n  }\n}\n")


def check_levels(figures: dict, nation: str = "FRA", tolerance: float = 0.03) -> None:
    """The loader refuses a file whose levels, weighted by data/regions `share`, miss `national` by over 3 %."""
    regions = json.loads((ROOT / "data" / "regions" / (nation + ".json")).read_text(encoding="utf8"))["regions"]
    share = {r["id"]: r["share"] for r in regions}
    for t, f in figures.items():
        mean = sum(share[x["region"]] * x["level"] for x in f["levels"]) / sum(share[x["region"]] for x in f["levels"])
        off = abs(mean / f["national"] - 1)
        print("level check %s: weighted mean %.3f against national %s (%.1f %%)" % (t, mean, f["national"], off * 100))
        assert off <= tolerance, t


def main() -> int:
    built = build()
    check_levels(built["figures"])
    have = json.loads(OUT.read_text(encoding="utf8"))
    if "--write" in sys.argv:
        OUT.write_text(render(have["_source"], built), encoding="utf8", newline="\n")
        return 0
    if "--check" in sys.argv:
        same = have["stock"] == built["stock"] and have.get("figures") == built["figures"]
        print("data/units/stock/FRA.json", "matches" if same else "DIFFERS from", "the sources as read now")
        return 0 if same else 1
    for r in built["stock"]:
        print(r)
    print(json.dumps(built["figures"], indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
