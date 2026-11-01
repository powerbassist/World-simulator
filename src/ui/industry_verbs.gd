extends RefCounted

## A firm's verbs, opened by its Act button on the Industry tab -- V5.3 a + b step 2,
## docs/design/v5.3-ab.md 3.2 "The tab, rebuilt". Every verb on offer is one row:
## its name and its money line. Only the verb that has FOCUS (a click or the
## keyboard, never hover) opens its full strip and its Go, so a major with six verbs
## stays one strip tall -- the readability gate's "monolithic panels" answered by
## showing one decision at a time.
##
## BAND A5: a verb whose condition fails is greyed and its failing line is printed
## under it, read before any press (CompanyVerb.refusal, the one source). G1's
## "destroy instantly a company? also with no warning" was a refusal shown only
## after the click, or only in a tooltip.
##
## Every figure is the sim's: a process's price range is Processes.estimate(), a
## firm verb's price and yearly bill are Companies.preview() on a copy against the
## live register. No formula is copied here.

const Companies = preload("res://src/sim/companies.gd")
const Processes = preload("res://src/sim/processes.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")

## The focused verb's strip, in px: about sixty characters of body text a line.
const STRIP_WIDTH := 520


## Builds the verb rows of `company` under `parent`. The panel keeps which verb has
## focus (`_focus_verb`) across its rebuilds; a focus moves the strip without one.
static func build(panel, parent: Control, ns, company) -> void:
	var state = panel._state
	var loader = panel._loader
	var details := {}
	for action in Companies.available(state, ns, loader.company_actions, String(company.id), loader):
		var id := String(action.id)
		var row := PanelKit.buttons(parent)
		var selector := CompanyVerb.button(state, loader, ns, company, action)
		selector.set_meta("action_id", id)
		row.add_child(selector)
		var est: Dictionary = Processes.estimate(state, ns, loader, action, String(company.id)) if Processes.is_process(action) else {}
		var money: Array = money_line(state, loader, ns, company, action, est)
		var money_label := PanelKit.plain_line(row, String(money[1]), PanelKit.Tone.PLAIN)
		money_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		money_label.theme_type_variation = EffectsStrip.cell_variation(EffectsStrip.money_tone(float(money[2])))
		selector.set_meta("money_label", money_label)
		var why := CompanyVerb.refusal(state, loader, ns, company, action)
		if why != "":
			var line := PanelKit.plain_line(parent, Strings.t(why))  # i18n: row-ok the sim's reason, its English the msgid
			ResultTone.tint(line, ResultTone.BLOCKED)
			selector.set_meta("refusal_label", line)
			continue
		var detail := VBoxContainer.new()
		# A reading measure, not the window's width: the money row puts its figure at
		# the right edge, which across a docked window is far from its caption.
		# Its wrapping lines need a width of their own inside a shrunk box.
		detail.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		detail.custom_minimum_size.x = STRIP_WIDTH
		parent.add_child(detail)
		var strip := EffectsStrip.new()
		detail.add_child(strip)
		strip.show_lines(String(money[0]), String(money[1]), float(money[2]),
			EffectsStrip.who_text(action.effects.get("bloc_offset", {})),
			when_text(action, est))
		var go := PanelKit.sized(Button.new())
		go.text = Strings.t("Go")
		go.set_meta("go", true)
		go.pressed.connect(func() -> void: panel._on_act(ns, company, action))
		detail.add_child(go)
		details[id] = detail
		selector.focus_entered.connect(func() -> void: _show(panel, details, id))
		selector.pressed.connect(func() -> void: _show(panel, details, id))
	_show(panel, details, String(panel._focus_verb))


static func _show(panel, details: Dictionary, id: String) -> void:
	panel._focus_verb = id
	for key in details:
		(details[key] as Control).visible = key == id


## [caption, text, gain]: what the verb does to the public purse, printed. A process
## is a range on the debt (the truth's fog, A4); a firm verb its one-off price and
## the yearly subsidy bill it moves, from a preview on a copy.
static func money_line(state, loader, ns, company, action, est: Dictionary) -> Array:
	var caption := Strings.t("Treasury")
	if Processes.is_process(action):
		var lo := -maxf(float(est["price_lo"]), float(est["price_hi"]))
		var hi := -minf(float(est["price_lo"]), float(est["price_hi"]))
		return [caption, EffectsStrip.range_text(lo, hi), hi]
	var preview: Array = Companies.preview(state, ns, loader.company_actions, action, String(company.id), loader)
	var once := -float((preview[1] as Dictionary).get("price_eur_bn", 0.0))
	var yearly := -(Companies.subsidy_bill_pct_gdp(preview[0]) - Companies.subsidy_bill_pct_gdp(ns)) * float(ns.gdp_eur_bn) / 100.0
	if absf(yearly) >= 0.05 and absf(once) >= 0.05:
		return [caption, Strings.t("%s once, %s a year") % [EffectsStrip.money_text(once), EffectsStrip.money_text(yearly)], yearly]
	if absf(yearly) >= 0.05:
		return [caption, Strings.t("%s a year") % EffectsStrip.money_text(yearly), yearly]
	if absf(once) >= 0.05:
		return [caption, Strings.t("%s once") % EffectsStrip.money_text(once), once]
	# A verb that moves no money says so in words, not as "0.0 bn".
	return [caption, Strings.t("No cost to the treasury."), 0.0]


## When it lands and what can go wrong, in whole sentences; `est` is the process's
## Processes.estimate(), {} for a firm verb.
static func when_text(action, est: Dictionary) -> String:
	var out := PackedStringArray()
	if Processes.is_process(action):
		var lo := int(est["months_lo"])
		var hi := int(est["months_hi"])
		if lo == hi:
			out.append(Strings.tn("Lands in %d month.", "Lands in %d months.", lo) % lo)
		else:
			out.append(Strings.t("Lands in %d to %d months.") % [lo, hi])
		if est.has("odds_lo"):
			out.append(Strings.t("A %d to %d %% chance the authority orders it.") % [
				roundi(100.0 * float(est["odds_lo"])), roundi(100.0 * float(est["odds_hi"]))])
	else:
		out.append(Strings.t("Takes effect at once."))
	if action.irreversible:
		out.append(Strings.t("It cannot be undone."))
	return " ".join(out)
