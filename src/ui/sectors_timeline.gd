extends RefCounted

## The Sectors overview's timeline -- G3 S3, the author's "C La frise": every running thing
## on one dated time scale, the picked row's decision in the side sheet (sectors_decision.gd).
##
## rows() is the one reader: the sim's processes, plant closures, rescues, failing majors'
## windows, a foreign bid and the sector programmes, each with the months to its end and
## to its answer. Nothing here is estimated: a row the sim keeps no end for (a programme)
## runs to the scale's edge, and when a process started is not kept, so a bar runs from
## today, not from its start (Design's "Not verified" on the picture).
##
## The marks follow the G3 decisions: amber only for "this waits on you", with its date; a
## window that closes without an answer due is an outline in the neutral tone; red only for
## bad news ("unanswered, it shuts"). The accent is today's line and the picked row.

const Processes = preload("res://src/sim/processes.gd")
const Closures = preload("res://src/sim/closures.gd")
const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")
const Investment = preload("res://src/sim/investment.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const Region = preload("res://src/core/region.gd")
const IndustryProgress = preload("res://src/ui/industry_progress.gd")
const SectorProgramme = preload("res://src/ui/sector_programme.gd")
const TimelineBar = preload("res://src/ui/timeline_bar.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const DateText = preload("res://src/ui/date_text.gd")

## The scale's months: never under SPAN_MIN (a near row still has room), never past SPAN_MAX.
const SPAN_MIN := 6
const SPAN_MAX := 12
## The left column's width, in px at text size 100: the picture's 360 (260 cut titles at 1.0).
const TEXT_WIDTH := 360.0
## Waiting rows first, the soonest answer first; then the rest by their end, the open-ended last.
const KIND_ORDER := ["ask", "closure", "failing", "bid", "process", "search", "rescue", "programme"]


## One row per running thing: {key, sector, company_id, kind, title, sub, ends, due, style,
## waits, then, bad, money, source}. `ends` and `due` are months from this one (the first
## day of month now + n), -1 for none; `style` is TimelineBar's.
static func rows(state, loader, ns) -> Array:
	var out: Array = []
	if state == null or loader == null or ns == null:
		return out
	var now: int = state.year * 12 + state.month
	var sector_of := {}
	for company in Companies.majors_of(loader, ns.id) + Companies.body_of(loader, ns.id):
		sector_of[String(company.id)] = String(company.sector)
	for row in Processes.rows(ns):
		var cid := String(row["company_id"])
		var stage := String(row["stage"])
		var asks: bool = not (row.get("ask", {}) as Dictionary).is_empty() and not row.has("answer")
		var verb := Strings.row_name("company-actions", _action(loader, String(row["action_id"])))
		_add(out, sector_of, cid, {"key": "process|%s" % String(row["id"]), "kind": "ask" if asks else "process",
			"title": Strings.t("%s: %s") % [loader.firm_name(ns.id, cid), verb],
			"sub": Strings.t("%s, then %s") % [Strings.t(String(IndustryProgress.STAGE.get(stage, stage))),  # i18n: row-ok the table's msgids
				Strings.t(String(IndustryProgress.NEXT.get(stage, "")))],  # i18n: row-ok the table's msgids
			"ends": maxi(int(row["months_left"]), 1), "due": 1 if asks else -1, "style": TimelineBar.DUE if asks else TimelineBar.BAR,
			"waits": asks, "then": Strings.t(String(IndustryProgress.NEXT.get(stage, ""))), "source": row})  # i18n: row-ok the table's msgids
	for row in Closures.open(ns):
		var cid := String(row["company_id"])
		var waits := _closure_waits(row)
		var firm: String = loader.firm_name(ns.id, cid)
		var city := _city(loader, ns, row)
		var jobs := Strings.t("%s jobs") % CompanyVerb.thousands(float(row.get("jobs", 0.0)))
		if waits:
			# A buyer back defaults to the sale (ClosureCard.build): its title says so.
			var title := _plant(firm, city, Strings.t("%s closes its %s plant"), Strings.t("%s closes a plant"))
			if String(row["status"]) == Closures.OFFERED:
				title = _plant(firm, city, Strings.t("%s: the buyer is back for its %s plant"), Strings.t("%s: the buyer is back for its plant"))
			_add(out, sector_of, cid, {"key": "closure|%s" % String(row["id"]), "kind": "closure",
				"title": title, "sub": jobs,
				"ends": maxi(int(row.get("due", now)) - now, 1), "due": maxi(int(row.get("due", now)) - now, 1), "style": TimelineBar.DUE,
				"waits": true, "bad": Strings.t("unanswered, it shuts") if String(row["status"]) == Closures.ANNOUNCED else "", "source": row})
		else:
			_add(out, sector_of, cid, {"key": "closure|%s" % String(row["id"]), "kind": "search",
				"title": _plant(firm, city, Strings.t("%s: a buyer for its %s plant"), Strings.t("%s: a buyer for its plant")), "sub": jobs,
				"ends": maxi(int(row.get("months_left", 1)), 1), "style": TimelineBar.WINDOW, "source": row})
	for row in Closures.rescues(ns):
		var cid := String(row["company_id"])
		_add(out, sector_of, cid, {"key": "rescue|%s" % cid, "kind": "rescue",
			"title": _plant(loader.firm_name(ns.id, cid), _city(loader, ns, row), Strings.t("%s: its %s plant rescued"), Strings.t("%s: its plant rescued")),
			"sub": Strings.t("%s jobs kept") % CompanyVerb.thousands(float(row.get("jobs", 0.0))),
			"ends": maxi(int(row["months_left"]), 1), "style": TimelineBar.BAR,
			"money": Strings.t("%s a year") % EffectsStrip.sum_text(-float(row["rescue_eur_bn_per_year"])), "source": row})
	for failure in Industry.failing(state, ns, loader):
		var cid := String(failure["company_id"])
		_add(out, sector_of, cid, {"key": "failing|%s" % cid, "kind": "failing",
			"title": Strings.t("%s: rescue window") % loader.firm_name(ns.id, cid), "sub": Strings.t("a failing major"),
			"ends": maxi(int(failure["months_left"]), 1), "due": maxi(int(failure["months_left"]), 1), "style": TimelineBar.DUE,
			"waits": true, "bad": Strings.t("unanswered, it goes under"), "source": failure})
	var bid: Dictionary = Industry.pending_bid(state, ns, loader)
	if not bid.is_empty():
		var cid := String(bid["company_id"])
		_add(out, sector_of, cid, {"key": "bid|%s" % cid, "kind": "bid",
			"title": Strings.t("%s: a foreign takeover bid") % loader.firm_name(ns.id, cid),
			"sub": Strings.t("from %s") % loader.nation_name(String(bid["bidder_nation"])),
			"ends": maxi(int(bid["months_left"]), 1), "due": maxi(int(bid["months_left"]), 1), "style": TimelineBar.DUE,
			"waits": true, "source": bid})
	for sector in EK.SECTOR_TREND.keys():
		if Investment.intensity_of(ns, String(sector)) <= 0.0:
			continue
		var stops: Array = SectorProgramme.stops(loader, String(sector))
		var at := SectorProgramme.current(ns, stops, String(sector))
		if stops.is_empty() or at <= 0:
			continue
		out.append({"key": "programme|%s" % sector, "sector": String(sector), "company_id": "", "kind": "programme",
			"title": Strings.row_name("investment-actions", stops[at]["action"]), "sub": Strings.t("the sector's programme"),
			"ends": -1, "due": -1, "style": TimelineBar.RUNNING, "waits": false, "then": "", "bad": "",
			"money": Strings.t("%s a year, running") % EffectsStrip.sum_text(-SectorProgramme.price(state, loader, ns, stops, String(sector), at)),
			"source": {"action": stops[at]["action"]}})
	out.sort_custom(_sooner)
	return out


## The scale's months for these rows.
static func span_of(rows: Array) -> int:
	var far := SPAN_MIN - 1
	for r in rows:
		far = maxi(far, maxi(int(r["ends"]), int(r["due"])))
	return clampi(far + 1, SPAN_MIN, SPAN_MAX)


## The last day to answer a row due `months` from now: the month end crossed into month now
## + `months` lands the default, so it is the last day of the month before (the Diary's
## "Answer by", diary_grid.gd).
static func answer_by(state, months: int) -> String:
	var t: int = state.year * 12 + state.month + maxi(months, 1) - 1
	var month := (t - 1) % 12 + 1
	var year := floori((t - 1) / 12.0)
	var day := DateText.days_in(month, year)
	return "%s %s" % [DateText.weekday(day, month, year), DateText.day_mon(day, month)]


## "Sun 1 Aug": the first day of month now + `months`, the day the month's end settles it.
static func date_in(state, months: int) -> String:
	var t: int = state.year * 12 + state.month + months
	var month := (t - 1) % 12 + 1
	var year := floori((t - 1) / 12.0)
	return "%s %s" % [DateText.weekday(1, month, year), DateText.day_mon(1, month)]


## The sheet: the lead (how many answers are due, by when), the month axis, one row per
## running thing, the legend. `picked` is the picked row's key; `pick` is called with a key.
static func build(parent: Control, state, rows: Array, picked: String, pick: Callable) -> VBoxContainer:
	var body := PanelKit.sheet(parent)
	body.set_meta("timeline", "sheet")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	var head := PanelKit.heading(top, Strings.t("Under way · %d") % rows.size())
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lead := PanelKit.plain_line(top, lead_text(state, rows), PanelKit.Tone.PLAIN)
	lead.theme_type_variation = UiTheme.LEAD
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.set_meta("timeline", "lead")
	if rows.is_empty():
		return body
	var span := span_of(rows)
	var today := (float(state.day) - 1.0) / float(DateText.days_in(state.month, state.year))
	var width := TEXT_WIDTH * UiTheme.text_scale()
	var axis := HBoxContainer.new()
	body.add_child(axis)
	var pad := Control.new()
	pad.custom_minimum_size.x = width
	axis.add_child(pad)
	var scale: Control = TimelineBar.new()
	scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axis.add_child(scale)
	scale.axis(state.month, state.year, span, today)
	for r in rows:
		_row(body, state, r, span, today, width, String(r["key"]) == picked, pick)
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 16)
	legend.set_meta("timeline", "legend")
	body.add_child(legend)
	for key in [[TimelineBar.DUE, Strings.t("your answer is due")], [TimelineBar.BAR, Strings.t("ends on its date")],
			[TimelineBar.RUNNING, Strings.t("runs until you stop it")],
			[TimelineBar.WINDOW, Strings.t("a window that closes")]]:
		var item := HBoxContainer.new()
		legend.add_child(item)
		var swatch: Control = TimelineBar.new()
		item.add_child(swatch)
		swatch.key(String(key[0]))
		PanelKit.plain_line(item, String(key[1])).autowrap_mode = TextServer.AUTOWRAP_OFF
	return body


## The sentence over the scale: the answers due and the last date among them.
static func lead_text(state, rows: Array) -> String:
	var due := rows.filter(func(r) -> bool: return bool(r["waits"]))
	if due.is_empty():
		return Strings.t("Nothing waits on you; the rows run on their own.") if not rows.is_empty() else Strings.t("Nothing is under way.")
	var last := 0
	for r in due:
		last = maxi(last, maxi(int(r["due"]), int(r["ends"])))
	var t: int = state.year * 12 + state.month + maxi(last, 1) - 1
	var month := (t - 1) % 12 + 1
	var year := floori((t - 1) / 12.0)
	# The year only when it is not this one ("due by February" in November reads as last February).
	var when := DateText.month_long(month) if year == int(state.year) else DateText.month_long_year(month, year)
	return Strings.tn("%d answer is due by %s.", "%d answers are due by %s.", due.size()) % [due.size(), when]


static func _row(body: Control, state, r: Dictionary, span: int, today: float, width: float, picked: bool, pick: Callable) -> void:
	# The picked row sits on a tile; the others on the sheet itself (a container with no box).
	var plate: Container = PanelContainer.new() if picked else MarginContainer.new()
	if picked:
		plate.theme_type_variation = UiTheme.TILE_PANEL
	plate.mouse_filter = Control.MOUSE_FILTER_STOP
	plate.set_meta("timeline_row", String(r["key"]))
	body.add_child(plate)
	var line := HBoxContainer.new()
	plate.add_child(line)
	var words := VBoxContainer.new()
	words.custom_minimum_size.x = width
	words.add_theme_constant_override("separation", 0)
	line.add_child(words)
	# One left edge for kicker, title and sub (Design's T11): the kicker and the sub sit in by the
	# title button's own content margin, read from its stylebox rather than typed.
	var edge := MarginContainer.new()
	words.add_child(edge)
	var sector := PanelKit.plain_line(edge, Labels.sector(String(r["sector"])).to_upper(), PanelKit.Tone.PLAIN)
	sector.theme_type_variation = UiTheme.HEADING
	var title := Button.new()
	# Not a toggle: the picked row's plate carries the ground, the name inside stays bare (Design's T15).
	title.flat = true
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.text = String(r["title"])  # i18n: row-ok built from msgids above
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.tooltip_text = String(r["title"])  # i18n: row-ok built from msgids above
	title.set_meta("timeline_pick", String(r["key"]))
	title.pressed.connect(func() -> void: pick.call(String(r["key"])))
	words.add_child(title)
	var inset := roundi(title.get_theme_stylebox("normal").content_margin_left)
	edge.add_theme_constant_override("margin_left", inset)
	var below := MarginContainer.new()
	below.add_theme_constant_override("margin_left", inset)
	words.add_child(below)
	PanelKit.plain_line(below, String(r["sub"]))
	var bar: Control = TimelineBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A click on the lane is a click on its row: the plate below picks it.
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(bar)
	var chips := []
	if int(r["due"]) >= 0:
		chips.append([Strings.t("answer by %s") % answer_by(state, int(r["due"])), UiTheme.CHIP_WARN, "event"])
	if String(r.get("bad", "")) != "":
		chips.append([String(r["bad"]), UiTheme.CHIP_BAD, ""])
	elif String(r.get("then", "")) != "" and int(r["due"]) >= 0:
		chips.append([Strings.t("then %s") % String(r["then"]), UiTheme.CHIP, ""])
	var inside := String(r.get("money", ""))
	if String(r["style"]) == TimelineBar.WINDOW:
		inside = Strings.t("window closes %s") % date_in(state, int(r["ends"]))
	elif String(r["kind"]) == "process":
		# A process's bar runs to its stage's end, not the process's (the sim keeps no more).
		inside = Strings.t("this stage ends %s") % date_in(state, int(r["ends"]))
	elif String(r["style"]) == TimelineBar.BAR and inside == "":
		inside = Strings.t("ends %s") % date_in(state, int(r["ends"]))
	bar.setup(String(r["style"]), span, today, int(r["ends"]), int(r["due"]), inside, chips)
	plate.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pick.call(String(r["key"])))


static func _add(out: Array, sector_of: Dictionary, company_id: String, row: Dictionary) -> void:
	if not sector_of.has(company_id):
		return
	row["sector"] = String(sector_of[company_id])
	row["company_id"] = company_id
	for k in ["due", "then", "bad", "money"]:
		if not row.has(k):
			row[k] = -1 if k == "due" else ""
	if not row.has("waits"):
		row["waits"] = false
	out.append(row)


static func _sooner(a: Dictionary, b: Dictionary) -> bool:
	var ka := KIND_ORDER.find(String(a["kind"]))
	var kb := KIND_ORDER.find(String(b["kind"]))
	if bool(a["waits"]) != bool(b["waits"]):
		return bool(a["waits"])
	var ea := int(a["due"]) if int(a["due"]) >= 0 else (int(a["ends"]) if int(a["ends"]) >= 0 else 999)
	var eb := int(b["due"]) if int(b["due"]) >= 0 else (int(b["ends"]) if int(b["ends"]) >= 0 else 999)
	if ea != eb:
		return ea < eb
	return ka < kb


static func _closure_waits(row: Dictionary) -> bool:
	return String(row["status"]) == Closures.ANNOUNCED or (String(row["status"]) == Closures.OFFERED and not row.has("answer"))


## The plant's city, or "" when the row names none.
static func _city(loader, ns, row: Dictionary) -> String:
	var city = Region.find_city(loader.regions.get(ns.id, []), String(row.get("city_id", "")))
	return String(city.city_name) if city != null else ""


## A plant's title as one whole sentence: with its city, or the sentence that names none
## (AGENTS.md: a sentence is whole, never a fragment spliced in); the callers translate both.
static func _plant(firm: String, city: String, with_city: String, without: String) -> String:
	return with_city % [firm, city] if city != "" else without % firm


static func _action(loader, id: String):
	for a in loader.company_actions:
		if String(a.id) == id:
			return a
	return null
