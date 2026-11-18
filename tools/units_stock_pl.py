#!/usr/bin/env python3
"""Rebuild data/units/stock/POL.json's `stock` and `figures` from the published sources.

Dev-only, not run by CI (network). Same shape and checks as tools/units_stock_fr.py, _de.py and _gb.py;
every number is a raw cell of a published file.

  python tools/units_stock_pl.py            # prints the table and the self-checks
  python tools/units_stock_pl.py --check    # also fails if data/units/stock/POL.json differs
  python tools/units_stock_pl.py --write    # rewrites its `stock` and `figures`, keeping `_source`

Hospitals, 2024, the 17 NUTS 2 regions:
  Eurostat hlth_rs_bdsrg2 (all hospital beds, NUTS 2) and demo_r_d2jan (1 January 2024) for the beds and the
  beds per 1 000 (one table, one scope, all 17 regions); GUS, Bank Danych Lokalnych (https://bdl.stat.gov.pl),
  subject P2452 "General hospitals", variables 63127 (hospitals) and 63129 (beds), level 3, for the count of
  general hospitals and their mean size. BDL flags the two Mazowsze regions (PL91, PL92) as having no data.

BDL's anonymous quota is small and answers 429 with a Retry-After: calls are spaced out, cached in the
temp directory, and a 429 is waited out as the server says, never retried in a loop.
"""
import gzip
import hashlib
import json
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "units" / "stock" / "POL.json"
BDL = "https://bdl.stat.gov.pl/api/v1"
CACHE = Path(tempfile.gettempdir()) / "bdl_units_stock_pl"
PAUSE = 8.0
YEAR = 2024
HOSPITALS, BEDS = 63127, 63129
# BDL's region names (upper case, 'REGION ...') to the game's region ids
REGION = {"MAŁOPOLSKIE": "PL21", "ŚLĄSKIE": "PL22", "WIELKOPOLSKIE": "PL41", "ZACHODNIOPOMORSKIE": "PL42",
          "LUBUSKIE": "PL43", "DOLNOŚLĄSKIE": "PL51", "OPOLSKIE": "PL52", "KUJAWSKO-POMORSKIE": "PL61",
          "WARMIŃSKO-MAZURSKIE": "PL62", "POMORSKIE": "PL63", "ŁÓDZKIE": "PL71", "ŚWIĘTOKRZYSKIE": "PL72",
          "LUBELSKIE": "PL81", "PODKARPACKIE": "PL82", "PODLASKIE": "PL84", "WARSZAWSKI STOŁECZNY": "PL91",
          "MAZOWIECKI REGIONALNY": "PL92"}
ORDER = list(REGION.values())


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept-Encoding": "gzip"})
    body = urllib.request.urlopen(req, timeout=120).read()
    return gzip.decompress(body) if body[:2] == b"\x1f\x8b" else body


def bdl(path: str, **params) -> dict:
    params.setdefault("format", "json")
    params.setdefault("lang", "en")
    params.setdefault("page-size", 100)
    url = BDL + path + "?" + urllib.parse.urlencode(params, doseq=True)
    CACHE.mkdir(exist_ok=True)
    cached = CACHE / (hashlib.md5(url.encode()).hexdigest() + ".json")
    if cached.exists():
        return json.loads(cached.read_text(encoding="utf8"))
    for _ in range(6):
        time.sleep(PAUSE)
        try:
            data = json.loads(get(url))
            cached.write_text(json.dumps(data, ensure_ascii=False), encoding="utf8")
            return data
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            wait = float(e.headers.get("Retry-After", "0").split()[0] or 0) * 1.15 + 15   # the server says how long
            print("BDL 429: waiting %d s" % wait, file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError("BDL kept refusing: " + url)


def region_values(variable: int) -> dict:
    """BDL level-3 values for 2024. The two Mazowsze regions (PL91, PL92) are flagged 'no data' (attrId 4): omitted."""
    data = bdl("/data/by-variable/%d" % variable, **{"unit-level": 3, "year": YEAR})
    out = {}
    for row in data["results"]:
        cell = next(v for v in row["values"] if v["year"] == str(YEAR))
        if cell.get("attrId") == 4:
            continue
        out[REGION[row["name"].removeprefix("REGION ")]] = float(cell["val"])
    missing = sorted(set(ORDER) - set(out))
    assert missing == ["PL91", "PL92"], "BDL no longer flags exactly PL91 and PL92 as without data: %s" % missing
    return out


def eurostat(code: str, **filters) -> dict:
    query = "&".join("%s=%s" % kv for kv in filters.items())
    url = "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/%s?format=JSON&lang=EN&%s" % (code, query)
    d = json.loads(get(url))
    geo = d["dimension"]["geo"]["category"]["index"]
    return {g: d["value"][str(i)] for g, i in geo.items() if str(i) in d["value"]}


def hospitals() -> dict:
    """Beds and population are Eurostat's for all 17 NUTS 2 regions (hlth_rs_bdsrg2, all hospital beds, and
    demo_r_d2jan); the count of general hospitals is GUS's, for the 15 regions that publish it."""
    count = region_values(HOSPITALS)
    general_beds = region_values(BEDS)
    beds = eurostat("hlth_rs_bdsrg2", time=YEAR, unit="NR")
    pop = eurostat("demo_r_d2jan", time=YEAR, sex="T", age="TOTAL")
    assert abs(sum(beds[g] for g in ORDER) - beds["PL"]) < 1, "the 17 regions do not add up to Poland"
    stock = [{"region": g, "type": "hospital", "units": int(count.get(g, 0)), "capacity": int(beds[g])} for g in ORDER]
    levels = [{"region": g, "level": round(beds[g] / pop[g] * 1000, 2)} for g in ORDER]
    national = round(beds["PL"] / sum(pop[g] for g in ORDER) * 1000, 2)
    capacity = round(sum(general_beds.values()) / sum(count.values()))   # mean beds of a general hospital, GUS
    print("general hospitals", int(sum(count.values())), "with", int(sum(general_beds.values())), "beds; all hospital beds", int(beds["PL"]))
    return {"stock": stock, "figure": {"figure": "hospital_beds_per_1000", "national": national, "levels": levels}, "capacity": capacity}


def build() -> dict:
    h = hospitals()
    print("catalogue capacity per new unit:", {"hospital": h["capacity"]})
    return {"stock": h["stock"], "figures": {"hospital": h["figure"]}, "capacity": {"hospital": h["capacity"]}}


def check_levels(figures: dict, nation: str = "POL", tolerance: float = 0.03) -> None:
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
        print("data/units/stock/POL.json", "matches" if same else "DIFFERS from", "the sources as read now")
        return 0 if same else 1
    for r in built["stock"]:
        print(r)
    print(json.dumps(built["figures"], indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
