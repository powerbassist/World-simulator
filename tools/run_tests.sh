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
  tests/test_events.gd
  tests/test_law_panel.gd
  tests/test_nation_panel.gd
  tests/test_calendar_panel.gd
  tests/test_people_panel.gd
  tests/test_game_loop.gd
  tests/test_menu.gd
  tests/test_map_view.gd
  tests/test_map_layers.gd
  tests/test_minimap.gd
  tests/test_map_markers.gd
  tests/test_shell.gd
  tests/test_window_frame.gd
  tests/test_hud.gd
  tests/test_ui_theme.gd
  tests/test_overview_panel.gd
  tests/test_save_load.gd
  tests/test_balance.gd
  # Every check in this one pins a KNOWN BUG rather than a feature -- it is the
  # playability audit's register, and it turns red when somebody FIXES one.
  # See docs/playability-audit.md.
  tests/test_playability.gd
)

# The MCP toolkit plugin registers an MCPRuntimeServer autoload, and its export
# gate is OS.has_feature("editor") -- true for `--headless --script`, so every
# test process binds a runtime port and announces it. Three lines per test, 55
# tests, none of them about the simulation. Filtered here rather than fixed in
# the addon (addons/ is gitignored and reinstalled per machine, so a patch there
# is lost) and rather than left in (a green suite nobody reads is a suite nobody
# reads). Exit status comes from godot via PIPESTATUS, never from grep.
mcp_noise='^\[MCP(RuntimeServer|Registry)\]'

failed=0
for t in "${tests[@]}"; do
  godot --headless --script "res://$t" 2>&1 | grep -Ev "$mcp_noise"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "FAIL $t" >&2
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "test suite failed" >&2
  exit 1
fi
echo "test suite passed"
