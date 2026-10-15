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
  tests/test_orgs.gd
  tests/test_council.gd
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
  # V4.7a: the chiefs -- the firm->person edge and the executive stopgap's
  # schema state, registered at authoring time like everything above it.
  tests/test_chiefs.gd
  # V4.3's machine test, registered at authoring time in this list rather than
  # discovered later -- the three-instance lesson above (summits, cabinet,
  # companies) is why it lands here unread.
  tests/test_characters.gd
  # V4.3's surface scanner: the register is the list. Registered at authoring
  # time for the same reason.
  tests/test_surfaces_people.gd
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
  # V4.7a: the two-tier register -- tiers, sparse fallback reads, and the
  # from_dict alias fix's mutation + lossless-roundtrip pins.
  tests/test_companies_tiers.gd
  tests/test_society.gd
  tests/test_demography.gd
  tests/test_unrest.gd
  tests/test_media.gd
  tests/test_cycle.gd
  tests/test_inflation.gd
  # V4.7b: the autonomy machine -- determinism, tick order, single writer,
  # body silence, zero-sum, and the three mechanics by construction.
  tests/test_industry.gd
  # V4.7b's UI surfaces -- the pending mark, the announce memory and the
  # panel's autonomy sections pinned through main's own memory dicts and
  # LIVE controls (queue_free is deferred; same-frame reads see ghosts).
  # Registered at authoring time per the pass-5 fleet's find: the silent
  # class is why this file exists.
  tests/test_industry_surfaces.gd
  # V4.2: the per-law effect ledger -- realized deltas (the clamp speaks for
  # itself), per-act accumulation, repeal subtracting through the ONE applier,
  # the refusals (constitutional, unrecorded), event silence, round-trip.
  tests/test_statute_ledger.gd
  # V4.2 T2: the composition machine -- the draft refusals, the budget
  # arithmetic and the derived price, countdown-to-composition, the legality
  # scan finding composed laws, the repeal draft (negated preview, NOT in
  # effects), determinism, round-trip + absence, and the price table's bloc
  # vocabulary pinned against BLOC_KEYS.
  tests/test_statute_compose.gd
  # V4.2 T4: custom tax keys through the params register -- birth writes rate
  # AND params (apply registers before the rate moves, or commit would refuse
  # its own applier), the zero-reference rule, the ONE erosion curve, opinion
  # at the shared scale, the authored five bit-identical, commit's custom
  # plumbing, one key one birth, repeal keeps the params, round-trip.
  tests/test_statute_tax.gd
  # V4.2 T5: the tax panel, the bill briefing and the two paid polls, pinned
  # through the real main.tscn -- every leg here can fail silently (a rate
  # row off a hand-written list, a quoted-not-landed price, an uncharged or
  # re-rollable poll, a forecast that never firms), and the single-writer pin
  # on poll_purchases is a source scan no sim-side test can see.
  tests/test_statute_surfaces.gd
  # V4.2 T6: the assembly's own life -- the idle hazard band, a bill dividing
  # with no player action, the endorsement moving its division and charging
  # once, the chief-backed lobby naming a real law and a real chief, the
  # in-flight guard, determinism, the has_budget gate, round-trip. Registered
  # at authoring time per the pass-5 fleet's find.
  tests/test_statute_assembly.gd
  # V4.2 T7: the grown book's content shape -- counts, theme and per-bloc sign
  # coverage, spread bands -- re-derived from JSON beside tools/law_lint.py.
  tests/test_law_content.gd
  # V4.4: re-derive event_lint.py's E1b per-choice mean and business-worst bands;
  # shell-only lint rules otherwise never run in the agent suite.
  tests/test_event_content.gd
  # V4.4: a chain may arm a hook event (pass 17's cooldown floor keeps the hook
  # door off it) -- loads clean; the collision-key legs stay on fixtures.
  tests/test_event_chain_loader.gd
  tests/test_credit.gd
  tests/test_tax.gd
  tests/test_sectors.gd
  tests/test_projects.gd
  tests/test_campaign.gd
  tests/test_pledges.gd
  # V4.1: the programme register machine -- the offer, the once-only term-start
  # choice, the three conclusions through the ONE applier, the derived progress,
  # and the leaf contract (preloads, AI inert, no hand-written id list).
  tests/test_programme.gd
  # V4.1: the credit CHANNEL -- the pulse Opinion prices, the bounded stock,
  # the decay band, and the main.gd tick ordering the same-month guarantee
  # rests on. PROGRAMME_SPAN is deliberately not pinned; the sweep owns it.
  tests/test_programme_channel.gd
  # V4.6: the goods register and the recipe table -- the register's size and
  # category coverage, and the cross-file rule that makes an input naming a good
  # nobody declares a LOAD ERROR rather than a recipe that produces nothing.
  tests/test_commodities_data.gd
  # V4.6: the commodity state and the production tick -- the leaf property, the
  # single writer, determinism across twelve months, and the two bounds a
  # shortage would otherwise escape (no NaN, prices inside the band).
  tests/test_commodities.gd
  tests/test_referendum.gd
  tests/test_upper_house.gd
  tests/test_judiciary.gd
  tests/test_events.gd
  # V4.4 T11: the event plate library -- the generator's --dry-run pinned
  # set-equal to what the helper can name, every nameable plate bytes-loading
  # once any ships, no orphan art, and the one-reader rule over src/ui.
  tests/test_event_art.gd
  # V4.4 T7: the desk figure on the top bar -- the empty desk reads a clear
  # state and stays visible, the count is the queue's own and the tooltip names
  # the worst severity, and the brass mark keys on the same read the strip does.
  tests/test_top_bar_desk.gd
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
  # V4.6's read-only commodity surface: the panel registers and renders at month
  # 0, the shortage alert flips on its threshold, and the two map modes are
  # registry entries the switcher grows without a legend edit. Registered at
  # authoring time -- the four historical omissions (companies, cabinet, summits,
  # map_plants) are why it lands here unread.
  tests/test_commodities_panel.gd
  # V4.1: the agenda surface -- the term-start pause, the offer built from the
  # register, the choose command path, the derived progress bar, and the cards.
  tests/test_agenda_panel.gd
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
  tests/test_map_network.gd
  tests/test_map_flows.gd
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
  # V4.5b2 T6: the council panel's verbs, the desk mark and the Europe figure.
  tests/test_orgs_panel.gd
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

# --print-tests: the machine-readable registry (the GUI and any caller read
# the list from here so the array above stays the only list anywhere).
if [ "${1:-}" = "--print-tests" ]; then
  printf '%s\n' "${tests[@]}"
  exit 0
fi

# Python is a gate dependency now -- tools/import_data.py already made it
# one for the import pipeline. Fail loud, never silent.
if ! command -v python >/dev/null 2>&1; then
  echo "python not found -- the suite runner needs it (tools/suite_runner.py)" >&2
  exit 2
fi

# Step 0: the gate tests its own tooling before it gates anything else.
python tools/suite_runner.py --selftest || exit 1

# A FRESH CLONE HAS NO .godot/, AND WITHOUT ONE THERE IS NO
# global_script_class_cache.cfg -- so every `class_name` in a committed addon is
# unresolvable and DialogueManager, the project's one autoload, fails to parse
# (the V2.8 review's cloning finding). One import pass builds the cache; the
# runner also does this, but keep it here so the error text is the bash one
# on a machine whose python is missing.
if [ ! -d ".godot" ]; then
  echo "no .godot/ -- importing once so the script class cache exists" >&2
  godot --headless --import >/dev/null 2>&1 || true
fi

# One execution core. The status line, per-test capture, noise filter and
# script-error scan that lived below this point moved into it, so they exist
# in exactly one place. Flags pass through: -j1 for sequential, --verbose
# for the old print-everything stream.
exec python tools/suite_runner.py --ci "$@" "${tests[@]}"
