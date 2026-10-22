extends PanelContainer

## The bill briefing -- V4.2 T5. One popup over a bill the player is about to
## put to the assembly (opened on Propose, for authored and composed laws
## alike) or has just drafted (opened by the tax panel's compose flow, where
## it carries the drafting months). What it says and the ONE source it reads:
##
##   - the channels, direction and magnitude, walked off the bill's effects
##     dictionary by effect_lines() below -- one walk, and the attribution
##     sentence at the top is those same lines joined, so the prose and the
##     rows cannot drift the way two walkers would;
##   - the bill's political price, per bloc, at the LANDED value --
##     clampf(value, LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX) -- because the
##     clamp is what the applier will actually write. T3's sweep recorded that
##     the derived price can QUOTE past the bound (urban +1.325 on a
##     half|max spec), so a quoted-but-never-landing figure is displayed only
##     as a note beside the landed one, never as the number;
##   - the target, for a repeal draft, with the negated ledger it was shown
##     at draft time;
##   - the two commissioned polls: the assembly forecast for the bill (firm
##     down to ABSTAIN_BAND where the assembly poll was bought) and the
##     country's bloc read at the poll's margin -- PollNoise's ordinary band,
##     or displayed_precise's +-1.0 where the popular poll was bought.
##
## Reads simulation state and never writes it; the single exception is the
## two commission buttons, which send player intent back as one explicit
## command -- Statute.buy_poll(). The division itself is not this panel's:
## its Propose verb routes through main.gd into law_panel.run_proposal(), so
## one propose path and one card path survive however the bill was asked for.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Labels = preload("res://src/ui/labels.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const LawPanel = preload("res://src/ui/law_panel.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const Statute = preload("res://src/sim/statute.gd")
const StatuteK = preload("res://src/sim/statute_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

## Emitted for the division, and ONLY for the division: main.gd hides the
## briefing and calls law_panel.run_proposal(law), whose `proposed` signal
## carries the card and the U4 baseline. A draft has no division to ask for.
signal propose_requested(law)

## Emitted when a poll commission lands, carrying the pre-purchase baseline
## and the label -- budget_panel.gd's `committed` contract. The refusal path
## emits nothing; the briefing shows the refusal itself.
signal polled(before: Dictionary, label: String)

var _state = null
var _loader = null
## The bill's key in the purchase register: the law id, or the draft id while
## the bill is still drafting (which is the law id it will carry).
var _bill_key := ""
## Set for a law on the book (authored or composed); empty for a draft.
var _law = null
## The draft entry (ns.draft_bills shape) for a draft; {} for a law.
var _draft := {}
var _ns = null
var _party_list: Array = []

var _body: VBoxContainer


func _ready() -> void:
	# Sized by content and placed by main.gd's CenterContainer -- the same
	# placement mechanism the four modal panels use, whose own comment records
	# why anchors cannot do this before the children exist. The height is the
	# content's honest minimum, measured on the captured frame: shorter and
	# the Propose/Close row scrolls below the fold of a popup that exists to
	# be answered -- the V2.1b finding (politics at 865 against an 826px
	# band) in a popup's shape.
	custom_minimum_size = Vector2(680, 600)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


## A bill on the book -- authored, or a composed law past its drafting.
func open_for_law(law, state, loader) -> void:
	_state = state
	_loader = loader
	_law = law
	_draft = {}
	_bill_key = String(law.id)
	_ns = _state.player()
	_party_list = _loader.parties.get(_ns.id, [])
	_rebuild()


## A parked draft -- the tax panel's compose flow opens this straight after
## Statute.draft() accepts the spec.
func open_for_draft(entry: Dictionary, draft_id: String, state, loader) -> void:
	_state = state
	_loader = loader
	_law = null
	_draft = entry
	_bill_key = String(draft_id)
	_ns = _state.player()
	_party_list = _loader.parties.get(_ns.id, [])
	_rebuild()


## A load invalidates everything this panel holds: the cached GameState is the
## discarded game, the purchase state on it is dead, and a stale poll press
## would write the dead run's books and push a dead-snapshot effects row into
## the live one. Called from main.gd's load path, beside the industry-map
## resets -- this panel is NOT in the window registry, so the setup() sweep
## that rebinds every registered surface never reaches it (the V2.8 drift
## class, one panel deeper).
func detach() -> void:
	hide()
	_state = null
	_ns = null
	_party_list = []
	_law = null
	_draft = {}
	_bill_key = ""


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()

	PanelKit.line(_body, tr("BILL BRIEFING — %s") % _bill_name(), PanelKit.Tone.PLAIN)

	# The attribution sentence IS the channel walk -- joined lines, not a
	# second description of the same effects. A bill that names no channel
	# (a pure birth, or a pure repeal) prints no sentence: the sections below
	# say what there is to say. Each line is a whole sentence with its own full
	# stop, so they are joined by a space and nothing is added (QA #50: ". " plus
	# a final "." printed every stop twice).
	var effects: Dictionary = _law.effects if _law != null else _draft.get("channels", {})
	var lines := effect_lines(effects, _ns)
	if not lines.is_empty():
		PanelKit.line(_body, " ".join(lines), PanelKit.Tone.PLAIN)
	var repeal_text := _repeal_line()
	if repeal_text != "":
		PanelKit.line(_body, repeal_text, PanelKit.Tone.PLAIN)

	_build_price()

	if not _draft.is_empty():
		var months := int(_draft.get("months_left", 0))
		PanelKit.line(_body, tr_n("In drafting: %d month before it reaches the order paper.", "In drafting: %d months before it reaches the order paper.", months) % months, PanelKit.Tone.PLAIN)

	_build_polls()

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	_body.add_child(buttons)

	# The division is a law's verb; a draft composes when its countdown ends.
	if _law != null:
		var propose_btn := Button.new()
		propose_btn.text = tr("Propose the bill")
		propose_btn.pressed.connect(func(): propose_requested.emit(_law))
		buttons.add_child(propose_btn)

	var close_btn := Button.new()
	close_btn.text = tr("Close")
	close_btn.pressed.connect(func(): hide())
	buttons.add_child(close_btn)


func _bill_name() -> String:
	if _law != null:
		return String(Strings.law_name(_law))
	return String(_draft.get("name", _bill_key))  # i18n: row-ok a drafted bill's composed name, not a data row


## What the bill does to the statue book's target, named for a player who
## will not know the id. Authored targets come off the loader; a composed
## target off the register it lives in.
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

## The bill's political price at what the applier will actually WRITE. The
## derived quote can sit past the +-1.0 clamp (T3's recorded bound), so every
## figure shown here is the landed one and a quote that exceeded the bound is
## a note beside it, never the number itself.
func _build_price() -> void:
	var section := PanelKit.section(_body, tr("The price"))
	var price: Dictionary = _law.effects.get("bloc_offset", {}) if _law != null else _draft.get("price", {})
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
	if offended.is_empty():
		PanelKit.line(section, tr("It offends no bloc outright."), PanelKit.Tone.DIM)
	else:
		PanelKit.line(section, tr("It offends: %s.") % ", ".join(offended), PanelKit.Tone.PLAIN)

	# The reversal preview is the record of what the player was SHOWN at draft
	# time -- the passage subtracts the target's LIVE ledger, so these lines
	# are a briefing, not the mechanism. include_bloc is TRUE here: a negated
	# ledger carries the bloc deltas the repeal will actually re-apply, and
	# dropping them showed a preview that named every channel but the one a
	# political-price-bearing repeal most moves (the ultra pass-2 finding).
	if not _draft.is_empty():
		var negated: Dictionary = _draft.get("negated", {})
		if not negated.is_empty():
			PanelKit.heading(section, tr("It reverses"))
			for line in effect_lines(negated, _ns, true):
				PanelKit.line(section, line, PanelKit.Tone.DIM)


## -- The polls ---------------------------------------------------------------

func _build_polls() -> void:
	var section := PanelKit.section(_body, tr("The polls"))

	# The assembly read. For a law, the same walk the legislature window
	# prints -- LawPanel's static, so the two windows cannot disagree about a
	# division -- at the band this bill's purchases buy. A draft has no
	# division to forecast until it reaches the order paper.
	if _law != null:
		var band := LawPanel.forecast_band(_ns, _bill_key)
		PanelKit.line(section, tr("The Assembly: %s") % LawPanel.forecast_text(
			_ns, _party_list, _law, band), PanelKit.Tone.PLAIN)
	else:
		PanelKit.line(section, tr("Drafting first; when it completes, the bill waits on your Propose in the Legislature."), PanelKit.Tone.DIM)

	# The country's read, bloc by bloc, at the margin the player has paid
	# for: the ordinary poll noise, or the commissioned +-1.0 where the
	# popular poll was bought. The poll is ABOUT this bill, so its hash is
	# keyed by the bill as well as the bloc -- two bills' polls are two
	# pieces of fieldwork, not one number read twice. A COMMISSIONED poll's
	# hash is keyed on the month the fieldwork happened -- the purchase
	# record's own month, stored exactly in poll_id units -- because the
	# fixed-forecast rule means the player bought one published figure, not
	# a fresh draw every month (the ultra pass-14 finding): the free poll
	# beside it keeps the live month, and the two legitimately read
	# differently as the months pass.
	var bought: Dictionary = _ns.poll_purchases.get(_bill_key, {})
	var precise: bool = bought.has(StatuteK.POLL_KIND_POPULAR)
	var id := PollNoise.poll_id(int(_state.year), int(_state.month))
	if precise:
		id = int(bought[StatuteK.POLL_KIND_POPULAR].get("month", id))
	var rows: Array = [["", tr("the country")]]
	for bloc in K.BLOC_KEYS:
		var truth: float = float(_ns.bloc_approval.get(bloc, 0.0))
		var shown: float = PollNoise.displayed_precise(id, _poll_key(bloc), truth) if precise \
			else PollNoise.displayed(id, _poll_key(bloc), truth)
		rows.append([Labels.bloc(String(bloc)), Num.f(shown, 1)])
	PanelKit.ledger(section, rows)
	if precise:
		PanelKit.line(section, tr("Commissioned poll — margin of error about %.0f point.") % PollNoise.PRECISE_MAX_PCT, PanelKit.Tone.DIM)

	# Stacked, not side by side: the two commission buttons are long sentences, and
	# in Archivo two of them in one row measured 716 px inside a 646 px view -- every
	# right-aligned figure above landed in the clipped strip (V5.1a QA).
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	section.add_child(row)
	for kind in [StatuteK.POLL_KIND_ASSEMBLY, StatuteK.POLL_KIND_POPULAR]:
		var btn := Button.new()
		# A translated sentence on one line is the widest thing in the briefing: it wraps
		# (two lines in a longer language) rather than push the figures out of the view.
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# The sim's own price (G8: a flat fee, thousands of euros, not a share of GDP).
		var cost_k: float = StatuteK.poll_cost_eur_bn(kind) * 1.0e6
		# One whole sentence per kind (the article and the kind are the sentence's own).
		btn.text = (tr("Commission an assembly poll — €%s k") if kind == StatuteK.POLL_KIND_ASSEMBLY
			else tr("Commission a popular poll — €%s k")) % Num.f(cost_k, 0)
		if bought.has(kind):
			# The fixed-forecast rule, made visible: a bought poll is a
			# published figure, and the second commission is refused by the
			# sim even if a stale frame offers the button.
			btn.disabled = true
			btn.tooltip_text = tr("Commissioned — the figures it bought are fixed.")
		else:
			btn.pressed.connect(_on_poll.bind(kind))
		row.add_child(btn)

	# One line, filled only by a refusal -- an empty label is no line at all,
	# which is what a briefing with nothing refused should show.
	var refusal := Label.new()
	refusal.name = "RefusalLine"
	refusal.hide()
	section.add_child(refusal)


func _poll_key(bloc: String) -> String:
	return "%s|%s" % [_bill_key, bloc]


func _on_poll(kind: String) -> void:
	# A hidden panel's stale signal must not act: after detach() the state is
	# the discarded game, and buy_poll() would charge the dead run's debt and
	# emit a snapshot nothing live can compare against.
	if _state == null:
		return
	var before := Trends.snapshot_now(_state)
	var result: Dictionary = Statute.buy_poll(_state, _ns, _bill_key, kind)
	if bool(result.get("refused", false)):
		var refusal: Label = _body.find_child("RefusalLine", true, false)
		if refusal != null:
			refusal.text = String(result.get("refusal", tr("Refused.")))
			refusal.show()
		return
	polled.emit(before, (tr("Commissioned an assembly poll: %s") if kind == StatuteK.POLL_KIND_ASSEMBLY
		else tr("Commissioned a popular poll: %s")) % _bill_name())
	_rebuild()


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
static func effect_lines(effects: Dictionary, ns, include_bloc := false) -> Array[String]:
	var out: Array[String] = []
	for key in effects.get("tax_rates_pct", {}):
		var v := float(effects["tax_rates_pct"][key])
		out.append((Strings.t("Raises %s by %s points.") if v > 0.0 else Strings.t("Lowers %s by %s points.")) % [
			_tax_label(String(key), ns), Num.f(absf(v), 1)])
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


## Authored keys carry prose labels; a composed key's name lives on the
## params register its birth wrote -- the register is the label's source, so
## a key the machine invents is never named by a table here.
static func _tax_label(key: String, ns) -> String:
	var authored := {
		"income": Strings.t("the income tax rate"),
		"corporate": Strings.t("the corporate tax rate"),
		"vat": "VAT",
		"capital_gains": Strings.t("the capital gains tax rate"),
		"wealth": Strings.t("the wealth tax rate"),
	}
	if authored.has(key):
		return String(authored[key])
	var params: Dictionary = ns.custom_taxes.get(key, {})
	return Strings.t("%s's rate") % String(params.get("name", key))  # i18n: row-ok a composed tax's name, not a data row


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
