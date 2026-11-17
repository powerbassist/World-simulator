#!/usr/bin/env python3
"""Rebuild data/units/stock/GBR.json's `stock` and `figures` from the published sources.

Dev-only, not run by CI (network and openpyxl). Same shape and checks as tools/units_stock_fr.py and
tools/units_stock_de.py; every number is a raw cell of a published file.

  python tools/units_stock_gb.py            # prints the table and the self-checks
  python tools/units_stock_gb.py --check    # also fails if data/units/stock/GBR.json differs
  python tools/units_stock_gb.py --write    # rewrites its `stock` and `figures`, keeping `_source`

Britain has no upper-secondary split, so its school type is its own: `secondary_school`, the state-funded
secondary schools (11 to 18, sixth forms included), with its own figure `secondary_pupils_per_teacher`: pupils
over teachers in full-time equivalents of the same schools, school year 2025/26, from one release per
nation. (France and Germany answer `upper_secondary_pupils_per_teacher`.)

  England     DfE, School workforce in England, reporting year 2025 (zip of data files, 288 MB, downloaded once),
              workforce_ptrs_2010_2025_nat_reg_la.csv, time_period 202526, regional rows, 'State-funded secondary'
  Scotland    Scottish Government, Pupil and teacher characteristics 2025, headline statistics (secondary schools,
              pupils, teachers; teachers in FTE, pupils are a headcount)
  Wales       Welsh Government, Schools' census results: January 2026 (ods tables 1, 6 and 8: maintained
              secondary schools, FTE pupils, FTE qualified teachers); middle schools are not secondary there
  Northern Ireland  DE / NISRA, Annual enrolments 2025/26 (post-primary schools and enrolments) and Teacher
              workforce statistics bulletin 2025/26 (post-primary teachers, FTE)

Hospitals (year 2024/25, except Wales whose 2024-25 total is not published):
  England     NHS England, KH03 "Bed Availability and Occupancy Data - Overnight", NHS Trust by Sector, Q4 2024-25
              (average daily available overnight beds). A trust goes to the English region of its registered
              postcode (NHS ODS API for the postcode, postcodes.io for the ONS region): a trust that runs sites in
              two regions counts wholly in one.
  Scotland    Public Health Scotland, Annual NHS beds information, beds by health board and specialty,
              'All Specialties', average available staffed beds, 2024/25
  Wales       Welsh Government, NHS beds: April 2023 to March 2024, average daily available beds
  Northern Ireland  Department of Health, Hospital statistics: inpatient and day case activity 2024/25
  population  ONS mid-2024 estimates through Nomis (NM_2002_1, all ages, persons)
"""
import collections
import csv
import gzip
import html
import io
import json
import re
import shutil
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "units" / "stock" / "GBR.json"
KH03 = "https://www.england.nhs.uk/statistics/wp-content/uploads/sites/2/2025/05/Beds-Open-Overnight-Web_File-Q4-2024-25.xlsx"
ODS_API = "https://directory.spineservices.nhs.uk/ORD/2-0-0/organisations/"
POSTCODES = "https://api.postcodes.io/postcodes"
SCOTLAND_BEDS = "https://www.opendata.nhs.scot/api/3/action/package_show?id=annual-hospital-beds-information"
WALES_BEDS = "https://www.gov.wales/nhs-beds-april-2023-march-2024-html"
NI_BEDS = "https://www.health-ni.gov.uk/news/release-northern-ireland-inpatient-day-case-and-outpatient-hospital-statistics-202425"
NOMIS = ("https://www.nomisweb.co.uk/api/v01/dataset/NM_2002_1.data.csv?geography=2013265921...2013265929,2092957699,2092957700,"
         "2092957701,2092957702&date=2024&gender=0&c_age=200&measures=20100&select=geography_name,geography_code,obs_value")
DFE_ZIP = "https://content.explore-education-statistics.service.gov.uk/api/releases/32476c77-5ff3-4efb-ad1e-a2173e74a4d4/files"
DFE_FILE = "data/workforce_ptrs_2010_2025_nat_reg_la.csv"
SCOTLAND_SCHOOLS = "https://www.gov.scot/publications/pupil-and-teacher-characteristics-2025/pages/headline-statistics/"
WALES_CENSUS = "https://gov.wales/sites/default/files/statistics-and-research/2026-07/schools-census-results-january-2026-081400.ods"
WALES_PAGE = "https://www.gov.wales/schools-census-results-january-2026-html"
NI_ENROLMENTS = "https://datavis.nisra.gov.uk/DEstatistics/annual-enrolments-schools-and-funded-pre-school-education-northern-ireland-202526.html"
NI_TEACHERS = "https://datavis.nisra.gov.uk/DEstatistics/teacher-workforce-statistics-bulletin-202526.html"
REGION = {"North East": "UKC", "North West": "UKD", "Yorkshire and The Humber": "UKE", "East Midlands": "UKF",
          "West Midlands": "UKG", "East of England": "UKH", "London": "UKI", "South East": "UKJ", "South West": "UKK"}
NOMIS_ID = {"E12000001": "UKC", "E12000002": "UKD", "E12000003": "UKE", "E12000004": "UKF", "E12000005": "UKG",
            "E12000006": "UKH", "E12000007": "UKI", "E12000008": "UKJ", "E12000009": "UKK", "W92000004": "UKL",
            "S92000003": "UKM", "N92000002": "UKN"}
ORDER = ["UKC", "UKD", "UKE", "UKF", "UKG", "UKH", "UKI", "UKJ", "UKK", "UKL", "UKM", "UKN"]


def get(url: str, data: bytes = None) -> bytes:
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36",
               "Accept-Encoding": "gzip", "Content-Type": "application/json"}
    body = urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers), timeout=300).read()
    return gzip.decompress(body) if body[:2] == b"\x1f\x8b" else body


def text(url: str) -> str:
    raw = get(url).decode("utf8", "ignore")
    return html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", re.sub(r"<script.*?</script>", " ", raw, flags=re.S))))


def num(s: str) -> float:
    return float(s.replace(",", ""))


# ---------------------------------------------------------------- hospitals

def england_beds() -> tuple:
    """({region id: (trusts, beds)}, mean general-and-acute beds of the trusts that have any, England's total)."""
    import openpyxl
    book = openpyxl.load_workbook(io.BytesIO(get(KH03)), data_only=True)
    sheet = list(book["NHS Trust by Sector"].iter_rows(values_only=True))
    trusts = [(r[4], r[6], r[7]) for r in sheet if r[1] == "2024-25" and r[3] and r[4]]
    postcode = {code: json.loads(get(ODS_API + code))["Organisation"]["GeoLoc"]["Location"]["PostCode"] for code, _, _ in trusts}
    region = {}
    unique = sorted(set(postcode.values()))
    for i in range(0, len(unique), 100):
        reply = json.loads(get(POSTCODES, json.dumps({"postcodes": unique[i:i + 100]}).encode()))
        for item in reply["result"]:
            region[item["query"]] = (item["result"] or {}).get("region")
    out = collections.defaultdict(lambda: [0, 0.0])
    for code, total, _ in trusts:
        gid = REGION[region[postcode[code]]]
        out[gid][0] += 1
        out[gid][1] += total
    national = next(r[6] for r in sheet if r[5] == "England" and r[1] == "2024-25")
    assert abs(sum(v[1] for v in out.values()) - national) < 0.01, "trusts do not add up to England"
    acute = [a for _, _, a in trusts if a and a > 0]
    return {k: (v[0], v[1]) for k, v in out.items()}, sum(acute) / len(acute), national


def scotland_beds() -> tuple:
    package = json.loads(get(SCOTLAND_BEDS))["result"]
    url = next(x["url"] for x in package["resources"] if x["name"].startswith("Beds by Health Board"))
    rows = list(csv.DictReader(io.StringIO(get(url).decode("utf-8-sig"))))
    beds = [x for x in rows if x["FinancialYear"] == "2024/25" and x["SpecialtyName"] == "All Specialties"]
    total = next(float(x["AverageAvailableStaffedBeds"]) for x in beds if x["HB"] == "S92000003")
    boards = [x for x in beds if x["HB"] != "S92000003" and float(x["AverageAvailableStaffedBeds"] or 0) > 0]
    assert abs(sum(float(x["AverageAvailableStaffedBeds"]) for x in boards) - total) <= 0.5 * len(boards), \
        "boards do not add up to Scotland (each is rounded to a whole bed)"
    return len(boards), total


def wales_beds() -> float:
    return num(re.search(r"average daily number of available beds in 2023-24 was ([\d,]+)", text(WALES_BEDS)).group(1))


def ni_beds() -> float:
    m = re.search(r"average number of available beds decreased by [\d.]+% \([\d.]+\) from [\d,.]+ to (\d[\d,]*\.\d)", text(NI_BEDS))
    return num(m.group(1))


def population() -> dict:
    rows = list(csv.DictReader(io.StringIO(get(NOMIS).decode("utf8"))))
    return {NOMIS_ID[r["GEOGRAPHY_CODE"]]: float(r["OBS_VALUE"]) for r in rows if r["GEOGRAPHY_CODE"] in NOMIS_ID}


def hospitals() -> dict:
    eng, acute_mean, eng_total = england_beds()
    boards, sco = scotland_beds()
    wal, ni = wales_beds(), ni_beds()
    pop = population()
    beds = {g: eng[g][1] for g in eng}
    units = {g: eng[g][0] for g in eng}
    beds["UKL"], units["UKL"] = wal, 0    # the release names no organisation count
    beds["UKM"], units["UKM"] = sco, boards
    beds["UKN"], units["UKN"] = ni, 5     # the five HSC trusts
    stock = [{"region": g, "type": "hospital", "units": units[g], "capacity": round(beds[g])} for g in ORDER]
    levels = [{"region": g, "level": round(beds[g] / pop[g] * 1000, 2)} for g in ORDER]
    national = round(sum(beds.values()) / sum(pop.values()) * 1000, 2)
    print("hospital beds", round(sum(beds.values())), "England", round(eng_total), "Scotland", sco, "Wales", wal, "NI", ni)
    print("general and acute: mean beds of the English trusts that have any:", round(acute_mean))
    return {"stock": stock, "figure": {"figure": "hospital_beds_per_1000", "national": national, "levels": levels},
            "capacity": round(acute_mean)}


# ---------------------------------------------------------------- schools

def england_schools() -> dict:
    """{region id: (schools, pupils FTE, teachers FTE)} for the state-funded secondary schools, 2025/26."""
    cache = Path(tempfile.gettempdir()) / "dfe_school_workforce_2025.zip"
    if not cache.exists():
        req = urllib.request.Request(DFE_ZIP, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=600) as r, open(cache, "wb") as f:
            shutil.copyfileobj(r, f)
    rows = csv.DictReader(io.TextIOWrapper(zipfile.ZipFile(cache).open(DFE_FILE), encoding="utf-8-sig"))
    out = {}
    for r in rows:
        if r["time_period"] == "202526" and r["geographic_level"] == "Regional" and r["establishment_type_group"] == "State-funded secondary":
            gid = REGION.get(r["region_name"], "UKI" if r["region_name"] in ("Inner London", "Outer London") else None)
            n, p, t = int(r["number_schools"]), float(r["pupils_fte"]), float(r["teachers_fte"])
            old = out.get(gid, (0, 0.0, 0.0))   # London is published as Inner and Outer London: added
            out[gid] = (old[0] + n, old[1] + p, old[2] + t)
    assert len(out) == 9, "nine English regions expected"
    return out


def last_number(page: str, start: str, label: str) -> float:
    """The last figure on the row `label` of the table that follows `start` (a heading in the page's text)."""
    i = page.index(start)
    m = re.search(re.escape(label) + r" ((?:[\d,]+ )+)", page[i:i + 1500])
    return num(m.group(1).split()[-1])


def scotland_schools() -> tuple:
    page = text(SCOTLAND_SCHOOLS)
    return (int(last_number(page, "Figure 1 Publicly funded schools", "Secondary")),
            last_number(page, "Figure 2 Pupils by sector", "Secondary"),
            last_number(page, "Figure 3 Teachers by sector", "Secondary"))


def ods_tables(data: bytes, names: set) -> dict:
    ns = {"t": "{urn:oasis:names:tc:opendocument:xmlns:table:1.0}", "x": "{urn:oasis:names:tc:opendocument:xmlns:text:1.0}",
          "o": "{urn:oasis:names:tc:opendocument:xmlns:office:1.0}"}
    root = ET.fromstring(zipfile.ZipFile(io.BytesIO(data)).read("content.xml"))
    out = {}
    for tb in root.iter(ns["t"] + "table"):
        name = tb.get(ns["t"] + "name")
        if name not in names:
            continue
        rows = []
        for r in tb.iter(ns["t"] + "table-row"):
            cells = []
            for c in r.findall(ns["t"] + "table-cell"):
                n = min(int(c.get(ns["t"] + "number-columns-repeated", "1")), 30)
                value = c.get(ns["o"] + "value")
                if value is None:
                    value = "".join("".join(p.itertext()) for p in c.findall(ns["x"] + "p"))
                cells += [value] * n
            rows.append(cells)
        out[name] = rows
    return out


def wales_schools() -> tuple:
    req = urllib.request.Request(WALES_CENSUS, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124",
                                                        "Referer": WALES_PAGE, "Accept": "*/*"})
    tables = ods_tables(urllib.request.urlopen(req, timeout=120).read(), {"Table_1", "Table_6", "Table_8"})

    def secondary(name: str) -> float:
        row = next(r for r in tables[name] if r[0].startswith("Wales") and r[0].endswith("January 2026"))
        header = next(r for r in tables[name] if r[0] == "Local authority")
        return float(row[header.index("Secondary")])
    return int(secondary("Table_1")), secondary("Table_6"), secondary("Table_8")


def ni_schools() -> tuple:
    enrol = text(NI_ENROLMENTS)
    schools = int(re.search(r"The number of post-primary schools in 2025/26 is (\d+)", enrol).group(1))
    pupils = num(re.search(r"Post-primary enrolments have fallen for the first time since 2016/17 to ([\d,]+)", enrol).group(1))
    bulletin = text(NI_TEACHERS)
    rows = re.findall(r"Post-primary schools Total ((?:[\d,]+(?:\.\d)? ){9}[\d,]+\.\d)", bulletin)
    teachers = num(next(r for r in rows if num(r.split()[-1]) > 1000).split()[-1])   # FTE teachers; the other table is the PTR
    return schools, pupils, teachers


def schools() -> dict:
    eng = england_schools()
    sco, wal, ni = scotland_schools(), wales_schools(), ni_schools()
    rows = {g: eng[g] for g in eng}
    rows["UKL"], rows["UKM"], rows["UKN"] = wal, sco, ni
    stock = [{"region": g, "type": "secondary_school", "units": rows[g][0], "capacity": round(rows[g][1])} for g in ORDER]
    levels = [{"region": g, "level": round(rows[g][1] / rows[g][2], 2)} for g in ORDER]
    pupils = sum(rows[g][1] for g in ORDER)
    teachers = sum(rows[g][2] for g in ORDER)
    print("secondary schools", sum(rows[g][0] for g in ORDER), "pupils", round(pupils), "teacher FTE", round(teachers, 1))
    print("Scotland", sco, "Wales", wal, "NI", ni)
    return {"stock": stock, "figure": {"figure": "secondary_pupils_per_teacher", "national": round(pupils / teachers, 2), "levels": levels},
            "capacity": round(pupils / sum(rows[g][0] for g in ORDER))}


# ---------------------------------------------------------------- the file

def build() -> dict:
    s, h = schools(), hospitals()
    print("catalogue capacity per new unit:", {"secondary_school": s["capacity"], "hospital": h["capacity"]})
    return {"stock": s["stock"] + h["stock"],
            "figures": {"secondary_school": s["figure"], "hospital": h["figure"]},
            "capacity": {"secondary_school": s["capacity"], "hospital": h["capacity"]}}


def check_levels(figures: dict, nation: str = "GBR", tolerance: float = 0.03) -> None:
    """The loader refuses a file whose levels, weighted by data/regions `share`, miss `national` by over 3 %."""
    regions = json.loads((ROOT / "data" / "regions" / (nation + ".json")).read_text(encoding="utf8"))["regions"]
    share = {r["id"]: r["share"] for r in regions}
    for t, f in figures.items():
        mean = sum(share[x["region"]] * x["level"] for x in f["levels"]) / sum(share[x["region"]] for x in f["levels"])
        off = abs(mean / f["national"] - 1)
        print("level check %s: weighted mean %.3f against national %s (%.1f %%)" % (t, mean, f["national"], off * 100))
        assert off <= tolerance, t


def render(source: str, built: dict) -> str:
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
    if "--write" in sys.argv:
        source = json.loads(OUT.read_text(encoding="utf8"))["_source"] if OUT.exists() else "TODO"
        OUT.write_text(render(source, built), encoding="utf8", newline="\n")
        return 0
    if "--check" in sys.argv:
        have = json.loads(OUT.read_text(encoding="utf8"))
        same = have["stock"] == built["stock"] and have.get("figures") == built["figures"]
        print("data/units/stock/GBR.json", "matches" if same else "DIFFERS from", "the sources as read now")
        return 0 if same else 1
    for r in built["stock"]:
        print(r)
    print(json.dumps(built["figures"], indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
