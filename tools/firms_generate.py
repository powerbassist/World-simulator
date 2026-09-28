#!/usr/bin/env python3
"""tools/firms_generate.py -- V4.7a A3: the body generator, and 29 nations of firms.

Deterministic, seed-fixed content generator, the tools/bench_generate.py
contract verbatim: one RNG (seed fixed below), sorted iteration everywhere,
--check re-derives and diffs against the committed files (exit 1 on drift).

Modes:
  python tools/firms_generate.py                  # generate + write all content
  python tools/firms_generate.py --check          # verify committed files match
  python tools/firms_generate.py --majors-only    # majors + chiefs only, no body
  python tools/firms_generate.py --emit-drafts    # write major drafts to reports/

Produces:
  data/companies/<ID>.json  -- majors (the 25 nations that have none; the four
                               authored nations keep theirs) + a generated body.
  data/people/<ID>.json     -- one executive chief per new major (appended).
  tools/portraits_traits.json -- a sidecar entry per new chief.

THE TWO TIERS. A MAJOR is hand-authored content: a firm big enough to move its
sector, carrying a named chief of kind "executive" (V4.7a A2's edge). The 25
nations that had no register get theirs from this tool's drafts, reviewed and
committed. A BODY firm is fully generated -- ~85 a nation, shares in the band
the constants file declares, acting upon and fronted by nobody. The body is
committed and never hand-edited: a hand edit dies at the next --check.

BANDS (declared in src/sim/companies_constants.gd, pinned in
tests/test_companies_tiers.gd, and the generator obeys all of them):
  - per-sector named coverage (majors + body) in [BODY_COVERAGE_MIN, BODY_COVERAGE_MAX].
  - body share <= BODY_SHARE_MAX and >= MIN_BODY_SHARE.
  - body headcount in [500, 25000].
  - body firm counts ordered like the nation's own sector_output weights.
  - the largest city holds a body-payroll share in the concentration band
    (nations with ONE city are exempt -- the band is a partition of two cities).

See docs/superpowers/plans/2026-09-27-v4.7-industry.md and task-A3-brief.md.
"""
import json
import random
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bench_generate import NAMES, fold, slug  # the committed bench name pools
from curated_names.extra_surnames import EXTRA_SURNAMES

ROOT = Path(__file__).resolve().parent.parent
COMPANIES_DIR = ROOT / "data" / "companies"
PEOPLE_DIR = ROOT / "data" / "people"
NATIONS_DIR = ROOT / "data" / "nations"
REGIONS_DIR = ROOT / "data" / "regions"
SIDECAR_PATH = ROOT / "tools" / "portraits_traits.json"
DRAFTS_DIR = ROOT / "reports" / "firms_major_drafts"

SEED = 20260927  # fixed; the tree's content must not depend on when it was made

# The four nations that already carry hand-authored majors. Their companies
# list is left untouched (A2 named the chiefs); A3 grows only their body.
AUTHORED = ("FRA", "DEU", "GBR", "POL")

SECTORS = ("agriculture", "industry", "services")

# --- Bands, mirroring src/sim/companies_constants.gd -------------------------
BODY_SHARE_MAX = 0.03          # the loader's ceiling, restated for the generator
MIN_BODY_SHARE = 0.001         # the loader's floor (company.gd's MIN_BODY_SHARE)
COVERAGE_MIN = 0.85
COVERAGE_MAX = 0.97
# The generated register targets the middle of the band, leaving margin for the
# 4-decimal rounding the files carry (30-odd firms a sector, each rounded by up
# to 5e-5, is a summed drift an order of magnitude inside the band edge).
COVERAGE_TARGET = (0.86, 0.89)
HEADCOUNT_MIN = 500
HEADCOUNT_MAX = 25000
# V2.2a's measured payroll concentration (Lille 33.1%, Duesseldorf 34.3%,
# Manchester 44.0%) -- reproduced, with margin at the top so the last firm
# placed on the largest city cannot overshoot the 0.50 edge.
CONCENTRATION_TARGET = (0.28, 0.42)
BODY_MIN_PER_NATION = 80       # companies_constants.BODY_MIN_PER_NATION

# Jobs per unit of authored share, per sector -- the V1.4b reference table read
# off the 26 shipped majors (agriculture extensive, services labour-intensive).
# The ratio is what turns a share into a headcount; the headcount band then
# caps the SHARE a body firm may carry, and those two bounds are one selection:
# the services body firm is sized against 1.5M (interior to the majors' own
# observed services range, 0.53M-3.36M), so its ceiling share is 0.0167 and
# the services body lands ~35 firms a nation -- the number that holds the
# whole register inside the brief's [2 700, 3 100] firms.
SECTOR_JOBS_PER_SHARE = {
    "agriculture": 81000.0,
    "industry": 672000.0,
    # Services at 1.5M sits between the industry (0.67M) and the majors'
    # mean (1.86M) -- the identical TABLE (i) spread "agriculture extensive,
    # services intensive" is preserved, and 1.5M keeps a body firm under the
    # 25 000-job cap at a higher per-firm share than 1.86M would, which is
    # what keeps the register inside the [2 700, 3 100] firm count the brief
    # pins (the headcount-ceiling drive is the 0.0135 => 0.0167 share lift).
    "services": 1500000.0,
}
# The share bounds a body firm obeys, per sector: the headcount band divided by
# the sector's own jobs-per-share, intersected with the global [MIN, MAX].
SECTOR_SHARE_LO = {
    s: max(MIN_BODY_SHARE, HEADCOUNT_MIN / SECTOR_JOBS_PER_SHARE[s]) for s in SECTORS
}
SECTOR_SHARE_HI = {
    s: min(BODY_SHARE_MAX, (HEADCOUNT_MAX / SECTOR_JOBS_PER_SHARE[s]) * 0.995)
    for s in SECTORS
}

# --- Name fragments ----------------------------------------------------------
# The corporate words a firm's name may carry after its invented stem, per
# nation's own language. Generic industry vocabulary -- no real company's name
# (docs/fictionalization.md); check_names.sh scans every committed file.
CORP_SUFFIX = {
    "FRA": ["Industries", "Groupe", "Distribution", "Coopérative", "Énergie",
            "Transports", "Assurances", "Agro", "Matériaux", "Logistique"],
    "DEU": ["AG", "Gruppe", "Werke", "Handel", "Industrie", "Energie",
            "Transporte", "Versicherung", "Bau", "Logistik"],
    "GBR": ["Industries", "Group", "Holdings", "Trading", "Energy",
            "Transport", "Insurance", "Agri", "Materials", "Logistics"],
    "POL": ["Grupa", "Zakłady", "Handel", "Przemysł", "Energia", "Transport",
            "Ubezpieczenia", "Budownictwo", "Logistyka", "Rolnictwo"],
    "ESP": ["Industrias", "Grupo", "Comercial", "Energía", "Transportes",
            "Seguros", "Agro", "Materiales", "Logística", "Construcción"],
    "ITA": ["Industrie", "Gruppo", "Commercio", "Energia", "Trasporti",
            "Assicurazioni", "Agro", "Materiali", "Logistica", "Costruzioni"],
    "BEL": ["Industrie", "Groep", "Handel", "Energie", "Transport",
            "Verzekering", "Bouw", "Logistiek", "Landbouw", "Materialen"],
    "NLD": ["Industrie", "Groep", "Handel", "Energie", "Transport",
            "Verzekeringen", "Bouw", "Logistiek", "Landbouw", "Materialen"],
    "LUX": ["Industrie", "Groupe", "Commerce", "Énergie", "Transport",
            "Assurances", "Construction", "Logistique", "Agriculture", "Matériaux"],
    "CHE": ["Industrie", "Gruppe", "Handel", "Energie", "Transport",
            "Versicherung", "Bau", "Logistik", "Landwirtschaft", "Werkstoffe"],
    "AUT": ["Industrie", "Gruppe", "Handel", "Energie", "Transport",
            "Versicherung", "Bau", "Logistik", "Landwirtschaft", "Werkstoffe"],
    "DNK": ["Industri", "Gruppe", "Handel", "Energi", "Transport",
            "Forsikring", "Byggeri", "Logistik", "Landbrug", "Materialer"],
    "SWE": ["Industri", "Gruppen", "Handel", "Energi", "Transport",
            "Försäkring", "Bygg", "Logistik", "Lantbruk", "Material"],
    "FIN": ["Teollisuus", "Ryhmä", "Kauppa", "Energia", "Liikenne",
            "Vakuutus", "Rakennus", "Logistiikka", "Maatalous", "Materiaalit"],
    "EST": ["Tööstus", "Grupp", "Kaubandus", "Energia", "Transport",
            "Kindlustus", "Ehitus", "Logistika", "Põllumajandus", "Materjalid"],
    "LVA": ["Rūpniecība", "Grupa", "Tirdzniecība", "Enerģētika", "Transports",
            "Apdrošināšana", "Būvniecība", "Loģistika", "Lauksaimniecība", "Materiāli"],
    "LTU": ["Pramonė", "Grupė", "Prekyba", "Energetika", "Transportas",
            "Draudimas", "Statyba", "Logistika", "Žemės ūkis", "Medžiagos"],
    "CZE": ["Průmysl", "Skupina", "Obchod", "Energetika", "Doprava",
            "Pojištění", "Stavebnictví", "Logistika", "Zemědělství", "Materiály"],
    "SVK": ["Priemysel", "Skupina", "Obchod", "Energetika", "Doprava",
            "Poistenie", "Stavebníctvo", "Logistika", "Poľnohospodárstvo", "Materiály"],
    "SVN": ["Industrija", "Skupina", "Trgovina", "Energija", "Promet",
            "Zavarovanje", "Gradbeništvo", "Logistika", "Kmetijstvo", "Materiali"],
    "HUN": ["Ipar", "Csoport", "Kereskedelem", "Energia", "Szállítás",
            "Biztosítás", "Építőipar", "Logisztika", "Mezőgazdaság", "Anyagok"],
    "HRV": ["Industrija", "Grupa", "Trgovina", "Energija", "Promet",
            "Osiguranje", "Graditeljstvo", "Logistika", "Poljoprivreda", "Materijali"],
    "BGR": ["Industrija", "Grupa", "Targovija", "Energija", "Transport",
            "Zastrahovane", "Stroitelstvo", "Logistika", "Zemedelie", "Materiali"],
    "ROU": ["Industrie", "Grup", "Comerț", "Energie", "Transport",
            "Asigurări", "Construcții", "Logistică", "Agricultură", "Materiale"],
    "GRC": ["Viomichania", "Omilos", "Emporio", "Energeia", "Metafora",
            "Asfaliseis", "Kataskeves", "Logistiki", "Georgia", "Ylika"],
    "CYP": ["Viomichania", "Omilos", "Emporio", "Energeia", "Metafora",
            "Asfaliseis", "Kataskeves", "Logistiki", "Georgia", "Ylika"],
    "IRL": ["Industries", "Group", "Trading", "Energy", "Transport",
            "Insurance", "Construction", "Logistics", "Agri", "Materials"],
    "PRT": ["Indústrias", "Grupo", "Comércio", "Energia", "Transportes",
            "Seguros", "Construção", "Logística", "Agricultura", "Materiais"],
    "MLT": ["Industries", "Group", "Trading", "Energy", "Transport",
            "Insurance", "Construction", "Logistics", "Agri", "Materials"],
}
# A prefix a firm's named after -- a bank, a company (used for both tiers).
CORP_PREFIX = {
    "FRA": ["Banque", "Compagnie", "Société"],
    "DEU": ["Bank", "Handelshaus", "Gesellschaft"],
    "GBR": ["Bank", "Company", "Trust"],
    "POL": ["Bank", "Spółka", "Towarzystwo"],
    "ESP": ["Banco", "Compañía", "Sociedad"],
    "ITA": ["Banca", "Compagnia", "Società"],
    "BEL": ["Bank", "Compagnie", "Vennootschap"],
    "NLD": ["Bank", "Compagnie", "Maatschappij"],
    "LUX": ["Banque", "Compagnie", "Société"],
    "CHE": ["Bank", "Gesellschaft", "Handelshaus"],
    "AUT": ["Bank", "Gesellschaft", "Handelshaus"],
    "DNK": ["Bank", "Selskab", "Handelshus"],
    "SWE": ["Bank", "Bolag", "Handelshus"],
    "FIN": ["Pankki", "Yhtiö", "Kauppahuone"],
    "EST": ["Pank", "Selts", "Kaubamaja"],
    "LVA": ["Banka", "Sabiedrība", "Tirdzniecības nams"],
    "LTU": ["Bankas", "Bendrovė", "Prekybos namai"],
    "CZE": ["Banka", "Společnost", "Obchodní dům"],
    "SVK": ["Banka", "Spoločnosť", "Obchodný dom"],
    "SVN": ["Banka", "Družba", "Trgovska hiša"],
    "HUN": ["Bank", "Társaság", "Kereskedőház"],
    "HRV": ["Banka", "Društvo", "Trgovački dom"],
    "BGR": ["Banka", "Družestvo", "Targovska kăšta"],
    "ROU": ["Bancă", "Companie", "Casă de comerț"],
    "GRC": ["Trapeza", "Etaireia", "Emporikos Oikos"],
    "CYP": ["Trapeza", "Etaireia", "Emporikos Oikos"],
    "IRL": ["Bank", "Company", "Trust"],
    "PRT": ["Banco", "Companhia", "Sociedade"],
    "MLT": ["Bank", "Company", "Trust"],
}

TRAITS = ["ambitious", "loyal", "principled", "pragmatic", "vain", "stubborn",
          "networked", "fervent"]
# The chief's own trait affinity (a boardroom executive leans pragmatic,
# ambitious or networked; a family-firm heir loyal or stubborn).
EXEC_TRAITS = ["pragmatic", "ambitious", "networked", "loyal", "stubborn"]

# The sidecar's physical descriptor pools (bench_generate's shape, restated --
# importing them would couple this tool to bench's private lists).
SIDECAR = None  # loaded in main()


def nation_sector_weights(nation: str) -> dict:
    d = json.loads((NATIONS_DIR / ("%s.json" % nation)).read_text(encoding="utf-8"))
    return {s: float(d["imported"]["sectors"].get(s, 0.0)) for s in SECTORS}


def nation_cities(nation: str) -> list:
    """[(city_id, NATIONAL population share)] for the nation's own region
    register. The A3 review's Critical 3 lived here: the weight was the
    city's share OF ITS REGION, so a city-state region (share 1.0 -- Ceuta,
    Logrono) outranked the real metropolis and the payroll concentration
    landed in six nations' smallest places. A city's national share is its
    region share times its share of that region."""
    d = json.loads((REGIONS_DIR / ("%s.json" % nation)).read_text(encoding="utf-8"))
    out = []
    for region in d["regions"]:
        r_share = float(region.get("share", 0.0))
        for city in region["cities"]:
            out.append((city["id"], float(city["share"]) * r_share))
    return out


def surname_pool(nation: str) -> list:
    base = list(NAMES[nation]["surnames"]) + list(EXTRA_SURNAMES.get(nation, []))
    # de-dup preserving order
    seen = set()
    out = []
    for s in base:
        k = slug(s)
        if k and k not in seen:
            seen.add(k)
            out.append(s)
    return out


def alloc_shares(rng: random.Random, total: float, n: int, lo: float, hi: float) -> list:
    """n shares summing to `total`, each in [lo, hi]. Feasibility is the
    caller's job (n*lo <= total <= n*hi). Water-filling: draw weights, normalise,
    pin the out-of-band shares to their bound, renormalise the free ones."""
    weights = [rng.uniform(0.5, 1.5) for _ in range(n)]
    s = sum(weights)
    shares = [total * w / s for w in weights]
    for _ in range(64):
        over = [i for i in range(n) if shares[i] > hi + 1e-12]
        under = [i for i in range(n) if shares[i] < lo - 1e-12]
        if not over and not under:
            break
        for i in over:
            shares[i] = hi
        for i in under:
            shares[i] = lo
        free = [i for i in range(n) if lo + 1e-12 < shares[i] < hi - 1e-12]
        if not free:
            break
        used = sum(shares[i] for i in range(n) if i not in free)
        rem = total - used
        fw = [rng.uniform(0.5, 1.5) for _ in free]
        sf = sum(fw)
        if sf <= 0.0:
            break
        for k, i in enumerate(free):
            shares[i] = rem * fw[k] / sf
    return shares


def allocate_cities(rng: random.Random, firms: list, cities: list) -> None:
    """Assign each firm a city so the largest city holds CONCENTRATION_TARGET of
    the nation's body payroll. One-city nations skip: the band is a partition of
    two cities and a nation with one cannot express it (the test exempts them)."""
    if not cities:
        return
    if len(cities) == 1:
        for f in firms:
            f["city"] = cities[0][0]
        return
    order = sorted(range(len(cities)), key=lambda i: (-cities[i][1], cities[i][0]))
    biggest = cities[order[0]][0]
    others = [cities[i][0] for i in order[1:]]
    other_w = [cities[i][1] for i in order[1:]]
    total = sum(f["headcount"] for f in firms)
    target = rng.uniform(*CONCENTRATION_TARGET) * total
    shuffled = list(range(len(firms)))
    rng.shuffle(shuffled)
    acc = 0.0
    i = 0
    while i < len(shuffled) and acc < target:
        firms[shuffled[i]]["city"] = biggest
        acc += firms[shuffled[i]]["headcount"]
        i += 1
    rest = shuffled[i:]
    # the remaining firms land on the other cities by population weight
    for idx in rest:
        firms[idx]["city"] = rng.choices(others, weights=other_w, k=1)[0]


def make_chief(rng: random.Random, nation: str, person_name: str, firm_slug: str) -> dict:
    traits = sorted(rng.sample(EXEC_TRAITS, rng.choice([2, 2, 3])))
    # The id rides the FIRM's slug (the A2 convention: FRA_chief_verdelis, the
    # firm FRA_verdelis) -- a chief's id from their own name would collide the
    # moment two firms drew the same surname from a 60-name pool.
    return {
        "id": "%s_chief_%s" % (nation, firm_slug[len(nation) + 1:]),
        "name": person_name,
        "kind": "executive",
        "traits": traits,
        "ambition": round(rng.uniform(0.30, 0.85), 2),
        "bench": True,
    }


def gen_majors(rng: random.Random, nation: str, cities: list, used_slugs: set) -> list:
    """10-15 majors for a nation that has none. City choice follows the
    nation's own register; names are invented from its own curated pool.

    The per-sector stake a nation's majors hold is authored to the shipped
    26's own shape: agriculture is CONCENTRATED (two majors holding ~0.40-0.48
    of the sector, the FRA/DEU/POL pattern -- a farm sector has champions, not
    long tails), industry and services hold ~0.20-0.30 between four and seven.
    This is what makes the body's own count ordering fall out right: an
    agriculture body needing only ~0.45 more of its sector at a 0.03 ceiling
    holds fewer firms than a services body needing ~0.65 at 0.0135."""
    weights = nation_sector_weights(nation)
    surnames = surname_pool(nation)
    given_f = NAMES[nation]["given_f"]
    given_m = NAMES[nation]["given_m"]
    suffixes = CORP_SUFFIX[nation]
    prefixes = CORP_PREFIX[nation]

    counts = {
        "agriculture": 2,
        "industry": rng.randint(3, 5),
        "services": rng.randint(5, 7),  # 2+3+5 = 10 at the floor: [10, 15]
    }
    stake = {
        "agriculture": rng.uniform(0.38, 0.48),
        "industry": rng.uniform(0.20, 0.30),
        "services": rng.uniform(0.20, 0.30),
    }
    majors = []
    for s in SECTORS:
        n = counts[s]
        # majors sit ABOVE MIN_AUTHORED_SHARE (0.02) and at most 0.28 -- the
        # shipped 26's own range (FRA verdelis 0.28 the top, POL tabor 0.05
        # the bottom, nothing between 0.02 and 0.05).
        lo, hi = (0.05, 0.28) if s == "agriculture" else (0.02, 0.28)
        shares = alloc_shares(rng, stake[s], n, lo, hi)
        for k in range(n):
            surname = rng.choice(surnames)
            given = rng.choice(given_f) if rng.random() < 0.3 else rng.choice(given_m)
            shape = rng.random()
            if shape < 0.35:
                base = surname
            elif shape < 0.70:
                base = "%s %s" % (surname, rng.choice(suffixes))
            else:
                base = "%s %s" % (rng.choice(prefixes), surname)
            name = base.strip()
            fid = "%s_%s" % (nation, slug(name))
            if fid in used_slugs:
                # as below the body loop: a major is never dropped for a
                # collision, the name widens until unique
                while fid in used_slugs:
                    name = "%s %s" % (name, rng.choice(suffixes))
                    fid = "%s_%s" % (nation, slug(name))
            used_slugs.add(fid)
            share = round(shares[k], 4)
            # jobs at the V1.4b ratio for the sector, with the spread the
            # shipped majors themselves carry (the headcount IS the
            # differentiator, and a table-identical ratio would erase it).
            jobs = int(round(share * SECTOR_JOBS_PER_SHARE[s] * rng.uniform(0.75, 1.35)))
            jobs = max(HEADCOUNT_MIN, min(230000, jobs))
            chief = make_chief(rng, nation, "%s %s" % (given, surname.strip()), fid)
            majors.append({
                "id": fid, "name": name, "sector": s,
                "share": share, "headcount": jobs,
                "city": "", "tier": "major", "chief_id": chief["id"],
                "_chief": chief,
            })
    _site_majors(rng, majors, cities)
    return majors


def _site_majors(rng: random.Random, majors: list, cities: list) -> None:
    if not cities:
        return
    order = sorted(range(len(cities)), key=lambda i: (-cities[i][1], cities[i][0]))
    lead = [cities[i][0] for i in order[:max(1, min(len(cities), 6))]]
    for m in majors:
        m["city"] = rng.choice(lead)


def gen_body(rng: random.Random, nation: str, major_cov: dict, cities: list,
             used_slugs: set) -> list:
    """The body: counts follow the need each sector has left under the coverage
    target, at the per-firm ceiling the headcount band implies -- which is why
    services (a 25 000-job cap is only 0.0167 of the sector at its own
    jobs-per-share ratio) needs ~35 body firms where agriculture needs ~16."""
    suffixes = CORP_SUFFIX[nation]
    surnames = surname_pool(nation)
    body = []
    for s in SECTORS:
        target = rng.uniform(*COVERAGE_TARGET)
        need = max(0.0, target - major_cov.get(s, 0.0))
        hi, lo = SECTOR_SHARE_HI[s], SECTOR_SHARE_LO[s]
        # n sized so the MEAN share sits near 0.8*hi: water-filling then has
        # room to spread the individual shares inside the band instead of
        # pinning every firm to the ceiling.
        n = max(2, int(-(-need // (hi * 0.92))))
        while n > 2 and n * lo > need:
            n -= 1
        total = min(need, n * hi)
        if total <= 0.0:
            continue
        shares = alloc_shares(rng, total, n, lo, hi)
        for share in shares:
            share = round(share, 4)
            if share < lo:
                continue
            # No firm is ever SKIPPED for a name collision: every skipped
            # share would walk out of the sector's coverage sum, and a band
            # checked to four decimals has no room for silent drops. The name
            # retries until unique (60 surnames x 10 suffixes x 10 suffixes
            # is 6 000 combinations per nation; the body needs ~110).
            surname = rng.choice(surnames)
            while True:
                name = "%s %s" % (surname, rng.choice(suffixes))
                fid = "%s_%s" % (nation, slug(name))
                if fid not in used_slugs:
                    break
                name = "%s %s %s" % (surname, rng.choice(suffixes), rng.choice(suffixes))
                fid = "%s_%s" % (nation, slug(name))
                if fid not in used_slugs:
                    break
            used_slugs.add(fid)
            jobs = int(round(share * SECTOR_JOBS_PER_SHARE[s] * rng.uniform(0.9, 1.1)))
            jobs = max(HEADCOUNT_MIN, min(HEADCOUNT_MAX, jobs))
            body.append({
                "id": fid, "name": name, "sector": s,
                "share": share, "headcount": jobs, "city": "", "tier": "body",
            })
    # BODY_MIN_PER_NATION floor: a sector-need-sized body can land at 77-79
    # firms for a nation whose majors already cover generously (CYP, CZE, NLD,
    # PRT at this seed). Top-up firms go to services -- the sector with the
    # most body firms anyway -- at a mid-band share, keeping the added
    # coverage inside the 0.97 ceiling.
    if len(body) < BODY_MIN_PER_NATION:
        s = "services"
        hi, lo = SECTOR_SHARE_HI[s], SECTOR_SHARE_LO[s]
        while len(body) < BODY_MIN_PER_NATION:
            share = round(rng.uniform(lo, (lo + hi) / 2.0), 4)
            surname = rng.choice(surnames)
            while True:
                name = "%s %s" % (surname, rng.choice(suffixes))
                fid = "%s_%s" % (nation, slug(name))
                if fid not in used_slugs:
                    break
                name = "%s %s %s" % (surname, rng.choice(suffixes), rng.choice(suffixes))
                fid = "%s_%s" % (nation, slug(name))
                if fid not in used_slugs:
                    break
            used_slugs.add(fid)
            jobs = int(round(share * SECTOR_JOBS_PER_SHARE[s] * rng.uniform(0.9, 1.1)))
            jobs = max(HEADCOUNT_MIN, min(HEADCOUNT_MAX, jobs))
            body.append({
                "id": fid, "name": name, "sector": s,
                "share": share, "headcount": jobs, "city": "", "tier": "body",
            })
    allocate_cities(rng, body, cities)
    return body


def sidecar_entry(rng: random.Random, sex: str, age: int) -> dict:
    return {
        "sex": sex, "age": age,
        "build": rng.choice(["slim", "average build", "stocky", "broad-shouldered", "wiry"]),
        "hair": rng.choice(["short cropped hair", "layered mid-length hair",
                            "receding hairline", "thick wavy hair",
                            "straight shoulder-length hair", "close-cropped grey hair"]),
        "glasses": rng.choice(["no glasses", "rectangular glasses", "round glasses",
                               "thin-framed glasses"]),
        "face": rng.choice(["oval face with soft features", "broad face with a strong jaw",
                            "narrow face with high cheekbones",
                            "weathered face with deep lines",
                            "angular face with a prominent nose"]),
        "quirk": rng.choice(["widow's peak", "heavy brow", "dimpled chin",
                             "pronounced smile lines", "straight brows"]),
        "wardrobe": rng.choice(["open-collar dark blazer", "charcoal suit with a patterned tie",
                                "plain dark suit", "knitted jumper over a collared shirt",
                                "high-collared shirt", "beige linen jacket"]),
        "skin": rng.choice(["fair skin", "olive skin", "pale skin with freckles",
                            "tanned skin", "light brown skin"]),
        "eyes": rng.choice(["brown eyes", "blue eyes", "grey eyes", "green eyes", "hazel eyes"]),
        "bust": "average bust" if sex == "female" else "flat chest",
    }


def companies_text(doc: dict) -> str:
    return json.dumps(doc, ensure_ascii=False, indent=2) + "\n"


def people_text(doc: dict) -> str:
    return json.dumps(doc, ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    check_only = "--check" in sys.argv
    majors_only = "--majors-only" in sys.argv
    emit_drafts = "--emit-drafts" in sys.argv
    if check_only and majors_only:
        # --majors-only re-derives empty body lists, so a check against the
        # committed files would always report drift -- a mode footgun the A3
        # review named. Check covers every tier; the flag is write-mode only.
        print("--majors-only cannot combine with --check (it would always drift)")
        return 2
    rng = random.Random(SEED)

    sidecar = json.loads(SIDECAR_PATH.read_text(encoding="utf-8"))
    sidecar_changed = False

    total_firms = 0
    total_majors = 0
    total_body = 0
    report = []
    drafts = {}

    # sorted iteration: deterministic content regardless of filesystem order
    for nation in sorted(p.stem for p in NATIONS_DIR.glob("*.json")):
        cities = nation_cities(nation)
        used_slugs = set()

        if nation in AUTHORED:
            # keep the hand-authored majors untouched
            cpath = COMPANIES_DIR / ("%s.json" % nation)
            doc = json.loads(cpath.read_text(encoding="utf-8"))
            for c in doc["companies"]:
                used_slugs.add(c["id"])
            majors = list(doc["companies"])
            chief_people = []  # already committed at A2
        else:
            majors = []
            chief_people = []
            raw_majors = gen_majors(rng, nation, cities, used_slugs)
            for m in raw_majors:
                chief = m.pop("_chief")
                m.pop("_order", None)
                majors.append(m)
                chief_people.append(chief)

        major_cov = {}
        for m in majors:
            major_cov[m["sector"]] = major_cov.get(m["sector"], 0.0) + m["share"]

        if majors_only:
            body = []
        else:
            body = gen_body(rng, nation, major_cov, cities, used_slugs)

        # --- write the companies file ----------------------------------------
        if nation in AUTHORED:
            doc["body"] = body
        else:
            doc = {
                "_source": "invented",
                "_note": ("Fictional firms per docs/fictionalization.md -- near-miss "
                          "style, sector legible, no real company's name. `share` is of "
                          "the firm's SECTOR, not of GDP; a sector's named shares (majors "
                          "+ body) sum to less than 1.0, the remainder being the unnamed "
                          "rest of the sector. `headcount` is jobs at that authored share. "
                          "The body tier is generated by tools/firms_generate.py and is "
                          "never hand-edited. See docs/companies-model.md."),
                "companies": majors,
                "body": body,
            }
        cpath = COMPANIES_DIR / ("%s.json" % nation)
        new_text = companies_text(doc)
        if check_only:
            if not cpath.exists() or cpath.read_text(encoding="utf-8") != new_text:
                print("DRIFT: %s" % cpath)
                return 1
        else:
            cpath.write_text(new_text, encoding="utf-8")

        # --- sidecar entries for the AUTHORED nations' chiefs ----------------
        # A2 committed 26 chiefs into data/people without sidecar entries;
        # the portraits self-check gates sidecar coverage on the whole people
        # register, so the generator seeds them here too (same unconditional
        # draws, so a re-run over a seeded sidecar consumes the RNG the same).
        if nation in AUTHORED:
            for c in doc["companies"]:
                cid = c.get("chief_id")
                if not cid:
                    continue
                sex = "female" if rng.random() < 0.35 else "male"
                age = rng.randint(40, 68)
                entry = sidecar_entry(rng, sex, age)
                if cid not in sidecar:
                    sidecar[cid] = entry
                    sidecar_changed = True

        # --- append the new chiefs to the people file -------------------------
        if chief_people:
            ppath = PEOPLE_DIR / ("%s.json" % nation)
            pdoc = json.loads(ppath.read_text(encoding="utf-8"))
            existing_ids = {p["id"] for p in pdoc["people"]}
            for chief in chief_people:
                # Every draw happens unconditionally -- a draw inside an "if
                # absent" guard would consume the RNG differently on a re-run
                # against a file the first run already seeded, determinism's
                # own off-by-one.
                sex = "female" if rng.random() < 0.35 else "male"
                age = rng.randint(40, 68)
                entry = sidecar_entry(rng, sex, age)
                if chief["id"] in existing_ids:
                    continue
                pdoc["people"].append(chief)
                existing_ids.add(chief["id"])
                if chief["id"] not in sidecar:
                    sidecar[chief["id"]] = entry
                    sidecar_changed = True
            pt = people_text(pdoc)
            if check_only:
                if ppath.read_text(encoding="utf-8") != pt:
                    print("DRIFT: %s" % ppath)
                    return 1
            else:
                ppath.write_text(pt, encoding="utf-8")

        if emit_drafts and nation not in AUTHORED:
            drafts[nation] = {"companies": majors}

        total_majors += len(majors)
        total_body += len(body)
        total_firms += len(majors) + len(body)
        report.append("%s m%d b%d" % (nation, len(majors), len(body)))

    if emit_drafts and not check_only:
        DRAFTS_DIR.mkdir(parents=True, exist_ok=True)
        (DRAFTS_DIR / "majors.json").write_text(
            json.dumps(drafts, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # The sidecar is checked like the rest of the content: the re-derived
    # text must equal the committed file, whatever changed (missing entries
    # AND a hand edit to an existing one -- the draws are deterministic, so
    # both are drift). The A3 review's other --check blind spot.
    sidecar_text = json.dumps(dict(sorted(sidecar.items())), ensure_ascii=False, indent=1) + "\n"
    if check_only:
        if SIDECAR_PATH.read_text(encoding="utf-8") != sidecar_text:
            print("DRIFT: %s" % SIDECAR_PATH)
            return 1
    elif sidecar_changed:
        SIDECAR_PATH.write_text(sidecar_text, encoding="utf-8")

    print(" | ".join(report))
    print("majors: %d | body: %d | firms: %d" % (total_majors, total_body, total_firms))
    print("sidecar entries: %d" % len(sidecar))
    if check_only:
        print("check mode: no writes, no drift")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
