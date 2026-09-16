extends RefCounted

## Every bound in the programme model, in one file. Same shape as
## pledges_constants.gd and the rest -- model parameters, not content, so not in
## data/. Rationale for every number is docs/programme-model.md; this file is the
## values, that file is the argument.
##
## *** TWO OF THE NUMBERS BELOW ARE FIXED AUTHORED CONSTANTS AND ONE IS THE DIAL. ***
## The two pulses are ±1.0 by construction (model section 3): the pulse is a unit
## step into a stock bounded [-1, 1], so the SWEPT constant PROGRAMME_SPAN scales
## the whole price and sweeping the pulses too would re-parametrise the same one
## dial twice. An `invalid` conclusion carries a ZERO pulse -- no constant here for
## it at all, programme.gd just adds nothing -- because the outcome was outside the
## player's agency, and charging the full fail price for it is the punishment
## docs/agency-model.md refuses for abstaining.

# --- The price ------------------------------------------------------------------------

const PROGRAMME_PULSE_COMPLETE := 1.0
const PROGRAMME_PULSE_FAIL := 1.0

## THE SWEPT DIAL. Swept at Task 4 (2026-09-15) over docs/programme-model.md
## section 6's pre-declared grid [0.5, 8] step 0.5, refined 0.1 across
## [3.6, 4.4]; the full table and the verdict are section 9 of that doc. The
## response is exactly linear at 0.25 points per span unit (a conclusion
## landing in the read month has one month of inertia behind it), P1 crosses at
## 4.0 and P2 at 3.8 (the 0.05 gap is maastricht's authored on_timeout, not the
## channel), the band is one-sided-up with no declared upper clause, and 4.0
## holds P1 at exactly its edge -- so the first coarse candidate strictly past
## the crossing ships. 4.5 reads +1.125 / -1.175 at month 6 against the +-1.0
## bands, with P3 inert to the bit, the stock clamped at 1.000000 everywhere,
## and a 14-month measured decay half-life (nominal 13.86).
const PROGRAMME_SPAN := 4.5

## Monthly decay on the stock, read by Opinion when it advances the stock. P5's
## band makes the decay real rather than a monument: at 0.05 a completed entry's
## credit halves in ln(2)/0.05 ~= 13.9 months -- a third of a term, so delivery
## this term is worth more than delivery last term, which is the honest shape of
## a record.
const PROGRAMME_DECAY_RATE := 0.05

## The stock's bound (model section 3). The bound is what lets PROGRAMME_SPAN be
## the whole price: no downstream clamp can set the number, which is the failure
## class that killed V4.0's level form.
const STOCK_MIN := -1.0
const STOCK_MAX := 1.0

# --- The register's status vocabulary ---------------------------------------------------

## The three conclusions plus the state before one. Read by the agenda panel, so
## they live here and not as literals in programme.gd -- one source, like every
## other string the UI will compare against.
const STATUS_ACTIVE := "active"
const STATUS_COMPLETE := "complete"
const STATUS_FAIL := "fail"
const STATUS_INVALID := "invalid"

# --- Content whitelists -----------------------------------------------------------------

## The five groups, model section 2's own list: economy / institutions / Europe /
## society / the office itself. A group is where the agenda panel files an entry,
## and nothing else -- it prices nothing.
const GROUPS := ["economy", "institutions", "europe", "society", "office"]

## The two halves of the offer contract. `possible` is WHAT makes an entry
## offerable; `activation` is WHO opens it. Task 2 implements `player` alone --
## the term-start choice -- and refuses the others at the offer rather than at
## the load, because `event` and `forced` are later blocks' writers and an
## activation nothing can yet fire is inert by construction, not broken.
const ACTIVATIONS := ["authored", "event", "player", "forced"]

## Which way the bar fills: `up` means the goal is above the current figure,
## `down` means below. The fraction is the panel's arithmetic; this file fixes
## only the vocabulary, so panel and content cannot disagree about what a
## direction string means.
const PROGRESS_DIRECTIONS := ["up", "down"]

## What a trigger -- `possible`, `complete`, `fail`, `invalid` -- may ask about,
## and the one figure `current_value` may name. BORROWED rather than re-declared,
## for law.gd's own reason in reverse: the states of the country a trigger can
## read are a property of the legislature's precondition model, and a second list
## would be one answer written twice. tests/test_programme.gd reads this file's
## preloads, so the borrow is pinned, not described.
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const TRIGGER_FIELDS := LegislatureK.PRECONDITION_FIELDS
const TRIGGER_OPS := LegislatureK.PRECONDITION_OPS

## Every key an authored entry may carry. The loader refuses an entry that carries
## a key not on this list beside the ones it needs -- the summits' sidecar
## contract's loud refusal: a typo'd field must be a load error, never an inert
## half of an entry nobody reads.
const ENTRY_FIELDS := [
	"id", "name", "summary", "group", "activation", "possible",
	"immediate", "complete", "fail", "invalid", "timeout_months",
	"current_value", "goal_value", "progressbar",
	"on_complete", "on_fail", "on_invalid", "on_timeout",
	"weight", "pinned",
]

## The keys an entry cannot be an entry without, ENFORCED at load:
## data_loader._extract_programme_entry refuses an entry missing any of them,
## and a `summary` that is present but empty fails the same check -- the offer
## prints it under the name, so a blank summary is a field the entry does not
## really carry. Everything else is optional: an entry may author any subset of
## the three triggers and any subset of the effect slots, because "no
## conclusion price" is a legal authoring choice and "an entry that could never
## conclude" is not -- that half is a load rule in data_loader.gd, not a
## whitelist here.
const REQUIRED_FIELDS := [
	"id", "name", "summary", "group", "activation", "timeout_months",
	"current_value", "goal_value", "progressbar",
]
