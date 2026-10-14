#!/usr/bin/env python3
"""tools/law_lint.py -- V4.2 T7: the statute book's authoring linter.

The loader (src/core/data_loader.gd -> Law.from_dict) already refuses a
malformed law at boot; this tool re-runs those same checks in Python -- two
implementations of one schema, the belt-and-braces the V4.3 orphan rule
learned -- and then applies the SPREAD discipline the loader cannot see,
because the loader reads one law at a time and spread is a property of the
book.

Modes (the tools/firms_generate.py shape: mode flags, no config):
  python tools/law_lint.py           # full report: tables printed, exit 1 on any failure
  python tools/law_lint.py --check   # CI-shaped: failures only, same exit contract
  python tools/law_lint.py --theme tax   # focus the spread tables on one theme

THE BANDS, DECLARED BEFORE ANY OF THE 79 NEW LAWS WERE WRITTEN (the
discipline: bands into the header first, content second, so the content is
written against the band and not the band against the content):

  TOTAL        the whole book carries 118..122 laws across data/laws/*.json.
  MAGNITUDE    every authored |bloc_offset| in [0.04, 0.40]. The register the
               existing 42 span -- farm_standards' rural -0.04 up to
               retirement_age_reform's pensioners -0.35 -- restated as a band,
               so a new entry cannot quietly invent a new scale.
  THEME SPREAD per theme, over every bloc_offset magnitude the theme carries,
               mean(|v|) / max(|v|) in [0.2, 0.8]. Below 0.2 one law shouts
               and the rest whisper -- a theme whose price is one extreme
               entry. Above 0.8 no lever in the theme is louder than any
               other, which is uniformity, not spread.
  CENTROID     per theme, |mean(position.economic)| <= 0.6 and
               |mean(position.social)| <= 0.6. A theme whose whole book sits
               in one corner of the two-axis space is a faction's shopping
               list, not a statute book. The centre is not required -- a
               centred theme is as suspect as a cornered one -- only that the
               book is not pinned.
  SIGN COVERAGE per bloc across the WHOLE book: at least one law helps it and
               at least one hurts it, no exceptions declared. Real laws have
               losers, and different laws' losers differ; a bloc that is only
               ever hurt (or only ever paid) is an authored faction, not an
               electorate.
  SCHEMA       the loader's own checks, re-derived here: ids unique and
               snake_case, themes valid, positions in range, effect keys and
               enums valid, the three anti-double-count pairs, majority/
               constitutional coherence, the preconditions whitelist with
               unrest_pct >=-only, authored entries carrying none of the
               runtime-only fields (repeals/composed/new_tax/origin).
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAWS_DIR = ROOT / "data" / "laws"
SYSTEMS_DIR = ROOT / "data" / "political-systems"

# --- The schema's own vocabulary, restated from src/ -------------------------
# law.gd THEME_KEYS
THEME_KEYS = ["tax", "labour", "social", "institutional", "business"]
# economy_constants TAX_KEYS / SPENDING_KEYS / SECTOR_TREND
TAX_KEYS = ["income", "corporate", "vat", "capital_gains", "wealth"]
SPENDING_KEYS = ["health", "education", "defence", "pensions", "infrastructure"]
SECTORS = ["agriculture", "industry", "services"]
# opinion_constants BLOC_KEYS
BLOC_KEYS = ["workers", "pensioners", "urban", "rural", "business", "students"]
# legislature_constants MAJORITY_KEYS / PRECONDITION_FIELDS / PRECONDITION_OPS
MAJORITY_KEYS = ["simple", "absolute", "two_thirds", "amendment"]
PRECONDITION_FIELDS = [
    "debt_to_gdp_pct", "unemployment_pct", "deficit_pct_gdp",
    "overall_approval_pct", "growth_annual_pct", "terms_served",
    "unrest_pct", "co2e_per_capita_t", "eu_member",
]
PRECONDITION_OPS = ["<", "<=", ">", ">=", "=="]
# law.gd SCALAR_EFFECT_KEYS / SHARED_EFFECT_CHANNELS
SCALAR_EFFECT_KEYS = [
    "structural_unemployment_pct", "potential_growth_pct", "other_revenue_pct_gdp",
]
SHARED_EFFECT_CHANNELS = [
    "tax_rates_pct", "spending_pct_gdp", "bloc_offset", "company", "society",
]
EFFECT_CHANNELS = SHARED_EFFECT_CHANNELS + SCALAR_EFFECT_KEYS + ["institutional"]
# law.gd SOCIETY_TERMS
SOCIETY_TERMS = ["corruption", "migration", "settlement", "press_freedom",
                 "judicial_independence"]
# nation.gd KNOWN_ELECTION_SYSTEMS / KNOWN_HEAD_OF_STATE_KINDS, and the
# entrenched-only institutional keys law.gd gates behind constitutional: true.
ELECTION_SYSTEMS = ["pr_dhondt", "pr_national", "fptp", "two_round", "parallel"]
HEAD_OF_STATE_KINDS = ["hereditary_monarch", "elected_president",
                       "executive_president", "collegial"]
ENTRENCHED_INSTITUTIONAL_KEYS = [
    "censure_rule", "dissolution_rule", "formation_method", "amendment_rule",
    "term_limit", "term_months", "system_id", "head_of_state",
]
KNOWN_CENSURE_RULES = ["simple_present", "constructive_absolute",
                       "absolute_members", "none"]
KNOWN_DISSOLUTION_RULES = ["confidence_failure", "executive_discretion",
                           "self_dissolution", "head_of_state_limited", "none"]
KNOWN_FORMATION_METHODS = ["largest_party", "coalition_negotiation",
                           "investiture", "chancellor_election",
                           "presidential_appointment", "directorial"]
KNOWN_AMENDMENT_RULES = ["ordinary_law", "three_fifths", "two_thirds",
                         "three_quarters", "referendum_required"]
RULE_ENUMS = {
    "censure_rule": KNOWN_CENSURE_RULES,
    "dissolution_rule": KNOWN_DISSOLUTION_RULES,
    "formation_method": KNOWN_FORMATION_METHODS,
    "amendment_rule": KNOWN_AMENDMENT_RULES,
}
# Runtime-only fields from_dict() never reads: authored content cannot claim
# them (law.gd's own docstrings say so on repeals/composed/new_tax/origin).
RUNTIME_ONLY_FIELDS = ["repeals", "composed", "new_tax", "origin"]
# A system transition must write the whole institutional state -- law.gd
# SYSTEM_CHANGE_REQUIRED_KEYS, plus head_of_state checked separately there.
SYSTEM_CHANGE_REQUIRED_KEYS = [
    "formation_method", "censure_rule", "dissolution_rule", "amendment_rule",
    "term_limit", "head_of_state",
]

# --- The bands (see the module docstring; restated as code) ------------------
TOTAL_MIN, TOTAL_MAX = 118, 122
OFFSET_MAG_MIN, OFFSET_MAG_MAX = 0.04, 0.40
SPREAD_MIN, SPREAD_MAX = 0.2, 0.8
CENTROID_MAX = 0.6
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class Report:
    """Failures accumulate; the exit code is theirs, the tables are printed either way."""

    def __init__(self, check_mode: bool):
        self.check_mode = check_mode
        self.failures: list = []

    def fail(self, msg: str) -> None:
        self.failures.append(msg)

    def note(self, msg: str) -> None:
        if not self.check_mode:
            print(msg)


def is_number(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def load_laws(rep: Report):
    """Every data/laws/*.json -> list of (filename, entry-dict). Top-level
    underscore-prefixed keys are file comments, the institutional.json shape."""
    files = sorted(LAWS_DIR.glob("*.json"))
    if not files:
        rep.fail("no data/laws/*.json files found")
        return []
    out = []
    for path in files:
        try:
            parsed = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            rep.fail("%s: unreadable or invalid JSON (%s)" % (path.name, e))
            continue
        if not isinstance(parsed, dict) or not isinstance(parsed.get("laws"), list):
            rep.fail("%s: invalid law file, expected {\"laws\": [...]}" % path.name)
            continue
        for i, entry in enumerate(parsed["laws"]):
            if not isinstance(entry, dict):
                rep.fail("%s: laws[%d] is not an object" % (path.name, i))
                continue
            out.append((path.name, entry))
    return out


def check_schema(fname: str, law: dict, rep: Report, seen_ids: dict,
                 system_ids: set) -> None:
    lid = law.get("id", "")
    where = "%s: %s" % (fname, lid or "<no id>")

    if not isinstance(lid, str) or not lid:
        rep.fail("%s: laws entry missing non-empty string 'id'" % fname)
        lid = "<no id>"
    elif not ID_PATTERN.match(lid):
        rep.fail("%s: id '%s' is not snake_case" % (fname, lid))
    if lid in seen_ids:
        rep.fail("%s: duplicate law id '%s' (also in %s)" % (fname, lid, seen_ids[lid]))
    else:
        seen_ids[lid] = fname

    for field in RUNTIME_ONLY_FIELDS:
        if field in law:
            rep.fail("%s: %s carries runtime-only field '%s' -- authored "
                     "content cannot claim it" % (where, lid, field))

    if not isinstance(law.get("name"), str) or not law.get("name"):
        rep.fail("%s: %s missing name" % (where, lid))
    if not isinstance(law.get("summary"), str) or not law.get("summary"):
        rep.fail("%s: %s missing summary" % (where, lid))

    theme = law.get("theme")
    if theme not in THEME_KEYS:
        rep.fail("%s: %s theme must be one of %s" % (where, lid, THEME_KEYS))

    pos = law.get("position")
    if not isinstance(pos, dict) or "economic" not in pos or "social" not in pos:
        rep.fail("%s: %s missing position {economic, social}" % (where, lid))
    else:
        for axis in ("economic", "social"):
            if not is_number(pos[axis]) or not (-1.0 <= float(pos[axis]) <= 1.0):
                rep.fail("%s: %s position.%s out of range [-1, 1]" % (where, lid, axis))

    majority = law.get("majority")
    if majority not in MAJORITY_KEYS:
        rep.fail("%s: %s majority must be one of %s" % (where, lid, MAJORITY_KEYS))
    constitutional = law.get("constitutional", False)
    if not isinstance(constitutional, bool):
        rep.fail("%s: %s constitutional must be a boolean" % (where, lid))
        constitutional = False
    if constitutional and majority != "amendment":
        rep.fail("%s: %s constitutional laws must set majority: 'amendment'" % (where, lid))
    if not constitutional and majority == "amendment":
        rep.fail("%s: %s majority 'amendment' requires constitutional: true" % (where, lid))

    cooldown = law.get("cooldown_months", 0)
    if not isinstance(cooldown, int) or cooldown < 0:
        rep.fail("%s: %s cooldown_months must be an integer >= 0" % (where, lid))
    if not isinstance(law.get("once", False), bool):
        rep.fail("%s: %s once must be a boolean" % (where, lid))

    systems = law.get("systems", [])
    if constitutional:
        if not isinstance(systems, list) or not systems:
            rep.fail("%s: %s constitutional laws must name at least one system"
                     % (where, lid))
        else:
            for sid in systems:
                if sid not in system_ids:
                    rep.fail("%s: %s names system '%s', which has no file in "
                             "data/political-systems/" % (where, lid, sid))
    elif "systems" in law:
        rep.fail("%s: %s 'systems' is only valid on a constitutional law" % (where, lid))

    preconds = law.get("preconditions", [])
    if not isinstance(preconds, list):
        rep.fail("%s: %s preconditions must be an array" % (where, lid))
        preconds = []
    for i, p in enumerate(preconds):
        if not isinstance(p, dict):
            rep.fail("%s: %s preconditions[%d] is not an object" % (where, lid, i))
            continue
        field = p.get("field")
        if field not in PRECONDITION_FIELDS:
            rep.fail("%s: %s preconditions[%d].field '%s' is not a recognised "
                     "field" % (where, lid, i, field))
        if p.get("op") not in PRECONDITION_OPS:
            rep.fail("%s: %s preconditions[%d].op '%s' is not a recognised "
                     "operator" % (where, lid, i, p.get("op")))
        # THE UNREST REGISTER: available() only ever OPENS laws, so unrest may
        # only ever be tested with >= -- a <= would make unrest a gate that
        # takes levers away (legislature_constants.gd, test_unrest.gd).
        if field == "unrest_pct" and p.get("op") != ">=":
            rep.fail("%s: %s preconditions[%d] tests unrest_pct with '%s' -- "
                     "unrest may only ever be >= (" % (where, lid, i, p.get("op")))
        if not is_number(p.get("value")):
            rep.fail("%s: %s preconditions[%d].value missing or not numeric"
                     % (where, lid, i))

    effects = law.get("effects")
    if not isinstance(effects, dict) or not effects:
        rep.fail("%s: %s effects must be a non-empty object" % (where, lid))
        return
    for key in effects:
        if key not in EFFECT_CHANNELS:
            rep.fail("%s: %s effects.%s is not a recognised effect channel"
                     % (where, lid, key))
    for scalar in SCALAR_EFFECT_KEYS:
        if scalar in effects and not is_number(effects[scalar]):
            rep.fail("%s: %s effects.%s must be numeric" % (where, lid, scalar))
    for keyed in ("tax_rates_pct", "spending_pct_gdp", "bloc_offset"):
        if keyed in effects:
            if not isinstance(effects[keyed], dict) or not effects[keyed]:
                rep.fail("%s: %s effects.%s must be a non-empty object" % (where, lid, keyed))
                continue
            known = {"tax_rates_pct": TAX_KEYS, "spending_pct_gdp": SPENDING_KEYS,
                     "bloc_offset": BLOC_KEYS}[keyed]
            for k, v in effects[keyed].items():
                if k not in known:
                    rep.fail("%s: %s effects.%s.%s is not a recognised key"
                             % (where, lid, keyed, k))
                if not is_number(v):
                    rep.fail("%s: %s effects.%s.%s must be numeric" % (where, lid, keyed, k))
    if "company" in effects:
        c = effects["company"]
        if not isinstance(c, dict):
            rep.fail("%s: %s effects.company must be an object" % (where, lid))
        elif c.get("sector") not in SECTORS:
            rep.fail("%s: %s effects.company.sector '%s' is not a recognised "
                     "sector (%s)" % (where, lid, c.get("sector"), SECTORS))
        elif not is_number(c.get("burden")):
            rep.fail("%s: %s effects.company.burden is missing or not numeric"
                     % (where, lid))
        elif float(c["burden"]) == 0.0:
            rep.fail("%s: %s effects.company.burden is 0.0 -- a rule that binds "
                     "nobody is not a rule" % (where, lid))
        for k in c:
            if k not in ("sector", "burden"):
                rep.fail("%s: %s effects.company.%s is not a recognised term"
                         % (where, lid, k))
    if "society" in effects:
        s = effects["society"]
        if not isinstance(s, dict):
            rep.fail("%s: %s effects.society must be an object" % (where, lid))
        else:
            for term, value in s.items():
                if term not in SOCIETY_TERMS:
                    rep.fail("%s: %s effects.society.%s is not a recognised term"
                             % (where, lid, term))
                elif not is_number(value):
                    rep.fail("%s: %s effects.society.%s is not numeric" % (where, lid, term))
                elif float(value) == 0.0:
                    rep.fail("%s: %s effects.society.%s is 0.0 -- a reform that "
                             "changes nothing is not a reform" % (where, lid, term))
            if not s:
                rep.fail("%s: %s effects.society names none of %s" % (where, lid, SOCIETY_TERMS))
    if "institutional" in effects:
        _check_institutional(fname, lid, where, effects["institutional"],
                             constitutional, rep, system_ids)

    # THE THREE ANTI-DOUBLE-COUNT PAIRS (law.gd load errors, re-derived).
    if "company" in effects and "structural_unemployment_pct" in effects:
        rep.fail("%s: %s carries both effects.company and "
                 "effects.structural_unemployment_pct -- one story told twice" % (where, lid))
    if isinstance(effects.get("society"), dict):
        if "corruption" in effects["society"] and "spending_pct_gdp" in effects:
            rep.fail("%s: %s carries both effects.society.corruption and "
                     "effects.spending_pct_gdp -- one story told twice" % (where, lid))
        if "migration" in effects["society"] and "structural_unemployment_pct" in effects:
            rep.fail("%s: %s carries both effects.society.migration and "
                     "effects.structural_unemployment_pct -- one story told twice"
                     % (where, lid))


def _check_institutional(fname, lid, where, inst, constitutional, rep,
                         system_ids) -> None:
    if not isinstance(inst, dict) or not inst:
        rep.fail("%s: %s effects.institutional must be a non-empty object" % (where, lid))
        return
    if inst.get("election_system") is not None:
        if inst["election_system"] not in ELECTION_SYSTEMS:
            rep.fail("%s: %s effects.institutional.election_system must be one "
                     "of %s" % (where, lid, ELECTION_SYSTEMS))
    if "election_threshold_pct" in inst:
        v = inst["election_threshold_pct"]
        if not is_number(v) or not (0.0 <= float(v) <= 20.0):
            rep.fail("%s: %s effects.institutional.election_threshold_pct out of "
                     "range [0, 20]" % (where, lid))
    for key in ENTRENCHED_INSTITUTIONAL_KEYS:
        if key not in inst:
            continue
        if not constitutional:
            rep.fail("%s: %s effects.institutional.%s requires constitutional: "
                     "true" % (where, lid, key))
            continue
        if key in RULE_ENUMS:
            if inst[key] not in RULE_ENUMS[key]:
                rep.fail("%s: %s effects.institutional.%s must be one of %s"
                         % (where, lid, key, RULE_ENUMS[key]))
        elif key in ("term_limit", "term_months"):
            v = inst[key]
            bounds = {"term_limit": (0, 10), "term_months": (12, 120)}[key]
            if not isinstance(v, int) or not (bounds[0] <= v <= bounds[1]):
                rep.fail("%s: %s effects.institutional.%s out of range %s"
                         % (where, lid, key, bounds))
        elif key == "system_id":
            if not isinstance(inst[key], str) or not inst[key]:
                rep.fail("%s: %s effects.institutional.system_id must be a "
                         "non-empty string" % (where, lid))
            else:
                if inst[key] not in system_ids:
                    rep.fail("%s: %s writes system_id '%s', which has no file in "
                             "data/political-systems/" % (where, lid, inst[key]))
                for req in SYSTEM_CHANGE_REQUIRED_KEYS:
                    if req not in inst:
                        rep.fail("%s: %s writes system_id but is missing "
                                 "effects.institutional.%s" % (where, lid, req))
        elif key == "head_of_state":
            h = inst[key]
            if not isinstance(h, dict):
                rep.fail("%s: %s effects.institutional.head_of_state must be an "
                         "object" % (where, lid))
                continue
            if h.get("kind") not in HEAD_OF_STATE_KINDS:
                rep.fail("%s: %s head_of_state.kind '%s' is not a recognised kind"
                         % (where, lid, h.get("kind")))
            if not isinstance(h.get("title"), str) or not h.get("title"):
                rep.fail("%s: %s head_of_state.title is missing or invalid" % (where, lid))
            if "name" in h:
                rep.fail("%s: %s head_of_state.name must not be set -- the holder "
                         "is derived at apply() time" % (where, lid))
            if h.get("kind") == "elected_president":
                ty = h.get("term_years")
                if not isinstance(ty, int) or not (1 <= ty <= 10):
                    rep.fail("%s: %s head_of_state.term_years out of range [1, 10]"
                             % (where, lid))
            elif "term_years" in h:
                rep.fail("%s: %s head_of_state.term_years must not be set for "
                         "kind '%s'" % (where, lid, h.get("kind")))
    if "system_id" in inst and "head_of_state" not in inst:
        rep.fail("%s: %s writes system_id but is missing "
                 "effects.institutional.head_of_state" % (where, lid))
    if "head_of_state" in inst and "system_id" not in inst:
        rep.fail("%s: %s effects.institutional.head_of_state is only valid "
                 "alongside system_id" % (where, lid))


def check_spread(themed: dict, rep: Report, focus: str) -> None:
    """The discipline the loader cannot see: magnitude, per-theme spread,
    per-theme centroid, whole-book per-bloc sign coverage."""
    all_offsets = {b: [] for b in BLOC_KEYS}

    rep.note("")
    rep.note("per-theme bloc_offset spread (mean(|v|)/max(|v|) in "
             "[%.1f, %.1f]), centroid (|mean| <= %.1f):" % (SPREAD_MIN, SPREAD_MAX, CENTROID_MAX))
    rep.note("  %-14s %5s %6s %6s %7s %7s %8s  %s" %
             ("theme", "laws", "n_off", "max", "mean", "ratio", "econ_c", "soc_c"))

    for theme in THEME_KEYS:
        laws = themed.get(theme, [])
        if focus and theme != focus:
            continue
        mags = []
        econ_sum = soc_sum = 0.0
        n = 0
        for _, law in laws:
            n += 1
            pos = law.get("position", {})
            econ_sum += float(pos.get("economic", 0.0))
            soc_sum += float(pos.get("social", 0.0))
            off = law.get("effects", {}).get("bloc_offset", {})
            if not isinstance(off, dict):
                continue
            for bloc, v in off.items():
                if is_number(v):
                    mags.append(abs(float(v)))
                    all_offsets[bloc].append(float(v))
        if n == 0:
            rep.fail("theme '%s' has no laws" % theme)
            continue
        centroid_e = econ_sum / n
        centroid_s = soc_sum / n
        if not mags:
            rep.note("  %-14s %5d %6d %6s %6s %7s %8.3f  %.3f" %
                     (theme, n, 0, "-", "-", "-", centroid_e, centroid_s))
            rep.fail("theme '%s' carries no bloc_offset anywhere" % theme)
            continue
        mmax = max(mags)
        mmean = sum(mags) / len(mags)
        ratio = mmean / mmax if mmax > 0 else 0.0
        rep.note("  %-14s %5d %6d %6.2f %6.3f %7.3f %8.3f  %.3f" %
                 (theme, n, len(mags), mmax, mmean, ratio, centroid_e, centroid_s))
        if mmax > OFFSET_MAG_MAX or (mags and min(mags) < OFFSET_MAG_MIN):
            bad = [m for m in mags if m < OFFSET_MAG_MIN or m > OFFSET_MAG_MAX]
            rep.fail("theme '%s': %d bloc_offset magnitude(s) outside "
                     "[%.2f, %.2f]: %s" % (theme, len(bad), OFFSET_MAG_MIN,
                                           OFFSET_MAG_MAX, sorted(bad)[:6]))
        if not (SPREAD_MIN <= ratio <= SPREAD_MAX):
            rep.fail("theme '%s': spread ratio %.3f outside [%.1f, %.1f] "
                     "(mean %.3f / max %.2f)" % (theme, ratio, SPREAD_MIN,
                                                 SPREAD_MAX, mmean, mmax))
        if abs(centroid_e) > CENTROID_MAX or abs(centroid_s) > CENTROID_MAX:
            rep.fail("theme '%s': position centroid (%.3f, %.3f) outside "
                     "[-%.1f, %.1f] on an axis" % (theme, centroid_e,
                                                   centroid_s, CENTROID_MAX))

    rep.note("")
    rep.note("per-bloc sign coverage across the whole book "
             "(each bloc helped somewhere and hurt somewhere):")
    for bloc in BLOC_KEYS:
        vals = all_offsets[bloc]
        pos = sum(1 for v in vals if v > 0)
        neg = sum(1 for v in vals if v < 0)
        rep.note("  %-10s +ve %3d  -ve %3d" % (bloc, pos, neg))
        if pos == 0 or neg == 0:
            rep.fail("bloc '%s' is one-signed across the whole book "
                     "(+%d/-%d) -- a bloc only ever hurt, or only ever paid, "
                     "is an authored faction" % (bloc, pos, neg))


def main() -> int:
    ap = argparse.ArgumentParser(description="Authoring linter for data/laws/")
    ap.add_argument("--check", action="store_true",
                    help="print failures only; same exit contract")
    ap.add_argument("--theme", default="",
                    help="focus the spread tables on one theme")
    args = ap.parse_args()
    rep = Report(args.check)

    system_ids = {p.stem for p in SYSTEMS_DIR.glob("*.json")}
    laws = load_laws(rep)
    seen_ids: dict = {}
    themed: dict = {}
    file_counts: dict = {}
    for fname, law in laws:
        check_schema(fname, law, rep, seen_ids, system_ids)
        themed.setdefault(law.get("theme", ""), []).append((fname, law))
        file_counts[fname] = file_counts.get(fname, 0) + 1

    total = len(laws)
    rep.note("")
    rep.note("per-file counts:")
    for fname in sorted(file_counts):
        rep.note("  %-20s %3d" % (fname, file_counts[fname]))
    rep.note("  %-20s %3d  (band [%d, %d])" % ("TOTAL", total, TOTAL_MIN, TOTAL_MAX))
    if not (TOTAL_MIN <= total <= TOTAL_MAX):
        rep.fail("statute book carries %d laws, outside [%d, %d]"
                 % (total, TOTAL_MIN, TOTAL_MAX))

    check_spread(themed, rep, args.theme)

    if rep.failures:
        print("")
        for f in rep.failures:
            print("FAIL %s" % f, file=sys.stderr)
        print("")
        print("law_lint: %d failure(s)" % len(rep.failures), file=sys.stderr)
        return 1
    if not args.check:
        print("")
    print("law_lint: book clean -- %d laws, schema + spread bands hold" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
