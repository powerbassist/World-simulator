extends RefCounted

## V5.3 b, band B5 (docs/design/v5.3-ab.md 4.3): the address's tuning. The shifts, the
## discount and the fade are the spec's first proposals; the others are stand-ins, labelled.

## Points of support an address moves among the blocs leaning toward a bill, and the neutral.
const SHIFT_TOWARD := 6.0
const SHIFT_NEUTRAL := 3.0
## The blocs against harden by this share of SHIFT_TOWARD, the other way. Repetition does not
## discount it, it grows it by HARDEN_GROWTH per earlier address in the window: an opponent
## minds a president always on air more. A STAND-IN: at the spec's flat 30 %, always addressing
## won bills in France and Britain (tools/legislature_probe.gd), since a tight yes line lost too
## few seats for anything to flip.
const HARDEN_SHARE := 0.3
const HARDEN_GROWTH := 0.5
## The k-th address within the window persuades REPEAT_WORTH^(k-1) of the first.
const REPEAT_WORTH := 0.6
const REPEAT_WINDOW_MONTHS := 6
## A shift fades to nothing over this many months, a third at a time.
const FADE_MONTHS := 3
## A bloc whose yes on the bill (Referendum.bloc_yes) is this far from even leans. A STAND-IN.
const LEAN_BAND := 0.1
## The persuasion skill does not exist yet ([[v5.3-skills]] 3). A LABELLED STAND-IN, read flat.
const PERSUASION_FLAT := 1.0
## Standing: approval over neutral, within these. A STAND-IN.
const STANDING_MIN := 0.5
const STANDING_MAX := 1.5
## How far a bloc's own outlets carry it: 1 + this x their reach x their alignment with the
## government, within these. A STAND-IN, and the same alignment the press's framing reads.
const OUTLET_BETA := 0.5
const OUTLET_MIN := 0.5
const OUTLET_MAX := 1.5
## What an address costs each bloc against, on bloc_offset, permanent. A STAND-IN the spec does
## not name and the band needs: nothing else makes always addressing end lower in approval.
const APPROVAL_PRICE := 0.004
