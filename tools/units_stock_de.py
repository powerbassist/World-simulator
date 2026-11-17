#!/usr/bin/env python3
"""Rebuild data/units/stock/DEU.json's `stock` and `figures` from the published sources.

Dev-only, not run by CI (network and openpyxl). The same shape and checks as
tools/units_stock_fr.py; every number is a raw cell of a published file.

  python tools/units_stock_de.py            # prints the table and the self-checks
  python tools/units_stock_de.py --check    # also fails if data/units/stock/DEU.json differs
  python tools/units_stock_de.py --write    # rewrites its `stock` and `figures`, keeping `_source`

Scope of upper secondary, the rule for every nation: FULL-TIME pupils, general and vocational, teachers in
full-time equivalents, both from the SAME table family and school year. Part-time apprentices
(Teilzeit-Berufsschulen) are out.

Sources (read 2026-11-17), described in the file's `_source`:
  pupils and teachers   KMK, Dokumentation Nr. 248 (April 2026), tabellenteil Z, tables Z1.2 (pupils) and Z3.2
                        (teachers, Vollzeitlehrkraefte-Einheiten), Laendervergleich 2024 = school year 2024/25
  schools               Destatis Statistischer Bericht 21111 and 21121, school year 2024/25, tables 21111-01 and 21121-01
  hospitals, beds       Destatis Statistischer Bericht "Grunddaten der Krankenhaeuser - Bundeslaender" (2025),
                        tables 23111-b02 (beds per 100 000 with Destatis's own population) and 23111-b14
"""
import gzip
import io
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "units" / "stock" / "DEU.json"
KMK = "https://www.kmk.org/fileadmin/Dateien/pdf/Statistik/Dokumentationen/SKL_Teil_Z_Zusammenfassung_2024.xlsx"
BASE = "https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Bildung-Forschung-Kultur/Schulen/Publikationen/Downloads-Schulen/"
GENERAL = BASE + "statistischer-bericht-allgemeinbildende-schulen-2110100257005.xlsx?__blob=publicationFile&v=3"
VOCATIONAL = BASE + "statistischer-bericht-berufliche-schulen-2110200257005.xlsx?__blob=publicationFile&v=2"
HOSPITALS = ("https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Gesundheit/Krankenhauser/Publikationen/Downloads-Krankenhaeuser/"
             "statistischer-bericht-grunddaten-krankenhaeuser-bundeslaender-2120611257005.xlsx?__blob=publicationFile&v=4")
LAND = {"Baden-Württemberg": "DE1", "Bayern": "DE2", "Berlin": "DE3", "Brandenburg": "DE4", "Bremen": "DE5",
        "Hamburg": "DE6", "Hessen": "DE7", "Mecklenburg-Vorpommern": "DE8", "Niedersachsen": "DE9",
        "Nordrhein-Westfalen": "DEA", "Rheinland-Pfalz": "DEB", "Saarland": "DEC", "Sachsen": "DED",
        "Sachsen-Anhalt": "DEE", "Schleswig-Holstein": "DEF", "Thüringen": "DEG"}
# KMK's column codes, in the order of its tables (then D = Deutschland)
KMK_COLUMNS = ["BW", "BY", "BE", "BB", "HB", "HH", "HE", "MV", "NI", "NW", "RP", "SL", "SN", "ST", "SH", "TH", "D"]
GAME = dict(zip(KMK_COLUMNS, LAND.values()))
# In scope: (block, row label). General Sekundarstufe II, and the full-time (Vollzeitform) vocational schools.
IN_SCOPE = [("general", "Gymnasien*"), ("general", "Schularten mit drei Bildungsgängen"), ("general", "Freie Waldorfschulen"),
            ("full", "Berufsfachschulen"), ("full", "Berufsober-/Technische Oberschulen"), ("full", "Fachgymnasien"),
            ("full", "Fachoberschulen")]
# Out of scope, listed with their size in `_source`.
OUT_OF_SCOPE = [("general", "Abendgymnasien"), ("general", "Kollegs"), ("full", "Berufsvorbereitungsjahr"),
                ("full", "Berufsgrundbildungsjahr"), ("full", "Berufsaufbauschulen"), ("full", "Fachschulen"),
                ("full", "Fachakademien/Berufsakademien")]
SCHOOL_TYPES_GENERAL = ("Gymnasien", "Schularten mit drei Bildungsgängen", "Freie Waldorfschulen")
SCHOOL_TYPES_VOCATIONAL = ("Berufsfachschulen", "Berufsoberschulen/Technische Oberschulen", "Fachgymnasien", "Fachoberschulen")


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept-Encoding": "gzip"})
    body = urllib.request.urlopen(req, timeout=300).read()
    return gzip.decompress(body) if body[:2] == b"\x1f\x8b" else body


def sheet(book, name: str) -> list:
    return list(book[name].iter_rows(values_only=True))[1:]


def kmk_table(book, name: str) -> dict:
    """{(block, label): {kmk column code: value}} for the Sekundarstufe II rows of a KMK Laendervergleich sheet."""
    out, block = {}, None
    for row in book[name].iter_rows(values_only=True):
        label = " ".join(str(next((c for c in row[1:5] if c), "")).split())
        if label.startswith("Anmerkung"):
            break
        if label.startswith("Sekundarstufe II,"):
            block = ("general" if "Allgemeinbildende" in label else "full" if "Vollzeitform" in label
                     else "part" if "Teilzeitform" in label else "vocational")
            out[(block, label)] = dict(zip(KMK_COLUMNS, row[5:22]))
            continue
        if label == "Sekundarstufe II":
            block = None
            continue
        if block and label:
            out[(block, label)] = dict(zip(KMK_COLUMNS, row[5:22]))
    return out


def schools() -> dict:
    import openpyxl
    book = openpyxl.load_workbook(io.BytesIO(get(KMK)), data_only=True)
    pupils, teachers = kmk_table(book, "Z1.2"), kmk_table(book, "Z3.2")
    for table in (pupils, teachers):
        for key in IN_SCOPE + OUT_OF_SCOPE:
            assert key in table, key
            land = sum(table[key][c] for c in KMK_COLUMNS[:-1])
            assert abs(land - table[key]["D"]) < 1.0, ("the 16 Laender differ from Deutschland", key, land, table[key]["D"])
    return {"pupils": pupils, "teachers": teachers}


def school_units() -> dict:
    import openpyxl
    general = openpyxl.load_workbook(io.BytesIO(get(GENERAL)), data_only=True, read_only=True)
    vocational = openpyxl.load_workbook(io.BytesIO(get(VOCATIONAL)), data_only=True, read_only=True)
    units = {}
    for r in sheet(general, "csv-21111-01"):
        if r[2] == "2024/25" and r[4] == "Schulen" and r[5] == "Insgesamt" and r[6] in SCHOOL_TYPES_GENERAL:
            units[(r[3], r[6])] = r[7]
    for r in sheet(vocational, "csv-21121-01"):
        if r[2] == "2024/25" and r[4] == "Schulen" and r[5] == "Insgesamt" and r[6] in SCHOOL_TYPES_VOCATIONAL:
            units[(r[3], r[6])] = r[7]
    return units


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
    kmk = schools()
    pupils, teachers = kmk["pupils"], kmk["teachers"]
    units = school_units()
    total, beds, per_100k, general_n, general_beds = hospitals()
    stock, ratios, bed_levels = [], [], []
    for name, gid in LAND.items():
        col = next(c for c, g in GAME.items() if g == gid)
        cap = sum(pupils[k][col] for k in IN_SCOPE)
        fte = sum(teachers[k][col] for k in IN_SCOPE)
        n = sum(v for (land, _), v in units.items() if land == name)
        stock.append({"region": gid, "type": "upper_secondary_school", "units": n, "capacity": int(cap)})
        stock.append({"region": gid, "type": "hospital", "units": total[name], "capacity": beds[name]})
        ratios.append({"region": gid, "level": round(cap / fte, 2)})
        bed_levels.append({"region": gid, "level": round(per_100k[name] / 100, 2)})
    assert sum(r["units"] for r in stock if r["type"] == "hospital") == total["Deutschland"] == 1807, "hospitals"
    assert sum(r["capacity"] for r in stock if r["type"] == "hospital") == beds["Deutschland"] == 468803, "beds"
    nat_pupils = sum(pupils[k]["D"] for k in IN_SCOPE)
    nat_fte = sum(teachers[k]["D"] for k in IN_SCOPE)
    school_units_total = sum(r["units"] for r in stock if r["type"] == "upper_secondary_school")
    school_pupils = sum(r["capacity"] for r in stock if r["type"] == "upper_secondary_school")
    assert school_pupils == int(nat_pupils), (school_pupils, nat_pupils)
    figures = {
        "upper_secondary_school": {"figure": "upper_secondary_pupils_per_teacher", "national": round(nat_pupils / nat_fte, 2), "levels": ratios},
        "hospital": {"figure": "hospital_beds_per_1000", "national": round(per_100k["Deutschland"] / 100, 2), "levels": bed_levels}}
    capacity = {"upper_secondary_school": round(school_pupils / school_units_total),
                "hospital": round(general_beds["Deutschland"] / general_n["Deutschland"])}
    print("catalogue capacity per new unit:", capacity)
    print("schools", school_units_total, "full-time upper-secondary pupils", school_pupils, "teacher FTE", round(nat_fte, 1))
    print("left out (national pupils / FTE):")
    for key in OUT_OF_SCOPE:
        print("  ", key[1], int(pupils[key]["D"]), round(teachers[key]["D"], 1))
    part = next(v for k, v in pupils.items() if k[0] == "part" and k[1].endswith("Teilzeitform"))
    print("   Teilzeitform (all part-time vocational):", int(part["D"]))
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
