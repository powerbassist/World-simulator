extends RefCounted

## V5.2d front pages (docs/design/v5.2-d-spec.md section 4). The numbers the
## press reads; src/sim/front_page.gd is their one reader.

## An outlet's tone toward the government, Media.outlet_alignment() cut in
## thirds of its [-1, +1] range at +/- TONE_CUT with the shared 1e-9 rule
## (src/core/cut.gd): friendly above, hostile below, neutral between. The
## headline templates are keyed by these three ids (data/headlines/).
const TONES := ["friendly", "neutral", "hostile"]
const TONE_CUT := 0.33

## An event earns a front page at this severity or above: the game's own
## "major" and "critical" (events_constants.SEVERITY_*), which includes every
## exposure. The author asked for "events importants"; minor events are the
## month's noise.
const EARNS_SEVERITY := 2

## A political moment's severity, for the tie-break against events: an
## election result, a government falling and a dissolution are critical; a law
## forced by 49.3 and a character's act are major.
const MOMENT_SEVERITY := {
	"election": 3,
	"censure": 3,
	"dissolution": 3,
	"article_49_3": 2,
	"character": 2,
}

## The card shows the lead story from at most two papers, and at most this
## many more stories as one line each ("also on the front page").
const ALSO_MAX := 2
