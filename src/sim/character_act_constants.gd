extends RefCounted

## The character layer's PRICE constants -- the swept half. character_constants.gd
## holds the schema (what validates); this file holds the numbers the probe
## sweeps, so the two never share a file the way programme's dial never lived
## beside its vocabulary. Rationale for every number is docs/people-model.md
## section 14.6's DECLARED bands and the sweep verdicts recorded beside them;
## this file is the values, that file is the argument.
##
## *** EVERY NUMBER HERE IS PRE-DECLARED THEN SWEPT BY tools/characters_probe.gd,
## and the probe's verdicts are the record -- a later session retuning one
## re-runs the probe rather than editing on opinion. ***
##
## ============================================================================
## THREE SIGN CONVENTIONS, ONE PER SECTION, SO NO READER EVER RE-DERIVES THEM
## ============================================================================
## 1. PRICES (the bloc_offset section): a price is a NEGATIVE number, because
##    the machine that consumes it ADDS. Government.penalise_blocs(ns, X) adds X
##    to every bloc's bloc_offset, and Legislature.apply_effects() adds each
##    entry of its bloc_offset dict; bloc_offset is an approval DEBIT, so the
##    constant carries the minus and NO CALL SITE NEGATES A PRICE. The first
##    ship had the three act prices positive, so an act of betrayal RAISED every
##    bloc's approval -- the whole-branch review's C1, found by the fact that
##    every authored BLOC_PENALTY in this project is negative.
## 2. MOVEMENTS (the loyalty/grudge section): constants in the direction their
##    NAME states are positive magnitudes (a served want GAINS loyalty, a denied
##    want GAINS grudge); a RELIEF or a COST is a positive magnitude whose CALL
##    SITE states the sign, because a relief cancels a pulse rather than naming
##    one.
## 3. FACTORS (the trait modifiers at the bottom): dimensionless multipliers.

## The act vocabulary, in the order tick_month evaluates them. Order is
## determinism, not priority: one act per person per month, and the same
## person in the same state always resolves to the same act.
const ACT_KEYS := ["resign", "defect", "challenge", "brief_against"]

# --- Standing seed ---------------------------------------------------------------------

## Where standing starts: everyone gets the base, ambition adds linearly, and
## the ambitious TRAIT adds its own floor -- the scalar is the dial, the trait
## is the floor (14.2's distinction, priced here for the one place it is read).
const STANDING_SEED_BASE := 0.3
const STANDING_SEED_AMBITION := 0.4
const STANDING_SEED_AMBITIOUS_BONUS := 0.1

## The act price's standing weight: weight = BASE + standing, so an act by the
## register's anonymous costs half what the same act by its heavyweight does.
## 0.5 puts standing 0 at 0.5x and standing 1 at 1.5x.
const STANDING_WEIGHT_BASE := 0.5

# --- Loyalty and grudge movement -------------------------------------------------------

## What one month's want read moves. Small by design: loyalty is a record
## built over a term, not a switch, and P1's idle band (<= 2 acts in 168
## months) is what the want-settling must NOT breach on its own.
const LOYALTY_WANT_SERVED := 0.02
const GRUDGE_WANT_DENIED := 0.02

## What the TERMINAL acts (resign, challenge) take off the register when they
## fire -- the defect takes no relief at all and the brief takes the valve
## below, so "every act" was the first ship's wrong tally (the standard
## review's find). It is a CATHARSIS, not a valve: large enough that the
## register falls well clear of the rung it just fired from, which is what
## lets a standing denial climb through the higher rungs on the way back up.
const GRUDGE_ACT_RELIEF := 0.2

## The BRIEF's own relief -- a VALVE, not a catharsis, and the ladder's
## ENVELOPE INVARIANT: it relieves EXACTLY one month of a single standing
## denial's net accrual (GRUDGE_WANT_DENIED - GRUDGE_DECAY_MONTHLY =
## 0.012). A lone frustrated ally therefore leaks for ever without
## escalating -- the valve cancels their climb at the rung it serves -- while
## a person denied TWO OR MORE wants nets +0.032 a month against this
## 0.012 relief and keeps climbing: the walk reaches the challenge floor and
## the defection threshold on the record of the betrayal's WIDTH, not its
## mere existence. GRUDGE_ACT_RELIEF stays the heavy relief the terminal
## acts (resign/challenge) take, which drops the register well clear of the
## rung it fired from.
const GRUDGE_BRIEF_RELIEF := 0.012

## *** THE LADDER CLIMBS BECAUSE OF THE EVALUATION ORDER, AND THAT IS THE
## LOAD-BEARING FACT (review C2 -- the first fix got the accrual right and the
## escalation wrong). *** `tick_month` walks CK.ACT_KEYS with the act key
## OUTER, so within one month every person is tested for "challenge" before any
## is tested for "brief_against". A grudge that stands above the BRIEF rung
## while still under the CHALLENGE floor leaks and drops by this relief -- back
## to a level from which a standing denial climbs THROUGH 0.5 and 0.6 on the
## way up, firing the higher rungs when it gets there. The rungs are therefore
## reachable in sequence, and no register caps the one below it.
##
## WHAT IT TAKES, per month, at GRUDGE_WANT_DENIED - GRUDGE_DECAY_MONTHLY:
##   one standing want denied            +0.012 -> brief rung ~38 mo, and the
##                                                  valve then roughly cancels
##                                                  the climb: a lone ally leaks
##   two standing wants denied           +0.032 -> brief ~14 mo, then the climb
##                                                  through 0.5 fires a
##                                                  challenge ~3 mo after the
##                                                  first leak, and 0.6 a
##                                                  defection ~3 mo after that
##   one denied want, PRINCIPLED (x2)    +0.032 -> as the two-want row
##   two denied, principled              +0.072 -> brief ~6 mo, challenge ~7
## This works BECAUSE challenge is tested before brief in the month the grudge
## is already over 0.5, and the relief is large enough that the register is not
## pinned at the rung it just fired from.

## What briefing against the government costs the BRIEFER in loyalty. They are
## burning the relationship, and it is the ONLY writer in the project that takes
## loyalty DOWN -- before the review there was none at all, which made
## LOYALTY_RESIGN_FLOOR unreachable by arithmetic rather than by taste (C2).
## Magnitude; the call site negates it (convention 2 above).
##
## ARITHMETIC: LOYALTY_RESIGN_FLOOR / LOYALTY_ACT_COST = 0.4 / 0.1 = 4 briefs
## from a neutral 0.0, and 14 from a full 1.0. Briefs are grudge-gated at 0.45
## and each one relieves GRUDGE_BRIEF_RELIEF -- the VALVE (0.012), not the
## catharsis: the walk couples the two registers precisely because loyalty
## drains by the full cost while the grudge only leaks one month's accrual per
## brief. A sustained betrayal walks a person from ally to resigned over
## years, never in one month. (The first ship's paragraph named
## GRUDGE_ACT_RELIEF here, which would make a brief a catharsis and pin
## nobody anywhere -- the standard review's find.)
const LOYALTY_ACT_COST := 0.1

## Grudge decay, monthly, straight (the trait modifiers live in characters.gd
## where the person is in hand).
##
## THE HALF-LIFE STORY CHANGED AT THE REVIEW, AND THE NEW ARITHMETIC IS THE
## POINT (C2). At 0.05 -- a ~14-month half-life, borrowed from the programme
## stock's decay -- a pulse of GRUDGE_WANT_DENIED (0.02) was under one month of
## decay, so no grudge could EVER survive the month it was written and no act
## threshold (0.45/0.5/0.6) was reachable. The pulse form changed too (see
## _settle_wants: a STANDING denial now accrues every month it stands), so the
## arithmetic to quote is the NET step per month, decay included.
##
## PER MONTH, WITH THE BRIEF'S VALVE IN PLACE (GRUDGE_BRIEF_RELIEF, above):
##   one standing want denied   net +0.012  -> brief rung 0.45 in ~38 mo, then
##                                            the valve out-runs the climb and
##                                            the walk STOPS there (correctly:
##                                            a lone frustrated ally leaks)
##   two standing wants denied  net +0.032  -> brief ~14, challenge floor 0.5
##                                            ~19, defection 0.6 ~28
##   three                      net +0.052  -> brief ~9, challenge ~11, defect ~15
## The decay is charged ONCE per person, not once per denied want, which is why
## the multiplicity runs faster than a per-want reading suggests. No authored
## person carries more than three wants, so three is the ceiling the content
## permits and 0.6 is reached only by the widest betrayal in the register.
const GRUDGE_DECAY_MONTHLY := 0.008

## Loyalty's band.
const LOYALTY_MIN := -1.0
const LOYALTY_MAX := 1.0

# --- Act thresholds --------------------------------------------------------------------

## Resign when loyalty falls below this. Negative: a resigned minister has
## been actively harmed, not merely unserved.
const LOYALTY_RESIGN_FLOOR := -0.4

## How far a LOYAL person's resignation floor drops (they tolerate more before
## they walk). 14.2's table said "loyalty floor higher" and nothing read it --
## the review's I3, made real: -0.4 - 0.2 = -0.6, so a loyal office-holder needs
## two more briefs (6 rather than 4 from neutral) to reach the door.
const LOYAL_RESIGN_RELIEF := 0.2

## Defect when the grudge passes this.
const GRUDGE_DEFECT_THRESHOLD := 0.6

## Challenge when standing passes this, AND the grudge floor -- the floor is the
## already-won/lost guard: standing alone would coup every leader on day one of
## a fresh term.
##
## REACHABILITY AT THE NEW NUMBERS (GRUDGE_DECAY_MONTHLY's own comment carries
## the table): the three thresholds keep their authored values and are now
## reachable by a player who keeps denying TWO OR MORE wants -- the floor at
## ~19 months, the defection threshold at ~28. At ONE denied want the walk
## reaches the brief rung and stops, because a leak's own relief out-runs a
## single denial's accrual. That is the shape the design wants: leaking is
## dissent, escalating to a leadership challenge takes a record of sustained
## denial across more than one thing this person cares about.
const CHALLENGE_STANDING_THRESHOLD := 0.7
const CHALLENGE_AMBITIOUS_DISCOUNT := 0.1
const CHALLENGE_GRUDGE_FLOOR := 0.5

## The VANISHING person's own discount, and its gate is the difference between
## this trait and ambition: it applies only when the challenge target IS an
## office:party_leadership want they carry. Weighted office wants are what a vain
## person is (14.2's table); a threshold discount for merely being vain is
## ambition with a second name.
const CHALLENGE_VAIN_DISCOUNT := 0.1

## Brief against when the grudge passes this -- below the defection threshold,
## because leaking is what a frustrated ally does on the way out.
const GRUDGE_BRIEF_THRESHOLD := 0.45

## V5.2b, the author's call (2026-10-24, verbatim: "Le cout s'efface"): the
## bloc_offset an act writes -- a brief, a resignation, a defection, a challenge
## -- fades with this half-life, so a leak hurts the next vote and is then
## forgotten. Laws, events, the programme and campaigns stay permanent; only the
## acts' share (NationState.act_bloc_offset) fades. Before V5.2b acts were rare
## (0 in an idle term) and a permanent price did no harm; once refused audiences
## feed the ladder, fourteen years of permanent briefs pinned the workers' and
## students' offsets on the clamp (tests/test_balance.gd).
const ACT_OFFSET_HALF_LIFE_MONTHS := 24

## The monthly multiplier, 0.5^(1/24), written out: GDScript folds no pow() into a
## constant, and test_characters pins the literal against the half-life.
const ACT_OFFSET_MONTHLY_KEEP := 0.9715319411536059

## V5.2b. The highest a REFUSAL (a declined, delegated or lapsed audience
## request) can lift a grudge: one month's decay and one brief's relief above the
## brief gate. Next month's decay leaves the person at the gate, one brief fires,
## and its relief takes them under it -- a refusal brings a person to the leak,
## never past it. MEASURED (the b1 re-baseline, 2026-10-24): uncapped, a
## principled person refused once sat 0.25 over the gate and leaked every month
## for a year, and refusing everyone for a term flipped France's 2032 vote in 28
## of 41 regimes. The rungs above the brief stay the wants' own.
const GRUDGE_REFUSAL_CEILING := GRUDGE_BRIEF_THRESHOLD + GRUDGE_BRIEF_RELIEF + GRUDGE_DECAY_MONTHLY

# --- Prices ----------------------------------------------------------------------------

## All prices are POINTS of bloc_offset, NEGATIVE (convention 1 above), weighted
## by the actor's standing through STANDING_WEIGHT_BASE. They are the
## government-price primitive's units, and the probe's P4 (total approval
## movement per year within +-3.0) is the readability bound the sweep answers.
const PRICE_RESIGN := -0.8
const PRICE_DEFECT := -0.5
const PRICE_CHALLENGE := -0.6
## The brief, -0.25 until V5.2b: the author's call on PR #104 (2026-10-24,
## verbatim "Fuite 40 % moins chere", Gameplay's option A). Once refused audiences
## feed the ladder, a brief is routine rather than rare -- three a term in a
## decline-everything France -- and at -0.25 x (0.5 + standing) one brief alone
## was about 0.31 of a bloc, two thirds of the 0.50 act-share band
## (docs/design/bands-v5.2.md, B3 amendment). The count comes from grudges, not
## from this price, so the share scales with it.
const PRICE_BRIEF := -0.15

## The blocs a leak lands on. Grievance-carrying blocs: unrest_constants'
## UNREST_BLOCS are the same two, and a leak about a government failure travels
## the channel the unrest opinion load already travels. Named here rather than
## inline so a fourth bloc-carrying read finds the list instead of restating it.
const BRIEF_BLOCS := ["workers", "students"]

# --- Trait factors ---------------------------------------------------------------------

## The faithful person's factor on a grudge PULSE from betrayal: halved -- they
## give the relationship the benefit of the doubt, so the loss registers later.
## (The first ship applied it to the RELIEF instead, which made loyal people
## hold grudges LONGER -- the exact opposite of the table. Review I2.)
const LOYAL_GRUDGE_FACTOR := 0.5

## The principled person's factor on the same pulse: doubled. Their want is
## their position, so losing it is a betrayal rather than a setback.
const PRINCIPLED_GRUDGE_FACTOR := 2.0

## The grudge's own decay, scaled per trait where the person is in hand.
## A person carrying both multiplies twice, which is honest: both gates apply.
const PRAGMATIC_DECAY_FACTOR := 2.0
const STUBBORN_DECAY_FACTOR := 0.5

## The fervent person's factor on a grudge pulse from a METER want, for the
## collective kinds (character_constants.KIND_COLLECTIVE) -- the grievance
## ladder IS their lever, so being denied there is denied in their own register.
const FERVENT_METER_FACTOR := 1.5

## The networked trait's multiplier on a brief's magnitude (14.2's table).
const NETWORKED_MAGNITUDE := 1.5