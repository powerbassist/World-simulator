#!/usr/bin/env python3
"""tools/event_lint.py -- V4.4 T8: the event book's authoring linter, law_lint.py's
sibling over data/events/.

The loader (src/core/data_loader.gd -> GameEvent.from_dict) already refuses a
malformed event at boot; this tool re-runs those same checks in Python -- two
implementations of one schema, the belt-and-braces the V4.3 orphan rule learned --
and then applies the SPREAD discipline the loader cannot see, because the loader
reads one event at a time and spread is a property of the book.

Modes (law_lint.py's shape: mode flags, no config):
  python tools/event_lint.py           # full report: tables printed, exit 1 on any failure
  python tools/event_lint.py --check   # CI-shaped: failures only, same exit contract

THE E1b CONSTRAINTS ARE EXACT AND PRE-DECLARED (docs/events-model.md's own
sentence, restated as code; a band moved without a sweep is a band broken):

  MEAN          every choice's size-weighted mean bloc_offset within +-0.008 of
                zero. Weights are opinion_constants.BLOC_SIZE: workers .30,
                pensioners .24, urban .15, rural .13, business .10, students .08.
                A mean off zero is a standing bribe or a standing tax -- an event
                is not a law the assembly chose.
  BUSINESS-WORST  the share of choices where `business` (size .10, the smallest
                bloc) is the strict worst stays <= 0.30. Holding every mean at
                zero pushes the cost onto the smallest bloc; this is the
                constraint with a probe attached (events-model E1b's finding).
  TOTAL         the book carries >= 9 events across data/events/*.json, with NO
                upper bound -- the content task grows it 9 -> 120+ and the lint
                must not fight that.

SCHEMA        the loader's own checks, re-derived here: ids unique and
              snake_case, categories valid, likelihood/respond_months/severity/
              weight/cooldown bounds, 2-4 choices with exactly one default and no
              empty effects, on_action in the vocabulary (and `election_lost`
              refused by name -- a lost election ends the game, so nothing could
              answer the event), arms targets exist, arms delays bounded,
              duplicate ids and same-subject+same-gate collisions.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVENTS_DIR = ROOT / "data" / "events"

# --- The schema's own vocabulary, restated from src/ --------------------------
# events_constants CATEGORIES / SUBJECT_OFFICES / ON_ACTIONS
CATEGORIES = [
    "scandal", "fiscal", "unrest", "personal", "european",
    "foreign", "industrial", "commodity", "disaster",
]
SUBJECT_OFFICES = ["head_of_government", "head_of_state", "largest_party_leader"]
ON_ACTIONS = [
    "law_passed", "law_repealed", "member_bill_passed", "minister_resigned",
    "takeover_bid", "firm_failed", "commodity_price_high", "accession_won",
]
# events_constants bounds
LIKELIHOOD_MIN, LIKELIHOOD_MAX = 0.002, 0.50
RESPOND_MONTHS_MIN, RESPOND_MONTHS_MAX = 1, 15
WEIGHT_MIN, WEIGHT_MAX = 0.2, 5.0
SEVERITY_MIN, SEVERITY_MAX = 1, 3
COOLDOWN_MAX_MONTHS = 60
ARMS_DELAY_MIN_MONTHS, ARMS_DELAY_MAX_MONTHS = 1, 18
MIN_CHOICES, MAX_CHOICES = 2, 4
# event.gd KNOWN_KEYS / CHOICE_KEYS -- an unknown key is a load error, so it is
# one here too; that is how a typo'd `severity` is caught before the loader runs.
KNOWN_KEYS = [
    "id", "name", "summary", "subject_office", "likelihood", "respond_months",
    "once", "preconditions", "choices", "interrupt", "sited",
    "category", "weight", "severity", "on_action", "cooldown_months",
]
CHOICE_KEYS = ["id", "label", "summary", "effects", "default", "arms"]
# law.gd SCALAR_EFFECT_KEYS, and its SHARED_EFFECT_CHANNELS minus `institutional`
# -- the one channel an event choice may not write (Emergency powers, tiered
# Someday; from_dict refuses it by name and this lint repeats the name).
SCALAR_EFFECT_KEYS = [
    "structural_unemployment_pct", "potential_growth_pct", "other_revenue_pct_gdp",
]
EFFECT_CHANNELS = ["tax_rates_pct", "spending_pct_gdp", "bloc_offset", "company", "society"]
# economy_constants TAX_KEYS / SPENDING_KEYS / SECTOR_TREND
TAX_KEYS = ["income", "corporate", "vat", "capital_gains", "wealth"]
SPENDING_KEYS = ["health", "education", "defence", "pensions", "infrastructure"]
SECTORS = ["agriculture", "industry", "services"]
# opinion_constants BLOC_KEYS, and BLOC_SIZE -- the weights ARE the sizes, which
# is the whole point of a size-weighted mean.
BLOC_KEYS = ["workers", "pensioners", "urban", "rural", "business", "students"]
BLOC_SIZE = {"workers": 0.30, "pensioners": 0.24, "urban": 0.15,
             "rural": 0.13, "business": 0.10, "students": 0.08}
# law.gd SOCIETY_TERMS
SOCIETY_TERMS = ["corruption", "migration", "settlement", "press_freedom",
                 "judicial_independence"]
# legislature_constants PRECONDITION_FIELDS / OPS, minus events_constants'
# EVENT_PRECONDITION_REFUSED -- the subtraction shape, one list refused down.
PRECONDITION_FIELDS = [
    "debt_to_gdp_pct", "unemployment_pct", "deficit_pct_gdp",
    "overall_approval_pct", "growth_annual_pct", "terms_served",
    "unrest_pct", "co2e_per_capita_t", "eu_member",
]
PRECONDITION_OPS = ["<", "<=", ">", ">=", "=="]
EVENT_PRECONDITION_REFUSED = ["overall_approval_pct"]

# --- The bands (see the module docstring; restated as code) -------------------
MEAN_BAND = 0.008
BUSINESS_WORST_MAX = 0.30
TOTAL_MIN = 9
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


def business_strictly_worst(off: dict) -> bool:
    """STRICT: business's offset sits below EVERY other named bloc's. A running
    min() credited a tie at the minimum to whichever bloc iterated first.
    tests/test_event_content.gd's _business_is_strictly_worst is the identical
    rule. A lone-business offset counts (nothing else is lower)."""
    if "business" not in off:
        return False
    return all(float(off["business"]) < float(v) for b, v in off.items() if b != "business")


def self_check_strict_rule(rep: "Report") -> None:
    """The shipped book has no tie at the minimum, so only synthetic rows can fail
    the strict rule. Tie placed with business first and last in iteration order."""
    tie_first = {"business": -0.05, "workers": -0.05, "urban": 0.02}
    tie_last = {"workers": -0.05, "business": -0.05, "urban": 0.02}
    strict = {"workers": -0.04, "business": -0.05, "urban": 0.02}
    if business_strictly_worst(tie_first) or business_strictly_worst(tie_last):
        rep.fail("self-check: a tie with business at the minimum counted as business strictly worst")
    if not business_strictly_worst(strict):
        rep.fail("self-check: business strictly lowest was not counted as business-worst")


def load_events(rep: Report):
    """Every data/events/*.json -> list of (filename, entry-dict). Top-level
    underscore-prefixed keys are file comments, the crises.json shape."""
    files = sorted(EVENTS_DIR.glob("*.json"))
    if not files:
        rep.fail("no data/events/*.json files found")
        return []
    out = []
    for path in files:
        try:
            parsed = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            rep.fail("%s: <no id>: unreadable or invalid JSON (%s)" % (path.name, e))
            continue
        if not isinstance(parsed, dict) or not isinstance(parsed.get("events"), list):
            rep.fail("%s: <no id>: invalid event file, expected {\"events\": [...]}" % path.name)
            continue
        for i, entry in enumerate(parsed["events"]):
            if not isinstance(entry, dict):
                rep.fail("%s: <no id>: events[%d] is not an object" % (path.name, i))
                continue
            out.append((path.name, entry))
    return out


def check_choice(fname: str, ev_id: str, choice: dict, rep: Report) -> None:
    where = "%s: %s" % (fname, ev_id)
    cid = choice.get("id", "<no choice id>")
    path = "%s.%s" % (ev_id, cid)

    for key in choice:
        if key not in CHOICE_KEYS:
            rep.fail("%s: %s: '%s' is not a recognised choice field" % (where, path, key))

    for field in ("label", "summary"):
        if not isinstance(choice.get(field), str) or not choice.get(field):
            rep.fail("%s: %s: missing or empty '%s'" % (where, path, field))

    effects = choice.get("effects")
    if not isinstance(effects, dict) or not effects:
        rep.fail("%s: %s: names no effect at all -- a choice that costs nothing resolves the deadline for free" % (where, path))
        return
    for key in effects:
        if key not in EFFECT_CHANNELS and key not in SCALAR_EFFECT_KEYS:
            rep.fail("%s: %s: effects.%s is not a recognised effect channel" % (where, path, key))
    if "institutional" in effects:
        rep.fail("%s: %s: effects.institutional is refused on an event choice -- Emergency powers, tiered Someday" % (where, path))
    for keyed, known in (("tax_rates_pct", TAX_KEYS), ("spending_pct_gdp", SPENDING_KEYS),
                         ("bloc_offset", BLOC_KEYS)):
        if keyed not in effects:
            continue
        vals = effects[keyed]
        if not isinstance(vals, dict) or not vals:
            rep.fail("%s: %s: effects.%s must be a non-empty object" % (where, path, keyed))
            continue
        for k, v in vals.items():
            if k not in known:
                rep.fail("%s: %s: effects.%s.%s is not a recognised key" % (where, path, keyed, k))
            if not is_number(v):
                rep.fail("%s: %s: effects.%s.%s must be numeric" % (where, path, keyed, k))
    for scalar in SCALAR_EFFECT_KEYS:
        if scalar in effects and not is_number(effects[scalar]):
            rep.fail("%s: %s: effects.%s must be numeric" % (where, path, scalar))
    if "company" in effects:
        c = effects["company"]
        if not isinstance(c, dict):
            rep.fail("%s: %s: effects.company must be an object" % (where, path))
        else:
            if c.get("sector") not in SECTORS:
                rep.fail("%s: %s: effects.company.sector '%s' is not a recognised sector" % (where, path, c.get("sector")))
            if not is_number(c.get("burden")):
                rep.fail("%s: %s: effects.company.burden is missing or not numeric" % (where, path))
    if "society" in effects:
        s = effects["society"]
        if not isinstance(s, dict):
            rep.fail("%s: %s: effects.society must be an object" % (where, path))
        else:
            for term, value in s.items():
                if term not in SOCIETY_TERMS:
                    rep.fail("%s: %s: effects.society.%s is not a recognised term" % (where, path, term))
                elif not is_number(value):
                    rep.fail("%s: %s: effects.society.%s is not numeric" % (where, path, term))

    # THE E1b MEAN, per choice. The default is judged by the same band: it is the
    # choice the desk charges while the player sleeps, so a mean off zero there
    # is a standing bribe or a standing tax arriving month after month.
    off = effects.get("bloc_offset", {})
    if isinstance(off, dict) and off:
        mean = sum(BLOC_SIZE.get(b, 0.0) * float(v) for b, v in off.items() if is_number(v))
        if abs(mean) > MEAN_BAND:
            rep.fail("%s: %s: bloc_offset size-weighted mean %+.4f outside +-%.3f -- a standing price, not a decision" % (
                where, path, mean, MEAN_BAND))


def check_event(fname: str, ev: dict, rep: Report, seen_ids: dict, gates: dict,
                arm_edges: dict) -> None:
    ev_id = ev.get("id", "")
    where = "%s: %s" % (fname, ev_id or "<no id>")

    if not isinstance(ev_id, str) or not ev_id:
        rep.fail("%s: <no id>: missing or empty string 'id'" % fname)
        ev_id = "<no id>"
    elif not ID_PATTERN.match(ev_id):
        rep.fail("%s: %s: id '%s' is not snake_case" % (where, ev_id, ev_id))
    if ev_id in seen_ids:
        rep.fail("%s: %s: duplicate event id '%s' (also in %s)" % (where, ev_id, ev_id, seen_ids[ev_id]))
    else:
        seen_ids[ev_id] = fname

    for key in ev:
        if key not in KNOWN_KEYS:
            rep.fail("%s: '%s' is not a recognised event field" % (where, key))

    for field in ("name", "summary"):
        if not isinstance(ev.get(field), str) or not ev.get(field):
            rep.fail("%s: %s: missing or empty '%s'" % (where, ev_id, field))

    if ev.get("subject_office") not in ("", None) and ev.get("subject_office") not in SUBJECT_OFFICES:
        rep.fail("%s: %s: subject_office '%s' must be one of %s" % (
            where, ev_id, ev.get("subject_office"), SUBJECT_OFFICES))

    if not is_number(ev.get("likelihood")):
        rep.fail("%s: %s: likelihood is missing or not numeric" % (where, ev_id))
    elif not (LIKELIHOOD_MIN <= float(ev["likelihood"]) <= LIKELIHOOD_MAX):
        rep.fail("%s: %s: likelihood = %s out of range [%s, %s]" % (
            where, ev_id, ev["likelihood"], LIKELIHOOD_MIN, LIKELIHOOD_MAX))

    if not is_number(ev.get("respond_months")):
        rep.fail("%s: %s: respond_months is missing or not numeric" % (where, ev_id))
    elif not (RESPOND_MONTHS_MIN <= int(ev["respond_months"]) <= RESPOND_MONTHS_MAX):
        rep.fail("%s: %s: respond_months = %s out of range [%d, %d]" % (
            where, ev_id, ev["respond_months"], RESPOND_MONTHS_MIN, RESPOND_MONTHS_MAX))

    if ev.get("category") not in CATEGORIES:
        rep.fail("%s: %s: category '%s' must be one of %s" % (where, ev_id, ev.get("category"), CATEGORIES))

    severity = ev.get("severity", 1)
    if not is_number(severity):
        rep.fail("%s: %s: severity is not numeric" % (where, ev_id))
    elif not (SEVERITY_MIN <= int(severity) <= SEVERITY_MAX):
        rep.fail("%s: %s: severity = %s out of range [%d, %d]" % (
            where, ev_id, severity, SEVERITY_MIN, SEVERITY_MAX))

    weight = ev.get("weight", 1.0)
    if not is_number(weight):
        rep.fail("%s: %s: weight is not numeric" % (where, ev_id))
    elif not (WEIGHT_MIN <= float(weight) <= WEIGHT_MAX):
        rep.fail("%s: %s: weight = %s out of range [%s, %s]" % (
            where, ev_id, weight, WEIGHT_MIN, WEIGHT_MAX))

    cooldown = ev.get("cooldown_months", 0)
    if not is_number(cooldown):
        rep.fail("%s: %s: cooldown_months is not numeric" % (where, ev_id))
    elif not (0 <= int(cooldown) <= COOLDOWN_MAX_MONTHS):
        rep.fail("%s: %s: cooldown_months = %s out of range [0, %d]" % (
            where, ev_id, cooldown, COOLDOWN_MAX_MONTHS))

    hook = ev.get("on_action", "")
    if hook == "election_lost":
        rep.fail("%s: %s: on_action 'election_lost' is refused outright -- a lost election ends the game, so nothing could answer the event" % (where, ev_id))
    elif hook not in ("", None) and hook not in ON_ACTIONS:
        rep.fail("%s: %s: on_action '%s' is not one of %s" % (where, ev_id, hook, ON_ACTIONS))

    preconds = ev.get("preconditions", [])
    if not isinstance(preconds, list):
        rep.fail("%s: %s: preconditions must be an array" % (where, ev_id))
        preconds = []
    for i, p in enumerate(preconds):
        if not isinstance(p, dict):
            rep.fail("%s: %s: preconditions[%d] is not an object" % (where, ev_id, i))
            continue
        field = p.get("field")
        if field not in PRECONDITION_FIELDS:
            rep.fail("%s: %s: preconditions[%d].field '%s' is not a recognised field" % (where, ev_id, i, field))
        elif field in EVENT_PRECONDITION_REFUSED:
            rep.fail("%s: %s: preconditions[%d] names '%s', refused on this channel -- an event priced in approval and gated on approval is positive feedback with nothing damping it" % (
                where, ev_id, i, field))
        if p.get("op") not in PRECONDITION_OPS:
            rep.fail("%s: %s: preconditions[%d].op '%s' is not a recognised operator" % (where, ev_id, i, p.get("op")))
        # The gates only ever OPEN events, so unrest may only ever be >= -- a <=
        # would make unrest a gate that takes levers away (legislature_constants'
        # own rule, which extract_preconditions shares with the law channel).
        if field == "unrest_pct" and p.get("op") != ">=":
            rep.fail("%s: %s: preconditions[%d] tests unrest_pct with '%s' -- unrest may only ever be >=" % (
                where, ev_id, i, p.get("op")))
        if not is_number(p.get("value")):
            rep.fail("%s: %s: preconditions[%d].value missing or not numeric" % (where, ev_id, i))

    choices = ev.get("choices")
    if not isinstance(choices, list):
        rep.fail("%s: %s: choices must be an array" % (where, ev_id))
        return
    if not (MIN_CHOICES <= len(choices) <= MAX_CHOICES):
        rep.fail("%s: %s: has %d choices, and an event carries between %d and %d" % (
            where, ev_id, len(choices), MIN_CHOICES, MAX_CHOICES))
    seen_choices: dict = {}
    defaults = 0
    for choice in choices:
        if not isinstance(choice, dict):
            rep.fail("%s: %s: a choice is not an object" % (where, ev_id))
            continue
        cid = choice.get("id", "")
        if not isinstance(cid, str) or not cid:
            rep.fail("%s: %s: a choice is missing or empty 'id'" % (where, ev_id))
        elif cid in seen_choices:
            rep.fail("%s: %s: has two choices called '%s'" % (where, ev_id, cid))
        else:
            seen_choices[cid] = True
        if isinstance(choice.get("default"), bool) and choice.get("default"):
            defaults += 1
        arms = choice.get("arms", {})
        if arms:
            if not isinstance(arms, dict):
                rep.fail("%s: %s.%s: arms must be an object {event_id, delay_months}" % (where, ev_id, cid))
            else:
                arm_edges.setdefault(ev_id, []).append(arms.get("event_id", ""))
                delay = arms.get("delay_months", 0)
                if not is_number(delay) or not (ARMS_DELAY_MIN_MONTHS <= int(delay) <= ARMS_DELAY_MAX_MONTHS):
                    rep.fail("%s: %s.%s: arms.delay_months = %s out of range [%d, %d]" % (
                        where, ev_id, cid, delay, ARMS_DELAY_MIN_MONTHS, ARMS_DELAY_MAX_MONTHS))
                if not isinstance(arms.get("event_id"), str) or not arms.get("event_id"):
                    rep.fail("%s: %s.%s: arms.event_id is missing or not a string" % (where, ev_id, cid))
        check_choice(fname, ev_id, choice, rep)
    if defaults != 1:
        rep.fail("%s: %s: has %d choices marked 'default' and needs exactly one -- what happens when the player says nothing is the whole of the deadline" % (
            where, ev_id, defaults))

    # THE SAME-SUBJECT + SAME-GATE COLLISION, the loader's own rule re-derived
    # (data_loader._load_events): gate = subject office + the sorted field+op+value
    # list AND the on_action (a hazard event and a hook event with one subject and
    # one gate are unrelated occasions); only an event that NAMES a subject or a
    # GATE can collide -- a pure-hazard crisis about nobody is a shape the content
    # owns, and two such events are separated by id, body, likelihood, once-ness and
    # the hash. Membership is a scope, not a trigger: it does not make an event name
    # a gate, but it stays in the key (an EU-only event and an ungated sibling fire
    # in different months) -- the loader does the same.
    named_gate = any(isinstance(p, dict) and p.get("field") != "eu_member" for p in preconds)
    if ev.get("subject_office") or named_gate:
        # The value float-formats and only numeric conds enter the key, the loader's
        # own shape (law.gd extract_preconditions stores `float(value)` and `continue`s
        # the rest) -- raw JSON `10` and `10.0` are one gate there and one here too.
        rows = sorted("%s%s%s" % (p.get("field"), p.get("op"), float(p.get("value"))) for p in preconds
                      if isinstance(p, dict) and is_number(p.get("value")))
        gate = "%s|%s|%s" % (ev.get("subject_office", ""), ev.get("on_action", ""), ",".join(rows))
        if gate in gates:
            rep.fail("%s: %s: has the same subject and the same gate as '%s' -- two events that can only ever fire in the same months are one event authored twice" % (
                where, ev_id, gates[gate]))
        else:
            gates[gate] = ev_id


def main() -> int:
    ap = argparse.ArgumentParser(description="Authoring linter for data/events/")
    ap.add_argument("--check", action="store_true",
                    help="print failures only; same exit contract")
    args = ap.parse_args()
    rep = Report(args.check)
    self_check_strict_rule(rep)

    events = load_events(rep)
    seen_ids: dict = {}
    gates: dict = {}
    arm_edges: dict = {}
    file_counts: dict = {}
    all_events: list = []
    for fname, ev in events:
        # Every event registers its id BEFORE any edge is judged, so a chain may
        # target an event authored in a later file -- the loader's own two-pass
        # order (_load_events judges chains only once the whole set is in hand).
        arm_edges.setdefault(ev.get("id", ""), [])
        check_event(fname, ev, rep, seen_ids, gates, arm_edges)
        all_events.append((fname, ev))
        file_counts[fname] = file_counts.get(fname, 0) + 1

    by_id = {ev.get("id", ""): ev for _fname, ev in all_events}

    # Second pass over the arms: now every id in the book is known.
    for fname, ev in all_events:
        for choice in ev.get("choices", []):
            if not isinstance(choice, dict) or not isinstance(choice.get("arms"), dict):
                continue
            target = choice["arms"].get("event_id", "")
            if isinstance(target, str) and target and target not in arm_edges:
                rep.fail("%s: %s: arms '%s', which is not a loaded event -- a chain that points at nothing can never land" % (
                    fname, ev.get("id", "<no id>"), target))
            # The loader's two set-level refusals (data_loader.gd, _load_events):
            # a target that is a hook event is re-delivered by the hook door the
            # same tick, and a chain that re-arms its own ancestry never ends.
            elif isinstance(target, str) and target:
                hook_of = by_id.get(target, {}).get("on_action", "")
                if hook_of:
                    rep.fail("%s: %s: arms '%s', whose on_action '%s' lets the hook door re-deliver it" % (
                        fname, ev.get("id", "<no id>"), target, hook_of))

    # Cycle walk over the same edges, depth-first with its own path, one report per
    # start -- the loader's rule, restated.
    for start_id in list(arm_edges):
        frontier = [(start_id, [start_id])]
        found = False
        while frontier and not found:
            node, path = frontier.pop()
            for nxt in arm_edges.get(node, []):
                if nxt in path:
                    rep.fail("chain through '%s' is a cycle ('%s' -> '%s' closes it)" % (start_id, node, nxt))
                    found = True
                    break
                if nxt in arm_edges:
                    frontier.append((nxt, path + [nxt]))

    total = len(all_events)
    rep.note("")
    rep.note("per-file counts:")
    for fname in sorted(file_counts):
        rep.note("  %-20s %3d" % (fname, file_counts[fname]))
    rep.note("  %-20s %3d  (band >= %d, no upper bound)" % ("TOTAL", total, TOTAL_MIN))
    if total < TOTAL_MIN:
        rep.fail("event book carries %d events, under the %d the machine can exercise" % (total, TOTAL_MIN))

    # THE E1b CONTENT-SET CHECK, over every choice in the book: holding every
    # mean at zero pushes the cost onto the smallest bloc -- how often is
    # `business` the strict worst, and is that share inside the declared band?
    worst_count = 0
    choice_total = 0
    per_event_worst: dict = {}
    for fname, ev in all_events:
        for choice in ev.get("choices", []):
            if not isinstance(choice, dict):
                continue
            off = choice.get("effects", {}).get("bloc_offset", {})
            if not isinstance(off, dict) or not off:
                continue
            choice_total += 1
            if business_strictly_worst(off):
                worst_count += 1
                per_event_worst.setdefault(ev.get("id", "<no id>"), []).append(str(choice.get("id", "")))
    share = worst_count / choice_total if choice_total else 0.0
    rep.note("")
    rep.note("E1b content-set check: business is the strict worst bloc on %d of %d choices = %.1f%% (band <= %.0f%%)" % (
        worst_count, choice_total, 100.0 * share, 100.0 * BUSINESS_WORST_MAX))
    for ev_id, cids in sorted(per_event_worst.items()):
        rep.note("  %-26s %s" % (ev_id, ", ".join(cids)))
    if choice_total and share > BUSINESS_WORST_MAX:
        rep.fail("event book: 'business' is the strict worst bloc on %.1f%% of choices, over the %.0f%% band -- holding the mean at zero pushes cost onto the smallest bloc" % (
            100.0 * share, 100.0 * BUSINESS_WORST_MAX))

    if rep.failures:
        print("")
        for f in rep.failures:
            print("FAIL %s" % f, file=sys.stderr)
        print("")
        print("event_lint: %d failure(s)" % len(rep.failures), file=sys.stderr)
        return 1
    if not args.check:
        print("")
    print("event_lint: book clean -- %d events, %d choices, schema + E1b bands hold" % (total, choice_total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
