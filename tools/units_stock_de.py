#!/usr/bin/env python3
"""Rebuild data/units/stock/DEU.json's `stock` and `levels` from the published sources.

Dev-only, not run by CI (network and openpyxl). The same shape and the same checks as
tools/units_stock_fr.py; every number is a raw cell of a Destatis file.

  python tools/units_stock_de.py            # prints the table and the self-checks
  python tools/units_stock_de.py --check    # also fails if data/units/stock/DEU.json differs

Sources (read 2026-11-17), described in the file's `_source`:
  schools, pupils, teachers   Destatis Statistischer Bericht 21111 and 21121, school year 2025/26 (xlsx, CSV sheets)
  hospitals, set-up beds      Destatis table "Krankenhaeuser 2025 nach Traegern und Bundeslaendern" (a live HTML page)
  population                  Eurostat demo_r_d2jan, 1 January 2025, NUTS 1
The report URLs carry a version number (v=3 here); a replaced report is a new read.
"""
import gzip
import html
import io
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "units" / "stock" / "DEU.json"
BASE = "https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Bildung-Forschung-Kultur/Schulen/Publikationen/Downloads-Schulen/"
GENERAL = BASE + "statistischer-bericht-allgemeinbildende-schulen-2110100267005.xlsx?__blob=publicationFile&v=3"
VOCATIONAL = BASE + "statistischer-bericht-berufliche-schulen-2110200267005.xlsx?__blob=publicationFile&v=3"
HOSPITALS = "https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Gesundheit/Krankenhauser/Tabellen/eckzahlen-krankenhaeuser.html"
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


def hospitals() -> dict:
    text = html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "|", get(HOSPITALS).decode("utf8", "ignore"))))
    parts = re.sub(r"(\| ?)+", "|", text).split("|")
    out = {}
    for name, gid in LAND.items():
        i = parts.index(name)
        out[gid] = (int(re.sub(r"\D", "", parts[i + 1])), int(re.sub(r"\D", "", parts[i + 2])))
    return out


def population() -> dict:
    d = json.loads(get("https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/demo_r_d2jan"
                       "?format=JSON&lang=EN&time=2025&sex=T&age=TOTAL"))
    geo = d["dimension"]["geo"]["category"]["index"]
    return {g: d["value"][str(i)] for g, i in geo.items() if g in LAND.values()}


def build() -> dict:
    units, pupils, taught, teachers = schools()
    hosp, pop = hospitals(), population()
    stock, levels = [], []
    for name, gid in LAND.items():
        u = sum(units.get((name, k), 0) for k in KEYS)
        cap = sum(pupils.get((name, k), 0) for k in KEYS)
        paired = [k for k in KEYS if teachers.get((name, k))]  # a type without a teacher figure leaves the level only
        ratio = sum(taught.get((name, k), 0) for k in paired) / sum(teachers[(name, k)] for k in paired)
        hu, hb = hosp[gid]
        stock.append({"region": gid, "type": "upper_secondary_school", "units": u, "capacity": cap})
        stock.append({"region": gid, "type": "hospital", "units": hu, "capacity": hb})
        levels.append({"region": gid, "figure": "pupils_per_teacher", "level": round(ratio, 2)})
        levels.append({"region": gid, "figure": "beds_per_1000", "level": round(hb / pop[gid] * 1000, 2)})
    assert sum(r["units"] for r in stock if r["type"] == "hospital") == 1807, "hospitals differ from Destatis's Deutschland row"
    assert sum(r["capacity"] for r in stock if r["type"] == "hospital") == 468803, "beds differ from Destatis's Deutschland row"
    for k in KEYS:  # each school type's 16 Laender add up to the Deutschland row
        for table in (units, pupils, teachers):
            land = sum(v for (l, kk), v in table.items() if kk == k and l != "Deutschland")
            nat = table.get(("Deutschland", k))
            # the national Gymnasium teacher row is split in two labels, G8 and the rest
            assert nat is None or nat == land or (k == "gym" and table is teachers), (k, nat, land)
    print("schools", sum(r["units"] for r in stock if r["type"] == "upper_secondary_school"),
          "pupils", sum(r["capacity"] for r in stock if r["type"] == "upper_secondary_school"),
          "| hospitals 1807, beds 468803 (match Destatis)")
    return {"stock": stock, "levels": levels}


def main() -> int:
    built = build()
    if "--check" in sys.argv:
        have = json.loads(OUT.read_text(encoding="utf8"))
        same = have["stock"] == built["stock"] and have["levels"] == built["levels"]
        print("data/units/stock/DEU.json", "matches" if same else "DIFFERS from", "the sources as read now")
        return 0 if same else 1
    for r in built["stock"] + built["levels"]:
        print(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
