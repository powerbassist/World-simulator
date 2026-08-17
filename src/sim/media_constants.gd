extends RefCounted

## Tuned constants for media and framing — V1.5d, the fourth and last session of the
## V1.5 block. The model, and the justification for every number here, is
## docs/media-model.md.
##
## A LEAF, and it has to stay one: law.gd preloads this file and data_loader.gd hangs
## off law.gd, so a preload here would reach the whole loader. society_constants.gd and
## unrest_constants.gd are leaves for the same reason.
##
## THE SESSION'S HEADLINE IS THAT THE MACHINE ALREADY EXISTED. opinion.gd's
## salience_weights() has amplified bad news at SALIENCE_GAIN = 5.0 since S10 --
## amplification with no source. "Bad news travels" is a claim about the press, and this
## project has been making it for six blocks with no outlet behind it. docs/tiers/v1.md
## section 5's first bullet does not ask for a machine; it asks for the SOURCE of one
## that is already running. Twenty-fifth instance of the stale-row failure
## docs/trade-model.md first recorded, and the fourth block running where the row's
## premise did not survive being counted.
##
## Every value below was set by tools/media_probe.gd against a band AND a tiebreaker
## fixed BEFORE the sweep ran. This session inherits the whole accumulated rule --
## V1.4c's (fix the tiebreaker, not only the band), V1.5a's (it must strictly ORDER the
## survivors), V1.5b's (it must not move when the grid is WIDENED), and V1.5c's four
## (nor when the grid is REFINED; a band whose ceiling is one regime's peak selects that
## peak; a two-sided interval bounded by two MODEL criteria takes the midpoint while a
## GUARD RAIL does not select at all; and a band can be aimed at an observable the
## channel does not reach).
##
## IT ALSO ADDS ONE, AND IT IS ABOUT THE MODEL RATHER THAN THE CONSTANT. Step 0 ran two
## tables before a line of src/ was written, and the first of them fired a kill switch
## whose response had been pre-committed -- and the pre-committed response was REFUSED,
## with the argument recorded in docs/media-model.md section 4 rather than the refusal
## slipped in. See FRAMING_BETA below.


# --- The framing machine ------------------------------------------------------

## How hard a bloc's own press pulls its salience gain away from the national average.
##
## THE DEVIATION IS MEAN-ANCHORED, and that is step 0's correction rather than the
## design's. The session was planned start-anchored -- the gain measured against the
## nation's own press stance at new game, which is start_service_quality's idiom and the
## one this project reaches for by reflex. Table (A) refuted it: `coalition_position` is
## what an outlet's alignment is measured against, and over 168 months France's travels
## 0.044 while Germany's travels 0.600 and Britain's 0.870. France holds a majority
## through every election, so its government's POSITION barely moves -- which put the
## constant at about 16 for Britain and about 250 for France. An anchor that is right
## for the roster and wrong for the player is docs/foreign-policy-model.md's
## globally-anchored amity in a new place.
##
## The pre-committed fallback was to delete the alignment term and let press_freedom
## backlash drive the deviation alone. REFUSED, because it makes the outlet register
## inert until the player passes a law, and a register nothing reads until a command
## fires is the decay docs/diplomacy-model.md's rule exists to prevent.
##
## Anchored on the size-weighted national mean instead, which buys six things the
## start-anchored version could not have -- the load-bearing one being that
## sum_b BLOC_SIZE[b] * dev[b] is EXACTLY 0, so the size-weighted mean gain is exactly
## SALIENCE_GAIN and every opinion constant measured since S10 keeps its calibration.
## tests/test_media.gd asserts that with exact equality rather than argument.
##
## Band, measured on a BLOC ROW and never on the headline -- step 0's table (B) is why:
## bloc-row headroom is 4.0-17.4 points, but an outlet names ONE audience, so the
## headline sees headroom x BLOC_SIZE. That is docs/diplomacy-model.md's finding for the
## sixth time, and here it is structural in the content schema rather than in a tuning
## table.
##   (i)  a hostile bloc's row moves past +-3.0 at the authored press, on `tax_max`;
##   (ii) `managed` -- a well-governed run -- must NOT move the headline past +-3.0.
##        Table (B) says FRA workers alone reaches 3.92 there, so this is a real
##        ceiling and not a formality: framing strong enough to destroy a well-governed
##        run is the second-approval-number failure section 5 warns about.
## Both edges were declared model criteria, so the tiebreaker was pre-committed as the
## MIDPOINT of the passing interval -- V1.5c's correction (e), applied rather than
## re-derived. IT WAS PRE-COMMITTED WRONG, TWICE OVER, and the two errors happen to
## cancel. This is the fifth distinct way a pre-committed tiebreaker fails and the
## reasoning is recorded here rather than in the doc alone:
##
##   1. BAND (ii) IS A BOUND AND NOT A SELECTOR -- V1.5a's failure (2), in the session
##      that inherited the warning. The `managed` headline moves 0.44 at beta 7.0 and
##      1.02 at beta 20.0, against a ceiling of 3.0. It never fires anywhere in the
##      reachable range, so it orders nothing. The interval's real upper edge is the
##      FRAMING_GAIN_MIN clamp, which is a GUARD RAIL.
##   2. SO V1.5c's RULE (e) SAYS THE MODEL EDGE GOVERNS AND THE SMALLEST PASSING VALUE
##      SHIPS -- and that is wrong here for a reason (e) did not contemplate. Rule (e)
##      was written against a LUMPY response: V1.5c's own table (d2) reads -2.11, -2.95,
##      -3.16, -9.01, so its floor sat on a shelf and refining the grid could not move
##      it. This response is LINEAR (2.98, 3.01, 3.12, 4.52, 5.45, 6.53, 9.27), so
##      "smallest passing" is just "wherever the band crosses": 3.02 clears the 3.0
##      floor by 0.3 %, and every refinement of the grid moves the answer. That is
##      V1.5b's widening diagnostic and V1.5c's refinement diagnostic, arriving through
##      the one rule that was supposed to be immune to them.
##
## THE RULE, EXTENDED: rule (e) assumes the model edge is a PLATEAU. When it is a smooth
## CROSSING, the model edge does not select either -- and with neither edge selecting,
## the only value stable under both widening and refinement is the interior. Both edges
## of [3.02, 6.00] are structural rather than grid artefacts (a band crossing and a
## clamp), so the midpoint is structural too, and it is the value furthest from both
## failure modes: unreadable below, off the simplex above.
##
## Midpoint of [3.02, 6.00] is 4.51; 4.50 is the nearest candidate. It reads 5.45 on a
## bloc row against the 3.0 floor and leaves the clamp slack until 6.20.
##
## BAND (i) IS MEASURED ON `managed>tax_max`, NOT ON `tax_max`, and that is V1.5c's
## reachability lesson applied rather than inherited as a sentence. Under `tax_max` from
## month 1 France loses the 2027 election and the run stops at month 16, so the band
## measured a government already on its way out -- and it showed a DISCONTINUITY there,
## 2.87 at beta 3.20 against 4.03 at 3.30, which is a discrete outcome flipping inside a
## sixteen-month window. Governing well for five years and only then provoking removes
## the discontinuity entirely. The cross-check was worth more than the constant.
const FRAMING_BETA := 4.50

## The floor under a framed gain, and it is not decoration.
##
## salience_weights() returns its weights UNNORMALISED when their total is non-positive,
## which is the one branch in that function that does not put the result on the simplex.
## A negative gain gets there: w = base * (1 + G * severity) goes negative for
## G < -1/severity. At that point docs/opinion-model.md's "a simplex cannot grow" is
## false and the [10, 90] approval-target bound goes with it.
##
## Zero rather than a small positive: gain 0 is the honest meaning of "this bloc's press
## does not amplify", and any positive floor would be a number with no argument behind
## it.
##
## SLACK BY 2.009 AT THE ORDINARY PRESS AND REACHED AT A SATURATED FREE ONE, and the
## second half is recorded rather than tuned away. press_freedom = +1.0 doubles the
## spread in both directions, so the bloc reading the paper friendliest to the government
## arrives at exactly zero and its readers stop amplifying bad news at all. That is
## DEFINITIONAL saturation rather than a guard rail doing a constant's work --
## unrest_constants.UNREST_MAX has the same character, "approached only under a player
## deliberately maximising it" -- and reaching it takes repeated liberalising laws.
##
## The sweep in table (C) very nearly missed this: its clamp column was measured at
## press_freedom = 0.0, where the binding point is beta 6.20, and at +1.0 it is 3.10. The
## clamps table now prints both stances, which is V1.3f's measuring-the-wrong-state error
## caught by a second table rather than by a later session.
const FRAMING_GAIN_MIN := 0.0

## The diameter of the two-axis ideology space -- sqrt(2^2 + 2^2), the distance from
## (-1,-1) to (+1,+1).
##
## GEOMETRY, NOT A TUNING, which is why this file carries its own copy rather than
## importing foreign_policy.gd's: that file preloads trade.gd which preloads coercion.gd,
## and media.gd is read from inside the monthly opinion tick. foreign_policy.gd says
## exactly this about its own copy.
const MAX_POSITION_DISTANCE := 2.8284271247461903


# --- Press freedom ------------------------------------------------------------

## The clamp on the accumulated press_freedom stance, symmetric.
##
## SIGNED BOTH WAYS, for the reason society_constants.CORRUPTION_MAX gives and one it
## did not need: there is no repeal verb in this project and a `once` law never returns,
## so [0, MAX] would be the permanent monotone charge docs/defence-model.md names -- and
## a press-liberalisation law would be INERT on a nation that has never censored,
## breaking docs/foreign-policy-model.md's property that nothing on the law list does
## nothing.
##
## The two ends are not mirror images even though the clamp is. At -1 every bloc's gain
## is flattened to exactly SALIENCE_GAIN: total censorship erases the media landscape
## and leaves the national average, which HELPS the blocs reading hostile papers and
## HURTS the blocs reading friendly ones. At +1 the spread doubles and a maximally free
## press polarises. That is what makes censorship a decision rather than a free win, and
## it is a property of the mean anchor rather than of this number.
const PRESS_FREEDOM_MAX := 1.00

## PRESS_UNREST_BETA is deliberately NOT here. It converts a press stance into grievance
## points, so it belongs beside SETTLEMENT_BETA and INEQUALITY_BETA in
## unrest_constants.gd -- the two coefficients it has to be compared against, and the
## file whose target reads all three. Keeping it here would also have cost unrest.gd a
## preload of this file, which tests/test_unrest.gd asserts the exact contents of.
##
## The rule the split follows is V1.5c's, applied rather than invented: the CLAMP on a
## register lives with the system that owns the register (PRESS_FREEDOM_MAX above, the
## way SETTLEMENT_STANCE_MAX lives with unrest), and the COEFFICIENT lives with the
## target that reads it.


# --- Content floors -----------------------------------------------------------

## The smallest authored reach that counts as an outlet.
##
## companies_constants.MIN_AUTHORED_SHARE's argument, transferred rather than copied:
## a firm too small to move its sector is a label, and an outlet nobody reads is a
## masthead. The floor is the same standard _validate_people() applies to an
## unreferenced person -- content with no reachable effect fails the load rather than
## sitting in a file looking like a feature.
const MIN_AUTHORED_REACH := 0.05
