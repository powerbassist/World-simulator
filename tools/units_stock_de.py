#!/usr/bin/env python3
"""Rebuild data/units/stock/DEU.json's `stock` and `levels` from the published sources.

Dev-only, not run by CI (network and openpyxl). The same shape and the same checks as
tools/units_stock_fr.py; every number is a raw cell of a Destatis file.

  python tools/units_stock_de.py            # prints the table and the self-checks
  python tools/units_stock_de.py --check    # also fails if data/units/stock/DEU.json differs

Sources (read 2026-11-17), described in the file's `_source`:
  schools, pupils, teachers   Destatis Statistischer Bericht 21111 and 21121, school year 2025/26 (xlsx, CSV sheets)
  hospitals, beds, beds per 100 000, general hospitals
                              Destatis Statistischer Bericht "Grunddaten der Krankenhaeuser - Bundeslaender" (2025),
                              tables 23111-b02 and 23111-b14 (the beds per head use Destatis's own population)
The report URLs carry a version number (v=3 here); a replaced report is a new read.
"""
import gzip
import io
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "units" / "stock" / "DEU.json"
BASE = "https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Bildung-Forschung-Kultur/Schulen/Publikationen/Downloads-Schulen/"
GENERAL = BASE + "statistischer-bericht-allgemeinbildende-schulen-2110100267005.xlsx?__blob=publicationFile&v=3"
VOCATIONAL = BASE + "statistischer-bericht-berufliche-schulen-2110200267005.xlsx?__blob=publicationFile&v=3"
HOSPITALS = ("https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Gesundheit/Krankenhauser/Publikationen/Downloads-Krankenhaeuser/"
             "statistischer-bericht-grunddaten-krankenhaeuser-bundeslaender-2120611257005.xlsx?__blob=publicationFile&v=4")
LAND = {"Baden-Württemberg": "DE1", "Bayern": "DE2", "Berlin": "DE3", "Brandenburg": "DE4", "Bremen": "DE5",
        "Hamburg": "DE6", "Hessen": "DE7", "Mecklenburg-Vorpommern": "DE8", "Niedersachsen": "DE9",
        "Nordrhein-Westfalen": "DEA", "Rheinland-Pfalz": "DEB", "Saarland": "DEC", "Sachsen": "DED",
        "Sachsen-Anhalt": "DEE", "Schleswig-Holstein": "DEF", "Thüringen": "DEG"}
# Upper secondary in every Land: the Gymnasium (its Sekundarbereich II pupils only) and these vocational types.
VOC = ("Fachgymnasien", "Fachoberschulen", "Berufsoberschulen/Technische Oberschulen", "Teilzeit-Berufsschulen")
KEYS = ("gym",) + VOC
PUPIL = "Schüler/innen"


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept-Encoding": "gzip"})
    body = urllib.request.urlopen(req, timeout=300).read()
    return gzip.decompress(body) if body[:2] == b"\x1f\x8b" else body


def sheet(book, name: str) -> list:
    return list(book[name].iter_rows(values_only=True))[1:]


def schools() -> tuple:
    import openpyxl
    general = openpyxl.load_workbook(io.BytesIO(get(GENERAL)), data_only=True, read_only=True)
    vocational = openpyxl.load_workbook(io.BytesIO(get(VOCATIONAL)), data_only=True, read_only=True)
    units, pupils, taught, teachers = {}, {}, {}, {}
    for r in sheet(general, "csv-21111-01"):
        if r[4] == "Schulen" and r[5] == "Insgesamt" and r[6] == "Gymnasien":
            units[(r[3], "gym")] = r[7]
    for r in sheet(general, "csv-21111-03"):
        if r[5] == "Gymnasien" and r[6] == "Insgesamt" and r[7] in ("Insgesamt", "Zusammen") and r[8] == PUPIL:
            if r[4] == "Sekundarbereich II":
                pupils[(r[3], "gym")] = r[9]
            if r[4] == "Alle Bildungsbereiche":
                taught[(r[3], "gym")] = r[9]
    for r in sheet(general, "csv-21111-18"):
        # Mecklenburg-Vorpommern files its Gymnasium teachers under 'Gymnasien (G8)'
        if r[4] in ("Gymnasien", "Gymnasien (G8)") and r[5] == "Insgesamt" and r[6].startswith("Voll- und") and r[7] == "Insgesamt":
            teachers[(r[3], "gym")] = r[8]
    for r in sheet(vocational, "csv-21121-01"):
        if r[4] == "Schulen" and r[5] == "Insgesamt" and r[6] in VOC:
            units[(r[3], r[6])] = r[7]
    for r in sheet(vocational, "csv-21121-02"):
        if r[4] == "Insgesamt" and r[5] in VOC and r[6] == "Insgesamt" and r[7] in ("Insgesamt", "Zusammen") and r[8] == PUPIL:
            pupils[(r[3], r[5])] = taught[(r[3], r[5])] = r[9]
    for r in sheet(vocational, "csv-21121-11"):
        if r[4] in VOC and r[5] == "Insgesamt" and r[6] == "Insgesamt" and r[7].startswith("Voll- und") and r[8] == "Insgesamt":
            teachers[(r[3], r[4])] = r[9]
    return units, pupils, taught, teachers


def hospitals() -> tuple:
    """Per Land from the Destatis report 'Grunddaten der Krankenhaeuser - Bundeslaender' (2025): hospitals,
    set-up beds and beds per 100 000 inhabitants (table 23111-b02), and the Allgemeine Krankenhaeuser
    (23111-b14), the general full-service hospitals whose mean size is the catalogue's capacity. The formatted
    sheets are read, not the csv ones: csv-23111-b02 has no Sachsen-Anhalt rows."""
    import openpyxl
    book = openpyxl.load_workbook(io.BytesIO(get(HOSPITALS)), data_only=True)
    total, beds, per_100k, general_n, general_beds = {}, {}, {}, {}, {}
    for r in book["23111-b02"].iter_rows(min_row=5, values_only=True):
        if r[0] == "Deutschland" or r[0] in LAND:
            total[r[0]], beds[r[0]], per_100k[r[0]] = r[1], r[2], r[3]
    for r in book["23111-b14"].iter_rows(min_row=5, values_only=True):
        if r[0] == "Deutschland" or r[0] in LAND:
            general_n[r[0]], general_beds[r[0]] = r[1], r[6]
    assert len(total) == 17 and len(general_n) == 17, "a Land is missing from the hospital tables"
    return total, beds, per_100k, general_n, general_beds


def build() -> dict:
    units, pupils, taught, teachers = schools()
    total, beds, per_100k, general_n, general_beds = hospitals()
    stock, ratios, bed_levels = [], [], []
    tp = tt = 0
    for name, gid in LAND.items():
        u = sum(units.get((name, k), 0) for k in KEYS)
        cap = sum(pupils.get((name, k), 0) for k in KEYS)
        paired = [k for k in KEYS if teachers.get((name, k))]  # a type without a teacher figure leaves the level only
        p, t = sum(taught.get((name, k), 0) for k in paired), sum(teachers[(name, k)] for k in paired)
        tp, tt = tp + p, tt + t
        stock.append({"region": gid, "type": "upper_secondary_school", "units": u, "capacity": cap})
        stock.append({"region": gid, "type": "hospital", "units": total[name], "capacity": beds[name]})
        ratios.append({"region": gid, "level": round(p / t, 2)})
        bed_levels.append({"region": gid, "level": round(per_100k[name] / 100, 2)})
    assert sum(r["units"] for r in stock if r["type"] == "hospital") == total["Deutschland"] == 1807, "hospitals"
    assert sum(r["capacity"] for r in stock if r["type"] == "hospital") == beds["Deutschland"] == 468803, "beds"
    for k in KEYS:  # each school type's 16 Laender add up to the Deutschland row
        for table in (units, pupils, teachers):
            land = sum(v for (l, kk), v in table.items() if kk == k and l != "Deutschland")
            nat = table.get(("Deutschland", k))
            # the national Gymnasium teacher row is split in two labels, G8 and the rest
            assert nat is None or nat == land or (k == "gym" and table is teachers), (k, nat, land)
    figures = {
        "upper_secondary_school": {"figure": "upper_secondary_pupils_per_teacher", "national": round(tp / tt, 2), "levels": ratios},
        "hospital": {"figure": "hospital_beds_per_1000", "national": round(per_100k["Deutschland"] / 100, 2), "levels": bed_levels}}
    capacity = {"upper_secondary_school": round(sum(r["capacity"] for r in stock if r["type"] == "upper_secondary_school")
                                               / sum(r["units"] for r in stock if r["type"] == "upper_secondary_school")),
                "hospital": round(general_beds["Deutschland"] / general_n["Deutschland"])}
    print("catalogue capacity per new unit:", capacity, "(general hospitals", general_n["Deutschland"], "with",
          general_beds["Deutschland"], "beds)")
    print("schools", sum(r["units"] for r in stock if r["type"] == "upper_secondary_school"),
          "pupils", sum(r["capacity"] for r in stock if r["type"] == "upper_secondary_school"),
          "| hospitals 1807, beds 468803 (match Destatis's Deutschland row)")
    return {"stock": stock, "figures": figures, "capacity": capacity}


def check_levels(figures: dict, nation: str = "DEU", tolerance: float = 0.03) -> None:
    """The loader refuses a file whose levels, weighted by data/regions `share`, miss `national` by over 3 %."""
    regions = json.loads((ROOT / "data" / "regions" / (nation + ".json")).read_text(encoding="utf8"))["regions"]
    share = {r["id"]: r["share"] for r in regions}
    for t, f in figures.items():
        mean = sum(share[x["region"]] * x["level"] for x in f["levels"]) / sum(share[x["region"]] for x in f["levels"])
        off = abs(mean / f["national"] - 1)
        print("level check %s: weighted mean %.3f against national %s (%.1f %%)" % (t, mean, f["national"], off * 100))
        assert off <= tolerance, t


def render(source: str, built: dict) -> str:
    """The file's text: one row a line, the `_source` kept as it stands."""
    rows = ",\n".join("    " + json.dumps(r, ensure_ascii=False) for r in built["stock"])
    figures = []
    for t, f in built["figures"].items():
        levels = ",\n".join("      " + json.dumps(r) for r in f["levels"])
        figures.append('    "%s": {"figure": "%s", "national": %s, "levels": [\n%s\n    ]}' % (t, f["figure"], f["national"], levels))
    return ('{\n  "_source": ' + json.dumps(source, ensure_ascii=False) + ',\n  "stock": [\n' + rows
            + '\n  ],\n  "figures": {\n' + ",\n".join(figures) + "\n  }\n}\n")


def main() -> int:
    built = build()
    check_levels(built["figures"])
    have = json.loads(OUT.read_text(encoding="utf8"))
    if "--write" in sys.argv:
        OUT.write_text(render(have["_source"], built), encoding="utf8", newline="\n")
        return 0
    if "--check" in sys.argv:
        same = have["stock"] == built["stock"] and have.get("figures") == built["figures"]
        print("data/units/stock/DEU.json", "matches" if same else "DIFFERS from", "the sources as read now")
        return 0 if same else 1
    for r in built["stock"]:
        print(r)
    print(json.dumps(built["figures"], indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
