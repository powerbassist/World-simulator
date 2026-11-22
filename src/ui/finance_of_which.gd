extends RefCounted

## What the books spend and take that no row of the Finances page sets -- V5.3 Finances slice 5, carried over from the
## Budget tab's "of which" lines when that tab went. Each is money the player did not set with a slider: a tariff he
## imposed, the dividends of a holding, the Union's contribution, a deployment he is bound to, a subsidy, an investment
## programme, public works, a regional fund, a plant rescue, the energy fleet. A budget that quietly widened its deficit
## for a reason nothing on screen names is the unnamed-reason failure these lines exist to prevent (docs/scenario-model.md).
##
## Under "Other revenue" and "Other spending" there is one line while they are shut, counting the parts that are not zero
## ("1 part", the names on its hover); a press opens each part with its figure. A part at zero is never listed, so a game that has
## never used the verb behind it shows nothing of it.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## [snapshot key, name] per side, in the order the Budget printed them.
const SPENDING := [
	["bloc_transfer_pct_gdp", "the Union"],  # i18n: msgid
	["deployment_bill_pct_gdp", "deployments"],  # i18n: msgid
	["subsidy_bill_pct_gdp", "subsidies"],  # i18n: msgid
	["investment_bill_pct_gdp", "investment"],  # i18n: msgid
	["project_bill_pct_gdp", "public works"],  # i18n: msgid
	["region_fund_bill_pct_gdp", "regional aid"],  # i18n: msgid
	["rescue_bill_pct_gdp", "plant rescues"],  # i18n: msgid
	["energy_bill_pct_gdp", "energy"],  # i18n: msgid
]
const REVENUE := [
	["tariff_revenue_pct_gdp", "tariffs"],  # i18n: msgid
	["dividend_revenue_pct_gdp", "dividends"],  # i18n: msgid
]


## {spending: [{part, bn}], revenue: [{part, bn}]} from a Budget snapshot: the parts that are not zero, signed (a net
## receiver of the Union's money reads negative).
static func read(snapshot: Dictionary) -> Dictionary:
	var gdp := float(snapshot.get("gdp_eur_bn", 0.0))
	return {"spending": _parts(snapshot, SPENDING, gdp), "revenue": _parts(snapshot, REVENUE, gdp)}


static func _parts(snapshot: Dictionary, table: Array, gdp: float) -> Array:
	var out := []
	for entry in table:
		var pct := float(snapshot.get(String(entry[0]), 0.0))
		# Any figure that is not zero is a part (the Budget's own em-dash rule): a plant rescue can cost a few tens of millions.
		if not is_zero_approx(pct):
			var bn := pct / 100.0 * gdp
			out.append({"part": String(entry[1]), "bn": bn})
	return out


## The parts under their header: a shut line naming them, or each with its figure once opened (`id` is the group's key in
## ctx["open_groups"], `ctx["toggle"]` flips it, as the revenue groups' folded kinds do).
static func build(box: Control, parts: Array, id: String, ctx: Dictionary) -> void:
	if parts.is_empty():
		return
	var gap := MarginContainer.new()
	gap.add_theme_constant_override("margin_left", 18)
	if (ctx["open_groups"] as Dictionary).has(id):
		var lines := VBoxContainer.new()
		for part in parts:
			var text := Strings.t("of which %s: %s bn") % [Strings.t(String(part["part"])), Num.fs(float(part["bn"]), 0 if absf(float(part["bn"])) >= 10.0 else (1 if absf(float(part["bn"])) >= 1.0 else 2))]
			PanelKit.plain_line(lines, text, PanelKit.Tone.DIM)
		gap.add_child(lines)
	else:
		var button := Button.new()
		button.theme_type_variation = UiTheme.GHOST  # a fold: a ghost with its chevron (g3-spec "Borderless toggle")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.name = "OfWhich"  # i18n: ok a node name, found by tests
		# Two words and a count, not the names: the page's prose is held at its ceiling, and the names are the hover.
		button.text = Strings.tn("%d part", "%d parts", parts.size()) % parts.size() + "  ▸"  # i18n: ok a glyph
		button.tooltip_text = Strings.t("of which: %s") % ", ".join(parts.map(func(p: Dictionary) -> String: return Strings.t(String(p["part"]))))
		button.pressed.connect((ctx["toggle"] as Callable).bind(id))
		gap.add_child(button)
	box.add_child(gap)
