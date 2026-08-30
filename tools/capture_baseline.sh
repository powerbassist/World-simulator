#!/usr/bin/env bash
# V2.5: capture one balance_probe run per regime x nation into $2.
# usage: bash tools/capture_baseline.sh <tree> <outdir>
set -u
TREE="$1"
OUT="$2"
mkdir -p "$OUT"
REGIMES=(
  hands_off
  spendthrift
  austerity
  managed
  tinkering
  tax_max
  tax_zero
  spend_max
  spend_zero
  ruinous
  managed_dissolves_early
  austerity_dissolves_late
  managed_cabinet_shorted
  austerity_cabinet_shorted
  managed_amends_term_limit
  managed_abolishes_the_monarchy
  managed_signs_agreement
  managed_imposes_tariffs
  managed_signs_pact
  managed_books_ahead
  managed_subsidises
  managed_regulates
  managed_nationalises
  managed_corrupts
  managed_tightens_migration
  managed_censors
  redistributive
  flat_tax
  managed_then_redistributive
  industrial_policy
  managed_then_invest
  public_works
  managed_then_build
  managed_campaigns_early
  managed_campaigns_late
  managed_calls_a_referendum
  managed_reforms_the_ballot
  managed_answers_softly
  managed_answers_hard
  managed_bill_is_held
  managed_bill_is_struck
  managed_captures_the_courts
  managed_keeps_its_word
  managed_breaks_its_word
  managed_breaks_nothing
  managed_settles
  managed_then_austerity
  managed_then_austerity_settles
)
for R in "${REGIMES[@]}"; do
  for N in FRA DEU GBR; do
    # Skip a capture that already exists, so a chunked or interrupted run
    # resumes instead of restarting the whole sweep. Each outdir is used once.
    if [ -s "$OUT/${R}_${N}.txt" ]; then
      continue
    fi
    godot --path "$TREE" --headless --script res://tools/balance_probe.gd -- "$R" "$N" 2>&1 \
      | grep -Ev '^\[MCP(RuntimeServer|Registry)\]' \
      | grep -Ev '^ERROR:' \
      | grep -Ev '^   at: ' \
      > "$OUT/${R}_${N}.txt"
  done
done
echo "captured $(ls "$OUT" | wc -l) runs into $OUT"
