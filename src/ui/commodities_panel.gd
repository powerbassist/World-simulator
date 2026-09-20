extends PanelContainer

## The commodities surface -- V4.6 Task 4. Read-only over `commodity_state`
## (Task 2's machine) and the two content registers (Task 1), and the FIRST
## reader either has ever had: `main.gd`'s tick comment says outright that nothing
## consumed the layer before this panel.
##
## THREE SECTIONS, and the split is the tier's own wording read as three jobs:
##   THE BALANCE     what a good's month looks like -- made, traded, priced,
##                   and whether the country got what it wanted. Grouped by the
##                   loader's categories because that partition is content, not a
##                   choice this file may make.
##   THE TREE        the recipe table as lines, output <- inputs. "Drawn, as its
##                   own screen" is satisfied by a structured listing rather than
##                   a node-edge graph: a graph layout is a drawing subsystem
##                   this block does not own, and the register it would draw is
##                   thirty-four recipes deep, which reads as a list.
##   THE ALERT       the goods the country could not cover.
##
## NO BUTTON, people_panel.gd's design rather than a gap. The two map modes are
## reached by the LEGEND's own switcher -- they are registry entries, so this
## panel setting one would mean inventing a second route the legend already
## provides, and a mode this panel could set but not show would be a control whose
## effect lives on a surface the player cannot see from here. (The task brief
## allowed either; the legend is the map's own mode surface and V2.1a's rule is
## that a second list of surfaces is the defect, not the feature.)
##
## WHAT IT DOES NOT DO: it writes nothing, and specifically not
## `commodity_state` -- commodities.gd is that register's one writer, and
## tests/test_commodities_panel.gd asserts both halves (a source scan for an
## indexed write, and a deep comparison across a refresh). It also does not tick:
## the month belongs to main.gd, and a panel that ticked would be a second
## simulation.

signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const DataLoader = preload("res://src/core/data_loader.gd")

## When a good reads as short: the value of what the country made plus what it
## bought, against the value of what it wanted, below this fraction.
##
## "STOCK" IS NOT A REGISTER ENTRY, and the honest substitution is stated rather
## than papered over: the tier asks for a shortage alert on a good "below a small
## fraction of one month's consumption", and `commodity_state` carries no stock at
## all -- commodities.gd's step 5 gives its reason in full ("a carried stock makes
## the gap negative for ever once it has accumulated"). The quantity that exists,
## and the same one the price step prices, is THIS MONTH'S FLOW: what was made and
## bought against what was wanted. So the alert reads coverage of the month's
## demand, which is the model's own shortage and not a proxy for it.
##
## 0.25 IS MEASURED, over the live tick on the 29-nation roster: France steadies
## at two alerts by month 12 (cotton at 0 % and uranium ore at 10 %) and holds
## there; at 0.75 the same readout flags twenty-four goods, which is a wall rather
## than an alert. Both flagged goods are CONTENT BOUND and the bound is recorded
## where the next session will look: cotton is made by two nations of twenty-nine
## and its world output is 3 % of world demand, and uranium ore is made by all
## twenty-nine but far short of what the electricity chain wants. Neither is a
## machine defect, and neither is reachable by a verb yet -- Task 4 ships no
## action, so this panel reports the world as authored.
##
## A PANEL CONST rather than a commodity_constants.gd entry, decided by the house
## rule's own test: that file holds the MODEL's tuning (price elasticity, the
## trade rate -- numbers the tick reads), and this is a presentation threshold the
## simulation never sees. It lives beside the only reader, with the measurement
## above so it is declared rather than magic.
const SHORTAGE_COVERAGE := 0.25

## The alert's heading, and the exact string the test drives its fixture against.
## A constant rather than a literal in two places, so the check cannot pass by
## matching a heading the panel no longer prints. UPPERCASE because that is what
## `PanelKit.section()` renders -- it tracks and upper-cases the section's own
## heading -- and a constant that held the mixed-case form would be a string no
## label on screen ever carries.
const SHORTAGE_HEADING := "SHORTAGES"

## At most this many rows in the alert list, with the rest counted. A shortage
## wall is the state this alert exists to summarise, and printing sixty rows of
## one would be the balance table again -- one the player has already scrolled
## past. Ordered worst-coverage first, so the head is the worst.
const ALERT_HEAD := 8

## The panel's width. Four columns plus a name column holding "Refined fuels" and
## "Pharmaceuticals" -- measured against the panel's own longest good name rather
## than guessed, and well inside U5a's ~886 band.
const PANEL_WIDTH := 560
const PANEL_HEIGHT := 660

var _state
var _loader
var _dirty := true

var _title: Label
var _body: VBoxContainer
var _close_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	# The body sits inside a right margin, companies_panel.gd's reason: a
	# ScrollContainer draws its bar OVER the content, so the right-aligned ledger
	# figures would run underneath it. This panel's body always overflows.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 14)
	scroll.add_child(gutter)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	gutter.add_child(_body)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	if not _dirty or not visible or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	var ns = _state.player()
	if ns == null:
		return
	var nation = _loader.nations.get(ns.id)
	if nation == null:
		return

	_title.text = "Commodities of %s" % nation.nation_name

	# remove_child THEN queue_free, which is map_legend.gd's own two lines and not
	# the plain queue_free most panels use. The reason is measured rather than
	# stylistic: a queue_freed child stays in the tree until the frame ends, so a
	# reader that refreshes and reads in the SAME frame sees the previous body as
	# well as the new one -- this task's own test hit exactly that (the shortage
	# heading survived a refresh that should have removed it), and it is the
	# "fold finding" AGENTS.md records in three other places. Detaching first
	# makes the read honest without the reader having to wait a frame.
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

	_build_alert(ns)
	_build_balance(ns)
	_build_tree()


## The alert. **The section is ABSENT when there is nothing short**, and that is
## how the never-silent rule and this line both hold at once: the panel is never
## silent (the balance and the tree below always render, from registers that exist
## from `new_game`), while a heading over "nothing is wrong" would put bad news and
## good news in the same voice. V1.7c's rule from the other side -- a fact the
## country has (no shortage) is stated by the ABSENCE of the alarm, not by an empty
## list under an alarm's name.
func _build_alert(ns) -> void:
	var short: Array = []
	for good_id in _goods_in_order():
		var coverage: float = _coverage(ns, good_id)
		if coverage < SHORTAGE_COVERAGE:
			short.append({"id": good_id, "coverage": coverage})

	if short.is_empty():
		return

	var body := PanelKit.section(_body, SHORTAGE_HEADING)

	# Worst first, then by id so two equal figures have a total order -- the
	# determinism rule the sim holds and a panel owes for the same reason: two
	# refreshes of one state must print the same screen.
	short.sort_custom(func(a, b) -> bool:
		if not is_equal_approx(float(a["coverage"]), float(b["coverage"])):
			return float(a["coverage"]) < float(b["coverage"])
		return String(a["id"]) < String(b["id"]))

	var rows: Array = []
	for i in mini(ALERT_HEAD, short.size()):
		var good_id := String(short[i]["id"])
		rows.append([
			_good_name(good_id),
			"%.0f%% covered" % (100.0 * float(short[i]["coverage"])),
		])
	PanelKit.ledger(body, rows)
	if short.size() > ALERT_HEAD:
		PanelKit.line(body, "and %d more." % (short.size() - ALERT_HEAD), PanelKit.Tone.BAD)
	else:
		PanelKit.line(body, "%d good%s below %d%% of the month's demand." % [
			short.size(), "" if short.size() == 1 else "s", roundi(SHORTAGE_COVERAGE * 100.0)],
			PanelKit.Tone.BAD)


## The balance, grouped by the loader's categories in the loader's own order. A
## category with no goods prints that fact rather than nothing, so a content pack
## that empties one reads as empty instead of as a section that vanished.
func _build_balance(ns) -> void:
	PanelKit.heading(_body, "The balance, this month")
	var prices: Dictionary = (ns.commodity_state.get("price", {}) as Dictionary)
	for category in DataLoader.COMMODITY_CATEGORIES:
		var goods: Array = []
		for good_id in _goods_in_order():
			if _category_of(good_id) == String(category):
				goods.append(good_id)
		var body := PanelKit.section(_body, String(category))
		if goods.is_empty():
			PanelKit.line(body, "No good carries this category.")
			continue
		var rows: Array = []
		for good_id in goods:
			var base := _base_price(good_id)
			var price := float(prices.get(good_id, base))
			var made := float((ns.commodity_state.get("output", {}) as Dictionary).get(good_id, 0.0))
			var net := float((ns.commodity_state.get("trade", {}) as Dictionary).get(good_id, 0.0))
			var want := float((ns.commodity_state.get("demand", {}) as Dictionary).get(good_id, 0.0))
			rows.append([
				_good_name(good_id),
				_qty_text(made),
				_signed_qty_text(net),
				# delta(), not a "%+.0f%%" -- the price moves by tenths of a percent
				# in an ordinary month and a fixed one-place format is V1.6b's
				# `+0.0` against a live figure. PanelKit widens until it is not a lie.
				PanelKit.delta(100.0 * (price / base - 1.0) if base > 0.0 else 0.0, "%"),
				"%.0f%%" % (100.0 * _coverage(ns, good_id)),
			])
		PanelKit.ledger(body, rows)
	PanelKit.line(_body, "Columns: units made · net units bought (positive) or sold (negative) · price against its base · the share of this month's demand covered. Prices are the one world vector; every nation's copy reads the same.")


## The tree, as lines. Grouped by the OUTPUT's category, in the loader's category
## order, because that is how a reader looks a good up -- and derived from
## `commodity_recipes` rather than authored, so a recipe added to content appears
## here with no edit in this file.
##
## `labour_per_unit` and `capital_per_unit` are deliberately NOT printed even
## though the register carries them: commodities.gd does not read them (its
## `_cheapest_route()` states why -- this layer has no wage or capital price to
## value them against), and a panel that printed a factor requirement the machine
## ignores would be presenting a lever the game does not have.
func _build_tree() -> void:
	PanelKit.heading(_body, "The industrial tree")
	PanelKit.line(_body, "What makes what. A good with no line is a primary producer: raw materials, crops and services are not made from anything.")

	var by_output: Dictionary = {}
	for recipe_id in _recipe_ids():
		var recipe: Dictionary = _loader.commodity_recipes[recipe_id]
		by_output[String(recipe.output)] = recipe

	for category in DataLoader.COMMODITY_CATEGORIES:
		var lines: Array = []
		for good_id in _goods_in_order():
			if _category_of(good_id) != String(category):
				continue
			var recipe = by_output.get(good_id)
			if recipe == null:
				continue
			lines.append("%s  <-  %s" % [_good_name(good_id), _inputs_text(recipe)])
		var body := PanelKit.section(_body, String(category))
		if lines.is_empty():
			PanelKit.line(body, "Made from nothing -- produced from the country's own endowment.")
			continue
		for text in lines:
			PanelKit.line(body, text)


## One recipe's inputs, in quantity order then by id: "1.40 iron ore · 0.30 coke".
## Sorted rather than left in the file's order so the line is a total order over
## the content and two runs print the same tree.
##
## The quantity goes through `_ratio_text()` and not "%.2f", which is a MEASURED
## fix: `uranium_fuel <- 0.004 uranium ore` printed as "0.00 uranium ore" -- a
## requirement rendered as zero, and a player reading it would conclude the fuel
## is made from nothing. (The panel's own smoke dump is what caught it.)
func _inputs_text(recipe: Dictionary) -> String:
	var parts: Array = []
	var inputs: Dictionary = recipe.inputs
	var ids: Array = inputs.keys()
	ids.sort()
	for input_id in ids:
		parts.append("%s %s" % [_ratio_text(float(inputs[input_id])), _good_name(String(input_id))])
	if parts.is_empty():
		return "nothing"
	return " · ".join(parts)


## A quantity at whatever precision it actually has: whole numbers plain, small
## fractions to their first significant digit rather than to a fixed one. The
## simulation's unit counts run from 0.004 (the uranium in a unit of fuel) to
## 1.6e11 (a nation's monthly services), and one format cannot show both -- this
## is PanelKit.delta()'s "widen until the digits are not a lie" applied to a
## magnitude instead of a movement, which is the same V1.6b defect one row over.
func _ratio_text(v: float) -> String:
	var magnitude := absf(v)
	if magnitude >= 100.0:
		return "%.0f" % v
	if magnitude >= 1.0:
		return "%.2f" % v
	for places in range(1, 5):
		if magnitude >= pow(10.0, -float(places)):
			return String(("%." + str(places + 1) + "f") % v)
	return "0"


## How much of the month's want this nation covered, from its own production plus
## what it bought. Clamped at 0 so an overshoot reads as 0 short rather than
## negative, and 1.0 where nothing was wanted -- a good nobody wants is not short,
## which is the negative control the test pins.
func _coverage(ns, good_id: String) -> float:
	var cs: Dictionary = ns.commodity_state
	if cs.is_empty():
		return 1.0
	var want := float((cs.get("demand", {}) as Dictionary).get(good_id, 0.0))
	if want <= 0.0:
		return 1.0
	var made := float((cs.get("output", {}) as Dictionary).get(good_id, 0.0))
	var bought := maxf(0.0, float((cs.get("trade", {}) as Dictionary).get(good_id, 0.0)))
	return clampf((made + bought) / want, 0.0, 1.0)


## A unit quantity at the scale this panel prints them. The register's counts run
## to 1.6e11 units a month (a nation's services) and a raw figure at that size is
## eleven digits in a ledger column -- what the panel's first smoke dump showed,
## and unreadable. Three significant-ish figures with a suffix is the game's own
## convention one quantity over (PanelKit.pop_text() prints millions and thousands
## for a population) and for the same reason: a reader compares magnitudes, not
## digits. Below a thousand the number prints plain, because "8.5 k" against a
## quantity whose meaningful movement is tens of units would hide the movement.
func _qty_text(v: float) -> String:
	var magnitude := absf(v)
	if magnitude >= 1e9:
		return "%.1f B" % (v / 1e9)
	if magnitude >= 1e6:
		return "%.1f M" % (v / 1e6)
	if magnitude >= 1e3:
		return "%.1f k" % (v / 1e3)
	return "%.0f" % v


## `_qty_text()`'s signed form for the net-trade column, where the sign is the
## whole content of the cell. **Zero prints as "0", never as the kit's em dash**:
## a nation that neither bought nor sold a good has a real reading there --
## self-sufficiency -- and PanelKit.MISSING means the figure is ABSENT, which is
## V1.6d's whole distinction. A dash in this column would say "not applicable"
## about the one value that means "neither".
func _signed_qty_text(v: float) -> String:
	if is_zero_approx(v):
		return "0"
	return ("+" if v > 0.0 else "-") + _qty_text(absf(v))


func _goods_in_order() -> Array:
	var out: Array = _loader.commodity_goods.keys()
	out.sort()
	return out


func _recipe_ids() -> Array:
	var out: Array = _loader.commodity_recipes.keys()
	out.sort()
	return out


func _good_name(good_id: String) -> String:
	var good = _loader.commodity_goods.get(good_id)
	return String(good.name) if good != null else good_id


func _category_of(good_id: String) -> String:
	var good = _loader.commodity_goods.get(good_id)
	return String(good.category) if good != null else ""


func _base_price(good_id: String) -> float:
	var good = _loader.commodity_goods.get(good_id)
	return float(good.base_price) if good != null else 0.0