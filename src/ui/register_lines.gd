extends RefCounted

## The order form's lines that read the sim beyond the quote (V5.3 c' register slice 2),
## here because register_panel.gd is at its size ratchet: the warning band's chip and range,
## the blocs a vote moves, and the Union's line. Each is a read of one sim call; none writes.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Labels = preload("res://src/ui/labels.gd")
const UK = preload("res://src/sim/units_constants.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const UnitEnvelope = preload("res://src/sim/unit_envelope.gd")


## The band (Units.band, read once by the caller) as the dot plot's range: from the worst
## band region's figure to the least behind's. The band is a rank, but every region between
## two of its members is further behind than the last of them, so the range is exactly the
## band's rows. NAN for an empty band (no zone, no glyph).
static func band_range(band: Dictionary, shown: Dictionary) -> Vector2:
	if band.is_empty():
		return Vector2(NAN, NAN)
	var lo := INF
	var hi := -INF
	for id in band:
		lo = minf(lo, float(shown[id]))
		hi = maxf(hi, float(shown[id]))
	return Vector2(lo, hi)


## The band's threshold said in words beside the glyph (the tone never alone).
static func band_chip(parent: Control, band: Dictionary) -> void:
	if band.is_empty():
		return
	var chip := PanelKit.chip(parent, Strings.t("%s %% behind the nation or worse") % Num.f(100.0 * UK.UNIT_REGION_BAND, 0),
		UiTheme.CHIP_WARN, "warning")
	chip.set_meta("band_chip", true)
	# Sized to its words, never the column's width.
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


## Who the vote pleases and who it does not, by bloc (UnitBuild.blocs, the vote's own move):
## the sizes are a fraction of a point, so the line names the blocs, not the points.
static func blocs(parent: Control, ns, loader, programme: Dictionary) -> void:
	var moves: Dictionary = UnitBuild.blocs(ns, loader, programme)
	var pleased: Array = []
	var against: Array = []
	for bloc in moves:
		if float(moves[bloc]) > 0.0:
			pleased.append(Labels.bloc(String(bloc)))
		elif float(moves[bloc]) < 0.0:
			against.append(Labels.bloc(String(bloc)))
	if pleased.is_empty() and against.is_empty():
		return
	var said: Array = []
	if not pleased.is_empty():
		said.append(Strings.t("Blocs for it: %s.") % ", ".join(pleased))
	if not against.is_empty():
		said.append(Strings.t("Blocs against it: %s.") % ", ".join(against))
	PanelKit.plain_line(parent, " ".join(said), PanelKit.Tone.PLAIN).set_meta("blocs", true)


## The Union's line on the order: what it would reserve at the vote (UnitEnvelope.reserve on
## a draft, as UnitWarnings.answers reads it), or why nothing. Nothing at all for a nation in
## no organisation or a type the Union does not cofinance.
static func union(parent: Control, state, ns, loader, programme: Dictionary, quote: Dictionary) -> void:
	var org := UnitEnvelope.org_of(loader, ns)
	if org == "" or not bool(loader.unit_types[String(programme["type"])].get("cofinanced", false)):
		return
	var now := UnitPrice.now(state)
	var draft := {"type": programme["type"], "op": UK.OP_BUILD, "rows": programme["rows"], "voted": now,
		"months_left": int(quote["build_months"]), "surcharge": quote.get("surcharge", {})}
	UnitEnvelope.reserve(loader, ns, draft)
	var reserved := float(draft.get("union", {}).get("reserved_eur_m", 0.0))
	var period := UnitEnvelope.period_of(loader, org, UnitEnvelope.year_of(now))
	var text := ""
	if reserved > 0.0:
		text = Strings.t("Union: about %s bn back after the opening.") % Num.f(reserved / 1000.0, 2)
	elif period.is_empty():
		text = Strings.t("No Union money this year.")
	elif UnitEnvelope.year_of(UnitPrice.opens_at(draft)) > int(period["pays_until_year"]):
		text = Strings.t("No Union money: opens after %d.") % int(period["pays_until_year"])
	else:
		text = Strings.t("No Union money: its envelope is spent.")
	PanelKit.plain_line(parent, text, PanelKit.Tone.DIM).set_meta("union", true)
