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
