#!/usr/bin/env bash
# Runs every headless test. Non-zero exit if any of them fails.
set -uo pipefail
cd "$(dirname "$0")/.."

tests=(
  tests/test_data.gd
  tests/test_political_systems.gd
  tests/test_clock.gd
  tests/test_economy.gd
  tests/test_budget.gd
  tests/test_budget_panel.gd
  tests/test_opinion.gd
  tests/test_polling_panel.gd
  tests/test_state_copy.gd
  tests/test_electoral_systems.gd
  tests/test_elections.gd
  tests/test_government.gd
  tests/test_government_panel.gd
  tests/test_censure.gd
  tests/test_discipline.gd
  tests/test_dissolution.gd
  tests/test_election_panel.gd
  tests/test_legislature.gd
  tests/test_amendment.gd
  tests/test_transition.gd
  tests/test_scenario.gd
  tests/test_diplomacy.gd
  tests/test_trade.gd
  tests/test_coercion.gd
  tests/test_bloc.gd
  tests/test_foreign_policy.gd
  tests/test_defence.gd
  tests/test_calendar.gd
  # V2.4a: the ribbon is the day surface, and its wiring (day-tick dirty,
  # furniture coverage, register-sourced tooltip) can fail silently -- most U1
  # bugs this project shipped were silent, and the drawn pixels themselves are
  # the screenshot pass's job, not a raster change-detector in here.
  tests/test_ribbon.gd
  # test_summits.gd was authored at V2.4b and never added here, so it ran only
  # by hand and went unnoticed for two sessions while SAVE_VERSION moved to 28
  # and then to 29 under its own frozen "!= 27" pin -- test_companies.gd's
  # failure at V1.5a in a new place: a check that silently covers less than it
  # appears to.
  tests/test_summits.gd
  tests/test_people.gd
  # ...and test_cabinet.gd was the THIRD instance, found by the V1.6 playability
  # audit: 55 test files on disk against 54 here. It covers can_assign, assign,
  # effectiveness and resignations -- a player verb (Politics -> Reassign) and one
  # of the three bookable diary verbs. It passes, so nothing was hidden by it; what
  # was hidden is that nobody would have known if it stopped passing.
  tests/test_cabinet.gd
  # test_companies.gd was authored at V1.4a and NEVER ADDED HERE, so V1.4a, V1.4b and
  # V1.4c all shipped with their own test file running only when invoked by hand. Found
  # at V1.5a by noticing test_society.gd was absent from a green suite and looking at
  # the list -- docs/people-model.md §9's finding in a new place: a check that silently
  # covers less than it appears to.
  tests/test_companies.gd
  tests/test_society.gd
  tests/test_demography.gd
  tests/test_unrest.gd
  tests/test_media.gd
  tests/test_cycle.gd
  tests/test_inflation.gd
  tests/test_credit.gd
  tests/test_tax.gd
  tests/test_sectors.gd
  tests/test_projects.gd
  tests/test_campaign.gd
  tests/test_pledges.gd
  tests/test_referendum.gd
  tests/test_upper_house.gd
  tests/test_judiciary.gd
  tests/test_events.gd
  tests/test_geography.gd
  # V2.5: the partition closes, the deviation is zero-mean, and the register still
  # has exactly one reader.
  tests/test_regions.gd
  # V2.7: the graph is content, the index is mean-one in output weights, and the
  # leaf takes Dictionaries and preloads nothing but its own constants.
  tests/test_network.gd
  tests/test_migration.gd
  # V2.6c: the third flow on the population registers -- direction, exact
  # conservation over the COMBINED flow, Luxembourg's one-region bound, and the
  # field's own import contract.
  tests/test_natural_change.gd
  tests/test_siting.gd
  # V2.8: the mix is a partition that reads exactly its content with no plants,
  # the dependency deviation is exactly 0.0, and the grid stays national.
  tests/test_energy.gd
  tests/test_law_panel.gd
  tests/test_nation_panel.gd
  tests/test_calendar_panel.gd
  tests/test_people_panel.gd
  # V2.3's pipeline: orphan art refused, the bytes-not-load() path held green
  # headless, the missing-portrait fallback, one committed icon per registered
  # window, and the card showing the player's leader's art.
  tests/test_portraits.gd
  tests/test_game_loop.gd
  tests/test_menu.gd
  tests/test_map_view.gd
  tests/test_map_layers.gd
  tests/test_minimap.gd
  tests/test_map_markers.gd
  tests/test_map_cities.gd
  tests/test_map_cull.gd
  tests/test_map_plants.gd
  tests/test_shell.gd
  tests/test_window_frame.gd
  tests/test_panel_kit.gd
  tests/test_hud.gd
  tests/test_ui_theme.gd
  tests/test_overview_panel.gd
  tests/test_save_load.gd
  tests/test_balance.gd
  # Every check in this one pins a KNOWN BUG rather than a feature -- it is the
  # playability audit's register, and it turns red when somebody FIXES one.
  # See docs/playability-audit.md.
  tests/test_playability.gd
  tests/test_acknowledgments.gd
)

# THE RUNNER IS THE WHOLE GATE -- there is no CI -- so a test file on disk that is
# missing from the array above runs NOWHERE, and passes for as long as nobody looks.
# That has now happened four times (test_companies at V1.4a, test_cabinet, test_summits
# at V2.4b, test_map_plants at V2.8), each found by eye whole sessions later, and each
# time the response was to add the one file rather than to close the class. Counting the
# directory closes it: an unregistered test is a RED suite in the session that writes it,
# which is the only moment the omission is cheap. A warning here would be read as noise
# and skipped, which is the failure this replaces.
unregistered=""
for f in tests/test_*.gd; do
  case " ${tests[*]} " in
    *" $f "*) ;;
    *) unregistered="$unregistered $f" ;;
  esac
done
if [ -n "$unregistered" ]; then
  echo "test files on disk but absent from this runner:$unregistered" >&2
  echo "add them to tests=() above -- an unregistered test runs nowhere" >&2
  exit 1
fi

# The MCP toolkit plugin registers an MCPRuntimeServer autoload, and its export
# gate is OS.has_feature("editor") -- true for `--headless --script`, so every
# test process binds a runtime port and announces it. Three lines per test, 55
# tests, none of them about the simulation. Filtered here rather than fixed in
# the addon (addons/ is gitignored and reinstalled per machine, so a patch there
# is lost) and rather than left in (a green suite nobody reads is a suite nobody
# reads). Exit status comes from godot via PIPESTATUS, never from grep.
mcp_noise='^\[MCP(RuntimeServer|Registry)\]'

# A test that quits(0) while the engine printed a SCRIPT ERROR is a GREEN RUN OVER
# BROKEN CODE, and this runner has produced two of them: V2.1b's tests reached
# panel members that session had deleted, both found by eye rather than here.
# V2.1c reproduced it on purpose -- a parse error in main.gd left test_shell.gd
# printing "all checks passed" over a scene that had not loaded. Zero are emitted
# today, so this costs nothing until it saves something.
script_error='SCRIPT ERROR|Parse Error'

# A FRESH CLONE HAS NO .godot/, AND WITHOUT ONE THERE IS NO
# global_script_class_cache.cfg -- so every `class_name` in a committed addon is
# unresolvable and DialogueManager, the project's one autoload, fails to parse.
# That is CLAUDE.md's first gotcha reaching the suite itself: V2.4b's adoption gate
# ("it must init under --headless --script, which is what tools/run_tests.sh is")
# only ever ran on a machine that already had the cache, so the gate passed warm and
# the invariant this runner rests on -- green from a fresh clone -- was false.
# One import pass builds the cache; it is skipped when .godot/ is already there, so
# this costs a warm run nothing.
if [ ! -d ".godot" ]; then
  echo "no .godot/ -- importing once so the script class cache exists" >&2
  godot --headless --import >/dev/null 2>&1 || true
fi

# A run is one engine start per test and several minutes long, and until now it
# printed nothing at all until the first one finished -- a suite with no cursor cannot
# be told from a hang. The status line goes to STDERR and is rewritten in place, so
# every test's own stdout reads exactly as it did before and `> log` still captures
# only test output. Not a terminal (a log, a pipe, a CI capture): one plain line per
# test instead, because a carriage return in a file is a line nobody can read.
BAR_WIDTH=24
total="${#tests[@]}"
started="$SECONDS"

_status() {
  # $1 = tests finished so far, $2 = the one about to run.
  local done="$1" name="$2" elapsed=$((SECONDS - started)) filled bar eta left
  if [ ! -t 2 ]; then
    printf '[%2d/%2d] %s\n' "$((done + 1))" "$total" "$name" >&2
    return 0
  fi
  filled=$((done * BAR_WIDTH / total))
  bar="$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' "$((BAR_WIDTH - filled))" '')"
  # The estimate is the mean of what has already run, so it is meaningless before the
  # first test returns and says so rather than printing a confident zero.
  eta="--:--"
  if [ "$done" -gt 0 ]; then
    left=$((elapsed * (total - done) / done))
    eta="$(printf '%d:%02d' "$((left / 60))" "$((left % 60))")"
  fi
  printf '\r\033[K[%s] %2d/%2d  %-30s %d:%02d elapsed, ~%s left' \
    "$bar" "$done" "$total" "$name" \
    "$((elapsed / 60))" "$((elapsed % 60))" "$eta" >&2
  return 0
}

_status_clear() {
  if [ -t 2 ]; then printf '\r\033[K' >&2; fi
  return 0
}

failed=0
finished=0
for t in "${tests[@]}"; do
  _status "$finished" "${t#tests/}"
  out="$(godot --headless --script "res://$t" 2>&1)"
  status="$?"
  finished=$((finished + 1))
  _status_clear
  echo "$out" | grep -Ev "$mcp_noise"
  if [ "$status" -ne 0 ]; then
    echo "FAIL $t" >&2
    failed=1
  elif echo "$out" | grep -Eq "$script_error"; then
    echo "FAIL $t -- exited 0 with a script error in its output" >&2
    failed=1
  fi
done

elapsed=$((SECONDS - started))
if [ "$failed" -ne 0 ]; then
  echo "test suite failed" >&2
  exit 1
fi
printf 'test suite passed -- %d tests in %d:%02d\n' "$total" "$((elapsed / 60))" "$((elapsed % 60))"
