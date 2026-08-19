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
  tests/test_law_panel.gd
  tests/test_nation_panel.gd
  tests/test_calendar_panel.gd
  tests/test_people_panel.gd
  tests/test_game_loop.gd
  tests/test_menu.gd
  tests/test_map_view.gd
  tests/test_map_layers.gd
  tests/test_minimap.gd
  tests/test_shell.gd
  tests/test_window_frame.gd
  tests/test_hud.gd
  tests/test_ui_theme.gd
  tests/test_overview_panel.gd
  tests/test_save_load.gd
  tests/test_balance.gd
)

failed=0
for t in "${tests[@]}"; do
  if ! godot --headless --script "res://$t"; then
    echo "FAIL $t" >&2
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "test suite failed" >&2
  exit 1
fi
echo "test suite passed"
