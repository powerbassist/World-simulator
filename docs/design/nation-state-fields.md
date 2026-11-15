---
title: NationState fields -- the why behind the society, demography, unrest, media and commodity registers
tags:
  - design
  - save
  - architecture
---

# NationState fields: the long arguments

Moved here from `src/core/nation_state.gd` (V5.3, the parent's ruling of 2026-11-15) so the file has room under the
2 000-line cap without moving a field. Each field keeps a one-line purpose and a pointer to its section here. The save
verdict itself is a column, `absent_ok` in `src/core/nation_fields.gd`; the prose below is the argument for it, as
written when each field was added, unchanged. See [[data-architecture]] for the save rules.

## `commodity_state`

The nation's commodity state: what it can make, what it wants, what it made,
what it bought and sold, and the ONE world price vector. Written by
commodities.gd and by nothing else (single writer, pinned by
tests/test_commodities.gd reading src/), seeded by Commodities.init_nation at
new game.

SEVEN KEYS, and the shape is the module's contract rather than this field's:
  capacity           good id -> units/month the nation COULD make. This is the
                     SEED-TIME SNAPSHOT (month-0 sector output through the
                     recipe structure): the tick derives capacity FRESH from
                     the live `sector_output` every month and never reads this
                     key back, so it is a record of how the game began and not
                     a live stock.
  demand             good id -> units it wants this month, at the live price.
  output             good id -> units made NET of what this nation's own
                     downstream recipes consumed of it, so the figure is value
                     added's own numerator rather than a gross production count:
                     a tonne of iron ore that went into this month's steel is
                     not also counted as iron ore output.
                     (Gross production would double-count every intermediate,
                     which is why the net form is stored.)
  surplus            good id -> output minus demand where that is positive,
                     i.e. what it has to sell; 0.0 where it does not.
  trade              good id -> units bought (positive) or sold (negative).
  price              good id -> the world price (EUR/unit), one vector shared
                     by every nation and clamped to
                     commodity_constants.PRICE_BAND of base.
  value_added_eur_bn what this month's output was worth, EUR bn -- the CHANGE
                     the block models (the step-0 verdict: levels are not
                     reproducible from recipes, deltas are). No SIM module
                     reads it; the readers are the UI surfaces (the
                     Commodities panel and the two map layers).

SERIALISED, SAVE_VERSION 37, and it earns the bump rather than riding one: an
absent register reads as a nation that can make nothing and holds no price
vector, which is the `region_gdp_eur_bn` class and not the neutral-empty one.
The whole dictionary travels under its own key, and it reaches from_dict()
through `nation_field_readers.commodity_state()` -- which casts and re-owns it, the
character registers' discipline applied to a register that is a dictionary of
dictionaries rather than a typed flat map.

THE LAZY SEED IN Commodities.tick_month() STAYS: save_manager refuses a mismatched
version, so no pre-37 save reaches this field through a load. It covers an ns from a
payload with the key absent (a stripped dictionary, a fixture, before the first tick)
and is a pure function of the nation's measured mix, pinned by tests/test_commodities.gd.

## `service_quality`

V1.5a. Spending line → the quality of that service as a stock, in points of GDP,
converging on what the nation actually spends on it delivered. Written by
Society.tick_month() and by nothing else. Keyed by society_constants.QUALITY_KEYS,
which holds `health` alone today for a reason that is the design rather than a
limitation: `defence` already has military_capability and `education` and
`infrastructure` already share potential_shift_pct, so a second stock on either
would be that lever twice.

EARNS THE SAVE_VERSION BUMP, 15 → 16, and it is the only one of the three fields
here that does. Absent it reads 0.0 against a France that has spent 11.0 % of GDP
on health for decades — every reader then sees a country whose hospitals have
ceased to exist, and the satisfaction term reads a collapse the player did not
cause. `military_capability`'s case at V1.3g verbatim, and it is the strongest
form of it: equilibrium-init does not rescue the field, because re-deriving it on
load would silently erase an accumulated decline the player spent a term earning.

## `start_service_quality`

The reference every quality satisfaction term is measured against — captured at
init from the equilibrium, so `service_quality - start_service_quality` is exactly
0.0 at new game. `start_deficit_pct_gdp`'s and `start_bloc_burden`'s treatment.

EARNS NOTHING. It is recomputed at init from the `spending_pct_gdp` every nation
file already authors, so like a firm's authored share it round-trips through
`data/nations/` rather than through the save. Serialised all the same, because a
save reloaded before its first tick must measure against the same reference it was
saved with rather than against a fresh equilibrium.

## `corruption`

V1.5a. Signed accumulated corruption, clamped to
±society_constants.CORRUPTION_MAX. Written by Legislature.apply() through the
`society` effect channel and by nothing else in the project — `regulation_burden`
above has the identical discipline, and `Society` only ever reads this.

Read as a factor on the quality stock's TARGET, not on the satisfaction delta.
Cabinet.effectiveness() multiplies deltas only, so a corruption factor placed
there would cost a player who never moves a spending line exactly zero.

EARNS NOTHING. Absent it reads 0.0 — no corruption — which is correct for every
version-15 save, because those games carried no `society` law to pass. `measures`
at V1.3c, `pacts` at V1.3g, `appointments` at U6a and `regulation_burden` at
V1.4b. Serialised regardless, for V1.4b's reason: a law writes it once and no tick
recomputes it, so a save that dropped it would silently repeal every
anti-corruption act the assembly ever passed.

## `young_share`, `old_share`

V1.5b. The share of the population aged 0–14 and 65+, as fractions. Written by
Demography.tick_month() and by nothing else. The 15–64 share is NOT here: it is
the residual `1 - young - old`, derived by Demography.working_share() at every
read, so the three sum to 1.0 by construction and a conservation bug is
structurally impossible — _apply_growth_to_sectors()'s discipline, which keeps
sector output summing to GDP with no reconciliation.

BOTH EARN THE SAVE_VERSION BUMP, 16 → 17. Absent they read 0.0, which is not a
neutral default but a different model: the working share becomes 1.0, the
dependency ratio 0.0, the denominator under the quality stock 0/start, and the
labour force the entire population. `military_capability`'s case at V1.3g and
`eu_member`/`neighbours`' at V1.3b — a reloaded game running a different model
from the one that saved it. Init-from-content does NOT rescue them, for
`service_quality`'s reason one session earlier: re-deriving on load would erase a
drift the player spent a term living through.

## `start_young_share`, `start_old_share`

The references the dependency factor is measured against — captured at init, so
Demography.dependency_factor() is exactly 1.0 at new game for all ten nations.
`start_service_quality`'s treatment and `start_bloc_burden`'s.

EARN NOTHING. Recomputed at init from the `imported.cohorts` every nation file now
carries, so they round-trip through `data/nations/` rather than through the save.
Serialised all the same, for start_service_quality's reason: a save reloaded
before its first tick must measure against the reference it was saved with.

## `young_share_per_yr`, `old_share_per_yr`, `participation_share`, `pop_growth_pct`

Static per-nation facts copied off `imported.cohorts` at init and never written
again — the treatment `eu_member` and `neighbours` get, and for the same reason:
it is what lets Demography take no loader, so Budget.project() runs the real model
forward on a copy and gets the real answer.

`pop_growth_pct` replaces economy_constants.POP_GROWTH_PCT, one flat 0.15 shared by
all ten. Measured, it spans Italy's **−0.238** to Luxembourg's **+1.938**, so the
constant had every nation in the roster growing and one of them shrinks.

EARN NOTHING, and they are the clearest case of it on this list: they are content.

## `migration_stance`

V1.5b. Signed accumulated migration stance, clamped to
±demography_constants.MIGRATION_STANCE_MAX. Written by Legislature.apply() through
the `society` effect channel and by nothing else — `corruption` above has the
identical discipline, and Demography only ever reads this.

The second term on `effects.society`, which V1.5a declared as schema two later
sessions would read rather than one session's private field. This is the first of
them, so the channel needed no widening beyond one key.

EARNS NOTHING. Absent it reads 0.0 — no standing migration policy — which is
correct for every version-16 save, because those games had no migration law to
pass. `corruption`'s case one session earlier. Serialised regardless and for
`corruption`'s reason: a law writes it once and no tick recomputes it, so a save
that dropped it would silently repeal every migration act the assembly passed.

## `gini_index`, `start_gini_index`

V1.5c. The Gini index, drifting at its own measured rate, and the reference the
deviation is taken against. Written by Demography.tick_month() and by nothing else —
`young_share`'s discipline, and it lives beside it rather than beside the unrest
fields below because this layer owns measured facts about the POPULATION and the
session that prices a fact owns the price rather than the fact.

THE DECLARED STOPGAP docs/tiers/v1.md §5 books to V1.5c, with §6 named as its real
writer. That row says the index "cannot be DERIVED", which is true — there are no
brackets, no deciles and no capital/labour split anywhere — and it does not follow
that it has to be invented: the provider behind every other figure in
`imported` publishes it for all ten. Nothing the player does moves this number, and
that is the mechanical form of the §5/§6 split rather than a limitation.

`gini_index` EARNS THE BUMP, 17 → 18, and `start_gini_index` earns nothing.
`young_share`'s split exactly: absent, the live index reads 0.0 against a France
sitting at 31.8, so the deviation the whole term is built on is measured from a
country with no inequality at all — and re-deriving on load would erase a drift the
player spent a term living through, which is `service_quality`'s reason. The
reference is recomputed at init from `imported.inequality` and round-trips through
`data/nations/`; serialised regardless, `start_young_share`'s treatment.

## `gini_index_per_yr`

Static per-nation fact off `imported.inequality`, never written again —
`young_share_per_yr`'s treatment and standing. SIGNED, and that is the roster rather
than a courtesy: six of the ten are growing more equal (NLD −0.417, ESP −0.350) and
four less (DEU +0.329, CHE +0.214), so a one-directional model would be wrong about
most of Europe. EARNS NOTHING — it is content.

## `unrest_pct`

V1.5c. The grievance index, 0–100, written by Unrest.tick_month() and by nothing
else. Exactly 0.0 at new game for all ten nations, because every term of its target
is a deviation against the nation's own start — `trade_baseline_by_partner`'s idiom
and `delivery_factor`'s, and what lets the whole layer go live with the shared
balance regimes moving only where an act actually fires.

EARNS THE SAVE_VERSION BUMP, 17 → 18. Absent it reads 0.0 — a perfectly calm France
— which silently ends a crisis the player spent a term living through, and
init-from-equilibrium does not rescue it for `service_quality`'s reason at V1.5a:
re-deriving on load erases the accumulation, which IS the state.

## `unrest_cooldown_months`

Months until industrial action can fire again. Written by Unrest.tick_month().

ALSO EARNS THE BUMP, and separately, which is why the two are asserted separately in
tests/test_save_load.gd. Absent it reads 0, and 0 means *act now* — so a reloaded
save fires a strike in its first month regardless of what the player was doing.
U6a's `diplo_months_to_act` case, where an absent counter read as "act now" and fired
nine acts in one month.

## `unrest_impulse_pct`

Points of annual growth the standing industrial action is costing, negative, decaying
toward zero. A SIXTH addend in economy.gd's growth sum and the only price unrest
charges — see docs/unrest-model.md §4 for why there is no direct opinion term.

DECAYING and not sustained, which is the distinction economy.gd's own comment draws
about the five terms already there: a measure in force and a subsidy in force are
standing conditions, and a strike is a SHOCK. Decayed by Unrest.tick_month() rather
than by Economy, so this field keeps one writer.

EARNS NOTHING. Absent it reads 0.0 — a shock already over — which is soft and
self-correcting within months, `trade_baseline_by_partner`'s case.

## `unrest_opinion_load`

What the country's grievance takes off every bloc's approval target, on the [-1, +1]
scale opinion.gd's satisfaction terms use. Written by Unrest.tick_month() and read by
opinion.gd from here rather than by calling Unrest — `deployment_opinion_load`'s
arrangement, and here it is what keeps the two files out of a preload cycle.

THE PRICE THE PROBE FORCED. V1.5c was designed with an output-only price, on the
premise that approval would fall through `growth` and `jobs`; measured on an isolated
path, fourteen years at maximum grievance costs 4.94 % of GDP and 0.42 points of
workers approval, because this opinion model prices RATES and a permanent LEVEL loss
is invisible to it. See unrest_constants.UNREST_OPINION_SCALE.

EARNS NOTHING. Absent it reads 0.0 and Unrest.tick_month() recomputes it from
`unrest_pct` on the next tick, so it fails soft for exactly one month —
`unrest_impulse_pct`'s case and `trade_baseline_by_partner`'s.

## `settlement_stance`

V1.5c. Signed accumulated settlement stance, clamped to
±unrest_constants.SETTLEMENT_STANCE_MAX. Written by Legislature.apply() through the
`society` channel and by nothing else — the THIRD term on that channel, after
`corruption` at V1.5a and `migration` at V1.5b, and the second piece of evidence that
V1.5a was right to call it schema rather than one session's private field.

It is what makes unrest CLOSABLE. Without it the only lever pointed at a strike is a
spending increase, and society_probe.gd table (c) established that raising a line
necessarily widens the deficit — so the player could buy industrial peace only by
opening `public_finances`, and unrest would be the permanent monotone charge
docs/defence-model.md names.

EARNS NOTHING. Absent it reads 0.0 — no standing settlement — correct for every
version-17 save, because those games had no settlement law to pass.
`migration_stance`'s case one session earlier, and serialised for its reason.

## `press_freedom`

V1.5d. Signed accumulated press-freedom stance, clamped to
±media_constants.PRESS_FREEDOM_MAX. Written by Legislature.apply() through the
`society` channel and by nothing else — the FOURTH term on that channel, after
`corruption`, `migration` and `settlement`. A channel carrying four registers written
by four different sessions is schema rather than luck, which is what
docs/society-model.md section 3 bet on when it opened the channel with one term.

TWO PRICES, ONE VERB, which is docs/coercion-model.md's shape: it scales the framing
deviation below, and it adds a signed term to Unrest.unrest_target(). The second is
this session's answer to "press freedom as a dial with LEGITIMACY costs" — there is
no legitimacy quantity and the row handed V1.5d the choice of inventing one or
dropping the clause. Neither: legitimacy is willingness to accept your rule outside
the ballot box, which is the grievance V1.5c already built. See
media_constants.PRESS_UNREST_BETA.

EARNS NOTHING. Absent it reads 0.0 — no standing press law — correct for every
version-18 save, because those games had none to pass. `settlement_stance`'s case one
session later, and serialised for its reason: a law writes it once and no tick
recomputes it, so a save that dropped it would silently repeal the act.

## `framing_gain`

V1.5d. Per-bloc salience gain, keyed by opinion_constants.BLOC_KEYS. Written by
Media.tick_month() and read by opinion.gd from here rather than by calling Media —
`deployment_opinion_load`'s and `unrest_opinion_load`'s arrangement for the third
time, and here it does two jobs at once: it keeps opinion.gd out of a preload cycle
AND it keeps opinion.gd from needing a DataLoader, which it has never had and which
would have cost fourteen call sites to give it.

Every entry is exactly opinion_constants.SALIENCE_GAIN at new game for all ten
nations, and forever for the seven with no data/outlets/ file. The size-weighted mean
across the six blocs is exactly SALIENCE_GAIN in EVERY state, because the deviation
media.gd computes is anchored on that mean — which is what lets this session change
what the electorate notices without re-baselining a constant measured at S10.
tests/test_media.gd asserts both with exact equality.

EARNS NOTHING. Absent it reads empty and Media.tick_month() rewrites it in full on
the next tick, so it fails soft for exactly one month — `unrest_opinion_load`'s case.
