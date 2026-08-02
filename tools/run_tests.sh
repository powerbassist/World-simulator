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
  tests/test_law_panel.gd
  tests/test_nation_panel.gd
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
