#!/usr/bin/env python3
"""tools/endowments_generate.py -- V4.11b: real endowments and the outline register.

  python tools/endowments_generate.py           # write both files
  python tools/endowments_generate.py --check   # re-derive and diff, exit 1 on drift

Writes:
  data/commodities/endowments.json -- for each raw and agri good, every producer's
      share of WORLD production: roster nations and world outlines by id, and the
      remainder the sources leave unnamed under WORLD_OTHER. Shares, never levels:
      src/sim/commodities.gd sizes the world volume from demand (docs/commodities-
      model.md section 8), so only WHO makes a good comes from here.
  data/world/outlines.json -- every country world.geojson draws that the roster does
      not simulate: its id, its Natural Earth name, and its GDP (the one figure its
      commodity DEMAND reads). Nothing else: a field nothing reads is inert content.

Sources (docs/data-sources.md, V4.11b; ATTRIBUTION.md):
  metals      USGS Mineral Commodity Summaries 2025, via Our World in Data's indicator
              API (sources/owid/minerals/*.json) -- ScienceBase itself was down
  energy      Our World in Data energy (coal/oil/gas production, TWh)
  agri        FAOSTAT QCL (crops and livestock), FO (roundwood)
  fish        World Bank / FAO capture + aquaculture via Our World in Data
  uranium     World Nuclear Association, 2024 mine production -- AUTHORED below as
              public facts with the citation (the author's call, 2026-10-16)
  outlines    World Bank GDP (nearest year 2019-2024); Taiwan AUTHORED (DGBAS)
"""
import csv
import io
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "sources"
ENDOWMENTS_OUT = ROOT / "data" / "commodities" / "endowments.json"
OUTLINES_OUT = ROOT / "data" / "world" / "outlines.json"
USD_TO_EUR = 0.92  # import_data.py's fixed rate, restated (that file is not a library)
YEAR = 2024

# Natural Earth codes the world map uses where ISO 3166 differs.
NE_TO_ISO = {"SDS": "SSD", "SAH": "ESH"}

MINERALS = {  # good -> OWID indicator id (USGS MCS 2025 mine production, tonnes)
    "iron_ore": "1131114", "bauxite": "1131083", "copper_ore": "1131096",
    "nickel_ore": "1131129", "lithium_ore": "1131119", "rare_earths": "1131149",
}
ENERGY = {"coal": "coal_production", "crude_oil": "oil_production", "natural_gas": "gas_production"}
FAO_QCL = {  # good -> FAOSTAT item code, element Production
    "cereals": "1717", "meat": "1765", "dairy": "1780", "vegetables": "1735",
    "wine": "564", "sugar": "1723", "cotton": "328",
}
FAO_ROUNDWOOD = "1861"

# World Nuclear Association, 'World Uranium Mining Production', 2024 tonnes U
# (world-nuclear.org, accessed 2026-10-16). Authored as public facts: WNA's reuse
# terms were not available to read, so no derived table of theirs is redistributed
# -- only the shares these figures imply.
URANIUM_2024 = {
    "KAZ": 23270, "CAN": 14309, "NAM": 7333, "AUS": 4598, "UZB": 4000, "RUS": 2738,
    "CHN": 1600, "NER": 962, "IND": 500, "UKR": 288, "USA": 260, "ZAF": 200,
}
URANIUM_WORLD_2024 = 60213

# Taiwan is absent from the World Bank. Directorate-General of Budget, Accounting
# and Statistics: 2024 GDP USD 781 bn (authored, rounded).
AUTHORED_GDP_USD_BN = {"TWN": 781.0}


def roster_ids():
    return sorted(p.stem for p in (ROOT / "data" / "nations").glob("*.json"))


def outline_ids():
    data = json.loads((ROOT / "data" / "geo" / "world.geojson").read_text(encoding="utf-8"))
    return sorted(f["properties"]["id"] for f in data["features"])


def ne_names_and_m49():
    """ADM0_A3 -> (name, M49 numeric). The 1:50m file carries both, and its
    ISO_N3_EH fills the -99s (France, Norway) ISO_N3 leaves."""
    data = json.loads((SOURCES / "ne_50m_admin_0_countries.geojson").read_text(encoding="utf-8"))
    out = {}
    for f in data["features"]:
        p = f["properties"]
        code = p["ADM0_A3"]
        n3 = p.get("ISO_N3") if p.get("ISO_N3") not in (None, "-99") else p.get("ISO_N3_EH")
        out[code] = (p["NAME"], None if n3 in (None, "-99") else int(n3))
    world = json.loads((SOURCES / "ne_110m_admin_0_countries.geojson").read_text(encoding="utf-8"))
    for f in world["features"]:
        p = f["properties"]
        out.setdefault(p["ADM0_A3"], (p["NAME"], None))
    return out


def iso_of(code):
    """Roster ids are ISO3 except Kosovo, whose data sources say XKX like the roster."""
    return NE_TO_ISO.get(code, code)


# --- per-source readers: {ISO3: production} plus the world total, latest year ------

def minerals(indicator):
    base = SOURCES / "owid" / "minerals"
    meta = json.loads((base / f"{indicator}.metadata.json").read_text(encoding="utf-8"))
    data = json.loads((base / f"{indicator}.data.json").read_text(encoding="utf-8"))
    ents = {e["id"]: (e.get("code") or e["name"]) for e in meta["dimensions"]["entities"]["values"]}
    year = max(y for e, y in zip(data["entities"], data["years"]) if ents[e] == "OWID_WRL" and y <= YEAR)
    out = {ents[e]: float(v) for e, y, v in zip(data["entities"], data["years"], data["values"]) if y == year}
    world = out.pop("OWID_WRL")
    out.pop("Other", None)  # stays in the unnamed remainder
    return out, world, year


# Kosovo has no ISO 3166 entry and OWID's energy file leaves its iso_code BLANK, so
# it is matched by name; the roster says XKX.
OWID_NAME_TO_ISO = {"Kosovo": "XKX"}
# How far back a producer's own last figure may sit behind the world's year. OWID's
# country series come from two vintages: the Energy Institute's (to 2024) for the
# large producers and the EIA's, which ENDS IN 2016, for everyone else -- Germany's
# and France's oil, Bosnia's and Kosovo's lignite. Reading every producer at the
# world's year alone silently zeroed ~1-2 % of each fuel's world output and moved it
# into the pool (the V4.11 review, pass 2). Ten years admits the 2016 vintage and
# nothing older; the year each such producer was read at is written beside its share.
ENERGY_STALE_YEARS = 10


def owid_energy(column):
    """{iso: value}, world, year, {iso: older year read} -- each producer at its OWN
    latest year within ENERGY_STALE_YEARS of the world's."""
    rows = list(csv.DictReader(open(SOURCES / "owid" / "owid-energy-data.csv", encoding="utf-8")))
    year = max(int(r["year"]) for r in rows if r["country"] == "World" and r.get(column) and int(r["year"]) <= YEAR)
    latest = {}
    for r in rows:
        code = OWID_NAME_TO_ISO.get(r["country"], r["iso_code"])
        y = int(r["year"])
        if len(code) != 3 or not r.get(column) or y > year or y < year - ENERGY_STALE_YEARS:
            continue
        if code not in latest or y > latest[code][0]:
            latest[code] = (y, float(r[column]))
    out = {code: v for code, (y, v) in latest.items()}
    older = {code: y for code, (y, v) in latest.items() if y < year and v > 0.0}
    world = next(float(r[column]) for r in rows if r["country"] == "World" and int(r["year"]) == year)
    return out, world, year, older


def fish():
    rows = list(csv.DictReader(open(SOURCES / "owid" / "capture-fisheries-vs-aquaculture.csv", encoding="utf-8")))
    def total(r):
        return float(r["er_fsh_aqua_mt"] or 0) + float(r["er_fsh_capt_mt"] or 0)
    year = max(int(r["year"]) for r in rows if r["entity"] == "World" and int(r["year"]) <= YEAR)
    out = {r["code"]: total(r) for r in rows if int(r["year"]) == year and len(r["code"]) == 3}
    world = next(total(r) for r in rows if r["entity"] == "World" and int(r["year"]) == year)
    return out, world, year


def fao(zip_name, item_code, m49_to_iso):
    z = zipfile.ZipFile(SOURCES / "fao" / zip_name)
    csv_name = next(n for n in z.namelist() if n.endswith("(Normalized).csv"))
    by_year = {}
    with z.open(csv_name) as raw:
        for r in csv.DictReader(io.TextIOWrapper(raw, encoding="latin-1")):
            if r["Item Code"] != item_code or r["Element"] != "Production" or not r["Value"]:
                continue
            by_year.setdefault(int(r["Year"]), {})[r["Area Code (M49)"].strip("'")] = float(r["Value"])
    # M49 '001' is the World row FAOSTAT publishes beside the countries.
    year = max(y for y, v in by_year.items() if "001" in v and y <= YEAR)
    rows = by_year[year]
    world = rows["001"]
    out = {}
    for m49, value in rows.items():
        iso = m49_to_iso.get(int(m49)) if m49.isdigit() else None
        if iso:
            out[iso] = out.get(iso, 0.0) + value
    return out, world, year


def shares_for(production, world, producers):
    """{producer: share} over the roster and outlines, the rest under WORLD_OTHER.
    A producer the source does not list reads 0.0 -- never a guess.

    Where the source's own country figures sum PAST its published world total
    (USGS rounds the rare-earths world to 390 000 t while its countries add to
    more), the denominator is that sum: the shares stay a partition and the
    unnamed remainder is honestly zero, rather than a negative 'other'."""
    world = max(world, sum(v for k, v in production.items() if len(k) == 3))
    shares = {}
    for pid in producers:
        value = production.get(iso_of(pid), 0.0)
        if value > 0.0:
            shares[pid] = round(value / world, 6)
    named = round(sum(shares.values()), 6)
    if named > 1.0 + 1e-4:
        sys.exit(f"named producers exceed world total ({named})")
    if named > 1.0:
        # Six-decimal rounding residue, absorbed by the largest share -- the
        # importer's own rule for a partition that must close exactly.
        largest = max(shares, key=shares.get)
        shares[largest] = round(shares[largest] - (named - 1.0), 6)
        named = 1.0
    shares["WORLD_OTHER"] = round(1.0 - named, 6)
    return shares


def build():
    names = ne_names_and_m49()
    roster = roster_ids()
    outlines = outline_ids()
    producers = roster + outlines
    m49_to_iso = {}
    for code, (_name, m49) in names.items():
        if m49 is not None:
            m49_to_iso.setdefault(m49, iso_of(code))

    goods = {}
    for good, ind in MINERALS.items():
        prod, world, year = minerals(ind)
        goods[good] = {"year": year, "source": "USGS MCS 2025 via OWID indicator %s" % ind,
                       "shares": shares_for(prod, world, producers)}
    for good, col in ENERGY.items():
        prod, world, year, older = owid_energy(col)
        shares = shares_for(prod, world, producers)
        goods[good] = {"year": year, "source": "OWID energy %s" % col, "shares": shares}
        stale = {pid: older[iso_of(pid)] for pid in sorted(shares) if iso_of(pid) in older}
        if stale:
            goods[good]["producer_years"] = stale
    for good, item in FAO_QCL.items():
        prod, world, year = fao("Production_Crops_Livestock_E_All_Data_(Normalized).zip", item, m49_to_iso)
        goods[good] = {"year": year, "source": "FAOSTAT QCL item %s" % item,
                       "shares": shares_for(prod, world, producers)}
    prod, world, year = fao("Forestry_E_All_Data_(Normalized).zip", FAO_ROUNDWOOD, m49_to_iso)
    goods["timber"] = {"year": year, "source": "FAOSTAT FO item %s (roundwood)" % FAO_ROUNDWOOD,
                       "shares": shares_for(prod, world, producers)}
    prod, world, year = fish()
    goods["fish"] = {"year": year, "source": "World Bank/FAO capture + aquaculture via OWID",
                     "shares": shares_for(prod, world, producers)}
    goods["uranium_ore"] = {"year": 2024, "source": "World Nuclear Association 2024 (authored)",
                            "shares": shares_for(URANIUM_2024, URANIUM_WORLD_2024, producers)}

    endowments = {
        "_source": "generated by tools/endowments_generate.py",
        "_note": ("V4.11b. For each raw and agri good, each producer's share of WORLD production; "
                  "WORLD_OTHER is what the source leaves unnamed. Shares only: the world volume is "
                  "sized from demand in src/sim/commodities.gd. See docs/commodities-model.md section 8."),
        "goods": {g: goods[g] for g in sorted(goods)},
    }

    gdp = wb_latest("NY.GDP.MKTP.CD")
    rows = []
    for oid in outlines:
        iso = iso_of(oid)
        usd = gdp.get(iso)
        if usd is None and iso in AUTHORED_GDP_USD_BN:
            usd = AUTHORED_GDP_USD_BN[iso] * 1e9
        rows.append({
            "id": oid,
            "name": names.get(oid, (oid, None))[0],
            # null: no measured GDP at any year in the window -- the outline makes
            # demand nowhere (a bound in docs/data-sources.md, never a guess).
            "gdp_eur_bn": None if usd is None else round(usd * USD_TO_EUR / 1e9, 3),
        })
    outline_doc = {
        "_source": "generated by tools/endowments_generate.py",
        "_note": ("V4.11b. Every country data/geo/world.geojson draws that the roster does not "
                  "simulate: a name and the GDP its commodity demand reads. No domestic model."),
        "outlines": rows,
    }
    return endowments, outline_doc


def wb_latest(code):
    data = json.loads((SOURCES / "wb_world" / f"{code}.json").read_text(encoding="utf-8"))
    best = {}
    for r in data[1]:
        if r["value"] is None or int(r["date"]) > YEAR:
            continue
        iso, y = r["countryiso3code"], int(r["date"])
        if iso and (iso not in best or y > best[iso][1]):
            best[iso] = (float(r["value"]), y)
    return {k: v for k, (v, _y) in best.items()}


def main():
    check = "--check" in sys.argv
    endowments, outlines = build()
    for path, doc in ((ENDOWMENTS_OUT, endowments), (OUTLINES_OUT, outlines)):
        text = json.dumps(doc, ensure_ascii=False, indent=1) + "\n"
        if check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                print("DRIFT:", path)
                return 1
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="\n")
            print("wrote", path)
    for g, e in endowments["goods"].items():
        top = sorted(((k, v) for k, v in e["shares"].items() if k != "WORLD_OTHER"), key=lambda x: -x[1])[:4]
        roster = sum(v for k, v in e["shares"].items() if k in set(roster_ids()))
        print("%-12s %d roster %.3f other %.3f top %s" % (g, e["year"], roster, e["shares"]["WORLD_OTHER"], top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
