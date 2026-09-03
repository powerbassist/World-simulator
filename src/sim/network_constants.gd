extends RefCounted

## Tuning for src/sim/network.gd. See docs/network-model.md.
##
## ONE SWEPT CONSTANT AND ONE DERIVED LENGTH, which is one more than
## src/sim/region_constants.gd ships and one fewer than the row implied. The graph
## itself carries no constant at all: adjacency is derived from the polygons,
## distance is great-circle, the endowment is measured, and the sea-link count is
## the number of components adjacency leaves. What is genuinely a free parameter is
## how hard a region's position is allowed to move its growth, and that is
## NETWORK_BETA alone.


## How far a region's growth deviates, in points per year, per unit of
## `specialisation * ln(accessibility)`. The session's only tuned constant.
##
## MULTIPLIED BY SPECIALISATION RATHER THAN STANDING ALONE, and that is the model
## rather than a coefficient: a region that makes what everyone else makes has no
## reason to care how far the market is, and one that makes something nobody near it
## makes has every reason. So the two terms are a product and the sweep sees one
## number -- V1.6e's refusal of a second authored strength, applied to a pair of
## measured quantities instead of to a pair of dials.
##
## MEASURED, not guessed: set to 0.0 at Task 6 and swept at Task 8, on the project's
## own order. Until the sweep runs the channel is inert and the balance harness is
## bit-identical, which is what makes Task 6 committable on its own.
##
## BAND, two clauses, both fixed before the sweep (docs/network-model.md section 6):
##   (i)  READABLE. Over 60 months the largest mover's share of national output must
##        move at least 0.1 percentage point -- one digit of src/ui/region_panel.gd's
##        own "%.1f%%", V2.6a's clause (i) on the output partition instead of the
##        population one.
##   (ii) BOUNDED. Over 168 months no region's share of national OUTPUT may drift
##        past region_constants.SHARE_DRIFT_MAX, and no region's share of national
##        POPULATION past the 0.0164 ceiling migration_constants.MIGRATION_RATE is
##        measured against -- because the network term moves output per head, which
##        is half of the Harris-Todaro pull, so it moves people too.
const NETWORK_BETA := 0.0


## The decay length of the market-potential sum, in endowment-adjusted km.
##
## DERIVED, NOT SWEPT, and the derivation is the graph's own: the continental
## component's diameter is 13 hops and its mean eccentricity 9.65, so a decay length
## that puts a region's own weight at e^-1 by the mean eccentricity makes the index
## read the CONTINENT rather than a region's own neighbours or the whole of Europe
## flat. Measured at Task 8 as the mean shortest-path km at that hop count and
## written here; it is a property of the roster, so a re-import that changes the
## roster changes it and tools/network_probe.gd prints it every run.
const DECAY_KM := 0.0
