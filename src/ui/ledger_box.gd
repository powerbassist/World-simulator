extends RefCounted

## The typed box beside a ledger slider -- V5.3 screen 4, PR 3. The slider is the quick move on a
## grid of one step; the box is the exact one, and it may hold a value the grid does not: France's
## fuel duty starts at 0.67 and its slider steps by 0.02, so a slider alone could not print the
## rate the law carries. The step and its decimals are the SIM's (TaxLibrary.step_pct and
## step_decimals), never derived here; this file only prints and reads a figure.
##
## What the box prints is the shortest decimals that show the value exactly (at most four: the data carries 0.6545), never
## fewer than the step's: a VAT of 8.1 prints "8.1" under a whole-point step, and an untouched row
## prints back the rate the nation starts with. The player's own decimal separator is written
## (Num.f) and read (parse() takes either).

const Num = preload("res://src/ui/num.gd")

## Most decimals a figure is shown with (the data's own finest is four), past which a value is a rounding artefact.
const MAX_PLACES := 4
## The box's text at its last write, which a refused entry puts back.
const SHOWN_META := "ledger_shown"


## `value` as the box shows it: `step_places` decimals, more while they hide part of the value.
static func text(value: float, step_places: int) -> String:
	var places := step_places
	while places < MAX_PLACES and absf(snappedf(value, pow(10.0, -places)) - value) > 1e-9:
		places += 1
	return Num.f(value, places)


## What the player typed as a number, with either decimal mark; NAN for anything else.
static func parse(typed: String) -> float:
	var clean := typed.strip_edges().replace(",", ".").replace(" ", "").replace(" ", "")
	return clean.to_float() if clean.is_valid_float() else NAN


## A box on `grid` for one lever. `on_typed(value)` is called with a number inside [lo, hi] when
## the player confirms (Enter) or leaves the box; anything that is not a number puts the figure
## shown back. Returns the box, so a panel can write its figure with show().
static func attach(grid: Control, lo: float, hi: float, on_typed: Callable) -> LineEdit:
	var box := LineEdit.new()
	box.custom_minimum_size.x = 76
	box.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.select_all_on_focus = true
	var confirm := func(_typed := "") -> void:
		# Left as it was shown: a figure shown to three places must not rewrite a rate that has more.
		if box.text == String(box.get_meta(SHOWN_META, "")):
			return
		var value := parse(box.text)
		if is_nan(value):
			box.text = String(box.get_meta(SHOWN_META, ""))
			return
		on_typed.call(clampf(value, lo, hi))
	box.text_submitted.connect(confirm)
	box.focus_exited.connect(confirm)
	grid.add_child(box)
	return box


## Writes `shown` into the box, unless the player is typing in it: a refresh must not take the
## figure from under their cursor.
static func show(box: LineEdit, shown: String) -> void:
	box.set_meta(SHOWN_META, shown)
	if not box.has_focus():
		box.text = shown
