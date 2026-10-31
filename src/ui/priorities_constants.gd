extends RefCounted

## The monthly briefing's ranking, as tuning -- V5.3-0 (docs/design/v5.3-0-readability.md
## 2.3). UI tuning beside the UI, as sound_constants.gd is: the ranking lives in
## src/ui because its fog rules read two src/ui modules (the poll reading and the
## feeling bands), and a src/sim file importing either would break rule 2.
## Band RF2 is what these numbers are tuned to.

## The kinds, in the table's row order: the third tie-break after weight and
## deadline, and the order a quiet month's standing reads come in.
const KINDS := ["crisis", "election", "decision", "bill", "majority", "commitment",
	"request", "programme", "bloc", "budget", "unrest", "person"]  # i18n: ok kind keys

## W, the weight of a kind. A decision weighs by its severity (sev 2 at 8, sev 1 at
## 6); every standing read weighs 1, so it only fills a slot nothing urgent wants.
const WEIGHT := {"crisis": 10.0, "election": 9.0, "decision_major": 8.0, "decision_minor": 6.0,
	"bill": 8.0, "majority": 8.0, "commitment": 7.0, "request": 6.0, "programme": 6.0,
	"bloc": 5.0, "budget": 5.0, "unrest": 5.0, "person": 4.0}  # i18n: ok weight keys
const STANDING_WEIGHT := 1.0

## U, urgency, by months to the deadline: at most 1 month away, 3, 6, then beyond.
const URGENCY_STEPS := [[1, 1.0], [3, 0.7], [6, 0.4]]
const URGENCY_FAR := 0.2
## A trend has no deadline: louder in the month it first qualifies, quieter after.
const TREND_ONSET := 0.7
const TREND_AFTER := 0.4
## A standing read has neither: it sits at the quiet end of the urgency scale.
const STANDING_URGENCY := 0.4

## M, magnitude, is clamped to this range.
const MAGNITUDE_MIN := 0.5
const MAGNITUDE_MAX := 1.5
## A desk entry's magnitude by severity (1, 2, 3).
const SEVERITY_MAGNITUDE := [0.75, 1.0, 1.5]
## A bloc's move counts one magnitude unit per this many points; the deficit's per
## this many points of GDP.
const BLOC_POINTS_PER_UNIT := 5.0
const DEFICIT_POINTS_PER_UNIT := 1.0

## N, novelty: the factor on a line shown last month whose urgency and size did not
## rise -- and never on a deadline this close (GLM's finding 3: a request about to
## lapse must not give way to a fresh trend).
const NOVELTY := 0.6
const NO_DAMPING_MONTHS := 3

## The election is a priority, not a standing read, once it is this close.
const ELECTION_NEAR_MONTHS := 6
## A crisis is an interrupt, or a desk entry of this severity.
const CRISIS_SEVERITY := 3
## A major card holds a slot (with an interrupt and a minor card in its last month).
const MAJOR_SEVERITY := 2

## The bloc trend: the polled mean of the last BLOC_WINDOW months against the mean
## of the BLOC_WINDOW before, moved by more than twice the poll's margin. The Society
## panel states "about 3 points" (poll_noise.gd's NOISE_MAX_PCT); a mean, because a
## 5-point move between two noisy readings is often the noise (GLM's finding 10).
const BLOC_WINDOW := 3
const BLOC_MARGIN_POINTS := 3.0
## The budget trend: the deficit worse by this many points of GDP against a year ago.
const DEFICIT_RISE_POINTS := 0.5
const DEFICIT_WINDOW_MONTHS := 12
## The unrest trend: rising in each of this many months, read from the briefing's own
## memory (unrest is not in state.history).
const UNREST_RISING_MONTHS := 3
## A person is a priority once their grudge reaches Feelings' "hostile, may leak":
## that band's lower cut, read from the table rather than copied (QA's RECORD on #218).
const HOSTILE_GRUDGE: float = preload("res://src/ui/feelings.gd").BANDS["grudge"][2][0]

## What a priority's Go opens, by kind (2.4): a domains.gd tab id, or "inbox" for a
## desk card raised in the inbox, or "person" for the person card.
const GO_TAB := {"crisis": "inbox", "decision": "inbox", "election": "campaign",
	"bill": "legislature", "majority": "politics", "commitment": "calendar",
	"request": "calendar", "programme": "agenda", "bloc": "legislature",
	"budget": "budget", "unrest": "society", "person": "people"}  # i18n: ok tab ids
