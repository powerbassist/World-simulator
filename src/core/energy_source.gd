class_name EnergySource
extends RefCounted

## Typed, validated in-memory representation of one entry in
## data/energy-sources.json. See docs/energy-model.md.
##
## EVERY FIELD IS REQUIRED AND NONE IS DERIVED FROM ANOTHER, which is
## src/core/project_action.gd's position rather than src/core/investment_action.gd's:
## V1.6e refused a second authored strength because a constant already turned its one
## dial into a bill, a rate and a coefficient. Here energy_constants.gd holds no such
## constant, so output, duration, two prices, an import intensity, an opposition
## and an emission intensity are seven independent facts about a named technology.
## A cheap fast small plant is a genuinely different object from a dear slow large
## one, and the ladder is the lever.
##
## THE BRANCH IS CHECKED AGAINST energy_constants.BRANCHES rather than left free.
## The mix is a partition over exactly the three branches the import measured, so a
## seventh source naming a fourth branch would produce a mix that does not sum to
## one -- an error a validator can catch and a runtime never would.

const K = preload("res://src/sim/energy_constants.gd")

var id: String = ""
var source_name: String = ""
var branch: String = ""
var output_twh: float = 0.0
var build_months: int = 0
var build_cost_pct_gdp: float = 0.0
var run_cost_pct_gdp: float = 0.0
var import_intensity: float = 0.0
var emission_t_per_twh: float = 0.0
var opposition: float = 0.0


static func from_dict(d: Dictionary, filename: String, errors: Array[String]):
	var s = new()

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: missing or invalid string field 'id'" % filename)
		return s
	s.id = d["id"]

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, s.id])
	else:
		s.source_name = d["name"]

	s.branch = String(d.get("branch", ""))
	if not K.BRANCHES.has(s.branch):
		errors.append("%s: %s branch '%s' is not one of %s" % [filename, s.id, s.branch, K.BRANCHES])

	s.output_twh = float(d.get("output_twh", 0.0))
	if s.output_twh <= 0.0:
		errors.append("%s: %s output_twh must be positive" % [filename, s.id])

	s.build_months = int(d.get("build_months", 0))
	if s.build_months <= 0:
		errors.append("%s: %s build_months must be positive" % [filename, s.id])

	s.build_cost_pct_gdp = float(d.get("build_cost_pct_gdp", 0.0))
	s.run_cost_pct_gdp = float(d.get("run_cost_pct_gdp", 0.0))
	if s.build_cost_pct_gdp <= 0.0 or s.run_cost_pct_gdp < 0.0:
		errors.append("%s: %s needs a positive build cost and a non-negative run cost" % [filename, s.id])

	s.import_intensity = float(d.get("import_intensity", -1.0))
	if s.import_intensity < 0.0 or s.import_intensity > 1.0:
		errors.append("%s: %s import_intensity must be in [0, 1]" % [filename, s.id])

	# The -1.0 sentinel is import_intensity's own idiom: a missing key would
	# otherwise read the 0.0 default, which for a fossil source is a silent lie,
	# so absence fails the loader's non-negative check rather than parsing into
	# a number. _validate_energy_sources() refuses on it.
	s.emission_t_per_twh = float(d.get("emission_t_per_twh", -1.0))

	s.opposition = float(d.get("opposition", -1.0))
	if s.opposition < 0.0:
		errors.append("%s: %s opposition must be non-negative" % [filename, s.id])

	return s
