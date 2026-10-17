extends RefCounted

## Every tunable in the election model, in one file. Same shape as
## economy_constants.gd and opinion_constants.gd — model parameters, not content,
## so not in data/. Rationale for every number is docs/election-model.md and
## docs/electoral-systems.md; this file is the values, those are the argument.
##
## Ideology-slot names appear here and nowhere else in code — data_loader.gd
## validates every parties/*.json slot against SLOT_KEYS at startup, so an
## unpositioned slot fails loudly instead of scoring zero affinity silently.

# --- Ideology space ------------------------------------------------------------

## Two axes: economic (-1 left … +1 right), social (-1 open … +1 traditional).
## Twelve slots exist across the ten authored party rosters today; four are
## one-offs (regionalist, regionalist_right, centrist, progressive_liberal), and
## each still gets a position — an authored slot with no position is exactly the
## silent-zero-affinity bug this table exists to prevent.
const SLOT_KEYS := [
	"centrist_liberal", "centre_right", "social_democratic", "green",
	"nationalist_right", "left_populist", "christian_democrat", "liberal",
	"regionalist_right", "regionalist", "progressive_liberal", "centrist",
]

const SLOT_POSITION := {
	"centrist_liberal":    {"economic":  0.1, "social": -0.3},
	"centre_right":        {"economic":  0.5, "social":  0.2},
	"social_democratic":   {"economic": -0.5, "social": -0.2},
	"green":               {"economic": -0.3, "social": -0.6},
	"nationalist_right":   {"economic":  0.3, "social":  0.8},
	"left_populist":       {"economic": -0.8, "social":  0.1},
	"christian_democrat":  {"economic":  0.3, "social":  0.5},
	"liberal":             {"economic":  0.4, "social": -0.5},
	"regionalist_right":   {"economic":  0.2, "social":  0.6},
	"regionalist":         {"economic": -0.1, "social":  0.3},
	"progressive_liberal": {"economic":  0.0, "social": -0.8},
	"centrist":            {"economic":  0.0, "social":  0.0},
}

## Each bloc's ideal point on the same two axes. Reused, not invented: the sign
## and rough magnitude follow directly from what opinion_constants.gd's
## BLOC_SALIENCE_BASE already says each bloc cares about — pensioners weight
## pensions and health (state spending, so left-of-centre economically) but are
## the most socially traditional bloc; students are left economically and the
## most socially liberal bloc; business is the only bloc right of centre.
const BLOC_IDEAL := {
	"workers":    {"economic": -0.6, "social":  0.1},
	"pensioners": {"economic": -0.2, "social":  0.5},
	"urban":      {"economic": -0.3, "social": -0.6},
	"rural":      {"economic":  0.1, "social":  0.6},
	"business":   {"economic":  0.7, "social":  0.1},
	"students":   {"economic": -0.5, "social": -0.8},
}

## How fast affinity falls off with ideological distance. The space spans a
## 2x2 square, corner-to-corner distance ~2.83; at this sigma a bloc sitting on
## top of a slot scores affinity 1.0 and a bloc a full axis-width away (distance
## 1.0) scores ~0.32 — close enough to still compete for, far enough to lose most
## of the prominence prior.
const AFFINITY_SIGMA := 0.8

## Share of the electorate that turns out, by bloc. Not from any dataset — a
## legible ordering matters more than a precise one: pensioners vote most
## reliably, students least, everyone else in between. Same "six numbers, not a
## model" shape as BLOC_SIZE.
const BLOC_TURNOUT := {
	"workers": 0.65,
	"pensioners": 0.82,
	"urban": 0.62,
	"rural": 0.70,
	"business": 0.75,
	"students": 0.45,
}

## The incumbent's vote-share multiplier is (1 + INCUMBENT_SWING * pull), with
## pull in [-1, 1]. 0.9, not 1.0, so the multiplier lands in [0.1, 1.9] — a
## universally hated incumbent shrinks hard but never hits zero, a beloved one
## roughly doubles. Guard rail, not a modelling claim, the same reasoning as the
## economy's clamps.
const INCUMBENT_SWING := 0.9

# --- Electoral systems ----------------------------------------------------------

## Power-law exponent for a single-member-plurality reduction: seat share ∝
## vote_share^exponent, renormalised. The MVP has no constituency geography (the
## map is S8, national borders only), so FPTP and two-round systems cannot be
## simulated seat by seat; this is the classic empirical "cube law" relationship
## between vote share and seat share under FPTP, softened for France's two-round
## system where second-round alliances damp the amplification a plurality system
## produces on its own.
const FPTP_EXPONENT := 3.0
const TWO_ROUND_EXPONENT := 2.0

## Italy's Rosatellum: roughly 61% of seats by proportional list, the remainder
## by single-member plurality contests this model cannot simulate seat by seat
## either, so the majoritarian share is approximated the same way FPTP is.
const PARALLEL_PR_WEIGHT := 0.62

# --- Election night (V4.9b) -----------------------------------------------------

## The regional swing election night draws, and why it exists at all. The model
## has no regional vote: vote_share() is one national number per party. A night
## where every region reported the national shares would be thirteen identical
## rows, so regional_shares() TILTS the incumbent per region by how far that
## region's unemployment sits from the national rate, weighted by how much the
## electorate cares about jobs -- the one issue the regions already carry data
## for (relative unemployment, imported). Where jobs matter, the regions hit
## hardest turn hardest on whoever governs. Display only: the tilts are
## renormalised so the population-weighted total is the verdict EXACTLY, and
## nothing reads them back into the sim.
##
## 2.0 was measured, not felt (tests/test_elections.gd prints it): at France's
## opening (jobs salience 0.165) the incumbent runs 24.4 % to 28.0 % across its
## thirteen regions around a national 26.5 % -- enough that the lead moves as
## the count comes in, small enough that no region reads as a landslide the
## national number does not contain.
const REGION_SWING := 2.0
## Guard rail on one region's multiplier, the INCUMBENT_SWING reasoning: an
## outlier region (an overseas department at three times the national rate) must
## not be drawn handing the incumbent nothing, or double.
const REGION_TILT_MAX := 0.35
