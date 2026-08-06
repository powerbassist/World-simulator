extends RefCounted

## Tuned constants for the interest model. The model itself is
## src/sim/foreign_policy.gd; the argument for every number here is
## docs/foreign-policy-model.md.
##
## > [!important] Interest is MATERIAL. Ideology is one weak term.
## > This is the session's central call and every weight below follows from it.
## > tools/bloc_probe.gd table (d) prints the eight non-player members'
## > coalition_position and they are CLUSTERED -- economic spans -0.54..+0.33,
## > social -0.50..+0.63. An interest function resting on that alone gives nine
## > nations that behave alike, which is docs/trade-model.md's GRAVITY_EXPONENT
## > = 1.0 finding in a new place: nine vectors that are arithmetically one
## > vector. So the spine is the directed trade weight, which spans 0.007 to
## > 0.421 with 13.1x asymmetries, and the ideology terms below are the smallest
## > weights in the file on purpose.

# --- Stake: how much B weighs in A's foreign policy -------------------------------------

## An even share of one nation's attention across the other nine.
##
## Not a tuning number -- it is 1/9 -- but named, because every threshold in this
## file is expressed against it rather than against an absolute. That is what
## makes the thresholds mean "more than its fair share of my attention" for every
## nation identically, and it is the anchor src/ui/map_layers.gd's trade ramp
## already uses for the same reason.
const EVEN_SHARE := 1.0 / 9.0

## Economic exposure: the directed trade weight, straight from src/sim/trade.gd.
##
## The largest weight in the file, because it is the only input with a 13x spread
## and because it already carries partner size, EU co-membership, a shared border
## and the pair's relations, each measured at V1.3b.
const STAKE_DEPENDENCE_WEIGHT := 1.00

## History: how far this pair has been moved from where it would rest.
##
## Deliberately the ABSOLUTE displacement rather than the signed level, and
## deliberately measured against resting rather than against a fixed midpoint.
## Both choices are about not writing the same fact twice -- the relations LEVEL
## is already inside the trade weight above, so reading it again here would be the
## redundancy docs/coercion-model.md records the coercion probe cutting between
## severity and an authored tariff rate. What is NOT already in the trade weight
## is that somebody acted: a pair sitting at its resting value has no history, and
## a pair twenty points off it has a great deal whichever direction it went.
##
## Consequence, stated because it shapes how the model plays: at new-game every
## pair is exactly at rest, so this term is zero for all forty-five and stake is
## purely material. It grows as the game is played. That is the right direction.
const STAKE_HISTORY_WEIGHT := 0.40

## Points of relations displacement that count as one full unit of history.
##
## 20.0, from docs/diplomacy-model.md's own measured reachable range: sixty months
## of the strongest content at maximum legal cadence moves a pair +25.1 / -30.7,
## and a single action's displacement decays with a 35-month half-life. So a
## sustained campaign reaches roughly one unit and a single act reaches a fraction
## of one, which is the ordering the drift constant was itself justified on.
const STAKE_HISTORY_SPAN := 20.0

## Ideology, and the smallest weight in this section by design. See the note at
## the top of the file: the members are clustered, so this term can only ever
## separate nine nations by a little, and a model that leaned on it would ship
## nine nations that behave alike.
const STAKE_IDEOLOGY_WEIGHT := 0.15


# --- Amity: how warm A is toward B, signed ----------------------------------------------

## AMITY_NEUTRAL is DELETED, and the probe is why.
##
## It was 56.5, the midpoint of the two extreme resting tiers -- which put every
## GBR pair at -0.575 permanently, because all nine of Britain's pairs rest at the
## floor of 45. Measured: France signed 9 of 9, Germany 9 of 9, Britain **0 of 9**,
## unreachably. Amity is now measured against the PAIR'S OWN resting value, so
## structure stays in the trade weight where V1.3b measured it and this reads only
## sentiment. See ForeignPolicy.amity() for the full account.

## Points of relations away from a pair's resting value that saturate amity at
## +/-1.
##
## 20.0, from the same measured range STAKE_HISTORY_SPAN uses: sixty months of the
## strongest content at maximum legal cadence moves a pair +25.1 / -30.7. So full
## amity is reachable by sustained play and by nothing less, and every pair reads
## exactly 0.0 at new-game.
const AMITY_SPAN := 20.0

## How much shared ideology warms a pair, on top of the relations level.
##
## Small, for the clustering reason, and present at all only because two
## governments at opposite ends of the space should not read as identically warm
## as two that agree when their relations happen to match.
const AMITY_IDEOLOGY_WEIGHT := 0.20


# --- Whether a partner signs an agreement -----------------------------------------------

## Replaces diplomacy_constants.AGREEMENT_ACCEPT_MIN, which was V1.3b's declared
## stopgap: a pair score against one threshold, with nothing about the target
## consulted. The three weights below are the three things a government actually
## weighs about a trade deal -- do they matter to me, do I trust them, and is the
## deal any good -- and each is measured rather than authored.

## How much the partner's economic weight in my own trade counts.
const ACCEPT_STAKE_WEIGHT := 1.00

## How much the state of the relationship counts.
##
## Above the stake weight, deliberately: a trade agreement is a treaty before it
## is an arithmetic gain, and a partner you distrust is refused whatever it is
## worth. This is also what keeps V1.3b's finding alive rather than inverting it
## -- the gate remained a relationship gate, it stopped being ONLY that.
const ACCEPT_AMITY_WEIGHT := 1.20

## How much the terms on the table count -- the deal's own weight_multiplier
## above 1.0, which is the openness the partner gains by signing.
##
## The largest of the three, because it is the only one an author can move and
## therefore the only one that makes a generous deal genuinely easier to sell than
## a thin one. Without it every agreement in the game would be equally acceptable
## and the content's terms would be decorative to the counterparty.
const ACCEPT_DEAL_WEIGHT := 1.50

## The bar the three terms together must clear.
##
## Every term reads zero at neutral -- stake at exactly an even ninth, a pair
## exactly at its resting value, a multiplier of exactly 1.0 -- so this number is
## interpretable on its own: how far above indifferent a partner has to be.
##
## Swept by tools/foreign_policy_probe.gd, and CONSTRAINED FROM ABOVE BY GBR for
## the second time in this block. `rest` is partners signing at new-game, `+10` is
## after one settle_dispute, the strongest single positive verb in the content:
##
##   bar    FRA rest/+10   DEU rest/+10   GBR rest/+10
##   0.60      9 / 9          9 / 9          0 / 9
##   0.90      7 / 9          9 / 9          0 / 9
##   1.20      7 / 9          9 / 9          0 / 4     <-- shipped
##   1.50      6 / 8          7 / 9          0 / 0     <-- CLOSED to Britain
##
## 1.20, with a 0.30 margin against the value that shuts one playable nation in
## three out of the feature entirely -- docs/amendment-model.md's unreachable
## German two-thirds is what that margin exists to avoid, and clearing a bar by
## exactly nothing is docs/scenario-model.md's deu_grand_coalition mistake.
##
## The consequence is V1.3b's, unchanged and still forced: for Germany the gate is
## non-binding, because everyone depends on the largest economy in the roster and
## no bar that leaves Britain a feature can bite there. So an agreement's
## DIFFICULTY for an EU nation is carried by the action's domestic price, and for
## Britain the gate IS the difficulty. tests/test_trade.gd asserted exactly those
## two halves for V1.3b and asserts them again here.
const ACCEPT_MIN := 1.20


# --- Whether a partner signs a defensive pact (V1.3g) -----------------------------------

## The three weights of a pact offer. Here rather than in defence_constants.gd
## deliberately: whether a partner signs is the INTEREST model's question, and
## splitting a counterparty decision across two files gives two notions of amity
## that will drift. defence_constants.gd holds what a commitment costs; this holds
## whether anyone agrees to one.
##
## Set from tools/defence_probe.gd table (g), which sweeps all ninety ordered pairs
## at months 0, 24, 60 and 168.
const PACT_STAKE_WEIGHT := 1.00

## Above the stake weight, as ACCEPT_AMITY_WEIGHT is. An alliance is a promise to
## bleed for somebody; trust should matter more in it than in a trade deal, not less.
const PACT_AMITY_WEIGHT := 1.40

## The asker's capability, as a ratio against DEFENCE's CAPABILITY_REFERENCE. The
## smallest of the three on purpose: a strong ally is worth having, but nobody signs
## a mutual defence treaty with a nation they distrust because its army is large.
const PACT_CAPABILITY_WEIGHT := 0.60

## The bar, and it was set at 1.60 on the argument that a permanent contingent
## liability is a bigger ask than a trade agreement. THE SWEEP SAID OTHERWISE, and
## it is V1.3e's Britain finding for the sixth time in this block:
##
##       bar    accepts   GBR-in   GBR asks
##      0.80         51       13          5
##      1.00         35        9          4
##      1.20         24        4          1
##      1.40         18        2          0
##      1.60         13        1          0
##
## At 1.60 Britain could not ask ANY of the nine for a pact and appeared in exactly
## one accepting pair of ninety -- structurally unable to have an alliance policy,
## while three of the ten nations are playable. At 1.00 it can ask four and appears
## in nine, and 61 % of ordered pairs still refuse, so the register keeps its
## information.
##
## BELOW ACCEPT_MIN's 1.20 rather than above it, which inverts the original
## argument and is worth stating: a trade agreement carries a third term the asker
## can move -- a generous `weight_multiplier` pushes a marginal pair over the line.
## A pact has no such lever. The same bar therefore excludes strictly more here, so
## matching the numbers would not match the difficulty.
const PACT_ACCEPT_MIN := 1.00


# --- Whether and how hard a target retaliates -------------------------------------------

## Replaces coercion_constants.RETALIATION_FRACTION as the ANSWER; that constant
## survives as the CEILING. V1.3c's stopgap mirrored every measure back at a fixed
## fraction after a fixed delay, weighing nothing.
##
## The shape here is one line of arithmetic and everything interesting falls out
## of it rather than being authored:
##
##     answer = imposed * clamp(leverage / (1 + EXPOSURE_DAMPING * exposure), 0, ceiling)
##
## where leverage is w(imposer -> target) / EVEN_SHARE -- how much the imposer
## depends on me, which is how much my answer would hurt -- and exposure is
## w(target -> imposer) / EVEN_SHARE, how much I depend on them, which is how much
## it would cost me. Both read weights_before_measures() for the reason
## docs/coercion-model.md gives: you hurt in proportion to the trade you destroy.
##
## The consequence is the one V1.3c's directed table was built to make sayable and
## could not yet act on: a small nation heavily dependent on a large one answers
## barely at all, because answering costs it more than it collects. That is not a
## constant, it is a ratio of two numbers V1.3b measured.

## How heavily one's own dependence damps the answer. 1.00 makes cost and capacity
## exactly commensurate, which is the neutral reading and the one to sweep from.
const RETALIATION_EXPOSURE_DAMPING := 1.00

## How much a soured relationship sharpens the answer, as a fraction added per
## unit of negative amity. A nation that already resents you answers harder than
## its books alone would justify, which is the one place ideology and grievance
## are allowed to beat arithmetic in this file.
const RETALIATION_AMITY_GAIN := 0.50

## Below this answered severity, no measure is entered at all.
##
## A floor rather than a rounding: an entry in the register at severity 0.01 is a
## diplomatic incident on the nation panel and on the map's relations layer that
## costs the target nothing and the player nothing. Refusing to open one is the
## honest reading of "it is not worth answering", and it is what lets the model
## say NO rather than only saying HOW MUCH.
const RETALIATION_MIN_SEVERITY := 0.05


# --- What a third party makes of an act it was not party to -----------------------------

## Replaces V1.3a's stopgap, which was that no third pair moves at all.
##
## One signed rule, applied to every nation X outside the acting pair: an act by A
## on B is an act on everyone with a stake in B. X's relations with the ACTOR move
## with the sign of the act, and X's relations with the TARGET move against it --
## so a hostile act costs the actor standing with B's friends and wins the target
## sympathy from them, and a friendly one does the reverse. Both scaled by
## stake(X -> B), so a nation that does not care about B does not notice.
##
## V1.3a parked third-party effects on the grounds that they need an alliance
## model, which was V1.3f's. That was right at the time and is no longer: stake
## already carries EU co-membership and the shared border, so the channel exists
## without an alliance in it. Alliances at V1.3g make it stronger, not possible.

## How far X's relations with the actor move, per point of the act's own relations
## delta, at an even-share stake.
const THIRD_PARTY_JUDGEMENT := 1.00

## How far X's relations with the target move, on the same terms.
##
## Below the judgement weight: sympathy for the wronged is real and weaker than
## the grievance against the wrongdoer, and keeping it lower is also what stops a
## sanctions campaign against one nation from warming that nation's other pairs
## faster than it cools the imposer's.
const THIRD_PARTY_SOLIDARITY := 0.60

## Stake below which X does not react at all, as a fraction of an even share.
##
## Without a floor, every act moves all eight remaining nations by some tiny
## amount, and forty-five pairs drift on every click for reasons no readout could
## ever explain. With it, an act moves the pairs that have a reason to move.
const THIRD_PARTY_MIN_STAKE_SHARE := 0.45


# --- How a council member weighs a proposal ---------------------------------------------

## Replaces V1.3d's stopgap, which read coalition_position and nothing else -- so
## a member's answer to a fund it would pay for and a fund it would draw on was
## identical if the two sat at the same point in ideology space.
##
## Every weight below is against something in the member's OWN books, and every
## one of them differs across the eight where coalition_position does not.

## What a rule would cost me, read as the burden it would add against my CURRENT
## books. A member already compliant with a deficit rule pays nothing for it; one
## in breach pays its full severity. Nothing authors that -- it is
## docs/bloc-model.md's own France-against-Germany row, turned into a vote.
##
## 3.00 rather than 1.00, and the probe is why. At 1.00 a single rule's burden
## tops out at that rule's own severity, and docs/bloc-model.md rescaled the four
## authored severities to sum to exactly BURDEN_MAX -- so no one of them exceeds
## 0.33. Against an ideology term reaching 0.35 that made the two COMMENSURATE,
## and the measured result was a council in which every member already in breach
## of the deficit rule voted FOR it: AUT +0.168, DEU +0.225, FRA +0.135, all
## carried by ideology over a cost they were actually going to pay. The weak
## ideology term was not weak enough, which is the same failure in the other
## direction from V1.3d's council-of-priors.
##
## At 3.00 a full breach of one rule reads about 1.0, roughly three times the
## ideology ceiling -- so a rule that will bite decides the vote and ideology
## decides only between members it would not bite.
const APPRAISE_RULE_WEIGHT := 3.00

## What a transfer would cost me, per percent of GDP. Signed, so a fund a member
## draws on is a reason to vote FOR.
##
## The largest weight here, because a transfer is the one term that is money now
## rather than policy later, and because it is the term whose sign varies across
## the council.
const APPRAISE_TRANSFER_WEIGHT := 1.20

## How much fiscal stress sharpens the response to a transfer.
##
## Scaled against the member's own deficit past this pivot, so a nation running a
## comfortable budget and one running an emergency budget do not price the same
## contribution the same way. 3.0 is the deficit figure the bloc's own fiscal rule
## names, which makes it the one number in this file the player has already read
## somewhere else.
const APPRAISE_DEFICIT_PIVOT := 3.0

## What a collective external measure would cost me: the share of my own trade
## that goes to the nations it would be aimed at, times its severity.
##
## This is the term that makes a common external tariff a genuinely divisive
## proposal rather than a free one. A member that trades heavily outside the bloc
## pays for it; one that barely does gets it for nothing.
const APPRAISE_EXTERNAL_WEIGHT := 0.80

## The Gaussian ideology term V1.3d's support() was made entirely of, retained at
## a fraction of its former authority.
##
## Retained rather than deleted for a reason worth stating: a council that voted
## purely on its books would have no politics in it at all, and two members with
## identical economies genuinely should be able to disagree. What it must not do
## is DECIDE, which at 0.35 against three material terms it cannot.
const APPRAISE_IDEOLOGY_WEIGHT := 0.35


# --- The agenda: acting first, rather than answering ------------------------------------

## V1.3f. Everything above this line is REACTIVE -- each function answers a
## question somebody else asked, which is why V1.3e added no serialised field and
## left SAVE_VERSION at 11. The weights below are the first in this file that make
## a nation choose a target and a verb unprompted.
##
## > [!important] The nine are restrained by consequence abroad, not by politics
## > at home -- and that asymmetry is DECLARED, not papered over.
## > Every diplomatic action carries a bloc_offset domestic price, and for the nine
## > that price is dead state: Opinion.tick_month() is gated on has_budget, so a
## > non-player nation's bloc_offset is written and never read. Giving them a
## > synthetic "appetite" constant to stand in for it would be an authored number
## > in place of a model, which is what AGREEMENT_ACCEPT_MIN and SUPPORT_SIGMA were
## > deleted for. Lifting the guard is the coupled-economy rewrite
## > docs/trade-model.md books separately.
## >
## > So the restraint is material and it is already measured: what a hostile act
## > costs the actor in its own trade (COST) and what the target would do back
## > (RISK). Both reuse the weights V1.3b measured and the answer
## > retaliation_fraction() already computes. The player is checked at home; the
## > nine are checked abroad.

## Months between one nation's turns at the agenda.
##
## Staggered DETERMINISTICALLY across the ten by index in a sorted id list, not by
## rand(): src/sim/ contains no RNG at all, and the budget projection ticks
## Diplomacy forward on a copy -- so a projection, a reloaded save and a played
## game must make the same picks or the panel that promises "this is what will
## happen" is lying. The stagger is what stops nine nations acting in the same
## month and burying src/ui/message_stack.gd's six card slots.
##
## Swept by tools/foreign_policy_probe.gd against how many acts reach a player in
## fourteen years, against the year-14 saturation of the ninety directed pairs.
const AGENDA_INTERVAL_MONTHS := 9

## AGENDA_STAKE_WEIGHT and AGENDA_WARMTH_WEIGHT are DELETED, and the probe is why.
##
## Stake was a weight on a term ADDED to the sum: `stake/EVEN_SHARE - 1`, a
## standing reason to act on a big partner. A friendly verb carries no hostility,
## so it also carries no cost and no risk -- and nothing anywhere in the arithmetic
## then stopped a nation state-visiting its largest partner every cycle forever.
## Measured over fourteen years: mean relations 79.6 against resting tiers spanning
## 45 to 68, and a pair pinned at the RELATIONS_MAX clamp. Stake is now a
## MULTIPLIER on a bounded opportunity, where scaling it is exactly equivalent to
## scaling AGENDA_ACT_MIN -- so a weight of its own is a second dial for one
## quantity, which is the redundancy docs/coercion-model.md records the coercion
## probe cutting between severity and an authored tariff rate.
##
## The warmth weight went with the shape it belonged to. A single signed term
## `amity * (warmth - hostility)` is REINFORCING: warm pairs want more warmth. That
## is the ratchet stated in one line, and it is replaced by three bounded
## opportunities below rather than damped by a smaller number.
##
## Deleted rather than left at a value nothing reads -- AGREEMENT_ACCEPT_MIN and
## SUPPORT_SIGMA's case, one session on.

## How hard a partner's importance enters the agenda, as an exponent on its stake
## share.
##
## Below 1.0 for the reason trade_constants.GRAVITY_EXPONENT is below 1.0, and it
## is the same nation that forced both. Stake enters the agenda TWICE -- choosing
## which target to act on, and then valuing the act against it -- so a linear read
## squares an already 8x spread, and a winner-takes-all pick never descends past a
## nation's top two partners.
##
## TAKEN FROM trade_constants.GRAVITY_EXPONENT rather than swept independently, and
## said plainly because the distinction matters: the two constants answer the same
## question about the same nation over the same vector, and giving this one its own
## sweep would be two numbers describing one judgement -- the redundancy
## docs/coercion-model.md records the coercion probe cutting. It was verified, not
## fitted: table (g2) shows the ranking it produces, and Britain reaching the top of
## every other nation's list by month 24.
##
## Not sufficient on its own, and that is recorded rather than implied. At 0.70 the
## GBR column was still 0 acts in fourteen years; what actually fixed it was
## AGENDA_ACT_MIN, and the diagnosis is under that constant. This narrows the gap
## Britain has to close; the bar is what lets it close one.
const AGENDA_STAKE_EXPONENT := 0.70

## How warm a nation tries to make a relationship that matters to it, in amity
## units, before it stops spending diplomacy on it.
##
## THE constant that makes the ratchet structurally impossible. Above this, the
## `deepen` opportunity is exactly 0.0 whatever the partner is worth, so a pair
## cannot be walked to the clamp by a nation acting forever. Below 1.0 by
## necessity: amity saturates at +/-1, so a target of 1.0 would be unreachable and
## the term would never close -- docs/amendment-model.md's unreachable German
## two-thirds, in the one place here it would do real damage.
##
## 0.50 is half of AMITY_SPAN, which is ten points of relations above a pair's own
## resting value -- about one settle_dispute, the strongest single positive verb in
## the content. So a nation will spend roughly one good act on an important
## relationship and then leave it alone.
const AGENDA_AMITY_TARGET := 0.50

## How much a soured relationship is worth REPAIRING, against deepening a healthy
## one.
##
## Above 1.0 deliberately: a government with a damaged relationship it depends on
## has a more urgent problem than one with a merely adequate relationship, and this
## is the term that pulls relations back UP toward rest after an exchange. Without
## it the world only ever cools, which is the ratchet's mirror image.
const AGENDA_MEND_WEIGHT := 1.30

## How much a soured relationship is worth ANSWERING, against repairing it.
##
## The choice between mending and punishing is NOT decided here -- it is decided by
## the cost and risk terms below, which apply to the hostile verb and not to the
## friendly one. This weight only sets how loud the grievance is before those two
## price it, which is what keeps the decision material rather than authored.
const AGENDA_GRIEVANCE_WEIGHT := 1.00

## What a hostile act costs the actor in its own trade, per even share of its own
## exposure to the target.
##
## Reads weights_before_measures() for the reason docs/coercion-model.md gives at
## length: the trade you destroy is the trade you had, not the trade that survives.
## This is one half of why a small nation does not sanction a large one, and it is
## the mirror of retaliation_fraction()'s own FRA/LUX finding arrived at from the
## acting side rather than the answering side.
const AGENDA_COST_WEIGHT := 1.00

## What the actor expects back, as the fraction retaliation_fraction() says the
## target would answer with.
##
## The second half of the same restraint, and deliberately a separate term rather
## than folded into COST: exposure is what an act costs me by itself, retaliation
## is what the other side chooses to do about it, and a nation can be cheap to hit
## while being dangerous to hit. Reusing the answering model here rather than
## authoring a symmetric one is what keeps the two sides of an exchange consistent.
const AGENDA_RISK_WEIGHT := 1.20

## What an act costs its own government at home, per unit of the action's authored
## bloc_offset magnitude.
##
## The one term that is NOT about the world, and it is here because the probe
## found its absence unmistakable: with only hostile acts priced, `settle_dispute`
## was nineteen of the last twenty-four acts of a fourteen-year run. It is the
## largest friendly verb in the content and the most expensive -- six blocs at
## -0.09, which the summary calls a climbdown -- and the nine were conceding a
## long-running national quarrel about once a year each, for free.
##
## Not the synthetic appetite constant this session refused: it reads the action's
## OWN authored price, exactly as accept_score() reads `weight_multiplier`. The
## content already states how hard each act is and the nine were the only ones not
## listening.
##
## Swept by tools/foreign_policy_probe.gd table (d3), on which verb a nation picks
## against its most important partner:
##
## on which verb each of the ten picks against its own most important partner:
##
##   weight   picks
##   0.00     settle_dispute x10                  <-- the concession is the norm
##   0.25     settle_dispute x7  state_visit x3
##   0.50     state_visit x10                     <-- flips here
##   1.00     state_visit x10                     <-- shipped
##   2.00     state_visit x10
##   4.00     state_visit x10
##
## 1.00, which is 2x the value the choice flips at. NOT higher, and the reason is
## an interaction the first attempt at this constant got wrong: the term applies to
## HOSTILE verbs too, and impose_tariffs carries 0.42 of authored offset against
## impose_sanctions' 0.48. At 2.00 the penalty is 0.84 to 0.96 and NO pair anywhere
## in the roster can mount a hostile act -- measured at 0 of 90 ordered pairs driven
## to full grievance, which is the coercion half of the agenda shipping as dead
## code. At 1.00 it is 6 of 90.
##
## So the constant is bounded from BELOW by the concession spam and from ABOVE by
## coercion becoming unreachable, and 1.00 is the only swept value comfortably
## inside both. That six pairs rather than sixty can coerce is the model rather
## than the number: acting first against a partner needs you to both resent them
## AND not depend on them, which is docs/coercion-model.md's leverage finding
## arriving from the acting side. The ordinary way a player receives coercion is
## still retaliation, which _tick_retaliation() has owned since V1.3c.
const AGENDA_DOMESTIC_WEIGHT := 1.00

## The bar the four terms together must clear for a nation to act at all.
##
## Every term reads zero at neutral -- stake at exactly an even ninth, a pair
## exactly at rest, a purely rhetorical act with no measure behind it -- so this
## number is interpretable on its own, exactly as ACCEPT_MIN is.
##
## This lets the agenda say NOTHING, the same job RETALIATION_MIN_SEVERITY does for
## an answer. It is NOT the main brake, and that is the model correction rather
## than a detail: the brake is AGENDA_AMITY_TARGET closing the `deepen` opportunity
## as a relationship improves. A bar alone cannot stop a ratchet, it can only slow
## one.
##
## > [!warning] The static sweep measured the wrong state, and said 0.05
## > tools/foreign_policy_probe.gd table (d2) sweeps this at NEW-GAME, where the
## > best desire anyone has against Britain is 0.1309 and a bar of 0.20 closes the
## > GBR column to zero. Read that way 0.05 looks right: 2.6x margin on the binding
## > pair, four times under the closing value.
## >
## > It is wrong, because new-game is not the binding state. Table (g2) prints the
## > same nations at months 0, 24 and 60, and by month 24 Britain IS everyone's top
## > pick -- and the entire desire landscape has fallen under 0.05. ITA -> GBR reads
## > 0.042, ESP 0.029, NLD 0.024. Two things pull it down together: `deepen` closes
## > as pairs approach AGENDA_AMITY_TARGET, and Britain's own room closes from
## > third-party judgement spillover WITHOUT ANYONE HAVING ACTED ON IT.
## >
## > So the measured failure was not that Britain is outranked -- it is outranked
## > for two years and then wins -- but that the world goes SILENT after two years
## > and Britain's turn never comes. Acts aimed at a GBR player over fourteen years:
## > 0 at bar 0.05, 35 at bar 0.02. FRA 52, DEU 58.
##
## 0.02, set on the dynamic measurement rather than the static one. The static
## column is kept in the probe because it is what makes the correction legible.
##
## What "100% of pairs live at new-game" does NOT mean is that everything happens:
## a nation acts once per AGENDA_INTERVAL_MONTHS and takes only its BEST candidate,
## so the ceiling on activity is the cadence. Fifty-odd acts across nine nations in
## fourteen years is what it actually produces. And the thing that makes pairs go
## quiet as a game is played is AGENDA_AMITY_TARGET, not this -- which is the whole
## model correction this session made.
const AGENDA_ACT_MIN := 0.02

## Stake below which an act between two OTHER nations does not earn the player a
## card, as a fraction of an even share.
##
## The same shape and the same units as THIRD_PARTY_MIN_STAKE_SHARE, and it exists
## for the same reason: message_stack.gd holds six cards and drops the oldest, so
## an unfiltered feed of nine nations acting on a cadence would push a sanction
## aimed at the player off the column before it was read. An act aimed AT the
## player always cards regardless of this floor -- that branch is in src/ui/, not
## here, because what is worth showing is a UI question and what happened is not.
const CARD_MIN_STAKE_SHARE := 0.90

## How many acts GameState.foreign_acts keeps before dropping the oldest.
##
## Held here rather than on GameState because the writer owns the bound -- the
## shape main.gd's RECENT_EFFECTS_KEPT already has, and forced anyway, since
## game_state.gd preloads diplomacy.gd and the dependency runs one way.
##
## Above message_stack.gd's six card slots on purpose: the stack shows what is
## worth interrupting the player for, this is what actually happened, and the
## record has to outlive the cards drawn from it.
const AGENDA_ACTS_KEPT := 24
