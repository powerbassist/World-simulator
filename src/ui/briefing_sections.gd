extends RefCounted

## What a bill's page says before the division, as sections a host lays out wherever it
## has room -- V5.3 screen 4, PR 2b. They were the bill briefing's own (briefing.gd, V4.2
## T5); the law sheet now builds the same ones inline so Propose divides without a popup in
## between, and the popup keeps them for the bills that still ask for it (a draft, an
## ownership bill). One builder, so the two pages cannot say different things:
##
##   - the channels: direction and magnitude, walked off the bill's effects dictionary by
##     effect_lines() below -- one walk, the attribution sentence is those same lines joined;
##   - the political price, per bloc, at the LANDED value -- clampf(value, LK.BLOC_OFFSET_MIN,
##     LK.BLOC_OFFSET_MAX) -- because the clamp is what the applier will actually write; a
##     derived quote that went past the bound is a note beside the landed figure, never the
##     number (T3's sweep: urban +1.325 on a half|max spec);
##   - the two commissioned polls: the assembly forecast (firm down to ABSTAIN_BAND where
##     the assembly poll was bought) and the country's bloc read at the poll's margin.
##
## Reads simulation state and never writes it; the single exception is the two commission
## buttons, which send player intent back as one explicit command -- Statute.buy_poll() or
## MeasurePolls.commission(). The host owns the redraw (`rebuild`) and the purchase's
## baseline (`polled`, finances_panel.gd's `committed` contract).

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Labels = preload("res://src/ui/labels.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const LawGrade = preload("res://src/ui/law_grade.gd")
const Statute = preload("res://src/sim/statute.gd")
const StatuteK = preload("res://src/sim/statute_constants.gd")
const PollStrip = preload("res://src/ui/poll_strip.gd")
const MeasurePolls = preload("res://src/sim/measure_polls.gd")

var _state = null
var _loader = null
var _ns = null
var _party_list: Array = []
## The bill's key in the purchase register: the law id, or the draft id while it is drafting.
var _bill_key := ""
## Set for a law on the book (authored or composed); null for a draft.
var _law = null
var _scale := 1.0
## The draft entry (ns.draft_bills shape) for a draft; {} for a law.
var _draft := {}
var _rebuild: Callable
var _polled: Callable
var _refusal: Label = null


## `law` is null for a draft, whose entry and id come in `draft`.
func _init(state, loader, law, scale: float, draft: Dictionary, bill_key: String, rebuild: Callable, polled: Callable) -> void:
	_state = state
	_loader = loader
	_law = law
	_scale = scale
	_draft = draft
	_bill_key = bill_key
	_rebuild = rebuild
	_polled = polled
	_ns = state.player()
	_party_list = loader.parties.get(_ns.id, [])


## A load invalidates the state this holds: a stale press would write the dead run's books.
func detach() -> void:
	_state = null


func bill_name() -> String:
	if _law != null:
		return String(Strings.law_name(_law))
	return String(_draft.get("name", _bill_key))  # i18n: row-ok a drafted bill's composed name, not a data row


## The bill as it reads at the player's grade. _law stays the row: the sim grades it once.
func _read():
	return LawGrade.read(_ns, _law, _scale)


## The channel sentence and, for a repeal, what it removes. A bill that names no channel (a pure
## birth, or a pure repeal) prints no sentence. Each line is a whole sentence with its own full
## stop, so they are joined by a space and nothing is added (QA #50).
func channels(box: Control) -> void:
	var effects: Dictionary = _read().effects if _law != null else _draft.get("channels", {})
	var lines := effect_lines(effects, _ns)
	if not lines.is_empty():
		PanelKit.line(box, " ".join(lines), PanelKit.Tone.PLAIN)
	var repeal_text := _repeal_line()
	if repeal_text != "":
		PanelKit.line(box, repeal_text, PanelKit.Tone.PLAIN)


## What the bill does to the statue book's target, named for a player who will not know the id.
func _repeal_line() -> String:
	var target := ""
	if _law != null:
		target = String(_law.repeals)
	elif not _draft.is_empty():
		target = String(_draft.get("repeals", ""))
	if target == "":
		return ""
	for law in _loader.laws:
		if String(law.id) == target:
			return tr("Repeals: %s.") % String(Strings.law_name(law))
	var custom: Dictionary = _ns.custom_laws.get(target, {})
	if not custom.is_empty():
		return tr("Repeals: %s.") % String(custom.get("name", target))  # i18n: row-ok a composed law's name, not a data row
	return tr("Repeals: %s.") % target


## -- The price ---------------------------------------------------------------

## `compact` is the sheet's: the rows alone, signed and toned, without the sentence that names
## the offended blocs again (the sheet is under a word ceiling, tests/test_prose_budget.gd).
func price(box: Control, compact := false) -> void:
	var section := PanelKit.section(box, tr("The price"))
	var price: Dictionary = _read().effects.get("bloc_offset", {}) if _law != null else _draft.get("price", {})
	if price.is_empty():
		PanelKit.line(section, tr("The book prices this bill at no bloc directly."), PanelKit.Tone.DIM)
		return

	var offended: Array = []
	for bloc in price:
		var quote := float(price[bloc])
		var landed := clampf(quote, LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX)
		var shown := Num.fs(landed, 2)
		if absf(quote) > absf(landed) + 0.005:
			shown += tr("  (priced %s, lands clamped)") % Num.fs(quote, 2)
		PanelKit.row(section, Labels.bloc(bloc), shown,
			PanelKit.Tone.BAD if landed < 0.0 else PanelKit.Tone.GOOD)
		if landed < 0.0:
			offended.append(Labels.bloc(bloc))
	if not compact and offended.is_empty():
		PanelKit.line(section, tr("It offends no bloc outright."), PanelKit.Tone.DIM)
	elif not compact:
		PanelKit.line(section, tr("It offends: %s.") % ", ".join(offended), PanelKit.Tone.PLAIN)

	# The reversal preview is the record of what the player was SHOWN at draft time -- the
	# passage subtracts the target's LIVE ledger, so these lines are a briefing, not the
	# mechanism. include_bloc is TRUE: a negated ledger carries the bloc deltas the repeal
	# will actually re-apply (the ultra pass-2 finding).
	if not _draft.is_empty():
		var negated: Dictionary = _draft.get("negated", {})
		if not negated.is_empty():
			PanelKit.heading(section, tr("It reverses"))
			for line in effect_lines(negated, _ns, true):
				PanelKit.line(section, line, PanelKit.Tone.DIM)


## -- The polls ---------------------------------------------------------------

## `assembly_text` is the briefing's own sentence of the forecast, read by the popup off
## LawPanel (which would make this file and the sheet a preload cycle); the sheet has the
## forecast above already, so it passes none.
func polls(box: Control, assembly_text := "") -> void:
	var section := PanelKit.section(box, tr("The polls"))
	# A draft has no division to forecast until it reaches the order paper.
	if _law == null:
		PanelKit.line(section, tr("Drafting first; when it completes, the bill waits on your Propose in the Legislature."), PanelKit.Tone.DIM)
	elif assembly_text != "":
		PanelKit.line(section, tr("The Assembly: %s") % assembly_text, PanelKit.Tone.PLAIN)

	# The country's read: what the player has bought, and the tiers they can buy. A bill that
	# has reached the order paper keeps its draft's key, the id it carries.
	PollStrip.build(section, _state, _loader, _bill_key, _on_poll)
	_whip_count(section)


## V4.2's priced whip count stays (the parent's ruling on #304): the tiers read the country,
## and this alone firms the Assembly's forecast for this bill. The sim's own price and refusal.
func _whip_count(section: Control) -> void:
	var whip := PanelKit.sized(Button.new())
	whip.name = "AssemblyPoll"  # i18n: ok a node name, found by tests
	whip.text = tr("Commission an assembly poll — €%s k") % Num.f(StatuteK.poll_cost_eur_bn(StatuteK.POLL_KIND_ASSEMBLY) * 1.0e6, 0)
	if (_ns.poll_purchases.get(_bill_key, {}) as Dictionary).has(StatuteK.POLL_KIND_ASSEMBLY):
		whip.disabled = true
		whip.tooltip_text = tr("Commissioned — the figures it bought are fixed.")
	else:
		whip.pressed.connect(_on_whip)
	section.add_child(whip)
	# One line, filled only by a refusal: an empty label is no line at all.
	_refusal = Label.new()
	_refusal.name = "RefusalLine"  # i18n: ok a node name, found by tests
	_refusal.hide()
	section.add_child(_refusal)


func _on_whip() -> void:
	# A hidden page's stale signal must not charge the discarded game.
	if _state == null:
		return
	var before := Trends.snapshot_now(_state)
	var result: Dictionary = Statute.buy_poll(_state, _ns, _bill_key, StatuteK.POLL_KIND_ASSEMBLY)
	if bool(result.get("refused", false)):
		if _refusal != null:
			_refusal.text = String(result.get("refusal", tr("Refused.")))
			_refusal.show()
		return
	_polled.call(before, tr("Commissioned an assembly poll: %s") % bill_name())
	_rebuild.call()


func _on_poll(tier: String) -> void:
	# After detach() the state is the discarded game, and the commission would charge the dead run's debt.
	if _state == null:
		return
	var before := Trends.snapshot_now(_state)
	if bool(MeasurePolls.commission(_state, _loader, _bill_key, tier)["ok"]):
		_polled.call(before, tr("Commissioned a poll: %s") % bill_name())
	_rebuild.call()


## -- The ONE effects walk ----------------------------------------------------

## Human lines for a bill's channels -- direction and magnitude, one walk
## over the effects dictionary that both the rows and the attribution
## sentence read. `bloc_offset` is skipped by default: it is the price, and
## the price has its own section above -- rendering it here too would print
## every price row twice. THE ONE EXCEPTION is the reversal walk, which passes
## `include_bloc`: a negated ledger's bloc deltas are not the price, they are
## what the repeal re-applies, so the preview renders them as reversal lines
## rather than dropping the one channel the bill most directly moves (the
## ultra pass-2 finding). THE SCALAR SHAPES BOTH EXIST HERE: a spec's scalars
## are bare floats and a negated ledger's are {"": value} keyed by the empty
## string (legislature.gd's ledger shape), and _scalar_of() reads either, so
## the reversal preview rides this same walk instead of a second one.
static func effect_lines(effects: Dictionary, _nation, include_bloc := false) -> Array[String]:
	var out: Array[String] = []
	for key in effects.get("tax_rates_pct", {}):
		var v := float(effects["tax_rates_pct"][key])
		out.append((Strings.t("Raises %s by %s points.") if v > 0.0 else Strings.t("Lowers %s by %s points.")) % [
			_tax_label(String(key)), Num.f(absf(v), 1)])
	for key in effects.get("spending_pct_gdp", {}):
		var v := float(effects["spending_pct_gdp"][key])
		out.append((Strings.t("Raises %s spending by %s%% of GDP.") if v > 0.0 else Strings.t("Cuts %s spending by %s%% of GDP.")) % [
			String(key), Num.f(absf(v), 2)])
	if effects.has("structural_unemployment_pct"):
		var v: float = _scalar_of(effects["structural_unemployment_pct"])
		out.append((Strings.t("Adds %s points of structural unemployment.") if v > 0.0 else Strings.t("Takes %s points of structural unemployment.")) % Num.f(absf(v), 2))
	if effects.has("potential_growth_pct"):
		var v: float = _scalar_of(effects["potential_growth_pct"])
		out.append((Strings.t("Lifts potential growth by %s points a year.") if v > 0.0 else Strings.t("Lowers potential growth by %s points a year.")) % Num.f(absf(v), 2))
	if effects.has("other_revenue_pct_gdp"):
		var v: float = _scalar_of(effects["other_revenue_pct_gdp"])
		out.append((Strings.t("Raises %s%% of GDP in other revenue.") if v > 0.0 else Strings.t("Forgoes %s%% of GDP in other revenue.")) % Num.f(absf(v), 2))
	if effects.has("company"):
		var company: Dictionary = effects["company"]
		# TWO SHAPES, the dual reading _scalar_of() gives the scalars above: a
		# bill's effects carry {"sector": ..., "burden": ...}, and a negated
		# ledger carries {sector: delta} keyed by the sector itself
		# (legislature.gd's ledger shape -- _subtract_ledger's own comment
		# records that the two differ). Without the second reading, a
		# regulation repeal's "It reverses" preview dropped the one line it
		# exists to show.
		if company.has("sector") and company.has("burden"):
			var v := absf(float(company.get("burden", 0.0)))
			if v != 0.0:
				var up: bool = float(company.get("burden", 0.0)) > 0.0
				out.append((Strings.t("Imposes a burden of %s on the %s sector.") if up else Strings.t("Lifts a burden of %s on the %s sector.")) % [
					Num.f(v, 2), Labels.sector(String(company.get("sector", "")))])
		else:
			for sector in company:
				var ledger_v := float(company[sector])
				if ledger_v != 0.0:
					out.append((Strings.t("Imposes a burden of %s on the %s sector.") if ledger_v > 0.0 else Strings.t("Lifts a burden of %s on the %s sector.")) % [
						Num.f(absf(ledger_v), 2), Labels.sector(String(sector))])
	for term in effects.get("society", {}):
		var v: float = _scalar_of(effects["society"][term])
		if v != 0.0:
			out.append(_society_line(String(term), v))
	if include_bloc:
		for bloc in effects.get("bloc_offset", {}):
			var v := float(effects["bloc_offset"][bloc])
			if v != 0.0:
				out.append(Strings.t("Moves the %s bloc's approval price by %s.") % [
					Labels.bloc(String(bloc)), Num.fs(v, 2)])
	return out


## Authored keys carry prose labels. The player-composed key and its
## register-read name retired at V5.3 e; a key outside the five (none can
## land) prints as its id, the spending lines' own fallback.
static func _tax_label(key: String) -> String:
	var authored := {
		"income": Strings.t("the income tax rate"),
		"corporate": Strings.t("the corporate tax rate"),
		"vat": "VAT",
		"capital_gains": Strings.t("the capital gains tax rate"),
		"wealth": Strings.t("the wealth tax rate"),
	}
	return String(authored.get(key, key))


## The five society terms, phrased by the stance they name. The SIGN is the
## direction (law.gd's schema: signed stances -- still true now the repeal verb
## exists (V4.2): repeal removes whole acts or nothing, it never moves a stance
## partway), so the phrase map carries the pair and the walker only picks the side.
static func _society_line(term: String, v: float) -> String:
	var up := v > 0.0
	match term:
		"corruption":
			return Strings.t("Loosens the anti-corruption stance.") if up else Strings.t("Tightens the anti-corruption stance.")
		"migration":
			return Strings.t("Opens migration.") if up else Strings.t("Tightens migration.")
		"settlement":
			return Strings.t("Settles with the unions.") if up else Strings.t("Takes a harder line with the unions.")
		"press_freedom":
			return Strings.t("Loosens the press laws.") if up else Strings.t("Tightens the press laws.")
		"judicial_independence":
			return Strings.t("Strengthens the courts' independence.") if up else Strings.t("Curbs the courts' independence.")
	return (Strings.t("Raises the %s stance by %s.") if up else Strings.t("Lowers the %s stance by %s.")) % [term, Num.f(absf(v), 2)]


static func _scalar_of(value) -> float:
	if typeof(value) == TYPE_DICTIONARY:
		return float(value.get("", 0.0))
	return float(value)
