extends RefCounted

## The Industry tab's In progress strip -- V5.3 a + b step 2, docs/design/v5.3-ab.md
## 2.3: a decision that takes time is shown at the top of the tab it belongs to,
## each row with its stage, the months left and what comes next, and a Stop that
## says what stopping costs before it is pressed (Processes.stop_price(), the sim's
## figure: the break fee or the legal fees spent, and the U-turn's blocs).
##
## Hidden while nothing runs, which is every game until a process starts: a strip
## that said "nothing in progress" would be words for nothing (the prose budget).

const Processes = preload("res://src/sim/processes.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")

## A process's stage, and what its end brings, as a player reads them.
const STAGE := {
	"negotiation": "negotiation",  # i18n: msgid
	"offer": "the offer",  # i18n: msgid
	"transition": "the transition",  # i18n: msgid
	"investigation": "the investigation",  # i18n: msgid
	"remedy": "the remedy",  # i18n: msgid
	"sale": "the sale",  # i18n: msgid
}
const NEXT := {
	"negotiation": "the transfer",  # i18n: msgid
	"offer": "the transfer",  # i18n: msgid
	"transition": "state control",  # i18n: msgid
	"investigation": "the ruling",  # i18n: msgid
	"remedy": "the break-up",  # i18n: msgid
	"sale": "the windfall",  # i18n: msgid
}


## The strip under `parent`, or null while nothing runs. `stop` is called with the
## process id and the row's words when its Stop is pressed.
static func build(parent: Control, state, loader, ns, stop: Callable) -> Control:
	var rows := Processes.rows(ns)
	if rows.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	parent.add_child(box)
	PanelKit.heading(box, Strings.t("In progress"))
	for row in rows:
		var verb := Strings.row_name("company-actions", _action(loader, String(row["action_id"])))
		var firm: String = loader.firm_name(ns.id, String(row["company_id"]))
		var stage := String(row["stage"])
		var months := int(row["months_left"])
		PanelKit.plain_line(box, Strings.tn("%s, %s: %s, %d month left, then %s.", "%s, %s: %s, %d months left, then %s.", months) % [
			verb, firm, Strings.t(String(STAGE.get(stage, stage))), months, Strings.t(String(NEXT.get(stage, "")))],  # i18n: row-ok stage words from the table above
			PanelKit.Tone.PLAIN)
		var price: Dictionary = Processes.stop_price(state, ns, loader, String(row["id"]))
		if not bool(price.get("ok", false)):
			continue
		var flow := PanelKit.buttons(box)
		var button := PanelKit.sized(Button.new())
		button.text = Strings.t("Stop")
		button.set_meta("process_id", String(row["id"]))
		var gain := -float(price["debt_eur_bn"])
		var money := PanelKit.plain_line(flow, EffectsStrip.money_text(gain), PanelKit.Tone.PLAIN)
		money.autowrap_mode = TextServer.AUTOWRAP_OFF
		money.theme_type_variation = EffectsStrip.cell_variation(EffectsStrip.money_tone(gain))
		button.set_meta("money_label", money)
		var who := EffectsStrip.who_text(price.get("bloc_offset", {}))
		if who != "":
			var angers := PanelKit.plain_line(flow, who)
			angers.autowrap_mode = TextServer.AUTOWRAP_OFF
		var what := "%s, %s" % [verb, firm]
		button.pressed.connect(func() -> void: stop.call(String(row["id"]), what))
		flow.add_child(button)
		flow.move_child(button, 0)
	return box


static func _action(loader, id: String):
	for a in loader.company_actions:
		if String(a.id) == id:
			return a
	return null
