extends RefCounted

## Every tunable in the party-discipline model, in one file. Same shape as
## economy_constants.gd, opinion_constants.gd, election_constants.gd,
## legislature_constants.gd and government_constants.gd — model parameters, not
## content, so not in data/, per docs/engine-decision.md Rule 1.
##
## The party's own `discipline` in data/parties/*.json stays content: it says how
## cohesive that particular invented party is at its best. Everything here says
## what the world does to that number, which is the same for every party.
##
## Rationale for every number is docs/discipline-model.md; this file is the
## values, that file is the argument.

# --- Where discipline is heading -------------------------------------------------

## The authored figure is a party at its best, so the target is only ever pulled
## *down* from it. Nothing in the model can make a party more cohesive than its
## own content says it is -- content is the ceiling, the model is the erosion.
##
## Below this a party has no line left to speak of. Not zero: a party whose
## members ignore it entirely is not a party, and every formula that reads
## discipline would then read the same as if the party were not in government.
const DISCIPLINE_MIN := 0.10

## How much of the authored discipline an utterly unpopular government costs its
## own coalition. Scaled by (APPROVAL_NEUTRAL - approval) / APPROVAL_SPAN, so it
## reaches full strength only at the floor of the approval model's range and is
## exactly zero for any government at or above neutral.
##
## Members of an unpopular government start voting for their own re-election
## rather than for the whip. This term plus the one below are what turn a
## nominal majority into a smaller real one over a term.
const APPROVAL_TERM := 0.50

## How much an imminent legislative election costs, on top of the approval term.
## Smaller, because it is about timing rather than standing: a popular government
## still holds its majority into an election.
const ELECTION_TERM := 0.20

## Months before a legislative election at which members start looking to their
## own seats. Ramped linearly from here to zero rather than switched on, so there
## is no month where the assembly's behaviour changes discontinuously.
const ELECTION_HORIZON_MONTHS := 12

## Fraction of the gap to target closed per month. Half-life ~8 months.
##
## Much slower than opinion_constants.INERTIA_RATE (0.25, half-life ~2.4 months),
## and deliberately: a poll turns in a news cycle, a parliamentary party's
## cohesion does not. This is also the term that stops a single bad month from
## costing the player their majority -- discipline follows the trend in approval,
## not its noise.
const DISCIPLINE_INERTIA := 0.08

# --- Disaffection ----------------------------------------------------------------

## How much an utterly unpopular government adds to an *undisciplined* coalition
## partner's willingness to bring it down. Scaled by unpopularity and by
## (1 - discipline), so a disciplined party stays loyal whatever the polls say and
## a party whose whips have lost the room does not.
##
## This term exists because without it discipline has no route into the censure
## arithmetic at all. government.gd's hostility() reads a partner's distance from
## the agreed position, and the formation search deliberately builds coalitions
## out of parties that are close to it -- on the authored French roster the three
## governing parties sit 0.26, 0.32 and 0.36 from the line, giving a raw hostility
## near -0.8 apiece. Subtracting discipline only pushes that further down, so
## eroding it could never flip a partner, and a censure motion could never reach
## 289 no matter how badly the player governed. Measured, not assumed: see
## docs/discipline-model.md.
##
## Cohesion and disaffection are two different questions. Cohesion asks whether a
## party likes this government's policy; disaffection asks whether its members
## want to be standing next to it at the next election. Only the second explains
## why coalitions collapse under unpopular leaders, and the model had no term for
## it before V1.1b.
##
## 1.0 is set so that a party at the discipline floor under a government at the
## bottom of the approval range crosses from "against" to "for" on a censure
## motion that follows a forced bill, and does not cross before that. A
## government at or above neutral approval is untouched by this term entirely.
const DISAFFECTION := 1.0

# --- Rebellion -------------------------------------------------------------------

## The largest share of a party's seats that can ever break from its own line on
## one vote. A party that loses more than a third of its seats on a division has
## split rather than rebelled, and splits are not modelled.
const REBEL_MAX := 0.35

## The strain at which the rebellion term saturates -- the gap between what a
## party votes and what its members would vote unwhipped.
##
## Equal to government_constants.COALITION_BONUS_MAX (0.45), which is the largest
## pull the whip can exert on a bill, so a party dragged as far as the model
## allows rebels at REBEL_MAX * (1 - discipline) and no further. Written as its
## own number rather than as a reference because the censure vote measures a
## different strain -- the discipline term itself -- against the same scale.
const REBEL_STRAIN_SCALE := 0.45

# --- What a vote costs -----------------------------------------------------------

## Applied to a party whose members broke ranks, scaled by how large the
## rebellion was as a share of REBEL_MAX. A whip that failed fails more easily
## next time; recovery is the ordinary inertia pull back toward target, so this
## is a step down and not an accumulator.
const REBELLION_PENALTY := -0.05

## Applied to every coalition party when a bill is forced through under Article
## 49.3. Bypassing your own majority is an insult to it, and this is the second
## price the article charges -- government_constants.FORCE_BLOC_PENALTY is what
## it costs with the public, this is what it costs in the chamber.
const FORCE_DISCIPLINE_PENALTY := -0.07

## Gameplay #157 (docs/design/v5.2-bplus-spec.md "R4", "The Assembly"). Applied to
## the holder's party at every removal of its portfolio -- Dismiss, or Reassign away,
## the president's own party included (Removal._removed). Above 49.3's -0.07, which
## insults the whole majority, because a dismissal singles one party out; equal to
## two full rebellions. No decay of its own: the tick's DISCIPLINE_INERTIA pulls it
## back, 0.92^n of the step left after n months (a half-life of about 8.3).
const DISMISSAL_DISCIPLINE_PENALTY := -0.10
