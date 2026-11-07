extends VBoxContainer

## The effects strip -- docs/design/v5.3-ab.md 2.1: what a verb will do, read
## before it is pressed. At most three lines: the money (the balance in EUR bn a
## year, signed), who it moves, and when and what can go wrong. Every verb that
## shows one builds it here, so the player learns one shape once; V5.3 a + b step
## 1 fills the money line for the Budget's and the Tax Code's Commit, and the
## verbs with blocs, durations and risks (the Industry processes) fill the rest.
##
## THE FIGURES ARE THE SIM'S OWN. A money figure is the difference of two
## Budget.preview() snapshots -- the books with nothing pending and the books
## with the verb committed, on copies of the state -- so the strip shows exactly
## what Commit will book (band B1) and copies no formula. Today's estimate is
## exact because the sim is deterministic on a copy; the statistics service of e
## will turn it into a range here, in one place.
##
## TWO KINDS OF COLOUR, never mixed (AGENTS.md): the money wears a STATUS tone --
## GOOD on a balance gain, BAD on a loss, plain when it rounds to nothing -- and
## never the accent. Its sign is printed too, so the colour is never alone.

const Budget = preload("res://src/sim/budget.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Labels = preload("res://src/ui/labels.gd")

## The money line's grain: a tenth of a billion, which is also the boundary of
## its tone -- a figure that prints as zero wears no colour.
const MONEY_PLACES := 1

## The strip's own keys among a panel's per-lever figures: the whole commit and
## the other tab's draft. Not words a tax key can be (Statute admits lowercase
## letters, digits and underscores), so a born key named "commit" keeps its row.
const COMMIT := "@commit"
const ELSEWHERE := "@elsewhere"

## What Commit will move the balance by, in EUR bn a year; read by the tests
## beside the text the line prints.
var money_bn := 0.0
var money_label: Label
var _caption: Label
var _money_row: HBoxContainer
var _who: Label
var _when: Label
## Beneath the three lines, the OTHER tab's uncommitted draft on the same books
## (the Budget's line about the Tax Code's, and the mirror): never merged into
## this tab's figures, which are what this tab's Commit books, never silent
## either. Its Go is the panel's to route (go_pressed).
var elsewhere_label: Label
var _elsewhere_row: HFlowContainer

signal go_pressed


func _init() -> void:
	add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	_money_row = PanelKit.row(self, tr("Balance this year"), "")
	_caption = _money_row.get_child(0)
	money_label = _money_row.get_child(1)
	_who = PanelKit.plain_line(self, "")
	_when = PanelKit.plain_line(self, "")
	_elsewhere_row = PanelKit.buttons(self)
	elsewhere_label = PanelKit.plain_line(_elsewhere_row, "")
	# One line, sized to its text: a wrapping label in a flow container has no
	# width of its own and wraps at every letter.
	elsewhere_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var go := PanelKit.sized(Button.new())
	go.text = tr("Go")
	go.pressed.connect(func() -> void: go_pressed.emit())
	_elsewhere_row.add_child(go)
	hide()


## The three lines, and the other tab's draft. A line given nothing is not drawn,
## and a strip with neither money nor a draft elsewhere is not drawn at all: a
## verb that moves nothing has nothing to say here.
func show_effects(gain_bn: float, who := "", when := "", has_money := true,
		elsewhere := "", elsewhere_bn := 0.0) -> void:
	money_bn = gain_bn
	_caption.text = tr("Balance this year")
	_caption.visible = true
	money_label.text = money_text(gain_bn)
	money_label.theme_type_variation = cell_variation(money_tone(gain_bn))
	_money_row.visible = has_money
	_who.text = who
	_who.visible = who != "" and has_money
	_when.text = when
	_when.visible = when != "" and has_money
	elsewhere_label.text = elsewhere
	elsewhere_label.theme_type_variation = cell_variation(money_tone(elsewhere_bn))
	_elsewhere_row.visible = elsewhere != ""
	visible = has_money or elsewhere != ""


## A verb whose money is not one balance figure a year -- a process priced as a
## range on the debt, its Stop, a firm's verb with a one-off price beside a yearly
## bill (V5.3 a + b step 2, the Industry tab): the same three lines, the money line
## under the verb's own caption and already printed by the caller from the sim's
## figures. `gain_bn` gives the tone its sign: a gain to the public purse is GOOD.
func show_lines(caption: String, money: String, gain_bn: float, who := "", when := "") -> void:
	money_bn = gain_bn
	_caption.text = caption
	# No caption: the money stands at the line's start (a closure's narrow columns).
	_caption.visible = caption != ""
	money_label.text = money
	money_label.theme_type_variation = cell_variation(money_tone(gain_bn))
	_money_row.visible = true
	_who.text = who
	_who.visible = who != ""
	_when.text = when
	_when.visible = when != ""
	_elsewhere_row.visible = false
	visible = true


## "-4.1 to -4.6 bn", the strip's range (the truth's fog, spec 2.1); one figure
## when both ends print alike.
static func range_text(lo_bn: float, hi_bn: float) -> String:
	if money_text(lo_bn) == money_text(hi_bn):
		return money_text(lo_bn)
	return PanelKit.Strings.t("%s to %s bn") % [PanelKit.Num.fs(lo_bn, MONEY_PLACES), PanelKit.Num.fs(hi_bn, MONEY_PLACES)]


## Who a verb moves, read off its authored bloc offsets: the blocs it pleases, then
## the blocs it angers, each a sentence of its own.
static func who_text(offsets: Dictionary) -> String:
	var up := PackedStringArray()
	var down := PackedStringArray()
	for bloc in offsets:
		if float(offsets[bloc]) > 0.0:
			up.append(Labels.bloc(String(bloc)))
		elif float(offsets[bloc]) < 0.0:
			down.append(Labels.bloc(String(bloc)))
	var out := PackedStringArray()
	if not up.is_empty():
		out.append(PanelKit.Strings.t("Pleases %s.") % ", ".join(up))
	if not down.is_empty():
		out.append(PanelKit.Strings.t("Angers %s.") % ", ".join(down))
	return " ".join(out)


# -- The sim's figures, as the strip and the cells beside each lever print them --

## The balance gain from `before` to `after`, in EUR bn a year: each snapshot's
## own deficit in euros, the balance being its negative.
static func balance_bn(before: Dictionary, after: Dictionary) -> float:
	return (float(before["deficit_pct_gdp"]) * float(before["gdp_eur_bn"])
		- float(after["deficit_pct_gdp"]) * float(after["gdp_eur_bn"])) / 100.0


## A key of two snapshots, moved in EUR bn a year (a share of each one's GDP).
static func moved_bn(before: Dictionary, after: Dictionary, key: String) -> float:
	return (float(after[key]) * float(after["gdp_eur_bn"])
		- float(before[key]) * float(before["gdp_eur_bn"])) / 100.0


## "+6.0 bn", "-14.5 bn"; a figure that rounds to nothing prints unsigned.
static func money_text(bn: float) -> String:
	if absf(bn) < 0.05:
		return PanelKit.Strings.t("%s bn") % PanelKit.Num.f(0.0, MONEY_PLACES)
	return PanelKit.Strings.t("%s bn") % PanelKit.Num.fs(bn, MONEY_PLACES)


## A sum that may be small, in full: under a tenth of a billion in millions
## ("-23 m"), so a priced answer never reads "0.0 bn" (QA's TAKE on #270: a third
## of the playable majors' buyer searches cost under 0.05 bn).
static func sum_text(bn: float) -> String:
	if absf(bn) < 0.1 and absf(bn) >= 0.0005:
		return PanelKit.Strings.t("%s m") % PanelKit.Num.fs(bn * 1000.0, 0)
	return money_text(bn)


## A one-off sum to or from the treasury, or the words for none: a verb or an
## answer that moves no money says so rather than printing "0.0 bn".
static func cost_text(bn: float) -> String:
	if absf(bn) < 0.05:
		return PanelKit.Strings.t("No cost to the treasury.")
	return money_text(bn)


## GOOD only on a gain to the balance (band B1), BAD on a loss, plain at zero.
static func money_tone(gain_bn: float) -> PanelKit.Tone:
	if gain_bn >= 0.05:
		return PanelKit.Tone.GOOD
	if gain_bn <= -0.05:
		return PanelKit.Tone.BAD
	return PanelKit.Tone.PLAIN


static func cell_variation(tone: PanelKit.Tone) -> String:
	match tone:
		PanelKit.Tone.GOOD:
			return PanelKit.UiTheme.GOOD_TEXT
		PanelKit.Tone.BAD:
			return PanelKit.UiTheme.BAD_TEXT
	return ""


## The cell that prints one lever's effect, in the column beside its value.
## Empty until the lever moves; wide enough for "-14.5 bn" so the column does
## not open under the player's drag and shift the slider they are holding.
static func cell(grid: Control) -> Label:
	var label := Label.new()
	label.custom_minimum_size.x = 76
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(label)
	return label


## Each moved lever's own effect on the balance: `alone` maps a key to the
## pending that commits it and nothing else. Priced through Budget.preview(), one
## per key, CACHED by that pending and by the `now` books it was measured against
## -- a drag moves one key a frame, so one preview a frame, not one per lever (the
## lever drag is 37 ms since V5.1-0a and one preview is ~19 ms). A key moved alone
## is the whole proposal, so its figure is `whole`'s (priced here, once, when the
## caller has not) and costs nothing more.
static func per_key(cache: Dictionary, state, now: Dictionary, alone: Dictionary,
		whole_pending: Dictionary, whole: Dictionary) -> Dictionary:
	if not is_same(cache.get("", null), now):
		cache.clear()
		cache[""] = now
	var out := {}
	for key in alone:
		var hit: Array = cache.get(key, [])
		if hit.is_empty() or hit[0] != alone[key]:
			var after: Dictionary
			if alone[key] == whole_pending:
				if whole.is_empty():
					whole = Budget.preview(state, whole_pending)
				after = whole
			else:
				after = Budget.preview(state, alone[key])
			hit = [alone[key].duplicate(true), balance_bn(now, after)]
			cache[key] = hit
		out[key] = hit[1]
	return out


## The books with `pending` committed on a copy -- Budget.preview()'s own body --
## read for the three figures the Tax Code prints from: the balance's two (what
## Budget.snapshot() copies of them, so balance_bn() reads it like a preview) and
## each revenue line, the yields the snapshot does not carry. Not snapshot()
## itself: an effect baseline is Trends' (tests/test_effect_baselines.gd), and
## this is not one. Read only off the copy, so the panel writes no state.
static func books(state, pending: Dictionary) -> Dictionary:
	var sim = state.duplicate_state()
	Budget.commit(sim, pending)
	var ns = sim.player()
	return {"deficit_pct_gdp": ns.deficit_pct_gdp, "gdp_eur_bn": ns.gdp_eur_bn,
		"revenue_lines": ns.revenue_pct_gdp.duplicate()}


## A row's yield in EUR bn a year on `books_now`; an em dash for a row with no
## revenue line of its own (the brackets, which shape income's base).
static func yield_text(books_now: Dictionary, key: String) -> String:
	var lines: Dictionary = books_now["revenue_lines"]
	if not lines.has(key):
		return PanelKit.MISSING
	return "%.0f" % (float(lines[key]) / 100.0 * float(books_now["gdp_eur_bn"]))


## Writes each lever's cell: its effect, toned, or nothing while it is unmoved.
static func paint(cells: Dictionary, effects: Dictionary) -> void:
	for key in cells:
		var label: Label = cells[key]
		label.text = money_text(effects[key]) if effects.has(key) else ""
		label.theme_type_variation = cell_variation(money_tone(effects[key])) if effects.has(key) else ""
