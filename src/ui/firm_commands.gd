extends RefCounted

## The firm and sector commands, shared by the two panels that offer them -- the Sectors
## overview (companies_panel.gd) and a sector's tab with its firm sheet (sector_panel.gd,
## V5.3 screen 5 slice 2). Moved out of companies_panel.gd rather than copied, so a verb
## refused, asked on a card or acted on reads the same from either tab.
##
## `panel` holds the command state both panels keep: `_state`, `_loader`, `_confirm` (the
## card an irreversible verb asks on), `_last_refusal` (shown at its head until the next
## act), `_dirty`, and the `acted(before, label)` signal main.gd turns into a decision
## delta. Every baseline is captured BEFORE the command (U4's contract).

const Processes = preload("res://src/sim/processes.gd")
const Closures = preload("res://src/sim/closures.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const Trends = preload("res://src/ui/trends.gd")
const Strings = preload("res://src/ui/strings.gd")
const ProposalNote = preload("res://src/ui/proposal_note.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")


## V5.3 e (docs/design/finance-bill.md section 12, the author's "par la loi de finances"):
## a programme is a row of the finance bill, tabled and started at the month's end if the
## bill carries. Nothing changes until then, so no trend card is pushed.
static func invest(panel, action) -> void:
	var sector := String(action.effects.get("investment", {}).get("sector", ""))
	var tabling := FinanceBill.table(panel._state, panel._loader, {"programmes": {sector: String(action.id)}})
	panel._dirty = true
	# RF7: the row's own refusal names the programme; any other (a law in the slot, a
	# finance bill queued, a rate out of range) is the bill's, said as every tabling says it.
	if tabling.get("tabled", false):
		panel._last_refusal = ""
	elif tabling.get("verb", false):
		panel._last_refusal = Strings.t("%s refused -- it is no longer on offer.") % Strings.row_name("investment-actions", action)
	else:
		panel._last_refusal = ProposalNote.body(tabling)


## An irreversible verb asks on a card first (CompanyVerb.ask); the rest act at once.
static func act(panel, ns, company, action) -> void:
	if action.irreversible:
		panel._confirm = CompanyVerb.ask(panel, panel._confirm, panel._state, panel._loader, ns, company, action, run.bind(panel, ns, company, action))
		return
	run(panel, ns, company, action)


static func run(panel, ns, company, action) -> void:
	var before := Trends.snapshot_now(panel._state)
	# V5.3 a: an ownership or structure verb opens its process (processes.gd).
	var result := Processes.execute(panel._state, ns, panel._loader, action, company.id)
	panel._dirty = true
	if not result.get("applied", false):
		# The refusal is the panel's to show, in the sim's own words.
		var reason := String(result.get("reason", ""))
		panel._last_refusal = Strings.t("%s refused%s") % [Strings.row_name("company-actions", action), " -- %s" % Strings.t(reason) if reason != "" else "."]  # i18n: row-ok the sim's reason, its English the msgid
		# Asked on a card: the refusal answers there, in sight (#152's RECORD 1).
		if action.irreversible and panel._confirm != null:
			panel._confirm.tell(panel._last_refusal)
		return
	panel._last_refusal = ""
	panel.acted.emit(before, "%s: %s" % [Strings.row_name("company-actions", action), company.company_name])


## Stop on an In progress row: the sim's own verb (Processes.stop), its price read on the
## row before the press.
static func stop(panel, process_id: String, what: String) -> void:
	var before := Trends.snapshot_now(panel._state)
	var result: Dictionary = Processes.stop(panel._state, panel._state.player(), panel._loader, process_id)
	panel._dirty = true
	if not bool(result.get("ok", false)):
		panel._last_refusal = Strings.t("Stop refused -- %s") % Strings.t(String(result.get("reason", "")))  # i18n: row-ok the sim's reason, its English the msgid
		return
	panel._last_refusal = ""
	panel.acted.emit(before, Strings.t("Stopped: %s") % what)


## An answer to a stage's ask (#248): Processes.answer(), the sim's own verb.
static func answer(panel, process_id: String, answer_id: String, what: String) -> void:
	var before := Trends.snapshot_now(panel._state)
	var result: Dictionary = Processes.answer(panel._state, panel._state.player(), panel._loader, process_id, answer_id)
	panel._dirty = true
	if not bool(result.get("ok", false)):
		panel._last_refusal = Strings.t("Answer refused -- %s") % Strings.t(String(result.get("reason", "")))  # i18n: row-ok the sim's reason, its English the msgid
		return
	panel._last_refusal = ""
	panel.acted.emit(before, Strings.t("Answered: %s") % what)


## An answer to a plant closure (#251): Closures.answer(), the sim's own verb.
static func closure(panel, closure_id: String, answer_id: String, what: String) -> void:
	var before := Trends.snapshot_now(panel._state)
	var result: Dictionary = Closures.answer(panel._state, panel._state.player(), panel._loader, closure_id, answer_id)
	panel._dirty = true
	if not bool(result.get("ok", false)):
		panel._last_refusal = Strings.t("Answer refused -- %s") % Strings.t(String(result.get("reason", "")))  # i18n: row-ok the sim's reason, its English the msgid
		return
	panel._last_refusal = ""
	panel.acted.emit(before, Strings.t("Answered: %s") % what)
