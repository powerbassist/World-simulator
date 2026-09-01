# Roadmap

Build order for Nation Simulator. Short, scoped sessions — **one clear objective
each**, git commit at every session boundary.

This document is **forward-looking**. What shipped is one line each in the table
below; the corrections made along the way are in [[decision-log]]; the models are
in the model notes.

Scope reference: [docs/scope.md](docs/scope.md) · [docs/tiers/mvp.md](docs/tiers/mvp.md) · [docs/tiers/v1.md](docs/tiers/v1.md) · [docs/tiers/v2.md](docs/tiers/v2.md) · [docs/tiers/declined.md](docs/tiers/declined.md)
Stack reference: [docs/engine-decision.md](docs/engine-decision.md) · [docs/data-architecture.md](docs/data-architecture.md)

## Two tracks

Work runs on two interleaved tracks rather than one queue.

| | |
|---|---|
| **S-track** | Simulation systems — the model, the rules, the numbers. |
| **U-track** | The shell, the UI, and the feedback the player reads. |

The S-track existed from S0. The U-track was invented at U1, after an audit found
the roadmap contained **no UI work whatsoever** across the MVP and all of V1 —
presentation had been assumed to fall out of each feature session, and by V1.1a
that had produced a game with no menu, no pause, and seven overlays bound to
seven keypresses. See [[decision-log]].

One track at a time per session. Interleaved, not parallel.

**U5a interrupted the S-track queue, and it was asked for rather than
scheduled.** The queue below was V1.3c when the user asked for the shell to
become a geopolitical simulator's rather than a dashboard's — the player
incarnating a ruler, not administering a country. That is a legitimate reason to
interleave and exactly what the two-track split exists to allow, but it is worth
recording that the U-track's *own* backlog did not surface it: U5 had been
reserved since V1.1d for a Military tab, and that reservation is now spent
differently. Nothing in U1–U4's own record predicted a whole-shell relayout,
because each of those sessions improved the dashboard rather than asking whether
a dashboard was the right object.

---

## Shipped

| | Block | What it added |
|---|---|---|
| S0 | Project skeleton | Godot project, folder layout, git, attribution |
| S1 | Nation data | Schema, `tools/import_data.py`, loader, validator, ten nations |
| S2 | Fictional content | Leaders and party systems, banned-names check |
| S3 | Time | Daily tick, pause, three speeds, `month_elapsed` |
| S4 | Economy and budget | Three sectors, GDP/growth/unemployment, three taxes, six spending lines, debt service, projection-before-commit |
| S5 | Public opinion | Six voter blocs, salience, inertia, display-only polling noise |
| S6 | Elections | Ten real electoral systems, EP elections, seat allocation, win/lose — **the loop closed here** |
| S7 | Laws | Data-driven law templates, ideology-space vote resolution, blurred vote forecast |
| S8 | Map | GeoJSON Europe, colouring, hover, click, nation panel |
| S9 | Save and load | Versioned JSON saves, slot list |
| S10 | Balance | Ten probe regimes over fourteen simulated years, MVP done-when evidence |
| V1.1a | Government | Formation per nation's real rules, coalitions, cohabitation, minority, censure, Article 49.3 |
| U1 | Shell | Main menu, settings, credits, pause menu, keyboard navigation |
| X1 | Fixes | Atomic save writes; banned-names check green, closing the last MVP box |
| U2 | Shell | Dashboard: persistent top bar, left tab rail, seven panels docked, map as a tab |
| U3 | UI | Overview and Economy rebuilt as hierarchies, one code-built theme, `Trends` over `history` |
| U4 | UI | Decision deltas: `recent_effects`, a baseline captured at commit, measured against the next history entry |
| V1.1b | Sim | Party discipline as live state, seat-level rebellions, disaffection — the censure branch fires |
| V1.1c | Sim | Dissolution and snap elections — the rule as ten-nation data, measured before it was built, no election-model change needed |
| V1.1d | Sim | Cabinet and ministers — five portfolios keyed to spending lines, competence and portfolio position both derived rather than authored, shortfall-driven resignation measured before it was built |
| V1.2a | Sim | A second playable nation — Germany, per-nation starting fiscal policy (`policy_defaults.json` retired), bloc weights confirmed global by measurement rather than assumption |
| V1.2b | Sim | Political system templates as a constraint not a defaults table, the head of state (five constitutional monarchies now say so), a named lose condition replacing a structural-flag dispatch, term limits enforced (France's two-term limit termed-out on the merits), Italy's *semestre bianco* dissolution blackout |
| V1.2c | Sim | Constitutional amendment — a sixth per-nation dispatch field (`amendment_rule`) at real constitutional fractions, a seventh law effect channel that sets rather than nudges an institution, the load-bearing cross-check extended to amendments; measured, not assumed, that Germany's real two-thirds is unreachable, and left unauthored-against rather than detuned |
| V1.2d | Sim | System transition — the amendment mechanism pointed at `system_id`, a completeness rule on the institutional bundle, the cross-check inverted to validate against the amendment's target rather than the systems it is proposed under, a seventh per-nation dispatch field (`permits_system_change`); the United Kingdom made the third playable nation, added to the scope at plan time once the original scope was found to ship to zero playable nations |
| V1.2e | Sim | Start scenarios — an authored starting state as the project's answer to difficulty, three axes not §2's four (the coalition stays derived), a new directory-scanned content type with its validation split per-file/cross-file; the declined difficulty slider's own falsifier measured and not fired, an approval axis caught decorative at design time and fixed through the existing offset channel, and two of the three shipped scenarios corrected by the measurement before release — **V1.2 closed** |
| V1.3b | Sim | Trade: per-partner intensity and agreements — `external_impulse_pct` made **directed**, ninety entries from partner size, EU co-membership, a shared border and the pair's relations, retiring the one GDP-weighted aggregate that was the same number for every viewer; **V1.3a's dropped size asymmetry landed here**, because a normalised directed weight has two sides where a symmetric pair key has one (LUX→DEU is 13.1× DEU→LUX); bilateral agreements as a **third effect channel on the existing diplomatic action** rather than a content type of their own, with sector winners and losers that must sum to zero at load; a second declared stopgap; `SAVE_VERSION` 9 → 10. Both named escalation triggers were GBR-shaped and the first **fired** — at the obvious exponent the whole feature is arithmetically a no-op for one playable nation in three. The balance harness came back **bit-identical across thirty fourteen-year runs**, and the model was shaped to make that provable rather than likely |
| U5a | UI | The ruler's shell — the map stops being a tab and becomes the background the game is played on; the 150px tab rail is deleted and `dashboard.gd` with it; the seven docked pages become **floating windows that pin**, so reading the budget while proposing the law that changes it is possible for the first time. Bottom-left portrait card with the player's own approval, four themed clusters with a sub-row along the bottom, date and speed in the bottom-right corner, a message column stubbed for V1.8. One theme retuned from flat grey to deep navy with a **brass** accent, the repo's first committed fonts and its first four committed icons, and a 1920×1080 base that opens fullscreen. `flag` added to all ten nation files as data with a layout string, because a colour table in the UI is Rule 1's `if nation_id == "FRA"` wearing a hat |
| V1.3a | Sim | Relations and diplomatic actions — the block's schema session: **pair-keyed relations**, the first live state that is neither per-nation nor global, symmetric by construction and derived from the only two inputs the data can supply (EU co-membership, and a shared border added as fact); a new content type on the law template's preconditions/cooldown/effects shape but explicitly *not* its vote; four player verbs on the Europe tab's existing nation panel; `law_bloc_offset` → `bloc_offset` at the fifth writer that is not a law; `SAVE_VERSION` 8 → 9. The named escalation trigger did not fire, and the measurement set every content number — including one it made a table redo, and one exploit it caught before the content shipped |

| V1.3c | Sim | Tariffs and sanctions — coercion in both directions, on the project's **first directed state**: `GameState.measures` keyed `"FRA>DEU"`, which is the additive escape hatch [[diplomacy-model|V1.3a]] named in advance and took without touching a line of relations or agreements, because a tariff and its retaliation are two acts where a relationship and a contract are one. One verb with two prices — a tariff collects and bites moderately, a sanction collects nothing and bites hard — and they are **the same mechanism read at two points on one curve**. A fourth effect channel on the existing diplomatic action; no new content type again. Three things fall out of two constants rather than being authored: a **real Laffer curve** with an interior maximum at 0.625 severity, the protectionist trade-off (revenue now, trend later, through V1.3b's openness channel unchanged), and the fact that **who you can hurt is a different question from who matters to you** — damage scales with `w(target → imposer)`, so FRA→LUX is 12.1× LUX→FRA. **The probe corrected the model twice before any content existed**: an authored tariff rate was cut as the same intensity written twice, and damage read off the post-measure weight made every severity above the revenue peak *strictly dominated*. The named escalation trigger — that being sanctioned is below the readable floor — **fired on the first sweep and was resolved by the second correction rather than by tuning**; `COERCION_IMPULSE_MAX` was then found binding in reachable play and raised. Third declared stopgap (retaliation), agreement expiry discharged in one line, `SAVE_VERSION` **stays at 10** and the test says why. Thirty fourteen-year runs **bit-identical** again |

| U5c | UI | The map layers — the ten stop being coloured by a hash of their id and start being coloured by what the player has with them. `src/ui/map_layers.gd` is the **only** place a roster fill is chosen and is a **registry rather than a mode flag**: three layers today (political, relations, trade), and a fourth is one entry plus one branch, which is what let this run before V1.3c instead of after it. Three calls, each of which could have gone the other way. **The viewer is always the player** — the symmetric/directed asymmetry is not about whose seat you look from but about what the readout may *claim*, so `FRA–DEU 68` names the pair and a trade share never claims the partner's side. **Alpha is per-layer and `LAND_ALPHA` is not inherited** — U5b's 0.42-goes-grey finding is about a ramp with no hue variation and does not transfer, so the data layers carry 0.50. **Both ramps are anchored on measured values** — relations on `docs/diplomacy-model.md`'s four resting tiers rather than the nominal 0–100, trade mid-anchored on an even ninth so the map reads *above or below its fair share*. Hover moved off the fill and onto the stroke, because lifting a fill toward the accent is the one place in this interface where pointing at a number would change it; the player's own nation takes a brass outline and `NO_VALUE`, having no pair with itself and no self-weight. The staleness the row never mentioned is fixed: the map drew only on hover, pan, zoom and resize, which was complete while a colour came from `hash(id)` and is not once relations drift monthly |

| V1.3d | Sim | The bloc — EU-shaped membership as a real constraint on domestic policy, and the **fourth kind of live state**: not per-nation, not a symmetric pair, not a directed pair, but one object binding eight nations at once. A proposal reaches the council, the members divide on ideology weighted by the `ep_seats` `data/eu_parliament.json` already carried, and what carries binds the player whether or not they voted for it. Rules do **not** refuse a budget — comply and you pay in the policy you could not run, defy and you pay in a penalty on the budget line and a share of the national agenda. **The `ISSUE_KEYS` question three sessions deferred here was answered yes**, on three structural grounds rather than a thematic one: `bloc_offset` never enters `issue_salience`, so a Europe priced on it could never be named by the polling panel or the result screen; a split price never clears the ±3.0 noise floor in the headline figure; and a flat offset cannot become more *salient*, which is exactly what a rule biting hard should do. The cost was measured first and the S10 ratio moved **+0.39 %**, in the safe direction. The split then fell out of a table written at S5 for unrelated reasons — pensioners and rural weight `growth` at nothing, so 37 % of the electorate takes the sovereignty cost and none of the single market. **The probe corrected the model twice again**: authored severities summing to 1.35 against a ceiling of 1.0 made the fourth rule free to break, and the first `EUROPE_SCALE` cleared the noise floor by almost exactly nothing. A hole the tests caught before it shipped: under a whole-council denominator abstaining and opposing are the same act, so the threshold is a share of the seats **cast**. Fourth declared stopgap; `SAVE_VERSION` 10 → **11**, answering the assertion V1.3c left. The balance re-run is **not** bit-identical and said so in advance — but GDP, growth, trend and unemployment are bit-identical in all thirty runs, and exactly one run changed outcome, on a two-seat censure margin |

| V1.3e | Sim | AI foreign policy: the interest model — why a nation the player does not govern answers one way rather than another, and the session that discharges **all four** declared stopgaps a–d shipped rather than the three its own ROADMAP row named. `src/sim/foreign_policy.gd` is a **pure read**: no `tick_month()`, no field on `NationState`, nothing new on `GameState`, so `SAVE_VERSION` does not move — which is what *no grievance ledger* buys, because the relations number **is** the memory. The session's central call is that **interest is material and ideology is one weak term**: `tools/bloc_probe.gd` prints the eight non-player members clustered in ideology space, so a function resting on `coalition_position` is [[trade-model|the `GRAVITY_EXPONENT = 1.0` finding]] in a new place — nine vectors that are arithmetically one vector. The spine is instead the directed trade weight, and the escalation trigger (cross-nation L1 below the 0.05 no-op line) **did not fire** at a minimum of 0.085. **The row split, exactly as the decomposition predicted**, but on *machine* count rather than the surface count the row named — that test fired on b, c and d without any of them splitting, and the real one is U5b's. **The probe corrected the model three times, which is five sessions running.** A globally-anchored amity read Britain's structural detachment as hostility and closed agreements to it entirely, **0 of 9** measured; anchoring sentiment on the pair's own resting value fixed it *and* removed a double-count, since EU co-membership and the border were already inside the trade weight. An ideology term commensurate with a rule's severity had every member in breach of the deficit rule voting **for** it. And `vote_reason()` named a cost term that had lost by a factor of five, which the balance re-run surfaced. A **fourth** correction came from a test: constructive abstention has a window 11 % of the range wide, V1.3d swept only three columns and got its own abstention property from the content by luck, and at the first threshold this session picked that window was **empty** — three vote options, two outcomes. `AGREEMENT_ACCEPT_MIN` and `SUPPORT_SIGMA` are **deleted**, not left unused. The screenshot pass earned its keep twice: every diplomatic action button had fallen below the fold, and a treaty the partner would refuse rendered as a live button that refused silently — V1.3b's own unread `refused_by_partner`, reappearing inside the session fixing it. Re-run **not** bit-identical and could not be: 15 of 30 runs move, every large mover is GBR taking the bloc's `common_external_tariff` — a V1.3d feature V1.3d's own re-run never fired — and exactly **one run of thirty changed outcome**, on a one-seat margin |

| V1.3f | Sim | AI foreign policy: the acting agent — the nine choosing a target and a verb **unprompted**, which is the last thing in the block that made them passive. Everything V1.3e built answers a question somebody else asked; `_tick_agenda()` is the first function in the project that starts a sentence. It lives in `diplomacy.gd` beside `_tick_retaliation()` because `foreign_policy.gd` preloads `trade.gd` preloads `coercion.gd` and can never reach `available()` or `execute()` — the interest model scores what it is handed. **No new content type, no new effect channel and no new verb: the agenda uses the ten actions `data/diplomatic-actions/` already ships**, which is the fifth session running. `SAVE_VERSION` 11 → **12**, earned by exactly one of the two added fields — an absent `diplo_months_to_act` reads as 0, and 0 means *act now*, so nine nations fire in the first month after a reload; an absent `foreign_acts` reads as "nothing has happened yet", which is correct, and the test asserts **both** halves. **The probe corrected the model four times, which is six sessions running**, and the first was the largest: a partner's importance as a standing **addend** made a friendly act free forever, so every nation state-visited its biggest partner on a loop — mean relations **79.6** against resting tiers of 45–68, with a pair pinned on the clamp, which is [[economy-model|`IMPULSE_MAX`]] a fourth time and [[trade-model|`state_visit`'s own exploit]] against an agent that never gets bored. Interest now **multiplies a bounded opportunity**, and `AGENDA_AMITY_TARGET` makes the ratchet structurally impossible rather than tuned away. Then: free concessions get spent freely (`settle_dispute`, the content's climbdown, was **19 of the last 24 acts** until the agenda started reading the action's own authored `bloc_offset` — the content already said how hard each act was and the nine were the only ones not listening); and **`third_party_effects()` was unbounded and backwards** — scaled by an uncapped `care/EVEN_SHARE` reaching 3.0, so one act moved eight *other* pairs harder than its own, and its solidarity half ran on friendly acts, where it says being *nice* to Germany cools everyone else toward Germany. Both survived V1.3e because only a player ever reached that function, rarely and mostly hostilely. **The fourth correction was that the sweep measured the wrong state**: the static new-game table said `AGENDA_ACT_MIN` 0.05 and the dynamic one said 0.02, because by month 24 Britain **is** everyone's top pick and the whole desire landscape has fallen under the bar — the world goes silent and Britain's turn never comes. GBR-aimed acts went **0 → 35** over fourteen years against FRA's 52. The re-run **could not be a diff and was budgeted as a re-baseline**, and came back far quieter than planned: **6 of 30 runs differ, every one GBR, every change last-digit, and zero outcome changes** — FRA and DEU bit-identical across all twenty, because relations move the trade *mix* and the mix reaches an economy only through partner deviations no regime produces. `message_stack.gd` takes its first content since U5a built it, without spending V1.8's argument: an act by a simulated nation is state `src/sim/` just wrote, not invented content. And the screenshot pass earned its keep again — the frame showed `act_reason()` computed, stored and **displayed nowhere**, which is [[trade-model|`refused_by_partner`]] a third time, caught before it shipped rather than two sessions later |
| V1.3g | Sim | Defence as domestic politics, and the **last session of the V1.3 block**. Capability as a stock derived from sustained defence spending, defensive pacts, deployments, and the alliance obligation that opens itself. **Two registers and no new SHAPE of live state** — a pact is symmetric pair state on the key builder relations and agreements already use, a deployment is directed pair state on the one measures use, and "the set of your allies" is a derived read. The genuinely multilateral case already exists as the bloc. `SAVE_VERSION` 12 -> **13**, earned by exactly one of three additions, and the third **splits**: an absent `military_capability` reads 0.0 against a France that has spent 2 % of GDP on defence for decades and every reader inverts; an absent `pacts` reads correctly as "nothing signed"; and an absent `deployments` is correct for the OBLIGED half, which the next tick re-derives from pacts x measures, and silently wrong for the CHOSEN half, which is derivable from nothing. The test asserts all four, and the split is the assertion worth having because it **pins** the property that obligations are derived. **The obligation is a LEVEL READ and that was the design pass's correction**: nothing in the project ever lifts a retaliation, so an edge-triggered obligation is a permanent monotone charge and the bill clamp stops being a guard rail — [[economy-model|`IMPULSE_MAX`]] in a fifth place, avoided rather than discovered. **The probe corrected the model three times**, seven sessions running: the nine never coerce each other so the obligation is unreachable without the council; the headline cannot move on a `defence` price because five blocs of six weight it at zero; and the first opinion table measured half the price. **What the obligation actually fires on was authored by nobody** — a pact held OUTSIDE the bloc, because the council's `common_external_tariff` is the only thing that reaches an ally unprompted. **The re-run is bit-identical across every shared regime**, and table (h) is why: `state_visit` wins 90 pairs of 90 on being the only verb priced at zero, so four new verbs changed no AI choice. That same finding is the session's honest limitation — **the four verbs are player content**, and a security term in `_desire_parts()` is a session rather than a constant |
| U6a | UI | The president's diary — the calendar, split off from U6 on **machine count** the way V1.3e split, and shipped on a headline the row did not name. The row said "a scheduling skin over the verbs that already exist"; counting found ~40 surfaces and **four machines**, above V1.3d's ~39 and the largest ever held. What ships is the half with no unmade content decision, U5b → U5c's own cut. **The headline is legibility rather than scarcity, and that is a measurement rather than a preference**: every observable in this project is piecewise-constant across a month — nothing in `src/sim/` has ever read a day, though `clock.gd` has emitted `day_advanced` since the MVP — so 14 March and 22 March differ only in the label, and booking as a *replacement* for acting is a deferral that buys nothing, which is V1.3c's and V1.3d's strictly-dominated shape a third time. So booking is **optional**, every verb keeps its act-now button, and `tests/test_calendar.gd` asserts a booking moves nothing at the moment it is made. What the diary shows instead is dated state the game has carried for sessions with no surface anywhere: election day, the European election, the presidential term, the council's next proposal and its pending vote, the dissolution lockout, and every diplomatic and legislative cooldown expiry. **The one tuned constant this session was going to add was measured and DELETED.** A monthly budget of the player's days was swept against a band fixed before the sweep ran, and the band is not mis-tuned but **structurally unreachable**: the median month offers 27 legal acts asking 124 days, so every budget from 4 to 24 bound in **100 %** of months over fourteen years. A ceiling that always binds is a cap, not an allocation. Deleted rather than left unused — V1.3e's treatment of `AGREEMENT_ACCEPT_MIN` — so `calendar_constants.gd` carries **no tuned constant at all**, a first in a long run, and the honest reason is carried forward: `available()` returns what is LEGAL and nothing yet models what the player WANTS, so a ceiling priced against legality always binds. **The probe corrected itself twice and the panel corrected it a third time, which is eight sessions running.** The fixed-date density table read a player who never acts, so cooldowns — much the densest source — reported exactly **0**, and it counted after the tick, so an election had already pushed its own date forward and 168 months showed **one**: V1.3f's measuring-the-wrong-state error, in this session's own probe, 19.6 % → **31.0 %**. Then the panel test found the sharp version the average hides: a **new game's next twelve months are completely empty**, because France's nearest dated event is sixteen months out and cooldowns do not exist until the player has acted — so the page every player sees first is the page with nothing on it. The pre-committed response to a thin diary was content or shape rather than a constant, and widening the horizon would have been the constant (it also bounds booking), so the answer is three shape decisions: a **twelve-month strip** rather than a month's page, a `later` footer, and a `Next:` line outside the scroll. `SAVE_VERSION` stays **13** and the assertion is worth more than a bump: `appointments` absent reads as "nothing booked" (`measures`' case), `day` is not serialised at all because `save_manager.gd` already carries `clock.day`, and the field that WOULD have earned one — a spent-days counter, which reads 0 when absent and hands a save-scumming player their month back — was never written because the probe cut the currency first. `src/sim/calendar.gd` **preloads no other system**, asserted by reading the file: `due()` returns entries as data and `main.gd` fires the verb, which is `cabinet-model`'s orchestrator precedent one scale wider, and cost **zero** new preloads because `main.gd` already had all three. The re-run is **bit-identical across all thirteen existing regimes**, and a **fourteenth** was needed for a second reason V1.3g's did not have: `balance_probe.gd` and `test_balance.gd` are month loops with **no clock**, so a day-resolution dispatch was structurally invisible to the whole harness and its bit-identity would have meant nothing. Booking does **not** go on `nation_panel.gd` — every verb row there is an HBox holding an autowrapping label beside one button, so a second button narrows the label and grows the row, at a panel already at 860px against a ~886 ceiling that has paid for that fold twice. Model, every constant and the measured tables: [docs/calendar-model.md](docs/calendar-model.md) |
| U6c | UI | The project marker layer - the last clause of `docs/tiers/v1.md` section 6, and the piece V1.6f split off. **Instance thirty-nine is in the row's own wording**: every statement of this machine called it *"per-project geography as content"*, and `data/project-actions/` is a global flat list, so a lon/lat inside `effects.project` puts every nation's rail spine at one point on the planet - fixing that means making the directory per-nation and reopening a call V1.6f made freely. **Geography is per-NATION**: `data/nations/*.json` grew an optional `project_sites` block, U6b's *a law names an office and the nation names the person* unchanged, so the action list stays global and `src/core/project_action.gd` was **not edited at all** - the `project_name` exception it offered as precedent was not needed, because no coordinate ever reaches `effects.project`. Coverage is FRA/DEU/GBR, `data/companies/`'s and `data/outlets/`'s rule, and an absent block is legal. **A marker is an always-on overlay, not a fifth `LAYERS` entry**, and what settles that is already in `map_view.gd`'s header - *no map layer adds, removes or reorders a draw layer* - plus the fact that as a layer it would be structurally dead content, reading exactly 0.0 for nine of the ten forever. **The hit test is a radius test in screen space** and reaches neither `_polygons` nor `_nation_at_lonlat`, so U5b's *unclickable structurally* survives; `tests/test_map_markers.gd` extracts that function's body from the source and fails on either name, and pins `LAYERS` at four. A click opens Public Works and does not fall through to the nation underneath. `SAVE_VERSION` stays **23** - a site is content that round-trips through `data/nations/` and a marker is derived at draw time - and no balance re-run was needed, because nothing in `src/sim/` was touched and a marker is not a verb. **The sixteenth screenshot pass found one bug and it was the readout's**: the hover text read *"12 of 96 months"*, which a player reads as twelve months DONE when it is twelve to go, and it is now worded exactly as `projects_panel.gd` words it |
| V1.7a | Sim | The campaign phase, and the **first session of the V1.7 block**. A per-bloc mobilisation register in LOG-ODDS, read by `Elections.vote_share()` in place of the authored turnout constant, plus the sixth computed spending line. **The row asked for three things and two were already answered, one of them by a DELETION.** Of *time, money, messaging*, only money survived: U6a swept a monthly budget of the player's days and **deleted** it on a reason that is general rather than about calendars (`available()` returns what is LEGAL and nothing models what the player WANTS, so a ceiling priced against legality always binds) - **instance forty** - and messaging is V1.5d's, exactly as this bullet predicted in advance, so `tests/test_campaign.gd` reads `campaign.gd` and fails if it so much as names `framing_gain` or `press_freedom`. **What money buys had to be found, and two of three candidates were refused.** Approval is the term's record and `vote_share()`'s own `pull` already reads it; framing is V1.5d's. What is left is **turnout** - `election_constants.BLOC_TURNOUT` is read in exactly two places, both inside `vote_share()`, and nothing had ever written it - so the register is a FIRST writer with no double count. A campaign does not change what people think of your record; it changes who bothers to vote on it. **Log-odds, so turnout is bounded strictly inside (0, 1) BY CONSTRUCTION** and this session ships no turnout clamp at all - and the property nobody authored falls out of it: the same effort moves students (+14.9 points at the cap) further than pensioners (+7.2), because a low-turnout bloc has more room. **The window is a LEVEL READ and the clear is its other half**, so the register empties itself the month after the vote with no hook in `elections.gd` and no flag anywhere - V1.3g's rule, applied to a thing that opens as well as closes. **An effort is a standing rate with a deadline**: it accrues and bills every month it runs, which is what kills the strictly-dominated shape a one-off purchase creates (same reach, less time paying) for the seventh time. **The probe corrected the session five times, eighteen running.** The band was INVENTED (*0.50 points of vote share*, a number that sounded like a margin) and is now anchored on what a point of approval is worth; `_headroom()` was wrong by a factor of a hundred; the emulation claim was false above the shipped window; the **content's targeting** was the gap rather than any constant, at 17 % of what perfect targeting reaches; and `MOBILISATION_MAX` was binding in a way worse than usual - once the accumulator saturates a longer run-up is strictly WORSE, so the clamp was **inverting** the timing decision rather than merely setting a number. `CAMPAIGN_WINDOW_MONTHS` = 8, selected by **maximin slack** over the feasible region, which is this page's own tiebreaker rules taken one step past V1.5d's *the interior governs*. **And maximising your own vote share is not the same as winning**: the pair that best raises France's incumbent's share NARROWS their lead, and the pair that best widens the lead LOWERS their share, because turnout is a rising tide inside a bloc rather than a transfer between parties. Recorded rather than fixed. The eighteenth `ISSUE_KEYS` question is answered **NO on test 1**, as V1.6e's and V1.6f's were and for the same reason - a session shipping a content object has somewhere to put the price. `SAVE_VERSION` stays **23** on three fields, and the test pins the absence so V1.7b has to say why it moves. **The re-run is bit-identical across all 34 existing regimes, predicted in advance** - the diff is additions only - with two new regimes of the expensive kind. **The seventeenth screenshot pass found two bugs**: a content name that collided with a window this game already has (*"Clear the Diary"* on a campaign button), and the flag pinning the scroll past the ledger it exists to check - V1.6e's correction has a DIRECTION as well as a subject. Model, every constant and the measured tables: [docs/campaign-model.md](docs/campaign-model.md) |
| V1.7b | Sim | Campaign promises and the trust price, the **second session of the V1.7 block** - and the row was recorded in advance as the one most likely to SPLIT, on the trust quantity. **It did not, and V1.5d's own criterion is what settled it - applied in the other direction.** [[docs/media-model.md]] sent legitimacy to the grievance because legitimacy is willingness to accept your rule OUTSIDE the ballot box; trust in a promise is squarely AT it, so the price lands on `ns.bloc_offset` - the permanent per-bloc accumulator V1.7a had already made a campaign's own lasting mark. A separate trust stock would have been section 5's *second approval number with a different label*. The landing site was measured **before a line of content existed**, which is what makes it a measurement rather than a preference: one machine, no split, and no new quantity anywhere. **The row's *read at the END of the term* is INSTANCE FORTY-TWO**, and it fails on two things that can be counted rather than argued: a single read there is strictly dominated by last-minute compliance (run unemployment at nine for four years, squeeze it to 6.9 for the final month, pay nothing - the shape this project has killed eight times), and it is structurally INVISIBLE at the vote it is about, because `main.gd` runs `Opinion.tick_month()` long before `Elections.tick_month()` and `INERTIA_RATE` delivers a quarter of the price in the month it is charged. So a promise is judged on a LEVEL every month it is live and the price is the integral - V1.7a's *a standing rate with a deadline* applied to the PRICE rather than to the spend. Graded-by-the-miss was designed and cut, because a per-field normaliser is a table with no measurement behind it; breach is BINARY per month and the count IS the memory. **`PRECONDITION_FIELDS` is the right shape and the wrong list**: three of its seven entries cannot be promised, and the interesting half is what a pledge list has that it does not - the taxes and spending lines the PLAYER SETS. **An outcome pledge is a bet on the world and a rate pledge is a self-imposed constraint**, separated by measurement rather than by theme: table (c0) reads each field's LUCK (the widest span within one budget) against its CHOICE (the span across three at the end), and `growth_annual_pct` comes back 8.215 against 0.641 where every tax and spending row measures luck EXACTLY 0.000. `inflation_pct` was on the list and the probe **DELETED** it - 0.114 and 0.045, both under the resolution of the model that produces them, so an authored threshold is a constant verdict. **`pledges_constants.gd` ships NO TUNED CONSTANT AT ALL**, `projects_constants.gd`'s position reached a second time, and the channel carries **no `op`** where all five before it do: a pledge charges only while it stands broken, so it stops the month the player comes back into compliance and the off switch is called GOVERNING. **The probe corrected the session five times, nineteen running.** The reachability table measured the wrong state (no `Elections.tick_month()`, so 168 months showed ONE run-up and ZERO judgements against a real three and two) - V1.3f's error a fourth time, in a file whose header warns about it; the growth pledge failed its readability band and the CONTENT moved; **the dominance test itself was the wrong test**, reporting five dominated promises off the authored (reward, breach) pair when the third quantity - how often a promise is actually BROKEN - is nowhere in the content and is a property of the budget the player intends to run, which is V1.7a's *share is not winning* in a new place; **the ordering statistic was LUCK and had to be EXPOSURE**, luck as a share of luck plus choice, because the deficit reads 1.284 of luck against unemployment's 1.182 and 16.445 of choice against 0.656; and the balance regime pair was **confounded** and needed a third regime that runs the identical budget switch and promises nothing. **Zero promises dominated in every column and each column has a different best promise** - the ladder is not orderable without knowing how the player intends to govern. The nineteenth `ISSUE_KEYS` question is answered **NO on test 1**, a fourth consecutive session for the same reason. `SAVE_VERSION` stays **23**, V1.3c's device answered and re-armed at V1.7c: absent, `pledges` reads as *nothing promised*, and it is serialised anyway because the REWARD HAS ALREADY BEEN PAID and a save that dropped it would delete the liability and keep the upside. **The re-run is bit-identical across all 36 existing regimes, predicted in advance** - the diff is additions only - with three new regimes, and the legibility evidence is exact: same budget, same promise, the incumbent takes 26.2 % in 2027 against a control's 25.9 and 10.6 % in 2032 against 11.1, so the promise is worth **+0.3 at the election it is made for and -0.5 at the election it is judged at**. **The eighteenth screenshot pass found two bugs, both the readout's**: a breach cost printed in no unit two lines under a turnout figure of the same shape, and a live promise that never said what it had cost - the one figure the section exists to be a ledger of. Model, every constant and the measured tables: [docs/pledge-model.md](docs/pledge-model.md) |

MVP done-when checklist: [docs/tiers/mvp.md](docs/tiers/mvp.md). All boxes ticked.

---

## Next

**V2 IS THE NEXT TIER, AND FOR THE FIRST TIME SINCE THE MVP THERE WAS NO ROW TO READ.**
Every session since S1 opened by reading a row, challenging it and counting what it named
-- which is how forty-nine stale-row instances were found. [[docs/tiers/v1.md]]'s rows are
closed, and `docs/tiers/someday.md` says of itself that it is *"a parking lot, not a
backlog"*. So deciding what follows V1 was the first half of the work rather than a
preamble to it, and [[docs/tiers/v2.md]] is the row set that makes the second half
possible.

**The organising goal is that THE WORLD BECOMES VISIBLE AND LOCATED.** V1 built machines,
and every one of them is legible only as a number on a panel: a firm is a share, a strike
is a percentage, a project is a countdown, a trade partner is a weight. **The country the
player governs has no places in it.** V2 gives the same simulation geography, faces, a
calendar that costs something, and motion. It opens no new front -- war stays in
[[docs/tiers/someday.md]] where V1.3g deliberately left it.

**Ten blocks, ordered so the visible payoff lands before the heavy rewrite.**

| # | Block | Track | Depends on |
|---|---|---|---|
| **V2.1** | the shell, re-cut | U | — |
| **V2.2** | the geographic register | S + data | V2.1 |
| **V2.3** | the face of power | U | V2.1 |
| **V2.4** | the president's day | S + U | V2.2 |
| **V2.5** | the economy from below | S | V2.2 |
| **V2.6** | people move | S | V2.5 |
| **V2.7** | network and resources | S | V2.5 |
| **V2.8** | energy, placed | S + U | V2.7 |
| **V2.9** | environment and climate | S | V2.8 |
| **V2.10** | the world in motion | U | V2.7 |

Estimated at **30-40 sessions**, comparable to V1. **Blocks 5 and after are rows to
challenge rather than commitments**, and that is written into the tier doc rather than left
implicit: a row written this far ahead is a hypothesis, and each block gets a decomposition
session that re-counts machines and surfaces before it splits.

**Four calls were made before any code, and two of them are the tier's whole shape.**

**A city is to population what a firm is to sector output.** V1.4a authored a firm as a
`share` of its sector with an unnamed residual, so the partition is exact by construction
and there is no reconciliation to get wrong. A city holds a share of its region, a region a
share of the nation, and rural-and-unnamed is the residual. That is why V2.2 can ship the
register before V2.5 rewrites the economy.

**Bottom-up and bit-identical are not opposites, and this is the claim V2.5 must measure
rather than assert.** If national = Σ regions *exactly* and every region is initialised on
the national trajectory, the balance regimes stay bit-identical until the first regional
divergence and every constant measured since the MVP keeps its calibration. What changes is
that the **spine becomes regional**, so every later lever may be regional. **The cheaper
version was offered and declined, and the record says so**: a ninth `economy.gd` addend
holding a city partition -- V1.4a's idiom, reading exactly 0.0 until something moves --
delivers the same thing from the player's seat, and the difference is invisible in play.

**The day becomes real for the president and for nothing else**, which discharges a debt
U6a wrote down by name. `clock.gd` has emitted `day_advanced` since the MVP and nothing in
`src/sim/` has ever listened, so U6a deleted its day budget on a reason that is general
rather than about calendars: *"`available()` returns what is **legal** and nothing models
what the player **wants**, so any ceiling priced against legality binds in 100 % of
months. That gap is a session, not a constant."* A ceiling priced against **travel and
ceremony** is not priced against legality. **V2.4 is that session.**

**Placing a power station is the first verb where the player writes a coordinate.** Every
lon/lat in the game today is authored -- U6c's `project_sites` -- and U6c's rule that *a
lon/lat nothing reads carries no information* is satisfied in its strongest possible form
when the player's own click is what reads it. V2.8 also **lifts** *"Energy mix policy with
emissions and dependency consequences"* out of `someday.md`, and that is recorded as a lift
rather than left to look as though it was always scheduled.

**One V1.8 call is reversed, and only for a flagged class.** [[docs/events-model.md]]
argues the Dispatches window is non-modal because *a crisis you can ignore and pay for is
the whole of "time pressure"; a modal removes the choice by removing the option of not
making it*. That argument survives for every event without the new authored `interrupt`
flag, which is most of them. What the flag buys is the case the argument does not cover:
an event nobody could reasonably choose to ignore.

**The stale-row count came back at three rather than four, and V2's own spine is what freed
the fourth.** V1.8's last sweep of the `| V1 |` column left **Embassies** and **Foreign
aid** (instance forty-nine, cheap -- a fifteenth and sixteenth entry in
`data/diplomatic-actions/` on the existing `effects.relations` channel) and **honeymoon and
fatigue**, deferred *in code* at `opinion_constants.gd`'s `APPROVAL_NEUTRAL` since S5 and
the oldest open deferral on the project. **Birth rate and life expectancy is no longer an
orphan**: [[docs/demography-model.md]] §14 had already recorded that the dataset objection
was wrong and that what actually blocked it was V1.5b's finding that `population` enters no
equation in `economy.gd` -- and **V2.5 is precisely the change that makes a head count
load-bearing**. It is a bullet of V2.6 now, arriving with the mechanism that reads it.

**The first row this tier wrote was wrong within the hour, and it was wrong in the
direction that matters.** The decomposition booked Eurostat regional data as covering all
ten with *"UK coverage ends around 2020"*, and the standing remedy — V1.5c's nearest-year
fallback, scoped to the affected series — was written into the plan before anything was
fetched. Probed, `nama_10r_2gdp` carries **zero** geo codes beginning `UK` in a dimension
holding 471 of them: Eurostat dropped UK regions after withdrawal, so the fallback had
nothing to fall back to. **GISCO's geometry carries all ten** (41 UK NUTS 2 features), so
the map and the figures disagree about the roster and only the figures are short. Britain
therefore needs a second source or an authored register, and V2.2 owns that call rather
than inheriting an answer. Two import gotchas came out of the same probe and are written
into [[docs/data-sources.md]] beside Natural Earth's: `XXZZ` **Extra-Regio NUTS 2** carries
GDP and has no geometry, and `FRY1`–`FRY5` are the overseas regions the existing bounding-box
filter already drops. Both belong in the unnamed residual, which is V1.4a's slot for the
firms a sector does not name.

**V2.2a took that call, and this paragraph is half wrong in the direction that
mattered.** The GDP finding holds and is worse than recorded -- `nama_10r_2gdp` carries
zero `UK` codes at **every** year, 2018 included, because the codes were removed from
the dimension rather than left empty. But `demo_r_pjangrp3` carries **41 UK NUTS 2
codes and 12 NUTS 1 codes with values at 2019**, summing to the UK national figure
exactly: **regional population is measured for all ten and only regional GDP is short.**
The register is a partition of population, so V2.2a needed no second source at all, and
the whole gap passes to V2.5 -- which is where the quantity becomes load-bearing. A
third import gotcha came out of the same session and none of the three probes found it:
**the Eurostat response carries two NUTS vintages at once**, `NL35`/`NL36` duplicating
`NL31`/`NL33` to the person, so an unfiltered Netherlands is 5.1 M people too large.
Left in [[docs/data-sources.md]] beside the other two.

### V2.1 — the shell, re-cut, and why it goes first

**U5a's own precedent decides the order.** U5a retuned the theme and moved the whole shell
*before* U5b, U5c, U6a, U6b and U6c built into it. V2 adds at least five new surfaces --
city, region, day agenda, energy, climate -- and designing them in the old grammar and
refactoring after is drawing twice. Unlike U5a, this pass **knows the full list of surfaces
in advance**, which is what makes a shell session decidable rather than speculative.

**Three failure classes recur across the screenshot record and all three are systemic
rather than per-panel**, which is the argument for a system instead of another round of
fixes:

- **The forgotten refresh.** `src/ui/main.gd`'s `_mark_all_dirty()` is a hand-written list
  under a comment predicting its own failure, and it has been wrong **twice** --
  `_people_panel` from U6b until V1.4a found it, then `_projects_panel` and
  `_campaign_panel` until V1.8. `WindowManager.register()` already knows all fifteen.
  Deriving the sweep from the registry makes the failure **structurally impossible rather
  than remembered**, which is this project's standing preference.
- **The fold.** `nation_panel.gd` paid for one at V1.3e and again at V1.3g, and **V1.3g
  proved height alone does not fix it** -- it took 80px plus two tightenings. No contract
  anywhere says a panel's primary action must be reachable, and the headless suite
  structurally cannot see a fold.
- **Row-building by hand.** Three shipped bugs trace to twenty-five panels each inventing
  their own rows: a format copied from a neighbouring row (V1.6b), a `.get(key, 0.0)`
  default printing a confident **0.00** against a live 31.80 (V1.6d), and two value columns
  each sizing to their widest row until one ran off the window (V1.6f).

| | Session | Ships |
|---|---|---|
| ~~**a**~~ | ~~the panel system~~ **Built** | six primitives (the row named five), the derived dirty registry, the fold contract, three panels migrated. See below |
| ~~**b**~~ | ~~the twenty-five panels~~ **Built** | the other sixteen migrated, six more panels declaring a verb, the fold contract turned from a report into a test. See below |
| ~~**c**~~ | ~~navigation and the resting screen~~ **Built** | the keyboard map off the registry, the open window marked whatever opened it, and the resting screen answered by a measurement -- one mark on the bar, no plate. See below |

**The one new visual rule is the fold line, and it is the existing signature reused rather
than a second one.** U5a's plate carries a 1px brass hairline on its **top** edge only, and
`tests/test_ui_theme.gd` fails if the other three are drawn. A panel whose content exceeds
its height draws that same hairline along its **bottom** edge -- structure encoding
something true rather than decorating, and pointed straight at the failure class that has
bitten five screenshot passes.

**V1.8 shipped events.** Only the re-parked **V1.1e** (upper
house and judiciary) was left in the tier after it, and V1.1e has since been built --
see *V1.1e* below. One session, not decomposed -- the first block since
V1.1 not to split -- and the reason is machine count rather than size: fire → pending →
choose → apply is **one pipeline**, which is V1.3d's rule, so V1.3e's split trigger
answers no. ~36 surfaces against V1.7c's ~30.

**Section 8's own two bullets are tiered NOWHERE, which is instance forty-four and the
largest gap between a section and its backing this count has found.** Every event-shaped
mechanic in the four `mechanics-*.md` tables is **Someday**; the only V1-tiered one the
section owns is the **Scandals** row §5 handed it at V1.5d. So there was no crisis left
to author that is not already a machine here, and the design followed from the count:
**an event does not add a consequence the game did not have, it adds an occasion on which
the player must pick one, a menu, and a deadline.** Three more instances came with it --
the "semi-random" collision with the no-randomness rule (**forty-five**, V1.6a's in the
same words), the union-of-channels claim being right about the timing and wrong about the
shape (**forty-six**), and `effects.institutional` on a choice being "Emergency powers",
tiered Someday (**forty-seven**).

**Instance forty-eight is the sharpest on this page's record, and forty-three prior
instances missed it**: *"Decree / executive order -- bypass the assembly on a narrow set
of matters, at a legitimacy cost"* is tiered **V1** and appears in **no row of any tier
doc**. An event choice that moves a budget line with no assembly division IS that
mechanic. **Forty-nine is not V1.8's** -- the same sweep found **Embassies** and **Foreign
aid** tiered V1, in no row and in none of `data/diplomatic-actions/`'s fourteen verbs,
recorded rather than built. Model: [docs/events-model.md](docs/events-model.md).

**The session's finding is that a per-decision price is not a lifetime charge**, which is
V1.6f's *a bill is not a cost* one block on. `bloc_offset` is a permanent clamped
accumulator whose every previous writer charges once for a chosen act or charges while a
condition holds; an event recurs and its default charges with no decision, so the first
ladder passed the per-decision band and **saturated the clamp over a career** -- at which
point every regime converges on the same floor and `tests/test_balance.gd` said so:
*managing the budget did not beat ignoring it on approval: 38.4 managed vs 38.6 ignored*.
The plan's escalation trigger 4 fired and was honoured by the response it named.

**V1.7 is decomposed into three sessions, V1.7a-c, and the BLOCK IS COMPLETE.** The row
was three bullets in [[docs/tiers/v1.md]] section 7 against FOUR items in the block cell
below, and neither count was right. The argument and the per-session table are under
*V1.7 - the decomposition* immediately below. Order: (a) the campaign phase, (b) campaign
promises and the trust price, (c) electoral system choice **and referendums**, which are
one shape and not two.

**(c) confirmed that they are one shape and refuted the decomposition about what the
shape IS, twice.** A referendum is not a bypass of the assembly but a **second
ratification stage at a lower chamber bar** - Art. 89 (FRA), Art. 138 (ITA), Art. 114
(LUX) and Art. 195 (CHE) all put an ordinary majority first, and every one of those
citations was already sitting in the nation files' own `government.amendment._note`,
authored at V1.2c for a mechanic that did not exist. And an electoral system is **not** a
seventh `effects.institutional` key, because that channel is legal only on a
`constitutional` law and electoral law is ordinary legislation in essentially all ten -
**instance forty-three**. See *V1.7c* below and [docs/referendum-model.md](docs/referendum-model.md).

**(b) was recorded in advance as the row most likely to split, and it did NOT** - the
third use of that device, after V1.3e (which split) and V1.5d (which did not). The
recorded trigger was the trust quantity, and what discharged it is that **V1.5d's own
criterion decides the landing site when you apply it in the other direction**: legitimacy
went to the grievance because it is willingness to accept your rule *outside* the ballot
box, and trust in a promise is squarely *at* it, so the price belongs on the register that
reaches the ballot box. `ns.bloc_offset` was measured for the job **before a line of
content existed**, which is the whole reason the trigger could be answered rather than
guessed at.

**V1.7a's finding is that a row can be answered by a DELETION, and this one was.** Of the
campaign bullet's three nouns - time, money, messaging - only *money* survived contact
with what is built. **Time does not exist**, because U6a swept a monthly budget of the
player's days and deleted it; the reason recorded there is general rather than about
calendars, and it applies here word for word. **Messaging is V1.5d's**, and that bullet
said so itself in advance - *"if V1.5d builds the peacetime half, this bullet reads it
rather than rebuilding it"* - which is the first time on this page a prediction written
into a row has come true and been collected. What money buys instead had to be found, and
it is **turnout**: `election_constants.BLOC_TURNOUT` is read in exactly two places, both
inside `Elections.vote_share()`, and nothing in this project had ever written it.
Model: [docs/campaign-model.md](docs/campaign-model.md).

**V1.6 was decomposed into five sessions, BECAME SIX, and ALL SIX ARE BUILT. The block
is COMPLETE - and so is section 6's LAST CLAUSE, built at U6c.** The argument, the four calls it made and the two rows it caught are under
*V1.6 - the decomposition* below. Order: (a) the business cycle, (b) inflation, (c) bond
yields and the credit rating, (d) five taxes and brackets, (e) sectoral investment,
(f) infrastructure projects - and **(e) was recorded in advance as the row most likely to
split, and split**, the device this page used for V1.3e (which split) and V1.5d (which did
not).

**V1.6f SPLIT AGAIN, on the rule rather than on a count, and that is the block's closing
finding.** Recounted, what was left of the row was two S-track machines and **one U-track
machine**: per-project geography as content, a marker draw pass on `map_view.gd`,
hit-testing and hover. V1.6e had already named that as the reason IT split; the same rule
applied twice in a row, which is the first time on this page. **V1.6f shipped the sim half
and the map went to U6c** - U5b -> U5c and V1.6e -> V1.6f a third time. The visible
consequence is in the content rather than in the code: **no project names a place**,
because a lon/lat nothing reads is a field carrying no information, so the five are generic
and the session that draws them owns naming them.

**U6c BUILT IT AND CORRECTED THE ROW'S OWN WORDING - instance thirty-nine.** *Per-project*
geography is the one thing it could not be: the action list is global, so a coordinate in
`effects.project` gives all ten nations one rail spine at one point, and the only repair is
to make `data/project-actions/` per-nation - reopening the call V1.6f made freely and that
nothing else asked to reopen. The site belongs to the **nation**, on an optional
`project_sites` block in `data/nations/*.json`, which is U6b's rule verbatim and leaves the
action list and `project_action.gd` untouched. Section 6 is now closed to its last clause.

**V1.6f's own finding is the one worth carrying forward, and it is about the difference
between a BILL and a COST.** Its cost clause was written on the arithmetic stack - 0.5200
against a headroom of 0.5639, comfortably inside - and the measured peak deficit came back
at **0.7615**. A build that runs for eight years **borrows** for eight years, so what
reaches `public_finances` is the bill *plus* V1.6c's interest on everything borrowed so
far. Every previous computed budget line in this game is a standing rate against a roughly
standing debt, so bill and deficit moved together and the distinction never mattered; **a
line that runs for a fixed term and then STOPS is the first one where it does**. The
general rule: a clause about what a lever costs must be measured on the quantity the
opinion model actually reads, not on the quantity the lever writes.

**V1.6e's own finding is the one worth carrying forward, and it is about where a lever
may land rather than about sectors.** The row asked for a lever "on `sector_output`
itself", and that quantity has an exact identity around it:
`Economy._apply_growth_to_sectors()` reconciles the three sectors against the month's GDP
target to the last bit, so an absolute injection is **cancelled by the cyclical residual
inside the same tick** -- 27.9 bn put into French industry leaves GDP +0.024 bn and moves
only the composition. The honest landing site is the per-sector trend RATE, the slot
`Trade.sector_shift()` occupies, and what separates the two is the sharpest sentence the
session produced: **a trade shift must sum to zero and an investment shift must not**. The
general rule: before banding a term, check that the quantity it writes has room for
another writer at all.

**Its second finding is that the strictly-dominated shape can appear in a PRICE.** This
project has caught it six times in effects -- tariff severities, bloc rules, a share
floor, a dividend yield, a Gini clamp. Here the effect was fine and the **bill** was flat:
backing French services moved growth 0.4865 points and backing French agriculture 0.0077,
for identical money. The fix scales the bill with the sector's own share of GDP, adds no
constant, and **deleted one** -- the three shares sum to exactly 1.0, so the whole bill is
bounded above by the cost constant itself and a clamp on top of it was a guard rail
guarding arithmetic.

**Its own finding is the one worth carrying forward, and it is about measurement rather
than about cycles.** V1.6a's two pre-committed bands have **no overlap at any
candidate**: at France's own measured growth volatility a recession moves approval by
about 2.8 points, under the +-3.0 poll-noise floor, and cannot be lifted over it without
making France more volatile than France is. Neither of V1.5c's two failure modes -
*the band failed* and *the constant cannot clear its floor* - and the remedy is neither
widen-and-re-select nor delete. The constant is **fitted** to the measured series
instead, and the rule that falls out generalises: **a band edge MOVES when the grid is
widened or refined; a fit CONVERGES.** Where something outside the game measures the
same quantity the model produces, a fit should be preferred to a band rather than used
as a fallback after one fails.

**Its second finding is that the decomposition is not exempt from the probe.** V1.6's
own call 3 booked half of V1.4c's inherited obligation to (a) as free, on the argument
that a dividend built on `sector_output` becomes procyclical the moment a cycle exists.
It measured 1.07x against a floor of 1.5x, because
`Companies.dividend_revenue_pct_gdp()` divides by GDP and the cycle moves numerator and
denominator together. **A quantity expressed as a share of GDP is not procyclical by
construction**, every fiscal line in this game is such a share, and the obligation
passes to (c) whole.

**V1.5 is decomposed into four sessions, V1.5a-d, and all four are built.**

**V1.5c is built, and it is the session where the inverted rule and the rule it
replaced finally agree.** The statistic is the grievance and **the verb is the
union's** — a rule about live state needing something to act on it never said the
actor had to be the player. Its own finding is that **the price it was designed with
does not reach a voter**: an output-only channel costs 4.94 % of GDP over fourteen
years and moves the workers approval row 0.42 points, because this opinion model
prices rates and a permanent level loss is invisible to it. Full write-up below;
model in [docs/unrest-model.md](docs/unrest-model.md).

**The decomposition's own finding is that this block breaks the rule every previous
block was built on.** V1.3 and V1.4 each shipped a player command per session, and
V1.3a's rule was that state ships *with* a verb or it decays to nothing. §5 has at
most two verbs across nine bullets, and both are levers on machines that must exist
first. So the rule inverts: **every session ships a statistic and the price it
charges.** The failure mode is the same one V1.3a was guarding — a number nothing
reads — and only the remedy changes.

**Its second finding is that §5's bullet 9 asks for a machine this project has
already built three times under three names.** `military_capability` is defence's
outcome stock; `potential_shift_pct` is education's *and* infrastructure's, since
S4. Of the five spending lines, **only health and pensions have none** — and
pensions needs a dependent count, so it waits for (b). V1.5a therefore *completes
and names* a pattern rather than inventing one, which is why it reuses
`defence.gd`'s `capability_target()` / `capability_step()` shape outright, including
its call that a starting stock is its **equilibrium and not zero**.

**V1.4 was decomposed into three sessions, V1.4a–c, and the block is COMPLETE.**
The argument, the three calls it made, and the per-session table are under *V1.4 —
the decomposition* below. Order: (a) the firm register and subsidies, (b) sector
regulation, (c) nationalisation and privatisation.

**V1.4a's own finding is the one worth carrying forward, and it is about content
rather than about firms.** The jobs channel's whole spread comes from two authored
headcounts: subsidising a retailer over a bank moves **0.229 points** of
unemployment, subsidising one industrial firm over another moves **0.010**, and
nothing in `src/sim/` says "services". A firm layer is more than a sector lever
exactly to the extent that firms sharing a sector are authored *differently* — so
the differentiator is the field to argue about when V1.4c adds its own, and a firm
with no rival is refused at load time rather than shipped as a lever that moves
nothing.

**V1.4b's finding is that V1.4a's escape from §6 does not transfer, and no
validator could have caught it.** V1.4a refused a sector holding one named firm,
which is a rule about the *target* — and a regulation's target IS the sector, so a
sector-wide burden priced on sector output is §6's lever with a minus sign whatever
the firm count. What separates them had to be found rather than inherited: a
regulation reaches **only the named partition**, and its **jobs price has no
analogue in a sector lever** because jobs-per-share is firm content. That is why
the jobs channel is not optional in (b), and why widening its charter from pure
reallocation to reallocation-plus-level was the right trade rather than a
compromise. The row also called for rules that "cost margin" — a quantity
`src/sim/` does not contain — and the corporate-receipts channel that would have
invented one was **cut before it was written**, because it creates (c)'s dividend
dependency instead of discharging it.

**V1.4c's finding is that the row named a control the model did not have, which is
"cost margin" one session on.** "A permanent loss of control" was the phrase, and a
grep says a subsidy works on any firm whoever owns it while a regulation targets the
sector — so before (c), ownership controlled nothing. The answer is one factor at one
existing site: a state holding absorbs the sector's compliance cost so the payroll
does not, it is **signed** so a public firm in a deregulated sector forgoes the
hiring too, and it adds **no constant at all**, because a total holding cancels a
term (b) had already measured. That is the **fourteenth** stale-row instance.

**Its second finding is that a band can pass three rows and still not choose a
constant.** `DIVIDEND_YIELD` landed inside its pre-committed 0.05–0.40 % of GDP at
0.02, 0.04 *and* 0.06, because that band measures whether the line is **readable**
rather than whether it is right. What chose was the ratio against
`DEBT_REAL_RATE_PCT`: at 0.04 every nationalisation paid for itself twice over and
came back better than a quiet run on the headline **and** the deficit — free on both
axes, the strictly-dominated shape for the fifth time. The correction moved what the
number is measured against, not the band.

**The `ISSUE_KEYS` question a, b and the whole V1.3 block deferred to (c) is answered
NO**, and the deciding number is structural rather than thematic: the S10 ratio
drifts **−1.46 %** where [[docs/bloc-model.md](docs/bloc-model.md)'s V1.3d moved
+0.39 %, because `business` carries `public_finances` at 0.34 and is the bloc that
makes ownership divisive at all. **The mechanic and the cost are the same number.** A
regulation had the same claim to a key and V1.4b took none.

**The decomposition has now caught the row double-booking five times where the
prompt named once.** Bond markets belonged to §6; a subsidy pointed at a firm *is*
§6's sectoral investment unless a firm is smaller than a sector; §6's collision came
back at (b) in a form (a)'s refusal cannot catch; "cost margin" named nothing; and
"a permanent loss of control" named nothing either. That is instances **eleven
through fourteen**, all found by counting rather than by being told.

**V1.3 was decomposed into six sessions, became seven, and is now COMPLETE** — the
argument, and the four calls it made, are under *V1.3 — the decomposition* below.
**V1.3a–g are all shipped.** V1.3e discharged all four declared stopgaps and
**split**, exactly as the decomposition predicted; V1.3f built the acting agent
that split off; V1.3g built defence and took defensive alliances with it, as this
page committed years of sessions ago. **There are no declared stopgaps left
anywhere in the block.**

**V1.3g's own finding is the one worth carrying forward**: the nine never coerce
each other, so the only thing in the project that reaches an ally unprompted is
the council's `common_external_tariff` — a [[bloc-model|V1.3d]] feature. An
alliance obligation therefore fires on a pact held **outside** the bloc, and never
on one held inside it. Nothing authored that, and it is why the row's "reads a, d"
was right in a way the row could not have known: d is what makes g fire.

**U6 split, and BOTH halves are built.** The row was ~40 surfaces and four
machines — the largest ever counted on this project — so it went the way V1.3e
went, on machine count. [[calendar-model|U6a]] shipped the diary;
[[people-model|U6b]] shipped the named-individual register
[[cabinet-model|V1.1d]] deferred.

**U6b's finding is that the deferral was right, and it took a measurement to say
so.** The roster half already existed — ~70 people as loose strings in five
places, with every nation file writing one name twice — so the session was a
migration into `data/people/` and a re-key of three serialised fields, not an
authoring exercise; only five names are new. The **minister** half was measured
against a floor fixed before the sweep and **cut before it was authored**: a
player meets 6–13 distinct people in fourteen years, roughly a fifth of what a
five-deep bench per party would cost. V1.1d's fork row stands.

**U6a's own finding is the one worth carrying forward, because it is about this
project rather than about calendars.** Every observable here is
piecewise-constant across a month — `clock.gd` has emitted `day_advanced` since
the MVP and nothing in `src/sim/` has ever listened — so two dates inside one
month differ only in the label, and a booking that merely defers is strictly
worse than acting. That is why booking is optional and why the session is judged
on legibility instead. It is also why the day budget died: a ceiling priced
against what is *legal* binds in 100 % of months, and nothing in this game yet
models what the player *wants*. **That gap is a session, not a constant**, and it
sits next to V1.3g's own named limitation rather than inside U6b.

**V1.1e SHIPPED THE UPPER HOUSE AND THE JUDICIARY, AND THE V1 TIER IS COMPLETE.**
Nothing is left in it. Section 1 closes with the two bullets it had been carrying since
the tier was written, and with **two more it turned out to have been carrying without
noticing** -- *Coalition formation* and *Confidence votes* were both built at V1.1a and
left unstruck for four blocks, which is **instances fifty and fifty-one**, found by
counting the section this session owns.

**The session discharged a stopgap declared in the DATA rather than in the code**, which
is new: `data/nations/DEU.json` carried *"Only the Bundestag half is modelled -- there
is no Bundesrat in this game"* from V1.2c, and three more citations were sitting in the
nation files for a mechanic that did not exist -- including one in
`src/sim/referendum.gd`'s own header, written one session earlier.

**NOT ONE of the ten upper houses is elected by the national electorate**, so the design
that suggests itself is wrong for eight of them and a second chamber is the LOWER
CHAMBER, LAGGED. An ideological tilt was designed, measured and **deleted twice**, and
what makes the chamber a check was already there and costs nothing: it votes at a
reduced whip where the Assembly votes at the full coalition bonus.

**The probe corrected the session three times and a TEST caught the fourth**, which is
twenty-two sessions running -- and the fourth is the one worth the space.
`tests/test_save_load.gd` reported *"no referendum was called, so the round trip
measures nothing"*: with no whip at all the Senat refused **seven of seven** authored
amendments, and France's `absolute` amendment row made that fatal, so V1.7c's whole
verb was dead one session after it shipped. **No whip at all is not `unwhipped`, it is
`no government exists`.** The other three: `bloc_offset` in the court's reach made it
strike down whatever was unpopular; the linear tolerance form amplified the roster's
spread until Germany could not legislate; and the whole judicial ladder was
**unreachable in all three playable nations** until its content moved -- the fix that is
also true, V1.4b's discipline and V1.7c's remedy.

**The re-run is bit-identical across all 45 shared regimes** -- the diff is additions
only -- and that is a CONSEQUENCE of where the gates sit rather than a coincidence:
every law regime in the harness calls `Legislature.apply()`, which by design skips both
gates, and `tests/test_judiciary.gd` asserts that. Three new regimes, all the expensive
kind. The legibility evidence is exact: same budget, `managed_captures_the_courts`
passes the whole ladder in month 6, rule of law falls **73.8 → 64.8** (below Italy's
67.6, the weakest in Europe), the grievance peaks at **11.87** against a quiet run's
8.79, and the president **LOSES the 2027 election at 23.5 %** where `managed` holds at
25.8. **Capturing the courts costs the office.**

`SAVE_VERSION` is **27**, on eight added fields of ten, failing the rule three different
ways and asserted apart. Model: [docs/upper-house-model.md](docs/upper-house-model.md)
and [docs/judiciary-model.md](docs/judiciary-model.md).

### V2.1a — the panel system, and the fold a headless harness could see after all (shipped)

**The row was written by the previous session rather than authored at plan time --
a first on this project -- and read cold it was wrong in five places and silent in
four.** `src/ui/` is **41 files**, not 25; `register()` knows **fourteen** panels,
not fifteen; the count came to ~18 surfaces against an estimated ~14. It was right
about the machine count, so the session did not split. What it did not name is
where the work actually was.

**FIVE hand-written lists of the same panel names, not one.** The row named
`main.gd::_mark_all_dirty()`. There were also `tools/screenshot.gd`'s
`_mark_panels_dirty()`, `tools/screenshot.gd`'s `PANEL_BY_WINDOW_ID`, and --
the one nobody was looking for -- `tests/test_shell.gd::EXPECTED_PANELS`, holding
**seven of fourteen**, so bloc, calendar, people, companies, projects, campaign and
dispatches had never been checked for registration, reachability, exclusivity or
cluster routing since U5a. That is not a refresh bug: it is `check_names.sh`'s U6b
failure and `run_tests.sh`'s `test_companies.gd` failure in a third place -- **a
check that silently covers less than it appears to**. All five are deleted, and
`tests/test_panel_kit.gd` forbids a sixth by refusing any file that names three or
more panels in one literal, **arrays and dictionaries both** -- a scanner that read
only arrays would have called `screenshot.gd` clean while it held the longest list
of the five.

**THE STEP-0 MEASUREMENT REFUTED A STANDING CLAIM, and the plan declared both
branches before it ran.** `tests/test_nation_panel.gd` has recorded since V1.3e
that *"a fold is a thing this suite structurally cannot see"*. The observation was
right and the diagnosis was wrong. The layout **does** run; what an autowrapping
Label is missing is not time but a **width**, and its minimum-size cache lags one
invalidation -- so a read in the same call as the write returns the answer for the
*previous* width, and a read one frame later is exact to the pixel. **Impose a
width, let a frame pass, then read.** `test_nation_panel.gd`'s note stands as a
description of itself rather than as a property of the engine, and the fold
contract is a real headless test.

**The one new visual rule was split in two, because it was doing two jobs.**
"There is more below" is the **scrollbar's** job, and `ui_theme.gd` had themed
`ProgressBar` and never `VScrollBar` -- so the affordance the row wanted to invent
already existed and had been engine-default grey on navy since U5a. The brass
hairline on the plate's bottom edge fires only when the panel's **primary action**
is below the fold, which is a thing a scrollbar structurally cannot say and is
exactly what cost five screenshot passes. Brass keeps one meaning; V2.2 has already
reserved the next spend of it. A panel declares its verb with an optional
`primary_action()`, duck-typed the way `mark_dirty()` is, so there is no base class
and no registry of which panels have verbs.

**The screenshot pass earned its keep for the twenty-first session running, with
three bugs of which two were live and older than the session.** `fit_within()` spent
the whole band on the **scroll** and then added the title bar, the separation and
two content margins on top, so **every window that filled its band overflowed it by
about fifty pixels** -- Politics ran 945px into an 886px band and, because
`clamp_into_parent()` constrains only position, its last row sat under the bottom
furniture. A window is also sized from its content as it was **before** the refresh
that fills it, because `open()` marks dirty and places in the same call. And the
session's own new theming **made the scrollbar disappear**: a `StyleBoxFlat` with no
content margins has a minimum size of zero, so styling `VScrollBar` gave it a colour
and a width of **0px**.

**A flag was written and deleted, which is U6a's currency one tier on.** `--fold`
resized the window to 1280x720 to force the mark and did nothing at all:
`project.godot` sets a 1920x1080 viewport with `stretch/mode="canvas_items"`, so the
layout is at 1080 whatever the window is. Once `fit_within` was correct the mark
fires on `--open politics` at the shipped size, and a flag that does nothing the
panel does not already do is noise.

**What is NOT fixed is measured and handed on**, so V2.1b does not have to
rediscover it. `get_combined_minimum_size()` is not the truth in either direction:
`economy_panel` reports **928px for ~500px** of rendered prose and opens with a
third of its band empty, `people_panel` reports **520px** and renders about **550**
and clips its last four rows. A grow-to-the-band heuristic was written for the
second and **deleted** -- every rect the engine reports agrees that the panel fits,
so the correction had nothing to key off and would have been a number tuned against
a symptom. Politics clears the fold by **twenty-one pixels**, which is one added
row from being `nation_panel.gd` at V1.3e.

No balance re-run and no new regime: nothing in `src/sim/` was touched and this adds
no verb, predicted in the plan rather than discovered. Model:
[docs/panel-system.md](docs/panel-system.md).

### V2.1b — the sixteen panels, and a handover that was a stale read (shipped)

**The row was wrong about the count twice and about the effort once.** `src/ui/` holds
**nineteen** `*_panel.gd`, three migrated at V2.1a, **sixteen** left -- not "twenty-five"
and not the "22 panels" the per-session table names. One of the three files that row
said would not fit one session's context together is **`map_view.gd`, which is not a
panel and builds no rows at all**. And *Low* was wrong: the migration is mechanical, and
two kit changes and one re-composition are not.

**FOUR PANELS HAD NO PRIVATE HELPER AND WERE THE ONES THAT MOST NEEDED MIGRATING.**
V2.1a's check asks whether a file still defines `_row` / `_line` / `_header`; `law`,
`calendar`, `election` and `polling` never had one and built **sixty-six raw Labels**
between them inline, so that check would have called all four clean forever. It is
`check_names.sh`'s U6b failure and `EXPECTED_PANELS` at seven of fourteen **in a third
place -- inside the test written to end exactly that.** The second assertion closes it:
every `src/ui/*_panel.gd` must name `PanelKit`, over a **directory scan** rather than a
sixth hand-written list of panel names.

**THE HANDOVER WAS A STALE READ, and V2.1a's own step-0 finding is what it missed.**
[[docs/panel-system.md]] section 7 handed this session two numbers and the claim that
`get_combined_minimum_size()` is not the truth in either direction -- economy reporting
**928px for ~500px** of prose, people **520px** against ~550 rendered. Measured against
each panel's drawn extent: **cold differs from warm in 4 of 14, and warm differs from
drawn in 0 of 14.** A panel that has never been shown has never been laid out at the
width it will really have, so its minimum answers for a width nothing draws -- which is
*the minimum-size cache lags one invalidation* one level up, applied to the panel
instead of to the Label. V2.1a found the rule and did not turn it on its own handover;
`fold_probe.gd`'s table (a) takes exactly that cold read. **Politics reads 4725 cold and
945 warm.**

**So the structural fix this session's plan booked was written, measured and DELETED**
-- U6a's day budget and V2.1a's own `--fold` flag a third time. It changed nothing in
any of the fourteen, because `window_frame._process()` already re-fits when the content
minimum moves, which is V2.1a's own fix doing the work its section 7 said was missing.
One item on that list was real and is not a measurement error: `people_panel` authored
520px against a ~700px register, so the window opened with a row cut through the middle
and three hundred pixels of band empty under it. **Height is the right answer there and
the wrong one for a fold**, and the general rule -- grow any window to the band -- stays
deleted, because five panels legitimately author a height shorter than their content and
scroll inside it.

**THE FOLD CONTRACT IS A TEST NOW, and the one panel that failed it could not have been
fixed by height.** Six panels gained a declared verb (`bloc`, `budget`, `calendar`,
`campaign`, `events`, `law`), taking the table from four rows to ten, and **politics
failed at 865 against an 826px band**. That panel holds 945px of content, so no height
exists that would have cleared it -- V1.3g's finding as an arithmetic impossibility
rather than a rule of thumb. The verbs moved **above** the readout: politics reads **73**
now, and it is structural rather than 39px of luck. Mutation-checked by putting the body
back on top, which turns the assertion red.

**Two kit changes, both forced by a panel rather than chosen.** `Tone.PLAIN` on `line()`
now means the panel's own **body** text: every tone resolved through
`_variation(tone, UiTheme.CAPTION)`, which was harmless for V2.1a's three callers and
would have silently shrunk and dimmed the **forty-five plain lines** `government_panel`
and `nation_panel` build between them. And a figure's caption wraps, because overview's
GOVERNMENT column is ~110px and V1.5a already paid for a caption that could not wrap
there. **Two retained tables were rebuilt as ledgers** -- polling's two and budget's
figure table -- and the second killed a live bug rather than a risk: `_set_figure()`
**returned silently on an unknown key**, which is how V1.3g's deployments line wrote into
nothing for three sessions while V1.4a documented it.

**The twenty-second screenshot pass found one bug and it was the readout's** (people's
clipped row), with no bug in the tool -- the second clean sheet the tool has had. No
balance re-run, no new regime, no `SAVE_VERSION` move: nothing in `src/sim/` was touched
and this adds no verb, predicted in the plan rather than discovered. Model:
[docs/panel-system.md](docs/panel-system.md) sections 7 and 9-12.

### V2.1c — navigation, and a resting screen that was silent 57 % of the time (shipped)

**The V2.1 block is complete.** V2.1a settled what a panel is, V2.1b migrated all
nineteen onto it, and what was left is how the player reaches one and what they are
looking at when none is open. Model: [docs/panel-system.md](docs/panel-system.md)
sections 13-17.

**The row's own question -- whether the resting screen should show anything at all --
was answered by MEASURING rather than by arguing, and the answer is one mark on the
bar and no plate anywhere.** `tools/nav_probe.gd` ran the real game for fourteen years
with nothing ever opened and counted the months in which a decision was in front of
the player against the months in which anything on screen said so: **42 of 74 silent
for a president who never touches a card, 64 of 74 for one who reads a card and closes
it.** The message column is the only route a pending thing has ever had -- six cards,
oldest dropped, dismissible, never re-pushed -- so **a council vote and an open
campaign window were silent in 100 % of their months, having no card at all**, and an
event's whole visibility is *one click of an X away from nothing*. `src/ui/pending.gd`
returns window ids, `action_bar.gd` turns them into clusters, and the mark is the
cluster's own icon in brass: section 4's rule -- *the state's own material marks what
matters* -- reused rather than joined by a second visual rule. **U5a deleted
`dashboard.gd` on purpose and the map is still the resting screen.**

**THE KEYBOARD WAS A HAND-WRITTEN LIST OF PANEL IDS IN A SEVENTH PLACE, and the test
written to catch that class could not see it.** `main.gd::_unhandled_input()` matched
**six** keycodes against six window ids, so the eight windows added since U5a had no
key at all; `tests/test_shell.gd` held **the same six** as a literal dictionary, and a
list cannot test a list. `test_panel_kit.gd`'s no-hand-written-list check scans
`src/ui/` and `tools/` for panel **variable** names, and these were ids and keycodes in
`tests/`. The map now lives at the `register()` call -- `register(id, title, content,
key)`, `shortcut()`, `id_for_key()`, and a `push_error` on a key already taken -- so
adding a surface stays *one register() and one line in `_build_action_bar()`*, and the
drawer's tooltip **reads the letter off the registry** rather than restating it.

**`WindowManager.opened` and `closed` had had no consumer since U5a**, which is
`message_stack.card_activated`'s case at V1.8 in a second place: the bar was the only
route that marked itself, so a keypress, a map marker (U6c) and a message card (V1.8)
each opened a window while the one control that says where you are went on saying
nothing. Both signals are consumed now, and the marks are the theme's existing pressed
style plus a brass icon -- **no new theme variation**, so `test_ui_theme.gd` is
untouched.

**Instance fifty-two, and the first of the V2 tier**, is in the row's own list of five
surfaces to place: [docs/tiers/v2.md](docs/tiers/v2.md) §4 calls the day agenda **"a
ribbon, not a grid"** and §2 reaches a city by **clicking the map**, so two of the five
arrive as something other than a drawer entry. **The cluster capacity table then
refused the question it was written to answer**: the bar may use **1384px of 1920** and
the widest drawer this game could plausibly grow uses **half** of it -- 0 of 16 measured
rows come near the edge -- so width cannot force a fifth cluster and cannot choose one
either. The four hold on grammar instead: **a cluster is the domain of the decision
rather than the shape of the object**, so region, city and energy are Economy, climate
is Society, and a fifth "Territory" cluster is refused with the count that would
reverse it written beside it.

**`tools/run_tests.sh` now fails a test that exits 0 with a `SCRIPT ERROR` in its
output, and the session reproduced the failure it was told about.** A parse error in
`main.gd` left `test_shell.gd` printing *"all checks passed"* over a scene that had
never loaded -- because that file read `_main._state` off a bare Control, which raises
rather than returning null. Both halves are fixed and zero script errors are emitted
today, so the check costs nothing until it saves something.

**No `SAVE_VERSION` move, no balance re-run and no new regime**, predicted in the plan
rather than discovered: nothing in `src/sim/` was touched and this session adds no verb.
**The twenty-third screenshot pass found no bug in the readout and one in the code it
was about to ship** -- `show_pending()` reached `Icon.load_icon()`, which reads an SVG
off disk and rasterises it on every call, on the path that refreshes with the clock, so
the bar was re-reading four files a day. Both tints are rasterised once now. The frame
before and after is identical to the pixel, which is the point worth recording: **a
screenshot pass structurally cannot see that class**, and this is the first bug on the
project's record found by reading a change's cost rather than by looking at it.

### V2.2 — the geographic register

**The block that makes every later one possible**, and the one that satisfies a
condition written at the MVP: [[docs/data-sources.md]] filed GeoNames with the status
*"Not imported at MVP. Listed here so the decision is already made when cities become
gameplay rather than decoration."* That condition is met here.

**THE PER-SESSION TABLE STOPPED AT V2.1c, SO THERE WAS NO V2.2 ROW TO READ AND THE
TIER/MODEL/EFFORT CALL WAS AUTHORED AT PLAN TIME.** That is the missing-row failure
this project has now logged more than fifty times, in its purest form -- not a row that
was wrong, a row that was absent. Counted cold: **~36 surfaces, ~14 new files and FOUR
machines** -- the import pipeline, the register and its loader, the map draw and hit
test, and two panels -- across **two tracks**, the tier table's own `S + data` against
section 2's *cities drawn and clickable* and *finer map geometry*, which are U. **The
block splits**, on the two-track rule that cut V1.6e, V1.6f and U6c, and on V1.3e's
machine count.

| | Session | Ships |
|---|---|---|
| ~~**a**~~ | ~~the import and the register~~ **Built** | Eurostat + GISCO + GeoNames, `data/regions/`, `data/geo/regions.geojson`, `region.gd`, `city.gd`, the loader's two-level partition validators, eighteen firms domiciled, probe, tests. **No UI at all.** See below |
| ~~**b**~~ | ~~the map and the two panels~~ **Built** | the city draw pass and its screen-space hit test, Region and City under Economy, finer map geometry, `--region` / `--city`. See below |

### V2.2a — the import and the register, and a band measured three times (shipped)

**A REGISTER AND NO BEHAVIOUR.** Nothing in `src/sim/` reads a region; a region carries
no GDP, no unemployment and no sector mix, and a city carries no population of its own.
V2.5 is the session that makes a region load-bearing and V2.6 the one that moves people
between cities, and each arrives with the field it needs rather than finding it
pre-authored and inert. `tests/test_geography.gd` fails if any file under `src/sim/`
preloads `region.gd` or `city.gd`. Model:
[docs/geography-model.md](docs/geography-model.md).

**The shape is V1.4a's partition at two levels, which is the tier's own call rather
than an analogy reached for afterwards** -- *a city is to population what a firm is to
sector output*. A region holds a share of its nation's population, a city a share of
its region, both sums are at most 1.0, and neither residual is stored: `1.0 - sum`
cannot drift from the thing it is the remainder of. **112 regions and 581 cities.**
An absent file is an **error** here, which is the one place this register departs from
the two it copies -- a nation with no companies has unpartitioned sectors and a nation
with no outlets has no press, and both are models the roster ran before; there is no
prior model in which a nation has no places.

**THE LEVEL IS PER NATION, AND THE ROW SAID NUTS 2.** For the nation this game is
about, NUTS 2 is the **pre-2016 regions**: Eurostat's own labels return `FRC1
Bourgogne`, `FRE1 Nord-Pas de Calais`, `FRE2 Picardie`, units abolished in 2016, and a
French player reading "Picardie" in a game set in 2026 reads a bug --
[docs/fictionalization.md](docs/fictionalization.md) names **Occitanie** as its example
of a real region, which is NUTS **1**. The inverse holds elsewhere and is why one level
cannot serve the roster: Italy's NUTS 1 is five statistical macro-areas and
Switzerland's is **one country**. So FRA, DEU, GBR and BEL are NUTS 1 and the other six
NUTS 2, and **no level field reaches `src/`** -- the loader reads `data/regions/` and
never learns a level exists, which is CLAUDE.md's first rule. The test checks that in
the DATA rather than by grepping `src/` for the word, which was the first version of
the check and failed on the comments explaining the absence.

**THE ROW'S BRITAIN PROBLEM WAS HALF WRONG, AND THE WRONG HALF IS THE ONE THAT
MATTERED.** The V2 preamble records that Eurostat dropped UK regions and that *"Britain
therefore needs a second source or an authored register"*. Confirmed and worse for
**regional GDP**: `nama_10r_2gdp` carries zero `UK` codes at **every** year, 2018
included, because the codes were removed from the dimension rather than left empty. But
`demo_r_pjangrp3` carries **41 UK NUTS 2 codes and 12 NUTS 1 codes with values at
2019**, summing to the UK national figure (66 647 112) exactly. **Regional population is
measured for all ten; only regional GDP is short** -- and regional GDP is the quantity
V2.5 makes load-bearing, not this one. So the register is a partition of **population**,
Britain reads 2019 through the same per-series nearest-year fallback V1.5c wrote for
`SI.POV.GINI`, and the gap passes to V2.5 whole. **ONS was probed before the call was
taken** rather than assumed unavailable: its beta API publishes
`gdp-by-local-authority`, which is 380 LAU rows with **no ITL codes at all**, so
aggregating it needs a fourth dataset as a lookup. Recorded so V2.5 does not re-derive
it -- and at NUTS 1 the authored fallback is twelve numbers rather than forty-one.

**THE GEOMETRY IS THE AUTHORITY ON THE ROSTER, and that single rule settles three
problems where the plan expected one.** A region with no polygon cannot be drawn and
this tier exists to locate things, so the register is the set of codes carrying both a
figure and a GISCO polygon. `<CC>ZZ` -- Extra-Regio, the output belonging to no region
-- falls into the residual with no filter of its own; `FRY` and `ES70` are dropped by
the bounding box that has dropped them from the map since S8; and the third was not in
the plan at all -- **the Eurostat response carries two NUTS vintages at once**. `NL35`
and `NL36` are the 2024 codes for Utrecht and Zuid-Holland and `NL31`/`NL33` the 2021
ones, equal to the person, so summing all fourteen Dutch codes overstates the
Netherlands by **5.1 M**. Filtering to what the 2021 geometry knows leaves exactly
twelve and the sum is the national figure to the digit. **The partition is exact in the
source itself** -- France's population, 68 091 703, is the sum of its own NUTS codes to
the unit -- so the residual is precisely what those rules removed, and it is non-zero
for two nations only: FRA 0.0330 and ESP 0.0460.

**The city join is a point in a polygon, and it CANNOT go through GeoNames' own
`admin1`** -- for France that is the 13 modern regions, which is NUTS 1 and therefore
*coarser* than the NUTS 2 the row asked for, so a code join would be silently wrong for
at least one nation and unverifiable for the rest. 4 002 cities land inside, 82 snap
(a coastal commune the GISCO 10M coastline cuts -- Birkenhead, Portsmouth, A Coruna,
Cadiz, Antibes), 40 are genuinely overseas and belong in the residual, and **0 fail**.

**THE ONE MEASURED CONSTANT WAS MEASURED THREE TIMES AND THE FIRST ANSWER WAS WRONG BY
29 %, and all three corrections came from READING THE GENERATED FILE rather than from a
check.** `CITY_MIN_POP` is swept against two clauses fixed before it ran -- roster mean
coverage at least 0.30, at most 600 named cities, the second written from the drawing
side because V2.2b draws by rank and the roster at the opening fit is ~1000 px wide.
The first sweep landed on `[82 000, 101 000]` and a midpoint of 91 500, and it was
measuring GeoNames rather than Europe: **607 `PPLX` rows** (sections of a populated
place -- Hamburg-Nord, Carabanchel, Eixample, Favoriten), then **a London naming twenty
of its own boroughs** and reaching 1.325 of itself with Brussels at 1.285, then
**thirty-six Paris and Marseille arrondissements** that neither the feature filter nor
the fit rule could see, because GeoNames codes some as `PPLX` and others as plain `PPL`
and Ile-de-France is large enough to hold Paris *and* its districts. The discriminator
is a **number**: a plain name-prefix test also eats `Mansfield Woodhouse`, `Newport
Pagnell`, `Amersham on the Hill`, `Ischia Porto` and `Kronberg Tal`, which are five real
places, where requiring a digit after the parent's name catches all thirty-six and none
of the five. Corrected, the clauses cross at **[69 000, 73 000]**, both edges are smooth
crossings rather than plateaux so **the interior governs** (V1.5d's rule), and the
midpoint is **71 000** -- the same answer at a grid of 2 000 and of 1 000, which is
V1.5b's refinement diagnostic, and interior to the swept range rather than on its edge.
The register is identical for any cut in 70 915..71 010.

**A third clause was written and DELETED**, and the reason is structural rather than a
retune: *"the worst nation names at least 0.20 of its population"* fails at every
candidate and its two failing nations do not move with the threshold at all --
Luxembourg has ONE city and it is 11.9 % of the country, and Swiss communes are
administratively small. A band an observable cannot reach is a bound and not a selector,
which is V1.5a's finding and V1.5c's, so it is recorded rather than met by shipping
4 691 cities. **Shares are rounded DOWN**, not to nearest: rounding to nearest put
Germany's sixteen Laender at 1.000003 of Germany, a residual of minus three parts in a
million, which is arithmetically nothing and is still a partition that does not hold.

**The firm domicile is the one thing making `Company.city` load-bearing before V2.2b
draws it**, and the table it produced is one the row did not ask for: **one city holds a
third to a half of a nation's named payroll** -- Lille 33.1 % of France's, Duesseldorf
34.3 % of Germany's, Manchester 44.0 % of Britain's. Nothing authored that, and it is
what makes V2.6's migration a decision rather than a diffusion. `headcount_in_city()`
lives in `companies.gd` and not on `src/core/region.gd`, because a core value type
preloading a sim system would invert `data -> sim -> ui`.

**`SAVE_VERSION` stays at 27 and the test pins three ABSENCES rather than three fields**
-- V1.6c's shape and V1.8's, and the third time this list has had a session whose
serialised contribution is nothing at all. The register is content: a region's share and
a city's share round-trip through `data/regions/` the way a firm's authored share and
headcount round-trip through `data/companies/`. **No balance re-run and no new regime**,
predicted in the plan rather than discovered, on U6c's precedent: nothing in `src/sim/`
was touched beyond one pure query and a region is not a verb. **No screenshot pass**, for
the first time since U5a -- there is no UI to photograph and a frame of an unchanged
shell proves nothing. It returns at V2.2b.

**`tools/check_names.sh` WENT RED ON A REAL CITY, and both halves of the rule that made
it red are true.** [docs/fictionalization.md](docs/fictionalization.md) says *"Do not
reuse a real company's actual name"* and, four rows above, *"Cities, regions, rivers |
Real | Lyon, Occitanie, the Rhone"* -- and **Santander** is a bank on
`tools/banned_names.txt` and a Spanish city of 173 635 people that GeoNames handed the
register. Banning it everywhere makes the check permanently red over a real place;
deleting the entry lets a session name a fictional bank after a real one. The ban that
matters is the one about **firms**, so `banned_names.txt` grew a `[places]` section
checked in `data/companies/` alone, and the negative case was run rather than assumed:
a firm renamed `Santander` still fails. One entry today, and the criterion for adding
another is written beside it.

**`data/geo/regions.geojson` is written and committed and `data_loader.gd` does NOT load
it.** Nothing draws it until V2.2b, so a launch should not pay 180 KB for it;
`tests/test_geography.gd` parses it directly to assert every named city lies inside its
own region's polygon, which is `tests/test_map_markers.gd`'s U6c containment check one
level down and the thing that catches a mistyped digit or a geometry vintage that has
moved under the figures. That keeps the file honestly read rather than decorative --
U6c's rule about a coordinate nothing reads, applied to the geometry rather than to the
point.

### V2.2b — the map and the two panels, and an enclave of each direction (shipped)

**THE ONE EXPECTED RED TURNED RED ON THE DAY IT NAMED.** V2.2a's absence assertion
failed the moment `data_loader.gd` grew the string `regions.geojson`, exactly as its
own message said it would, and was flipped into a presence check with the history
recorded beside it: `region_features` holds **112 polygons**, its key set must equal
the register's region ids, and the loader cross-checks the same join at load time as
the fourth `_validate_regions()` rule -- the geometry is the authority on the roster,
so a region with figures and no polygon is an import that has drifted from its own
authority.

**REGIONS ARE THE FILL, at every zoom.** Each nation draws its 1:10m GISCO regions in
the nation hue with a dim hairline between them, over a same-hue 1:50m base and under
the bright 1:50m national stroke -- the base exists because GISCO and Natural Earth
disagree at the coast by a few kilometres, which is a few pixels at MAX_ZOOM, and the
base turns that disagreement from a hole in the country into a seam the eye cannot
find. The screenshot pass judged the seam: legible at the opening fit, and Corsica's
fill sits a hair off its stroke, recorded as the accepted cost of two vintages rather
than traded away.

**The two-pass draw is load-bearing, and the roster carries the proof itself.** With
holes dropped (the loader's standing rule), a host region's outer ring covers its
enclave, so whether the enclave's boundary survives depends on draw order -- and the
roster holds **one enclave of EACH direction**: Berlin (3.7 M) outpopulates its host
Brandenburg (2.6 M), Bremen (0.7 M) is a third of its host Niedersachsen (8 M). No
fill-and-stroke order renders both, and the first version of this draw was one pass;
the correction came from the data, not from a review.

**BRASS CROSSES, and this is the spend the tier reserved.** Radius is a function of
population -- `sqrt(pop / 8 M)` against `RADIUS_BASE`, clamped at both ends -- so a
9 M capital and its 71 k suburb read as the same kind of thing without the suburb
vanishing; London draws ~9.6 px and the smallest towns clamp at 2. **Ascending
population, so the largest draws last and wins an overlap**, the marker convention
where draw order and hit order walk one list. `CITY_MIN_ZOOM = 2.0` sits JUST UNDER
the opening Europe fit (which computes to ~2.1 on 1080p), on `LABEL_MIN_ZOOM`'s own
discipline -- the first draft sat at 2.2, ABOVE the fit, and would have shipped 581
cities the default frame never shows; the volume clause was measured for the ~1000 px
opening fit, so the threshold belongs below it. **The hit test reads the same gate**,
so a glyph that is not drawn is never a target. The name is on hover alone, one
formatter shared with both panels (`PanelKit.pop_text`), so the map and the panels
cannot print two roundings of one figure.

**The hit test takes the marker contract, and the purity check fired on a COMMENT.**
`_city_at_screen_point()` is a radius test in screen space over the city list and
nothing else -- the tier doc's own instruction -- and `tests/test_map_cities.gd`
polices it from the source the way `tests/test_map_markers.gd` polices the markers'.
That test extracts everything from one `func` to the next, which swallows the
following function's doc comment: this session's city doc legitimately *named* the
things it must not reach, and the markers' check read the name and went red. **The
test was the authority and the source moved** -- the function now sits where both
extraction windows are clean, and its doc says so. A click chain runs markers, then
cities, then nations, each hit stopping the fall-through.

**The panels.** Region (key **T**) and City (key **V**) land under Economy, the
cluster going 4 → 6; `nav_probe.gd`'s `OTHER_ROUTES` carries the city's map cross as
its third entry. The Region panel prints the partition its register rests on and a
league table in authored order (which the importer writes descending by population)
whose payroll column is the one live number in it -- `headcount_in_city()` over each
region's cities -- and **zero is a TRUE zero there for seven of ten nations**, printed
as `0` rather than an em dash: V1.6d's bug was an absent figure printed as a
confident zero, and this is a present figure that is empty. The City panel carries
both of §16's routes -- the drawer's ranked list of the player's cities, and
`show_city()` for any nation's cross, with the back button outside the scroll for the
fold's reason. A city's population is its two shares through the LIVE national
population, so the panels stay true as demography moves.

**`SAVE_VERSION` stays 27 and there is no balance re-run**, both predicted: nothing
under `src/sim/` was touched, and drawing is not a verb (U6c's precedent, twice
running). The screenshot pass **returned** after V2.2a's skip and judged three frames
-- the default fit (hairlines inside every nation, crosses legible, Germany and
England dense but readable), `--region`, and `--city` (Paris centred and zoomed, the
hover label reading "Paris -- 2.1 M", the panel showing Banque Méridienne's 68 k and
the same 2.1 M the label prints). Two `--` flags exist where every flag before them
staged a mutation, because the register is static content and the frame is the whole
point.

**Two handoff notes were STALE, and both say the same thing: V2.1a already fixed the
drift.** `screenshot.gd`'s `_mark_panels_dirty()` was named as a hand-written list to
extend; V2.1a deleted it to one line through the registry, so registering the two
panels IS the whole job and no list exists anywhere to add them to. And the
month-136 warning on `nav_probe.gd`'s loop was inherited by nothing: no probe this
session runs a month at all, and `geography_probe.gd` still runs none -- a register
no tick writes has no wrong state to measure.

### U5a — the ruler's shell (shipped)

The session that changed what the game *is a picture of*. U2 built a dashboard,
U3 and U4 made it a good one, and none of the three asked whether a dashboard
was the right object — the player was administering France through a set of
tabs. U5a makes the map the background, the interface instrument furniture laid
over it, and the player's own face a permanent fixture in the corner.

**The ask was three things and shipped as one, decomposed before any code.** The
request was the shell, a world satellite map, and a calendar of appointments
with named people. The calendar is a simulation feature wearing a UI costume —
it needs person entities that do not exist, which is the thing [[cabinet-model|V1.1d]]
explicitly deferred — and the map half is independent of the HUD half. Split
into U5a (this), **U5b** (the map) and **U6** (the calendar and the roster), each
with its own plan. The count for U5a alone came to ~28 surfaces, between V1.2d's
~21 and V1.3b's ~33.

**Four calls, recorded because each could have gone the other way:**

1. **Windows pin, and that is why the rail could die.** A tab rail guarantees
   one thing a set of floating windows does not: the player never has to tidy
   up. `window_manager.gd` keeps that guarantee as its single rule — *opening a
   panel closes the open unpinned one, and leaves every pinned one alone* — so
   the default behaves exactly like tabs and the pin buys the case tabs could
   never serve. Without the pin this would have been a reskin.
2. **Brass, not cyan.** The reference and every game HUD reach for a cool glow.
   Brass is the state's own material — seal, instrument bezel — and it is the
   one bold move in a palette that is otherwise disciplined navy. The signature
   is one rule applied everywhere: a 1px brass hairline on a plate's **top edge
   only**, light falling on glass laid over a map table. `tests/test_ui_theme.gd`
   asserts the other three edges stay bare, because that is precisely the kind
   of thing a later session tidies into `set_border_width_all()` without
   noticing the interface stopped having a point of view.
3. **The message column ships as furniture with nothing behind it.** Events are
   V1.8 and [docs/tiers/v1.md](docs/tiers/v1.md) argues at length that they stay
   last. Building the column now costs a file; wiring it to invented content now
   would cost the argument. The API is real and tested so V1.8 adds calls rather
   than a layout.
4. **The flag became data, not a table in the UI.** Ten `flag` blocks with a
   `layout` string `src/ui/flag.gd` dispatches on — the same
   dispatch-on-a-data-string shape as `formation_method` and the six fields
   after it. A colour table keyed by nation id inside a panel is
   `if nation_id == "FRA"` with extra steps, which
   [docs/engine-decision.md](docs/engine-decision.md) Rule 1 forbids outright.
   This is the one place the session touched `data/`, and it earns **no**
   `SAVE_VERSION` bump: a flag is static content read at startup and never
   written to a save.

**Two things the plan got wrong, both found by looking at the running game
rather than by reasoning.** The first: with the map promoted to background, its
opening zoom of 1.0 — fine inside a tab — left Europe as a 480×420 object
floating in the middle of 1920×1080, and every test passed while it did, because
no test asks what fraction of the screen the map fills. The second: the panels
report combined minimum heights up to 974px against a usable band of 886, so a
window sized to its content grew straight through the bottom furniture and the
player could not reach its last row. Both are the class of bug the U-track
exists for and neither is visible headless; `tools/shot.gd` (throwaway, not
committed) rendered the scene to a PNG because `--headless` draws nothing.

**One deviation from the plan, stated rather than absorbed.** The plan said the
session touched no `data/` and no `src/core/`. The flag did both — ten JSON
files, `Nation.from_dict()` and a validator. It is presentation content, it
fails at load like every other bad field, and it was the only way to draw a flag
without breaking Rule 1; but the plan's claim was wrong and the row says so.

### V1.3d — the bloc (shipped)

The session that answers a question three earlier ones deferred to it, and the
first to add a kind of state rather than a kind of pair. Full account:
[[bloc-model]]. What belongs here is what the session's own record adds.

**The `ISSUE_KEYS` call went the expensive way, and the reasons were structural
rather than thematic.** V1.3a, V1.3b and V1.3c each priced their domestic cost
through `bloc_offset` and each named this as V1.3d's decision. The argument that
settled it is not "Europe is important enough to deserve an issue" — it is that
`opinion.gd` builds the national agenda from the salience weights alone, so a
Europe priced on `bloc_offset` is **structurally unnameable** by the polling
panel's own list and by `elections.gd`'s attribution. The session's headline
mechanic would have been invisible on the two surfaces that exist to tell the
player why they lost. Two supporting reasons and one measured cost are in
[[bloc-model]]; the cost is **+0.39 %** on the ratio S10's finding was about, and
it moves in the safe direction.

**The political map of Europe fell out of a table written at S5, and nothing
authored it.** The opinion model has no signed split — every satisfaction reaches
every bloc with the same sign, and [[opinion-model|the tax split]] is two issues
moving opposite ways rather than one issue signing twice. So `europe` had to be
one-signed, and the division had to come from somewhere else. It does: pensioners
and rural carry **no `growth` entry at all**, so 37 % of the electorate receives
the constraint and none of the single market, while business weights `growth`
0.19 and `public_finances` 0.34 and receives both. A eurosceptic countryside and
a pro-European boardroom, derived from weights set for unrelated reasons.

**The probe corrected the model twice before any content shipped, which is now
four sessions running.** The authored rule severities summed to 1.35 against a
`BURDEN_MAX` of 1.0, so the clamp removed 0.35 of real burden and a player already
defying three rules got **nothing** from breaching the fourth — the
strictly-dominated shape [[coercion-model|V1.3c's probe caught]] for tariff
severity, in a new place. And the first `EUROPE_SCALE` put one defied rule at
−3.24 against a ±3.0 noise floor, which is [[scenario-model|`deu_grand_coalition`'s]]
clearing-by-nothing mistake; swept to 0.80, where it lands on the −4.9 to −7.4
this project already measured for a full embargo.

**A hole in the vote was caught by a test rather than by looking, and it was the
one thing that made a whole verb pointless.** With the threshold taken against the
council's *whole* strength, abstaining and opposing leave `seats_for` identical
and therefore always produce the same outcome — abstention was a slower way of
voting no. Taken against the seats actually **cast**, the three choices genuinely
differ, which is also what the real Council does.

**The council was a legislature the player controlled, and the fix was content
rather than a constant.** The first sweep had six of seven proposals decided by
France's own vote. The probe prints the eight members' positions, and they are
clustered — so no `SUPPORT_SIGMA` alone spreads the tallies. Moving
`common_defence_floor` to where a defence commitment actually sits in ideology
space is what put a proposal beyond France's reach; 0.90 is then the only swept
value where some proposals carry without the player, some are theirs to decide,
and some are lost whatever they do.

**The re-run could not be bit-identical, and the reason is the block's cleanest
distinction.** V1.3b's and V1.3c's both were, because an agreement and a measure
each need a player command and no balance regime issues one. A bloc rule needs no
command at all — the council meets whether or not the player engages. That is the
difference between a verb and an institution, and it is also why this session
needed **no eleventh regime** where b and c each did. What the re-run shows is
sharp: GDP, growth, trend and unemployment are **bit-identical across all thirty
runs**, so every economy constant measured through them is untouched; debt and
deficit move only for members and only by the standing contribution; and exactly
**one run of thirty changed outcome** — a GBR censure that carried by two seats
against a 326 threshold, flipped by a tenth of an approval point. All three S10
assertions still pass.

**Two things the plan got wrong and the build found.** The plan said the
projection would need no change; it did — `Budget.project()` had to tick `Bloc`,
and the *test harnesses* had to as well, which `tests/test_budget.gd` caught by
comparing a projection that advanced the council against a reality where it never
met. And the plan claimed the dilution preserved the S10 ratio *exactly*; it does
not, because the six candidate rows are not uniform. It preserves it to +0.39 %,
which is the measurement rather than the claim.

### V1.3c — tariffs and sanctions (shipped)

The first session that perturbs a partner on purpose, and the one that took the
directed-state escape hatch V1.3a named. Full account: [[coercion-model]]. What
belongs here is what the session's own record adds.

**The measurement corrected the model twice, both times before any content
existed, and that is the whole case for the probe-first discipline.** The first:
`effects.measure` carried both a `severity` and a `tariff_rate_pct`, and revenue
came back *exactly* linear in the rate — 0.0005 per point, every rate, every
nation — because the trade bite read severity and the rate only scaled the
answer. Two numbers for one intensity, the same redundancy V1.3b's own probe
caught between the gravity tie bonuses and the relations term. The rate was cut,
and cutting it is what turned an **asserted** Laffer curve into a real one: with
severity the only dial, revenue has an interior maximum at exactly
`1/(2 × MEASURE_TRADE_BITE)`, and nothing authors that number.

The second correction was larger. Damage was read off the **post-measure** trade
weight, which is intuitive and wrong: a full embargo has destroyed the trade it
would damage through, so damage saturated while cost kept rising and **every
severity above the revenue peak was strictly dominated** — less money *and* less
harm for more trend loss. A trap in the content, caught with no content in the
repo. The fix is that the two effects read different weights because they are
different quantities: you damage in proportion to the trade you *destroy*, you
collect in proportion to what still *crosses*.

**The named escalation trigger fired, and then unfired — which is the outcome
the trigger existed to produce.** The prior was poor: [[trade-model]] had
measured the transmission channel at 6% of `IMPULSE_MAX` under a synthetic
recession larger than any sanction should manage. The first sweep confirmed it —
−1.41 approval against a ±3.0 noise floor, not legible for any playable nation,
which the plan had named in advance as a **model** decision rather than a tuning
one. The second correction moved it to −4.9/−6.7/−7.4 without touching
`TRADE_BETA` or any economy constant. Had it not, the plan's stated fallback was
to ship coercion as a lever the player *wields* and barely *feels*, declared
rather than tuned until the panel twitched.

**A clamp was found binding in reachable play, which is the failure this project
keeps rediscovering.** `COERCION_IMPULSE_MAX` was set provisionally at 4.0 on the
reasoning that it should sit "comfortably inside" `IMPULSE_MAX_PCT`. A player who
tariffs three partners collects three retaliations, damage sums over imposers,
and at 4.0 the clamp rather than the model was setting the growth rate — the
`IMPULSE_MAX = ±50` failure [[economy-model]] records, a third time. It ships at
6.0, *equal* to `IMPULSE_MAX_PCT`, which is a principled anchor where "somewhat
less" was a feeling: a coercion shock may be as large as the largest budget shock
and no larger.

**GBR surfaced a third time, and the gate direction inverted.** V1.3b's trigger
was that a relations-based bar closes a feature to Britain. Here there is no bar
— a hostile verb needs no relations floor, and copying `AGREEMENT_ACCEPT_MIN`'s
shape would have closed the feature to whoever is *friendliest*. What Britain's
isolation costs it is leverage: revenue is open to it (0.120 against 0.179 and
0.161, within 1.5×) because tariffing collects on your own external demand, but
its best possible *hit* is a quarter of the other two's, because damage needs
someone who depends on you. Forced by the trade vector, thematically right, and
recorded rather than tuned away. **The probe's first version of that table
measured the wrong thing** — it picked each nation's largest trade partner when
damage scales the other way — and reported GBR at a quarter of the others' reach
for a reason that was an artefact before it was a finding.

**One repair the plan did not predict, found by a test rather than by looking.**
The budget panel built its "now" column from `Budget.snapshot()`, which reads the
revenue dictionary as the last monthly tick left it — so a tariff imposed *this*
month showed an em dash under Revenue until the clock moved, the panel telling
the player their new revenue source collects nothing. It now builds that column
from `preview()` with nothing pending, which recomputes on a deep copy and writes
no sim state.

**`SAVE_VERSION` stays at 10, and the test says so.** Every field V1.3c adds
passes the stated rule: an absent `measures` reads as `{}`, which is correct for
every version-10 save because those games could not impose one. That is
`scenario_id`'s case and `agreements`' case, against `eu_member`/`neighbours`,
which read as an actively wrong model. `tests/test_save_load.gd` asserts the
version is still 10, so a later session raising it has to come and say why.

### V1.3b — trade: per-partner intensity and agreements (shipped)

The session that made `external_impulse_pct` **per-partner**, and the one that
owed the balance harness a re-run. Full account: [[trade-model]]. What belongs
here is what the session's own record adds.

**"Unquiets `external_impulse_pct`" was an overclaim, and it is corrected above
and in [[v1]] rather than quietly delivered.** The decomposition table's own
wording — *made per-partner rather than one GDP-weighted aggregate* — shipped
literally and fully. The prose promised more. The channel is now structurally
correct and still numerically small, because nothing in the shipped game
perturbs a partner except an agreement, which is bilateral and so does move the
partner's trend. That makes the channel live rather than dormant, but it does
not make it loud, and saying so is cheaper than discovering it at V1.3c.

**The first named escalation trigger fired, and it was structural rather than a
tuning miss.** At the obvious gravity exponent of 1.0 the derived weight vector
is GDP-proportional — and GBR, which is in no EU pair and whose `neighbours`
list is empty, has both tie bonuses constant across all nine partners, so both
**cancel under normalisation**. Its vector is then *identically* the aggregate
the session replaced: L1 distance 0.000, measured. One playable nation in three
would have received a per-partner model that was arithmetically the thing it
replaced. The exponent is the only lever that moves GBR at all, and it shipped
at 0.70. This is the same class of cold read [[transition-model|V1.2d]] made
when it found its own scope shipping to zero playable nations — caught by the
plan's own named measurement, before any of the model was built.

**The second trigger did not fire, but it constrained a constant from above and
that consequence is recorded rather than left to be found.** Every GBR pair
rests at 45.0 and the strongest positive verb reaches 60.7, so any
relations-based gate must sit under 60.7 or the feature is closed to Britain
entirely — [[amendment-model|Germany's two-thirds]] repeated. It shipped at 52.
The consequence: for France and Germany the gate is non-binding against almost
every partner, so an agreement's difficulty there is carried by its **domestic
price** rather than by the gate. For GBR the gate *is* the difficulty. That
asymmetry is forced, not chosen, and it is thematically right.

**A second exploit was caught the way V1.3a's was, and it decided the model's
central call.** The obvious openness figure — trade mass over own GDP — would
have let relations move the trend *level*. `state_visit` is +5 relations, per
target, with no preconditions and **no domestic price at all**; nine clicks a
year would have bought about two permanent points of GDP on infrastructure for
free. Openness shipped as a ratio against a no-agreement counterfactual instead,
so relations move the **mix** and only an agreement moves the level. That choice
also killed a monotonic ratchet — partner GDP growing at trend forever would
have walked the index up ~20% over the harness's fourteen years from time
passing alone, putting the clamp rather than the model in charge of trend
growth, which is the `IMPULSE_MAX = ±50` failure [[economy-model]] already
records, committed a second time.

**And it made the harness re-run cheap by making it exact.** Because the
openness index is exactly 1.0 with nothing signed and the impulse is exactly
zero while partners sit at their own baselines — both by construction — the
re-run's question sharpened from *has anything moved materially?* to *has
anything moved at all?* Thirty fourteen-year runs, captured from the V1.3a tree
and diffed: **bit-identical**. Every economy constant measured through this
channel is still valid, unchanged and unargued.

**The synthetic probe found a real ordering bug that was invisible and would
have surfaced a session later.** The weight table is snapshotted before the tick
loop, but the impulse also reads each partner's `growth_annual_pct`, which
`_tick_nation()` overwrites — so resolved inside the loop, France read *this*
month's growth for the five partners sorted before it and *last* month's for the
four after. Both answers are zero while nothing is perturbed, so no test could
have seen it; it would have surfaced at V1.3c as a mystery. Found only because
the probe injected a partner recession the shipped game cannot produce.

**One repair the plan predicted and one it did not.** `Budget.project()` never
ticked `Diplomacy`, which was harmless until relations reached the economy;
measured at 2e-9 relative from a displaced state, small and still a broken
done-when condition, so `project()` now takes a loader. The one the plan did not
predict: storing an agreement's **terms** rather than its id in the register let
`src/sim/trade.gd` take no loader at all, which is what kept
`Economy.tick_month()`'s signature unchanged across **twenty-eight call sites**.

One piece of V1.2 work is still deferred rather than done, with somewhere to
point now: **V1.2c authored no amendment content naming `parliamentary_republic`**,
because Germany's real two-thirds bar was measured unreachable. V1.2e's
`deu_grand_coalition` start makes it reachable (0.727 against 0.667). The
content itself was left to the session that picks it up — see
[[scenario-model]].

### V1.3a — relations and diplomatic actions (shipped)

The block's schema session, and the first live state in this project that is
neither per-nation nor global. The full account — all four design questions,
every constant's rationale, and the measured tables — is [[diplomacy-model]].
What belongs here is what the session's own record adds to this document's
arguments.

**All four design questions went the cheap way, and one of them cost a third
input.** Relations are **symmetric** — one number per unordered pair, 45 in all,
keyed `"DEU|FRA"` by the one helper permitted to build a key, so
`rel(A,B) == rel(B,A)` is structurally true rather than maintained. Starting
values are **derived**, not authored, from EU co-membership (which every nation
file already carried) and a shared land border (added as a *fact*, the same
class as `assembly_seats`, cross-checked at load for mutuality). Size
asymmetry — the third input the roadmap expected to use — was **dropped as a
direct consequence of the symmetry call**: under a symmetric key a size
disparity cannot be expressed, because the pair's single number has no side to
attach it to. Handed to V1.3b's read-time trade weighting rather than quietly
omitted. `bloc_offset` was renamed, at the fifth writer that is not a law.

**The named escalation trigger did not fire, but the measurement rewrote
itself once.** The reachable range is ample — even the mildest authorable
content moves a pair further than the 8-point gap between two resting tiers,
so no precondition is unreachable. But the probe's first table asked *how long
a pair takes to return within one point of resting after sustained use*, which
from a twenty-point displacement is four-plus half-lives **by construction** —
so nearly every row read "> 120 months" and the table looked like it was
reporting that the drift does nothing. A second table was added rather than the
first one reinterpreted, and it is the one that justifies the constant: a
**single** action has a 35-month half-life, 78% present after a year and 30%
after a term.

**The measurement's real finding was in the other table, and it was not the one
the plan named.** The plan expected to check whether an action's bloc effect
clears poll noise. It does, at 0.08 and above — but only when the effect hits
**all six** blocs. An offset applied to fewer never clears the floor in
`overall_approval_pct`, not even at the content ceiling, because the roll-up is
weighted. A split price is legible on the polling panel's per-bloc rows and
nowhere else. Not a bug — a policy that divides the country should not move the
average — but an action whose only price was a two-bloc offset would have
shipped looking like a decision with no visible consequence.

**And it caught an exploit before the content shipped.** The obvious content
for the visible-cost slot was a six-bloc *gain*, since condemning foreigners is
domestically popular. The cooldown is per (action, target), so nothing would
have stopped the player applying it against all nine neighbours in one month —
+0.72 accumulated into a channel clamped at +1.0, saturating approval outright.
The visible six-bloc action shipped as a pure **cost** instead, and the popular
verb ships **split**, so mass use moves blocs in opposite directions and is
self-limiting. This is the first correction on this document's record to come
from a measurement finding an *exploit* rather than an unreachable number.

**The counterparty response is a declared stopgap, and the test asserts it.**
An action's own `relations` delta is the entire reaction; no reasoning, no
retaliation, no third pair moves. `tests/test_diplomacy.gd` asserts that acting
on Germany leaves `DEU|ITA` exactly at its resting value, so V1.3e replacing
the stopgap is a visible test change rather than a silent one.


### V1.4a — the firm register and subsidies (shipped)

The first content class in the project that is **not the face of something that
already exists**. U6b's "no new effect channel" held because a leader fronts a
nation and a party leader fronts a party; a firm fronts nothing, so V1.4 owns
`effects.company` — and `data/company-actions/` takes
`data/diplomatic-actions/`'s shape so that a, b and c share one content type the
way V1.3a's directory served five sessions.

**Firms are load-bearing on GDP without a second reconciliation.** A firm holds a
`share` of its sector and its output is read through it, so the partition is exact
by construction and `Economy._apply_growth_to_sectors()`'s existing GDP
reconciliation is untouched. What reaches the economy is two **deviation** terms
that read exactly 0.0 until a verb moves something, which is what let the whole
register go live with **every shared balance regime bit-identical**.

**Headcount follows share and not sector output**, and that is the file's sharpest
call: read off the level, a firm would hire every month the economy grew, which is
a second answer to the Okun term the macro model already owns. What a firm layer
adds is reallocation, and reallocation is all it should add.

**The probe corrected the model twice, ten sessions running.** A flat rival floor
made three different values of `SHARE_SHIFT_PER_MONTH` produce the identical
five-year outcome — the clamp-sets-the-number failure in a third place — and the
fix moved the model rather than the constant: a rival keeps half its **authored**
share, so the endpoint of a subsidy is content and the rate went back to setting
speed, re-chosen on a column that did not exist before the correction. Then
`SUBSIDY_GROWTH_BETA` at 0.30 had one firm worth more than a percentage point of
every tax at once, and came down to 0.20. The kill switch — the jobs channel
against a floor fixed before the sweep — **cleared**, at 0.229 points. Model:
[docs/companies-model.md](docs/companies-model.md).

**The screenshot pass earned its keep for the seventh session running**, and this
time both bugs were the tool's and the panel's rather than the model's: the ledger
figures ran underneath the scroll bar, and twenty-four ticked months were captured
under a top bar still showing the starting GDP — `--agenda` has always had that
second one and got away with it because nothing it does moves those figures. It
also found a live **U6b bug**: `_people_panel` was never added to
`main.gd`'s `_mark_all_dirty()`, so the People window refreshed once on the frame
it was built and never again.

### V1.4b — sector regulation (shipped)

**A regulation is a law, and that is the entire session boundary.** It reaches
`effects.company` through `Legislature.apply()` and an assembly division where a
subsidy reaches it directly through `Companies.execute()` — V1.3a's distinction
between a diplomatic action and a law, one block later. `src/core/law.gd` grew a
fifth `business` theme and a `_extract_company()` validator; `legislature.gd` grew
**one dispatch branch**. Nothing in `src/sim/` learned a new verb.

**One quantity, read twice, and no new channel.** `NationState.regulation_burden`
is a signed per-sector register written by `Legislature.apply()` and by nothing
else, priced through the two deviation channels V1.4a already built: a negative
term inside `firm_impulse_pct()` and a compliance factor inside `headcount()`,
which the existing `firm_jobs_offset_pct` picks up for free. That is V1.3c's "one
verb, two prices" **literally** — one quantity at two existing sites — where a
second growth impulse would have been a second machine wearing the phrase. No new
field beyond the register, no budget line, no clamp.

**`_extract_company()` refuses a firm id, and the refusal is the design.** Share
movement is the subsidy's persistent channel; a law that could name a firm would be
a second writer of it. The a/b split is in the schema, not only in the docs. And a
law carrying both `effects.company` and `structural_unemployment_pct` is a **load
error** — same act, same landing site, same units — which is the legislature model's
prose rule made mechanical for the one case where it could be.

**The probe corrected the content twice and itself once, eleven sessions running,
and not one correction was to the model.** Both channels were V1.4a's and already
measured; what was unmeasured was the content. The kill switch **cleared** at
0.0942 points against a floor of 0.05, and the standing prediction written before
the sweep — that agriculture cannot clear it at any sane value — **held exactly**, at
0.0083–0.0126, and is recorded as a structural bound. The first draft of
`data/laws/business.json` made the whole regulation stack **free**: +6.45 headline
against a ±3.0 floor, because the design rule said a regulation's losers must not be
named in `bloc_offset`. That rule was too broad, and the probe's own numbers say
why — a saturated burden moves growth ~0.1 %/yr and unemployment ~0.02 points,
**below the opinion model's resolution**, so the political price has to be authored.
Then the cost-against-buy table's unweighted `bloc_offset` sum hid two same-sector
dominations, one of which was fixed by **swapping two burdens** rather than retuning
offsets, because a safety regime genuinely is the heavier compliance load.

**`SAVE_VERSION` stays at 15 and the test pins it.** A version-15 save comes from a
game that could not pass a `business` law, so an absent register reads as every
burden 0.0 — which is the truth about that save, not a soft failure. Serialised all
the same, because a law writes it once and no tick recomputes it. The assertion that
the version is *still* 15 is left in place so V1.4c's ownership register has to come
and say why it bumps.

**The re-run is bit-identical across all fifteen existing regimes, predicted in
advance**, and the sixteenth was the **cheap kind**: `AMENDMENT_REGIMES` already
applies a law at a month, so only the content was new. Model, every constant and
every measured table: [docs/companies-model.md](docs/companies-model.md) §10–19.

### V1.4c — nationalisation and privatisation (shipped)

**Three fields on one register, three writers, one apiece.** `state_share` joins
`share` and `regulation_burden`, and the split is the whole of what V1.4 built: a
subsidy moves the first, an ownership op the second, a law the third.
`tests/test_save_load.gd`'s assertion that a serialised entry carries nothing beyond
`share` and `subsidy` was **turned red on purpose and widened by exactly one key** —
a fourth still fails, so a later session storing a baseline has to come and say why.

**A dividend is a yield on OUTPUT, and `companies-model.md` §13 called it a session
early.** `state_share × share × sector_output × DIVIDEND_YIELD`, with no margin,
profit or productivity quantity invented — owning margin whole is
[docs/tiers/v1.md](docs/tiers/v1.md) §6's ground and a re-baseline of every measured
number. It lands as the second computed **revenue** line after V1.3c's tariffs.

**The purchase and the windfall are a BALANCE-SHEET write, and that is the call that
paid for itself three times.** `Companies.execute()` writes `debt_eur_bn` — a capital
transaction is a swap, not income; every existing budget line is a standing rate; and
a one-off on the revenue side would move `deficit_pct_gdp` inside the month, which is
**a company action's own precondition field**. Writing the stock instead means the
interest is priced by `Budget.recompute()`, the level is read by the bloc's own
`debt_to_gdp_pct` rule, and it has been serialised since the MVP. **Nationalising a
champion can put the player in breach of a rule Brussels passed** — V1.3d meeting
V1.4c the way V1.3d met V1.3g.

**`SAVE_VERSION` stays at 15, which is not what the row expected**, and the test says
so. An absent `state_share` reads 0.0 — *the state owns nothing* — which is the truth
about every version-15 save. The dividend line is recomputed on the first tick, and
the purchase was never a field. The one thing that would have bumped it is a
`start_state_ownership` baseline for a thirteenth issue, and there is none.

**The probe corrected the model once and the content once, twelve sessions running**,
and the kill switch **cleared at 0.0942 points** with V1.4b's standing prediction
about agriculture holding exactly — because the shield's size *is* V1.4b's own jobs
price read from the other side, to the digit. `PRICE_TO_OUTPUT` had exactly one row
in band, the only sweep in the file where that happened. Model, every constant and
every measured table: [docs/companies-model.md](docs/companies-model.md) §20–29.

**The re-run is bit-identical across all sixteen existing regimes, predicted in
advance**, and the seventeenth is the *expensive* kind — an ownership op is a verb no
budget regime issues. A **no** on `ISSUE_KEYS` is what kept it clean, and that trade
was written down before the measurement rather than discovered after it.

**The screenshot pass earned its keep for the ninth session running, and two of its
three bugs were older than the session.** The date has read `01 JAN 2026` under every
tick-forward flag since `--agenda`, because a hand-rolled month loop moves the
simulation and leaves the Clock node alone — V1.4a found the same disagreement one
row up on the top bar and fixed only that. And **the budget panel has never had a
deployments row**: V1.3g wrote `_set_figure("deployments", …)` with no `FIGURE_ROWS`
entry, `_set_figure()` returns silently on an unknown key, and V1.4a then wrote
"beside the deployment line" about a line that was not there.

### V1.7 - the decomposition, and why these three

Written before any code, which is where a block-shaped row belongs.

| | Session | Content | Reads |
|---|---|---|---|
| **V1.7a** | ~~The campaign phase~~ **shipped** | A per-bloc **mobilisation** register in LOG-ODDS, read by `Elections.vote_share()` in place of the authored turnout constant, plus the **sixth** computed spending line - the second one that STOPS, and the first that stops on a date the player cannot move. `SAVE_VERSION` **stays 23** on three fields; re-run bit-identical in all 34 | - |
| **V1.7b** | ~~Campaign promises and the trust price~~ **shipped** | A pledge is a `{field, op, value}` triple on `PRECONDITION_FIELDS`' SHAPE but not its list, judged on a LEVEL **every month it is live** rather than once at the end - instance forty-two. The price needed no new quantity: it lands on `ns.bloc_offset`, so **(b) did not split**. `SAVE_VERSION` **stays 23**; re-run bit-identical in all 36 | a |
| **V1.7c** | ~~Electoral system choice and referendums~~ **shipped** | One shape, and **neither half was the shape this cell described**. `election_system` is lifted to `NationState` as predicted, but it is written by an **ORDINARY Act** and not by an amendment - instance forty-three, and the institutional whitelist split. A referendum is a **second ratification stage at a lower chamber bar**, not a bypass. Both stopgaps on [[amendment-model]] discharged. `SAVE_VERSION` **25** on three fields of four; re-run bit-identical in all 38 | - |

**Machine count is TWO, which is what makes it three sessions and not four.** The
campaign and the promise ledger are machines. Electoral-system choice is not:
`src/sim/electoral_systems.gd` already ships all five methods with a dispatch and
`INSTITUTIONAL_EFFECT_KEYS` already sets institutions absolutely, so it is V1.6c's credit
rating - *one extra read of something already built* - and that is why it shares a session
with the referendum rather than owning one.

**(b) was the row most likely to split**, recorded here in advance, and it **did not**.
The cut was the **trust quantity**: if the price could not land on an existing register
the way V1.5d landed legitimacy on the grievance, the ledger and the price were two
sessions. It landed on `ns.bloc_offset`, and the trigger was discharged by a measurement
taken before any content was authored rather than by an argument - [[docs/pledge-model.md]]
section 1.

**No V1.7 session ships a U-track machine**, so nothing here is expected to split on the
two-track rule that cut V1.6e and V1.6f. Recorded because two consecutive sessions did.

Four calls, each of which could have gone the other way:

1. **(a) is the campaign, and the deciding property is that it is the only one of the
   three that ships a VERB.** V1.3a's rule - state ships with a verb or it decays - and
   the block runs under it rather than under V1.5's inversion, because every bullet here
   is something a president DOES. Promises need the campaign to be made in; the
   institutional pair needs neither.
2. **Referendums join (c) rather than owning (d), and the reason is the schema.** A
   referendum exists precisely because a supermajority is sometimes unreachable, and
   [[amendment-model]] already carries `referendum_required` as a declared-unresolved
   amendment rule with *"V1.1f/V1.7"* written beside it. Building it is finishing that
   dispatch, not adding a machine - and the electoral-system key is the same edit to the
   same channel. Splitting them would be splitting on theme, and this page's split
   trigger has been machine count since V1.3e.
   <br>**Right about the session boundary and wrong about the argument for it, and V1.7c
   says so.** The nation whose supermajority is unreachable is Germany, and **Germany's
   constitution has no referendum route at all** (Art. 79) - so the collision this call
   names is true in the abstract and does not resolve for the nation it was named about.
   What actually made the two halves one session is narrower and held: both are edits to
   `effects.institutional`, and the interesting half is that they land on **different
   bars**.
3. **Messaging is a REFERENCE and not a machine, and the row said so before the block
   started.** Section 7's own bullet handed V1.5d the peacetime half with the condition
   attached. V1.5d built it and CUT the campaign-time twin, on the ground that damping
   hostile framing is `press_freedom`'s positive direction with a different label - one
   accumulator, two writers. So (a) reads it, and `tests/test_campaign.gd` fails if
   `campaign.gd` so much as names `framing_gain` or `press_freedom`.
4. **The campaign's target had to be FOUND, and two of the three candidates were
   refused.** Approval is the term's record and `vote_share()`'s own `pull` term already
   reads it, so a campaign term there is a second writer of the one quantity the whole
   game is judged on. Framing is refused by (3). What is left is **turnout**, which had
   no writer at all - and the distinction is the honest one rather than a convenience: a
   campaign does not change what people think of your record, it changes who bothers to
   vote on it.

**The row was wrong twice, and both were found by counting.** Instances **forty and
forty-one**.

- **"Time" names a currency this project MEASURED AND DELETED.** U6a swept a monthly
  budget of the player's days against a band fixed before the sweep ran and found it
  structurally unreachable: the median month offers 27 legal acts asking 124 days, so
  every budget from 4 to 24 bound in **100 %** of months. A ceiling that always binds is a
  cap, not an allocation. The reason carried forward there is not about calendars -
  `available()` returns what is *legal* and nothing models what the player *wants* - and
  it is exactly why a campaign priced in time would have rebuilt the deleted thing.
- **The section has no bullet for referendums and three other places point at it.**
  Section 1's own bullet list, the re-parked V1.1f row, and `nation.gd`'s
  `KNOWN_AMENDMENT_RULES` comment. The block cell below names four items and the section
  names three, and the missing one is the one with a declared stopgap in the code waiting
  on it. Cross-referenced into **both** rows.

**The orphan check came back CLEAN.** Every V1-tiered row in
[[docs/brainstorm/mechanics-governance.md]] - campaign phase, campaign promises, electoral
system choice, referendums - is named by section 7 or section 1, and decree / executive
order is Article 49.3, built at V1.1a.

### V1.7c - the referendum, and the row that was right about the channel and wrong about the bar

**Everything about the model, all four constants, the four corrections the probe made and
the two the screenshot pass made** is in
[docs/referendum-model.md](docs/referendum-model.md). The findings worth carrying out of
it:

**Instance forty-three is that `effects.institutional` is legal ONLY on a `constitutional`
law.** [[docs/tiers/v1.md]] section 7 asked for electoral-system choice as "a seventh
`effects.institutional` key", and `constitutional` forces `majority: "amendment"`, so the
row's own wording entrenches the electoral system at each nation's amendment threshold.
Electoral law is ordinary legislation in essentially all ten - France's code electoral,
changed by ordinary law in 1985 and again in 1986; Germany's Bundeswahlgesetz in 2023;
Italy's Rosatellum; Britain's ordinary Act. Right for GBR alone, and only because GBR's
`amendment_rule` already IS `ordinary_law`. So the whitelist **split**: two ordinary keys,
six entrenched ones, and an error string that names which rule was broken. That is
V1.4a/V1.4b's own split written into the schema rather than only into the docs, one block
later and in the other direction.

**The referendum is a SECOND RATIFICATION STAGE and the citations were already in the
data.** Not a bypass of the assembly: Art. 89 (FRA), Art. 138 (ITA), Art. 114 (LUX) and
Art. 195 (CHE) all put an ordinary chamber majority first, so the popular vote replaces
the **supermajority** and never the division. Every one of those was sitting in the nation
files' own `government.amendment._note`, authored at V1.2c for a mechanic that did not
exist. `government.amendment.referendum` is the **seventh** dispatch-on-a-data-string
field, and `referendum_required` gains an ordinary-majority seat fraction - what makes it
*mandatory* is the nation's own mode, not the table.

**THE POPULAR VOTE SHIPS NO TUNED CONSTANT.** It is `Elections.vote_share()` with two
options: YES at the law's own authored `position`, NO at the **size-weighted mean of
`BLOC_IDEAL`** - measured at (-0.230, +0.084), derived from a table written at S5 for
unrelated reasons rather than authored, V1.5d's mean anchor one block on. Affinity at the
existing `AFFINITY_SIGMA`, weights at `BLOC_SIZE x Campaign.turnout_of()`, and YES
carrying the incumbent's per-bloc pull on the existing `INCUMBENT_SWING`. Two properties
nobody authored fall out: a referendum held inside V1.7a's run-up reads the campaign's
mobilisation for free, and one held outside it reads `BLOC_TURNOUT` **bit-for-bit**. The
plan-time arithmetic predicted 45.8 % yes on `abolish_term_limits` and the live
measurement came back **0.458**.

**A KILL SWITCH THAT SWEEPS A RANGE THE PLAYER CANNOT REACH IS NOT A KILL SWITCH**, and
that is the session's sharpest correction. Table R1 swept approval 30 to 65 and CLEARED -
four of seven amendments winnable "somewhere". Table R6 then measured what a French
president actually holds under a budget they can stay in office on: **40.0 to 50.3** over
fourteen years, against a crossover at ~52. V1.3f's measuring-the-wrong-state error a
fifth time, in the file written to avoid it. The probe now measures the reachable range
FIRST and every approval band is written inside it; the escalation declared in advance,
`STATUS_QUO_PULL`, fired and was honoured rather than `INCUMBENT_SWING` being raised.

**The verb was unreachable twice, for two different reasons, and one fix was the model and
one was CONTENT.** First the chamber bar read as an absolute majority put route B at 270
of the 289 seats it needed in every one of 168 months; Art. 89's first stage is the
ordinary legislative procedure, a majority of votes CAST. Then France's only amendment,
`abolish_term_limits`, is rejected **270-307** by its own assembly. A position sweep found
a real window - economic -0.4 to -0.2, social -0.1 to 0.0, yes-seat fraction 0.534-0.551,
**above an ordinary majority and below 3/5** - and that window IS the referendum.
`single_term_reform` is authored into it, the Jospin commission's *mandat unique*.
V1.4b's discipline: the fix that is also true is the better fix.

**Withdrawing costs exactly what losing costs, and that is a PROOF rather than a second
constant.** A withdrawal charges the same offset and sets the same cooldown, so holding
the vote weakly dominates it by construction: the two outcomes are identical except that
holding it might carry. A withdrawal priced below a loss is the free-hedge shape this
project has killed ten times; one priced above needs a number solved against the first,
which `investment_action.gd` refuses as one strength written twice.

**No new tick anywhere.** `Legislature.tick_month()` already existed and is already called
by `main.gd`, `balance_probe.gd`, `test_balance.gd` and eight probes, so the countdown and
the settlement go there - V1.6a's argument taken deliberately, making V1.5d's bug
structurally impossible rather than remembered. Its signature widens to
`tick_month(state, loader)`, required and not defaulted. `src/sim/referendum.gd` is a
**leaf**: `resolve_due()` returns the verdict as DATA and `legislature.gd` applies the
law, U6a's `Calendar.due()` one block on, and `tests/test_referendum.gd` reads the source
to say so.

**The re-run is bit-identical in every printed FIGURE across all 38 shared regimes,
predicted in advance, and the one line that moved names a LAW rather than a number.**
`managed_books_ahead` books "the first proposable law" and the new amendment sits first
in `data/laws/amendments.json`, so the diary row reads `Single-Term Presidency Act` where
it read `Term Limits Abolition Amendment` - a content-ordering artefact, and a latent
fragility in that regime worth naming rather than fixing here. Two new regimes, both the
**expensive kind**: a referendum and an electoral-reform Act are verbs no budget regime
issues.

**The legibility evidence is exact and it costs a term.** Same budget, `managed` against
`managed_calls_a_referendum`: GDP, growth, trend, unemployment, debt and deficit are
**identical to the digit** in every year the two share (2032: 3084, +1.27, +1.31, 7.67,
125.2, −2.86), and approval is **56.7 against 49.3** with the worst bloc at rural 52
against rural 45. The referendum carried, the mandate is worth **+7.4 points**, and the
president is **out of office in 2032** - termed out by the very amendment they won,
where `managed` holds a second term at 26.7 %. The electoral half is visible in the
assembly rather than in the figures: after June 2029, `managed_reforms_the_ballot`
governs on **326 of 577** where `managed` has **377**, because the power law's
amplification of the largest party is gone. "Producing visibly different assemblies" is
the row's own phrase, measured.

**The nineteenth screenshot pass found one bug and it was the readout's**: the session
made `election_system` live state and left **no surface saying which one is live**, so a
player who passed the Proportional Representation Act could not read that it had taken
effect until the next legislative election three years later. A lever whose only feedback
is a three-year wait has no readout at all. `government_panel.gd` now names the method
and its threshold beside the amendment rule, and unlike the referendum line it is
**never silent** - an absent referendum route is a fact most constitutions simply do not
have, where every assembly in the world is elected somehow.

**Germany gets nothing, and the decomposition expected otherwise.** Art. 79 provides no
referendum at any stage, so Germany's measurably unreachable `two_thirds` is unchanged and
`restore_the_monarchy` stays unpassable content. Recorded rather than fixed.

### V1.7a - the campaign phase, and the row answered by a deletion

**Everything about the model, both bands, all four constants, the five corrections the
probe made and the two the screenshot pass made** is in
[docs/campaign-model.md](docs/campaign-model.md). The four findings worth carrying out of
it:

**A band must be anchored on something the model already measures, and this one was
invented twice before it was.** The first clause read *"at least 0.50 points of vote
share"* - a number picked because it sounded like a margin - and every candidate failed
against it while the table never said whether 0.50 was the right ruler. It was not. The
only other thing that moves `Elections.vote_share()` at all is **approval**, through the
`pull` term, so the band is written in points of approval: at least what ONE point is
worth (below that governing swamps it) and at most what the **poll floor** is worth (above
that a campaign substitutes for the record). Measured: 0.3415 and 1.0147 points of vote
share. V1.6a's *prefer a fit to a band* one step further out - prefer an ANCHOR to a
number.

**Maximin slack, which is this page's own tiebreaker rules taken one step further.**
V1.5d established that where two model criteria bound a quantity from opposite sides
neither edge selects and the interior governs. But *the interior of a passing LIST* is a
statement about the grid, and V1.5b's whole finding was that a grid must never choose. The
interior of the **feasible region** needs no grid: take the candidate whose WORST relative
slack is largest. It is stable under refinement, stable under widening, and it degrades
correctly - where one criterion is far looser than the other it returns the edge of the
tighter one, which is what a bound should do. `CAMPAIGN_WINDOW_MONTHS` = **8**, at 23.1 %.

**A binding guard rail can INVERT a decision rather than merely set a number.** This
project has caught `IMPULSE_MAX`'s failure five times, always as *the clamp is setting the
number*. Here `MOBILISATION_MAX` at 0.60 did worse: once the accumulator saturates a
LONGER run-up is strictly worse, because it costs more months of bill for exactly the same
reach - so the clamp was not setting the timing decision the whole lever exists to pose,
it was reversing it. At 0.90 the worst reachable stack is 0.6800, slack by 0.2200.

**And MAXIMISING YOUR OWN VOTE SHARE IS NOT THE SAME AS WINNING**, which nobody authored.
`Elections.vote_share()` renormalises per bloc, so turnout is a rising tide inside a bloc
rather than a transfer between parties - and the parties nearest you in ideology space are
exactly the ones sharing your voters. The pair that best raises France's incumbent's share
(+0.4204) NARROWS their lead (-0.4033); the pair that best widens the lead (+0.6475)
LOWERS their share (-0.2417). Under a plurality verdict the quantity to maximise is the
lead, so the best play can be a campaign that lowers your own vote. Recorded rather than
fixed: it is a property of [[election-model]]'s vote-share model, not a defect in this one.

### V1.6 - the decomposition, and why these five

Written before any code, which is where a block-shaped row belongs: V1.6 was five
bullets plus an obligation inherited from V1.4c, and one line is not a session.

| | Session | Content | Reads |
|---|---|---|---|
| **V1.6a** | ~~The business cycle~~ **shipped** | A **stateless** deterministic shock over all ten nations, into `economy.gd`'s growth sum. Amplitude **fitted** to France's measured growth volatility, per-nation spread **imported**, common share **measured twice**. `SAVE_VERSION` **19**. Re-baselined V1.5c's two constants and found them unchanged | - |
| **V1.6b** | ~~Inflation~~ **shipped** | A stock on the **unemployment gap**, not the output gap -- the row's three named inputs are one quantity written three times AND the measurement refuted the survivor. No nominal layer. Two prices: a growth addend and the **thirteenth `ISSUE_KEYS` entry**, the first YES after five noes. Three constants measured, two swept. `SAVE_VERSION` **20** on three fields of four | a |
| **V1.6c** | ~~Bond yields and the credit rating~~ **shipped** | `DEBT_REAL_RATE_PCT` is the **anchor** and the spread reads exactly 0.0 at new game. **TWO of the four named inputs do not exist**: the deficit is the debt's derivative (`corr` 0.9948) and inflation cannot reach a real rate. The rating is stateless, pinned in the save format. V1.4c's obligation discharged **on a rate**. `SAVE_VERSION` **21** | a, b |
| **V1.6d** | ~~Five taxes and brackets~~ **shipped** | Capital gains and wealth as `TAX_KEYS` 4 and 5, brackets *within* income as a base factor. The Gini stopgap is discharged by a **derived read** -- not the second field this table asked for, because none is needed. `GC.TAX.*` covers 10 of 10 and is still unusable (central government, and capital gains bucketed WITH income). `ISSUE_KEYS` answered YES **twice at once** at -0.739 %. `SAVE_VERSION` **22**. Three new regimes | - |
| **V1.6e** | ~~Sectoral investment and infrastructure projects~~ **shipped, and it SPLIT** | A capital stock per sector on the sector's own **trend rate** -- `sector_output` has no room for a second writer, measured. No employment term, and that is a CONSEQUENCE rather than a prohibition. The bill scales with the sector's share, which DELETED a constant. `SAVE_VERSION` **stays 22**; re-run bit-identical in all 32 | a, d |
| **V1.6f** | ~~Infrastructure projects~~ **shipped, and it SPLIT AGAIN** | A discrete dated commitment that bills while it builds and pays **once** when it opens, on `_update_potential_shift()`'s TARGET - `law_potential_target_pct`'s shape, so **no third quantity reaches trend**. No second scheduler: U6a's register is a deferred COMMAND, and what was reused is the diary, for zero preloads. The bill is the first computed line that STOPS. `SAVE_VERSION` **23** on the DONE half of one dictionary; re-run bit-identical in all 34. **The map half was U6c, now built** | a, c, e |

*(V1.6c's own numbers, and the two rows it deleted, are under* **V1.6c - the bond
market, and two of four inputs that were not there** *below.)*

**Machine count is five, which is what splits it** -- the cycle, inflation, the bond
market, the distribution, and the sector lever. [[foreign-policy-model|V1.3e]]'s
trigger. Two things the row reads as machines and that are not: the **credit rating**
(one extra read of the yield, `Defence.allies()`'s shape) and the **procyclical
dividend** (booked as free, and refuted -- see below).

**(e) is the row most likely to split**, recorded here in advance the way this page
recorded V1.3e (which split) and V1.5d (which did not). The cut is **infrastructure
projects -> (f)**, and the reason is architectural rather than a fourth feature: a
*rate at a sector* and a *discrete dated commitment* are different shapes, and the
second is a scheduler.

**IT SPLIT, AND THE PREDICTED REASON WAS TRUE WITHOUT BEING THE BINDING ONE.** Counting
put projects at three machines of five, and the third is the one this row drops: *visible
on the map* is a marker on `map_view` with per-project geography as content, which is a
**U-track surface**. This project runs one track per session. "A scheduler" is an argument
about shape; the two-track rule is a rule, and it is what actually decides. Recorded
because the next row predicting a split should predict the reason as well as the fact.

**AND THEN V1.6f SPLIT ON THE SAME RULE, WHICH NO ROW ON THIS PAGE HAD DONE BEFORE.**
Recounted at the start of that session, what was left was two S-track machines - the
in-flight register and the payoff-plus-bill - and the one U-track machine above. Two
consecutive sessions cut on the same clause; the rule did not need re-arguing the second
time, which is what a rule is for. **The map was U6c, and it is built** - the last piece of
section 6, and the session that found instance thirty-nine in the phrase this page used
three times: geography is per-NATION, not per-project.

Four calls, each of which could have gone the other way:

1. **(a) is the cycle, and the deciding property is that everything else is measured
   against it.** Every V1.5 constant was measured on a flat cycle and owes a
   re-baseline; measuring section 6's own constants flat and adding the cycle at (c)
   or (d) is that mistake repeated inside the block that inherits it. It is also
   policy-independent, which is [[society-model|V1.5a]]'s own deciding property, and
   it is the only section 6 item that re-baselines *another block's* constants.
2. **Section 6 runs under BOTH block rules, and the decomposition says which per
   session.** V1.3a's rule was *state ships with a verb or it decays*; V1.5 inverted
   it to *every session ships a statistic and the price it charges*. Section 6 is
   genuinely half each. (a), (b) and (c) ship **no verb at all** --
   [[mechanics-economy]] tiers the central bank and interest rates **Someday** and
   [[out-of-scope-mvp]] records that France does not set its own rate, so inflation
   and the cycle are pressures with no dedicated lever -- while (d) and (e) ship
   verbs. Neither is a compromise.
3. **The V1.4c obligation splits, and the row files it under the wrong owner.**
   Section 6 files "the risk a state-owned firm carries" under *inflation and the
   business cycle*. `companies_constants.gd`'s own comment shows why that is half
   right: the yield equals `DEBT_REAL_RATE_PCT` because there is "no risk and no
   business cycle for an equity premium to be compensation FOR" -- two clauses, and
   only the second needs a borrowing rate that moves. **(a)'s probe then refuted the
   first half as well**, so the whole obligation went to (c). See below.
4. **The stopgap discharge needs a SECOND FIELD, not a second writer.** `gini_index`'s
   single writer is `Demography.tick_month()`, and `tests/test_unrest.gd` *and*
   `tests/test_demography.gd` both read the source and fail if a second appears --
   `share`/`state_share`/`regulation_burden`'s discipline. So (d) writes a policy
   offset and the effective index is a derived read, recorded here so (d) does not
   discover it as a test failure.

**The row was wrong twice, and both were found by counting.** Instances **twenty-seven
and twenty-eight**.

- **"Infrastructure projects" names a machine that has existed since S4, and the row
  merges two mechanics into one bullet.** `economy.gd`'s `_update_potential_shift()`
  has been a first-order lag on sustained infrastructure spending at `INFRA_BETA` for
  six blocks -- and V1.5's own decomposition named `potential_shift_pct` as
  "education's *and* infrastructure's, since S4" while catching only the education
  half. [[mechanics-economy]] tiers them as **two** mechanics with different sketches,
  and the row drops that page's *"visible on the map"* clause entirely -- a surface
  U5b and U5c built and that no section 6 bullet mentions. That is what makes (e) the
  split candidate.
- **"Arriving whether or not deserved" collides with the model's hardest rule, and the
  resolution was already in the repo.** [[economy-model]] forbids randomness outright,
  because determinism is what makes `Budget.project()` exactly equal to what follows --
  a done-when condition. `poll_noise.gd` solved the same problem from the other side
  with a pure function of (id, key). And the property the row actually asks for is
  **attribution, not surprise**: a downturn you did not cause and are judged on anyway.
  That survives a cycle the player can see coming, and (a) found it survives it
  *because* of the poll floor rather than despite it.

**The orphan check came back CLEAN, which is itself the finding.** Every V1-tiered
mechanic in [[mechanics-economy]] is named by a section 6 bullet or already built --
tariffs at V1.3c, the whole private-companies table at V1.4. Section 5's row missed
eight; section 6 misses none. What section 6 gets wrong is a merge and an owner, not a
gap.

### V1.6f - infrastructure projects, and the bill that is not the cost

**The row never says what a project's PAYOFF IS**, which is V1.6b's instance thirty in a
new place and instance **thirty-seven** on this page's count. The answer was already in the
model rather than needing inventing: `ns.law_potential_target_pct` is a permanent
accumulator with its own bound added to `Economy._update_potential_shift()`'s target, and
**a passed law and a finished project are the same act** - a one-time decision producing a
permanent addend. So the payoff is the **sixth writer of that target**, V1.6f adds **no
third quantity reaching trend**, and `economy_constants.SHIFT_MAX_PCT`'s comment - which
V1.6e had to amend - needed no second amendment and now records that it was checked.

**Instance thirty-eight: "slow" was already half spent.** `SHIFT_ADJUST` is a five-year lag
on that target - t50 **41.2 months**, t90 **137.0** - so a build of N months *and then* that
lag are two answers to `mechanics-economy.md`'s one word. A band on the build length alone
would have measured half the wait, so the band is written on the **delivered fraction from
commit** instead, and solved: the shortest project must build in <= 38.8 months to hand back
0.30 inside a presidential term, and the longest must take > 60 so it hands back nothing
inside one. The escalation trigger - *if no legal build length can clear it, SHIFT_ADJUST's
own lag is binding and the response is to shorten the BUILD, never SHIFT_ADJUST* - did not
fire.

**U6a's `appointments` register was checked before a second scheduler was written, and it
is NOT this machine.** That register holds a **deferred command**: `due()` fires it once,
`main.gd` runs a verb that already exists, `Calendar.cancel()` is free and leaves no trace,
and `calendar.gd` preloads no system **by design**. A project is a **commitment in flight** -
it bills every month, it can be abandoned part-built, and half a motorway is not free. What
IS reused is the **surface**: `Calendar.fixed_dates()` gained one row per build and **no
preload at all**, because the register counts **months remaining**, the idiom every other
countdown in this project already uses. `src/sim/projects.gd` does no date arithmetic, and
`tests/test_projects.gd` asserts the calendar is still a leaf.

**The probe corrected the session three times, seventeen sessions running, and the first is
the block's closing finding.** The cost clause was written on the **bill** - the largest
permitted stack is 0.5200 against a 0.5639 headroom - and the measured peak deficit came
back at **0.7615**. Banded on the measured peak instead and solved to a fixed relation:
`peak = 1.4626 x stack`, so **every point of project bill costs 1.46 points of deficit**,
the stack may reach 0.3875, and the re-authored ladder ships at 0.3600. The second: the
uniform-scale sweep that found it then **declared escalation trigger 2** - the largest scale
that fits takes the cheapest project under its legibility floor - and that was a statement
about the sweep rather than about the model, because clause (i) binds the CHEAPEST project
and clause (ii) the DEAREST PAIR, so one multiplier cannot satisfy both and the free
variable is the ladder's SPREAD. V1.5b's *the range was choosing the constant*, with the
range one dimension short. The third: the abandonment price was measured against a president
who never began, so all five rows read the net of a start and a cancellation taken in the
same month - about -0.02 of offset, under the floor, and **identical across five projects
that are not alike**, which is what gave it away. **And a fourth was the probe reading its
own prose**: the boundary check for "does this module touch the employment path" matched
`projects.gd`'s header, which argues about it. A check a COMMENT can fail is a check the
next comment will quietly break.

**The model ships no cost, speed or strength constant, and that is the session's shape.**
V1.6e had one dial and three constants turning it into a bill, a build rate and a trend
coefficient, so `investment_action.gd` refuses a second authored term as one strength
written twice. Here there is no such constant, so **duration, price and payoff are three
independent facts** about a named object and the validator requires all three. What is left
in `projects_constants.gd` is bounds - and **a concurrency ceiling was considered and is not
there**, because how many may run at once is the `project_count` precondition every action
carries, which makes it content.

**Cost per unit of payoff FALLS with size and what buys the discount is TIME.** That is the
only reason a big project is not strictly dominated by three small ones, and the probe checks
it as a standing test rather than asserting it: **0 dominated pairs**, and the largest project
cannot deliver anything at all inside the term that signs it. **The kill switch cleared at
+0.2621 %/yr** and four of five sit below the floor, which is that shape rather than a miss.
**A programme you can stop; a project you can only abandon** - V1.6e's withdrawal leaves 63 %
of its capital standing a year on and an abandonment leaves nothing.

**The seventeenth `ISSUE_KEYS` question is answered NO on test 1**, as V1.6e's was and for
the same reason, and the interesting half is that **two consecutive sessions failed the same
test for the same reason**: a session that ships a content object has somewhere to put the
price and a session that ships only a statistic does not. That, and not importance, has
decided all seventeen. `SAVE_VERSION` is **23**, earned by the **DONE half** of one
dictionary - V1.3g's `deployments` split in a new place, and the split is worth more than the
bump. **The re-run is bit-identical across all 34 shared regimes**, predicted in advance, with
**two new regimes of the expensive kind**, both surviving both presidential elections. Same
budget, `managed` against `public_works` in 2037: GDP 3340 -> **3354**, trend +1.31 ->
**+1.53**, worst bloc rural 43 -> **38**, and **unemployment 7.67 in both** - V1.6e's own
no-jobs finding visible in the harness one landing site further out.

**The fifteenth screenshot pass found two bugs and both were the readout's.** The budget
row shipped as `0.19% (6 bn) (1 building)` and that cell is **wider than any other on the
panel** -- both value columns size to their widest row, so one extra clause on one row
pushed the whole `proposed` column past the window edge and put the budget on a horizontal
scroll bar it had never needed. The number was right and the frame still showed a budget
the player could not read without dragging; the count moved to Public Works and
`Budget.snapshot()` lost the two keys nothing then read. And the diary read **"Opens: Build
the High-Speed Rail Spine"**, because the only name in the content was the ACTION's -- an
imperative, right on a button and wrong after a colon -- so `effects.project` gained an
authored `project_name`, deliberately NOT in the three-quantity term list, because a name
is not a strength.

Full argument: [[projects-model]].

### V1.6e - sectoral investment, and the write the model refuses

**The row asks for a lever "on `sector_output` itself", and that quantity cannot have a
second writer.** `Economy._apply_growth_to_sectors()` grows each sector at its own rate,
distributes the residual by cyclical beta and ends with `ns.gdp_eur_bn = total` -- the
sector sum IS the month's GDP target by construction. The probe measures rather than
asserts it: 27.9 bn injected into French industry before a tick leaves GDP **+0.024 bn**
against the control and moves the industry share +0.006. **A write to `sector_output`
survives as composition and never as level.** Instance **thirty-five**.

What has room is the per-sector TREND RATE, the slot `Trade.sector_shift()` already
occupies -- and the difference between the two is the whole of why one is a lever and the
other a reallocation: **a trade shift must sum to zero, an investment shift must not**.
So the shift is read at BOTH of `economy.gd`'s sites, and adding it at `trend_pct()` as
well as inside the sector loop is what stops the residual taking the level effect straight
back. **The probe found the same leak in code that was already there**: the trade shift
sums to zero as raw points but `trend_pct()` share-weights, so `industrial_compact` at
France is **-0.1538** share-weighted and the residual absorbs it. Recorded rather than
repaired -- a composition-only term losing its level to the residual is correct behaviour,
and only `_apply_growth_to_sectors()`'s comment is stale.

**Instance thirty-six: "carries no employment term" is a CONSEQUENCE, not a prohibition.**
V1.4b earned its jobs price because jobs-per-share is firm content -- but Okun reads
`growth - trend` and structural unemployment reads only the tax wedge, the law offset and
the firm layer, so **a term that raises trend has no permanent employment channel available
to it at all**. *Sectoral investment buys output and, in the long run, no jobs.* Pinned
bit-identically in `tests/test_sectors.gd`, and visible in the harness rather than only in a
test: same budget, `industrial_policy` prints the **identical unemployment as `managed` in
every printed year** while GDP diverges 4.9 % and the rural row falls 43 -> 38.

**The probe corrected the model twice, sixteen sessions running, and the first is the
strictly-dominated shape appearing in a PRICE.** Six previous instances were all in
effects; here the effect was proportionate and the BILL was flat, so backing French
services moved growth 0.4865 points and backing French agriculture 0.0077 for identical
money -- sixty-three to one. The fix scales the bill with the sector's own share of GDP: the
return per euro is then the same wherever it is spent, *which sector* goes back to being a
question about composition and politics, and it adds **no constant**. It also **deleted**
one -- the three shares sum to exactly 1.0, so the whole bill is bounded above by
`INVESTMENT_COST_PCT_GDP` itself and `INVESTMENT_BILL_MAX_PCT_GDP` was a guard rail
guarding arithmetic. U6a's treatment of the day budget, one block on.

**The second correction is V1.6d's own finding arriving in the session after it.** The
beta band's clause (ii) -- *stays under `SHIFT_MAX_PCT`* -- is true at every candidate above
the clamp point BY THE CLAMP, so a grid wide enough to reach it reports an interval whose
upper edge is a guard rail. Clause (ii) reads the unclamped shift now and both columns are
printed. **And a third the grid nearly caused**: two of the three constants are closed form
and the first run still reported the widest PASSING GRID ROW as the interval -- 0.40 where
the exact edge is 0.46. That is V1.5b's *the range was choosing the constant* in the one
place it should have been impossible.

**All three constants are closed form or fitted to a fixed point**, which is the strongest
first-pass position this project has reached. `INVESTMENT_COST_PCT_GDP` = **0.8161**, the
midpoint of an interval whose lower edge is `0.20 / 0.7930` (France's services share) and
whose upper edge is what [[tax-model|V1.6d]] left of `DEFICIT_SCALE_PP` -- **the one thing
this session was told to measure before assuming there was room**, 1.38 points of a
six-point span. `CAPITAL_CONVERGENCE` = **0.4518**, the midpoint taken in MONTHS rather than
in the rate because the band is written in months and the map is convex; t90 = 60.0 exactly,
which lands on `SHIFT_ADJUST`'s own five-year constant and nothing arranged that.
`SECTOR_TREND_BETA` = **0.7124**, measured by exact emulation and **iterated to a fixed
point** in one pass.

**The kill switch cleared at 0.5760 and two of three sectors are below the floor.** That is
a structural bound recorded rather than tuned around: the lever's power is proportional to
the sector's share, French agriculture is 1.4 % of GDP, and nothing a president does to it
moves France -- V1.4b's own agriculture prediction from the other direction. The
share-scaled price is what stops it being a trap. **Escalation trigger 1 did not fire**: a
year after withdrawal 63 % of the capital is still standing, so a withdrawal is not a
demolition and no asymmetric second rate was added. The guard rail is **slack** at 0.7053
against 1.00.

**The sixteenth `ISSUE_KEYS` question is answered NO, on test 1 alone.** Every YES on that
list was paid because the price was not nameable otherwise -- inflation ships no content
object and a tax has no `data/taxes/`. This ships `data/investment-actions/` WITH an
authored `bloc_offset`, which is exactly what `ownership` had at V1.4c. The S10 ratio was
deliberately not swept, on V1.5a's ground. What was measured instead is that the authored
price is legible: the three largest packages move their worst bloc **+5.80, +5.27 and
-6.14** against a +-3.0 floor while moving the headline +0.31, +1.31 and -1.08 -- clearing
on the per-bloc rows and on none of the headlines, which is V1.3a's finding used as designed.

`SAVE_VERSION` stays **22** and the test says why: an absent register reads as no programme
and nothing built, which is the truth about every version-22 save. Serialised anyway,
because no tick re-derives the capital from content, and the test **checks that premise**
rather than asserting it. **The re-run is bit-identical across all 32 shared regimes**, as
predicted, with **two new regimes** of the expensive kind -- an investment programme is a
verb no budget regime issues, and both new ones survive both presidential elections.

**The fourteenth screenshot pass found one bug and it was the tool's.** The first frame of
`--invest` showed the ledger reading a live 0.654 % of GDP and +0.513 %/yr against three
sector rows all saying *"No state programme"*, because the sector the flag had backed is the
last of the three and sits below the fold of a panel that scrolls by design. **The figures
were right and the frame was still evidence for the wrong claim.** The flag pins the panel
to the bottom now. The window's title also changed, "Companies" -> "Industry", because the
panel is no longer only about firms; the id is untouched.

Full argument: [[sector-model]].

### V1.6d - five taxes, and the tripwire that could not fire

**Step 0 inverted its own prediction, and that is the row's first finding.** The session
was told to expect the World Bank government-finance branch to be as thin as (c) found
it. It is not: `GC.TAX.TOTL.GD.ZS`, `GC.TAX.YPKG.*` and `GC.TAX.GSRV.RV.ZS` all cover
**10 of 10** nations with 30-35 rows each. **Coverage was never the problem.** What rules
them out is universe and granularity -- `GC.*` is CENTRAL government, so France reads
22.78 % of GDP against the 46.1 its own file carries and Switzerland 9.45 against 27.8,
which [[data-sources]] rejected at S1 in almost these words; and `GC.TAX.YPKG.*` puts
income, profits **and capital gains** in one bucket, which is precisely the split the
session exists to create. There is no property series at all. So both base shares are
authored, exactly like the three already there, and the check **confirmed a standing
rejection rather than discovering one**.

**Instance thirty-two: the wealth tax is not on the other four's rate scale, and three
shared tables assumed it was.** Its base is a **stock** at 4.00x GDP against income's
0.50 flow, so one point of wealth rate is eight points of income tax in revenue.
`opinion_constants.TAX_SCALE_PP` was shared by every key in POINTS OF RATE and had to
become per-key; and `Budget._erosion()` returned a flat **1.0** when a nation's own
starting rate was zero, so revenue was linear in the rate forever -- correct for a tax
nobody has, and a live exploit the moment a player invents one, which this session's
content makes reachable on the first frame (Switzerland taxes no private capital gain,
eight of the ten have no wealth tax). **The zero reference had to be per key too**: one
shared value put an invented capital-gains tax's revenue peak at three points against
real rates of twenty-five. One constant cannot serve two rate scales, found twice inside
one session.

**Instance thirty-three: the row asks the `ISSUE_KEYS` question without noticing.** Its
own criterion -- *each new tax earns its row by having a visibly different bloc-weight
profile* -- **is V1.3d's collinearity test restated in content terms**. Answered **YES
twice at once**, a first, and at a measured cost in the **unsafe** direction: the S10
ratio drifts **-0.739 %** against V1.3d's accepted +0.39 % and V1.4c's refused -1.46 %.
It is paid because **the alternative is not a cheaper price but no price at all** --
`opinion.gd` writes a satisfaction for every `TAX_KEYS` entry, so a tax with no key is a
number nothing weighs, and the wealth lever would then collect **4.2 points of GDP for
free**. Where V1.4c differs is that `ownership` had an authored `bloc_offset` to be
priced on instead; a tax has no content object anywhere. **The first rows drifted
-1.640 % and the fix was CONTENT rather than a constant** -- V1.3d's own move -- because
the flat-weight control drifts only **-0.106 %**, so the cause is the profile: the first
rows gave two taxes eight of the ten barely levy **twice** `tax_corporate`'s share of the
national agenda.

**Instance thirty-four is that V1.5c's tripwire did not fire, and could never have.**
That test mutates the corporate rate, every `state_share` and every `regulation_burden`
and requires the Gini to be bit-identical; it was written to go red the day section 6
landed. Section 6 landed and it still passes -- because **those three are the three
section 6 does not own**. Its instruments are brackets, capital gains and wealth. The
tripwire was armed against the instruments the model ALREADY HAD rather than the ones
that were coming. The old assertion is kept, being still true and still worth pinning,
and the real tripwire is added beside it.

**The discharge needs no second field, where the decomposition's call 4 asked for one.**
`Tax.gini_policy_offset()` is a pure function of the schedule and two rates the save
already carries, so `Demography.tick_month()` stays the single writer, nothing is stored,
and both read-the-file checks pass untouched -- `Defence.allies()`' shape and
`Credit.rating()`'s one session on.

**Two constants are banded, three are FITTED, and one band was found unable to select.**
`PROGRESSIVITY_BASE_BETA` ships at the midpoint of a **closed-form** interval, so no grid
can move it. The three Gini betas are fitted to the widest measured roster drift over one
term (NLD, 2.085 points) and land on a **fixed point**. `TAX_SCALE_PP_BY_KEY`'s
pre-committed band **could not discriminate**: clause (i) passed at every candidate with
the identical approval move, because the whole reachable move saturates the satisfaction
at every scale -- so it was measuring the clamp -- and clause (ii) reduces to a
rearranged inequality. V1.5a's two failures at once in one row, replaced by a fit against
`TAX_SCALE_PP`'s own fraction of income's reachable span. **The kill switch cleared** and
had to be isolated first: the version that committed real budgets showed a *flatter*
schedule making the country CALMER, because flattening narrows the deficit. Isolated, the
offset moves the first strike **27 -> 26 / 29 / 32** months. **`GINI_POLICY_MAX_PT`'s
first value bound** at half the roster's Gini span, and it is the whole span instead.

**The escalation trigger is recorded rather than retuned**: the two new taxes alone move
**77 %** of `DEFICIT_SCALE_PP`'s six-point span, which is under it, so the pre-committed
response applies -- retuning that constant re-baselines every opinion constant measured
since S5.

**The re-run is not bit-identical, the prediction said so, and the REASON given was
wrong** -- recorded rather than quietly corrected. The plan expected float ordering from
five revenue keys plus a smaller residual; what actually moves is the **salience
simplex**, which two new issue keys renormalise, reaching approval, then `hardship()`,
then the grievance, then V1.6c's yield. **Trend is bit-identical in all 217 printed
year-rows**, GDP, growth and unemployment in 216, approval's worst move is **0.90** under
the +-3.0 floor, and there is **one outcome change of 51** -- `tinkering` 2032, the
regime V1.6c's own re-run flipped, flipping back. **Three new regimes**, needed because
every existing one sets three tax keys and no schedule, so the whole session was
structurally unreachable by all 29: V1.3a's rule returning for the first time in this
block.

**The thirteenth screenshot pass found two bugs after V1.6c's clean sheet**, and the
sharper is about a defensive default: `Budget.snapshot()` never carried the new figure at
all, the panel read it with `.get(key, 0.0)`, and the row printed a confident **0.00**
against a live 31.80. A default that hides a missing key is worse than a crash. The
second is **a live bug recorded rather than fixed**: `budget_panel.gd` refreshes from a
`_pending` captured in `setup()`, so a budget committed by anything but its own sliders
leaves the panel stale and offering to undo it -- and `Legislature.apply()` commits tax
changes in exactly that way. Fixing it needs a design call about a player's half-finished
edits, so the tool re-syncs and [[tax-model]] section 11 carries the bug.

Full argument: [[tax-model]].

### V1.6c - the bond market, and two of four inputs that were not there

**The row asks the yield to read debt, deficit, `unrest_pct` and inflation. Two of the
four do not survive, and both were killed by measurement rather than by argument.**

**`DEBT_REAL_RATE_PCT` stays the ANCHOR, which is the call that kept the re-baseline
bounded.** It is flat at 2.0, it is the entire fiscal pressure of the MVP, and every
balance number this project has ever measured is quoted against it. The yield is that
constant plus a spread whose every input is a deviation against the nation's **own
start**, so the spread reads **exactly 0.0** at new game -- `trade_baseline_by_partner`'s
and inflation's idiom, and V1.5d's six framing gains averaging back to the one. The
alternative, a yield on the absolute debt level, gives the ten different opening ratings
and changes France's debt service on frame 1; it is also mostly decorative, since only
the player has a budget.

**Step 0 looked for a sovereign-rate series before writing a band, and there is not one.**
`FR.INR.RINR` covers **4 of 10** on disjoint windows with France carrying zero rows;
`GC.DOD.TOTL.GD.ZS` covers 7 of 10 with four of them under five years. OECD `IRLTLT01`
carries it and [[data-sources]] already rejected the IMF WEO on redistribution terms. So
the slopes are swept, and that is a checked result rather than the reach for a band this
page keeps warning about. **The cross-check then nearly agreed**: the empirical range is
0.02-0.05 and the swept answer is **0.0150**, a factor of 1.3 rather than an order of
magnitude. What excludes an honest 0.02 is the **opinion model's resolution**, not the
bond market -- at 0.02 a do-nothing president's debt service uses half of
`DEFICIT_SCALE_PP`'s whole span on its own.

**Instance thirty-one: the deficit is the DERIVATIVE of the debt.** That was a suspicion
and not a result -- a level and a trajectory really are different information -- and the
sweep is what settled it. Three clauses, mutually inconsistent: isolated against a
control the deficit term is legible only above a slope of 0.20, and by 0.145 it already
outweighs twelve months of the level it exists to lead. `corr(debt gap, deficit gap)`
measured **0.9948** against the standard V1.6b used, 0.3185. Deleting it removed the
session's **only positive feedback loop** with it, because `debt_service_pct_gdp` is
*inside* `deficit_pct_gdp`.

**The inflation term was deleted DESPITE PASSING ITS BAND, and that is the sharper
finding.** 2 of 7 candidates cleared it, so the band alone would have kept it.
`DEBT_REAL_RATE_PCT` is a **real** rate and inflation raises a **nominal** one, so a term
there is the Fisher effect -- the nominal layer V1.6b cut, smuggled back in through the
yield. What survives in real terms is a *risk* premium about volatility, against which
this model's realised inflation sd is 0.040 where the series is 1.14. Every previous
deletion on the decision log was a band failing; this is the first where the band was the
weaker instrument. **A band is a test of size, not of legitimacy.**

**The probe corrected the session three times, seventeen sessions running, and the debt
slope needed THREE sets of bands.** The first measured a spendthrift regime, which does
not widen the debt but *spirals* to the clamp -- a band on a saturated run measures the
clamp. The second measured `hands_off` and passed at 0.0005, because a debt ratio walking
110 to 200 moves the service line 1.8 points at the *anchor* rate with no channel at all
-- a band on a raw move measures the model that was already there, and the fix is the
control `tests/test_trade.gd` needed at V1.6a. The third ships, interior and stable under
refinement, and **iterated to a fixed point**: the shipped value equals the midpoint
measured at it, which is stronger than V1.6b's 0.003 check. The third correction was
`YIELD_MIN`, set to -1.0 on `INFLATION_MIN`'s argument and moved to **0.0** once the
probe found the sign bug behind it -- a player who runs surpluses drives `debt_eur_bn`
negative, and two negatives multiply, so **a treasury holding net assets would have paid
interest on them**.

**V1.4c's obligation is discharged on a RATE**, which is the one quantity in this model
that is not a share of GDP and therefore exactly what V1.6a's refutation asked for. The
dividend is held `EQUITY_PREMIUM_PCT` = **1.12** above the anchor while the borrowing
rate floats past it; the crossing is exact and needs no simulation. The kill switch did
**not** fire, and its clause (i) was tightened on the record from *some reachable regime*
-- satisfied only by one that survives a single term, so a bound rather than a selector,
V1.5a's `CORRUPTION_DELIVERY_BETA` failure -- to `hands_off`, which makes the better
claim: **doing nothing for long enough turns a nationalisation into a loss.**

**The re-baseline is the cleanest split this block has produced.** 0 of 29 regimes
bit-identical, as predicted, and **one outcome change of 48** -- `tinkering` 2032, the
regime whose whole point is that churning every line produces a worse deficit than doing
nothing. Growth, trend and unemployment are **bit-identical in all 217 printed
year-rows**, and GDP in 216, because the yield reaches the **budget** and never the
economy: `debt_service_pct_gdp` is not a player-set line, so it never enters
`demand_impulse_pct`. What moves is debt, the deficit that services it, and the approval
that prices the deficit. **No thirtieth regime** -- a yield is not a verb.

The **twelfth screenshot pass found no bug**, a first, and that is reported rather than
dressed up. Full argument: [[credit-model]].

### V1.6b - inflation, and the row's own input refuted by the data

**The row asked for "a price pressure from the gap, the impulse and (a)'s shock", and
none of the three survived.** The first defect was visible without measuring: the output
gap IS the accumulated integral of the growth addends, so a target reading the gap AND
the impulses that fill it is one quantity written three times -- V1.3c's
`tariff_rate_pct` error. The second needed the data. Regressed on `FP.CPI.TOTL.ZG`
against a gap built the way `economy.gd` builds one, the **output gap carries no signal
and its sign FLIPS between sub-samples** (+0.204 pre-euro, +0.098 euro era, -0.140
pooled) while the **unemployment gap** carries a stable correctly-signed Phillips
relation in both disjoint halves. So the model reads unemployment, which is
[[economy-model]]'s own treatment of Okun -- the honest textbook relationship rather
than a bespoke one -- and it dissolves the double count rather than patching it, because
`unemployment_pct - structural_unemployment_pct` is ONE existing quantity that already
carries the cycle, the demand impulse and every other shock. **Instances twenty-nine and
thirty**, the second being that the row names a price and never says what it is.

**Three constants are measured and two swept, and the selection rule for the measured
slope is the model's own premise.** Two disjoint sub-samples bracket it at [0.252,
0.376]; the **euro-era** figure ships, because [[out-of-scope-mvp]] records that France
does not set its own interest rate and that is exactly what 1999-2024 measures. The
pooled figure is the weakest of the three and would have been the wrong one to ship on
the use-all-the-data instinct. Persistence is converted EXACTLY rather than
approximately -- the twelfth root of the annual AR(1), where a linear `rho/12` would
have made the model 20 % stickier than the data.

**The `ISSUE_KEYS` question is answered YES for the first time**, after V1.3d's yes for
`europe` and five noes. What separates it: it ships no verb and no content object, so
unlike every previous candidate there is **no authored `bloc_offset` it could be priced
on instead**; and a flat load structurally cannot become more salient, which is the one
thing inflation must do. Test 4 was measured as a FIT rather than a band --
`|corr(inflation, growth)|` 0.2276 against `|corr(jobs, growth)|` 0.3185, the
entanglement the model already accepts. The **S10 drift is +0.75 %, in the safe
direction**, and a flat-weight control drifts -0.059 %, which isolates the cause as the
bloc profile rather than the thirteenth key as such.

**The legibility floor appears in a second place and is recorded rather than traded
against.** Table (a) runs first and puts the reachable deviation at **0.145 points**.
That is enough for the opinion price and not for the growth one: the visibility band
needs beta >= 2.0, one point of inflation costing two points of annual growth -- more
per point than V1.6a's whole business cycle. **The band's own prescription, ship it
visible or delete it, is refused in both halves**: not raised, because that is tuning a
measured slope's consequence until it is visible (V1.5b's and V1.6a's refusals); not
deleted, because the term is STRUCTURAL rather than decorative, being the only thing
that makes the loop negative feedback. On the GDP axis the channel is honestly below the
readable floor.

**The probe corrected itself twice, sixteen sessions running, and the second is the
sharper.** The table that chose `INFLATION_SCALE_PP` was **not independent of it**: the
probe cannot change a const at runtime, so the first version rescaled the measured
headline from the shipped value -- and the passing interval MOVED when the shipped
constant moved. V1.5b's *the range was choosing the constant* in a new costume, caught
only by setting the constant once and re-running. The fix emulates a candidate exactly,
by displacing the stock to whatever produces the same satisfaction.

**The re-run: 0 of 29 regimes bit-identical, ONE outcome change of 47, no thirtieth
regime.** The six approval-only movers are exactly the contractionary regimes, which is
the one-sided growth cost visible in the harness rather than a coincidence -- they push
unemployment up, inflation falls below the anchor, and the channel never fires. The one
flip is the same mechanism read politically: a ruinous budget wrecks the economy, prices
fall, and the voter rewards the disinflation. `ruinous` still loses in 2032 at 21.9 %.

**`SAVE_VERSION` is 20, on three fields of four -- a first on this list** -- and they
fail the rule by three DIFFERENT failures, so the test asserts them separately. The
screenshot pass earned its keep for the **eleventh** session running and both bugs were
the readout's: a format **copied from the neighbouring row** (`%+.1f` against a quantity
whose whole reachable range is 0.145 points, printing "+0.0" against a live figure), and
a flag that ticked 48 months and so ran **past** the thing it exists to photograph.
Model: [[inflation-model]].

### V1.6a - the business cycle, and a legibility floor that cannot be met

**The row asked for randomness and the model forbids it, so the cycle is a pure
function of (nation id, absolute month).** `Cycle.impulse_pct()` sums three sines whose
periods and signs come from a splitmix32 hash of the nation id -- `poll_noise.gd`'s
device moved into `src/sim/`, deliberately duplicated rather than shared because that
file's header states as an architectural claim that nothing in `src/sim/` references
it. There is **no `tick_month()` and no accumulator**: `Economy.tick_month()` writes
`cycle_impulse_pct` from a pure read in the same pre-pass that writes
`coercion_impulse_pct`.

**That is the session's structural call, and it is aimed squarely at V1.5d's bug.**
Neither balance harness had ever called `Media.tick_month()`, so both ran the
pre-session model and their agreement was about nothing. Every harness in this project
already calls `Economy.tick_month()`, so a system reached from inside it **cannot be
forgotten by one and remembered by another** -- and the claim was falsified before it
was trusted: a 1434-line diff on the first run, with no wiring edits at all.
`tests/test_cycle.gd` reads the file and fails if a `tick_month()` or a member `var`
appears.

**Both constants are measured or fitted, and the sweep planned for one of them was
deleted.** `CYCLE_COMMON_SHARE` was to be the second swept constant; the series that
supplies the per-nation amplitude also says what the common share **is** -- var(common
factor) / mean var(nation) = **0.619** over 33 years, cross-checked against a mean
pairwise correlation of **0.633**, two statistics of one dataset agreeing to 0.014.
That is V1.5c's two-harness rule applied to a measurement rather than to a probe.

**The dataset exists for the third session running, and it cost more than the last
two.** V1.5b's ageing slope was "one extra read of a series already on disk"; this
needs a **different window**, 1990-2024, because measuring volatility takes several
cycles and 2015-2024 contains one. **The exclusion is the block's one editorial act
and it is load-bearing**: on the existing window France's growth standard deviation is
**3.333**, and **0.579** with 2020-21 removed -- a factor of 5.8. A session that reused
that window would have shipped a business cycle whose entire amplitude was one
pandemic, and it would have looked measured. 2008-09 is not excluded, because a
financial crisis *is* a business cycle. The result spans 0.689 (France) to 1.475
(Luxembourg) and its ordering holds across five windows.

**The session's sharpest finding is a floor that cannot be met, and it is recorded
rather than traded against.** The two pre-committed bands -- readable past the +-3.0
poll-noise floor, and no more volatile than France measurably is -- **have no overlap
at any candidate** on a grid refined to 0.05 and widened to 4.00. Readable needs ~1.9;
honest needs at most ~1.7.

> At France's own measured growth volatility, a business cycle moves approval by about
> **2.8 points**, under the +-3.0 floor, and it cannot be lifted over it without making
> France more volatile than France is.

That is [[defence-model]]'s deployment-below-the-floor treatment, and it is the right
way round twice over: `poll_noise.gd` fuzzes *approval* because a poll is published,
while growth and unemployment are printed exactly -- so the cycle's primary readout
carries no noise and only its secondary one does; and **that is the mechanic**, because
a slump unmistakable in the figures and ambiguous in the polls is precisely a president
who cannot prove it was not their fault. The constant is **fitted** instead: at 1.70 the
model's realised growth sd is **1.260** against France's measured **1.262**, interior to
the grid with candidates failing on both sides, and a fit *converges* under refinement
where a band edge merely moves.

**Both pre-committed bands failed first, in the two ways the probe's own header named,
and the header keeps the pre-commitment rather than being rewritten.** Band (i) read the
national headline and passed at *every* candidate -- 6.271 at an amplitude of 0.25 --
because a committed budget moves approval six points on its own and the band was
measuring the budget. Moving it to the **workers** row bought only 8 %, and three
sessions of the previous block had already established that a single issue cannot carry
a headline. Band (ii) was flat at 7.346 for seventeen candidates of nineteen, `ruinous`
setting it rather than the cycle. An interim replacement ceiling was a bound at 23.208.

**The decomposition's own call 3 was refuted by this session's probe.** The procyclical
half of V1.4c's obligation was booked to (a) as free, because sector output already
moves with the cycle. It does not work:
`Companies.dividend_revenue_pct_gdp()` returns `100.0 * paid / gdp_eur_bn`, so the cycle
moves numerator and denominator together and they cancel -- 1.07x against a
pre-committed 1.5x floor. **A dividend expressed as a share of GDP is not procyclical by
construction**, and the obligation passes to V1.6c whole.

**The re-baseline came back unchanged, on two harnesses, and that is a measurement.**
Section 6's own bullet says a cycle arriving there re-baselines `UNREST_THRESHOLD_PCT`
and `UNREST_CONVERGENCE` together. Every grievance peak rises -- balance_probe's
`hands_off` 3.29 -> 7.57, `managed` 5.31 -> 9.17 -- and **the act count is identical in
all 29 regimes**. The convergence rate holds for a structural reason: its band is
bracketed by two other constants' half-lives, neither of which a cycle moves.

**Three bugs, all harnesses rather than the model.** `Budget.project()` **never advanced
the clock** -- it ran twelve ticks at one date for eleven sessions, invisible because
nothing in it computed a figure from the date until now; `tests/test_budget.gd`'s own
runner froze it too, which is why the two agreed to 1e-9 while both were wrong; and
`tests/test_trade.gd` measured a partner recession **against zero**, which returned
**+0.039** once eight other partners were moving. All three are V1.5d's finding at
different depths.

**The re-run was predicted NOT bit-identical and was not: all 29 regimes differ, and
there are ZERO outcome changes.** Largest movements are 3.32 % of GDP, 2.74 points of
growth, 1.26 of unemployment and 7.60 of approval -- against **0.07 points of
deficit**, because every budget line is a share of GDP and the books scale with the
economy, which is [[economy-model]]'s own reason for that choice becoming visible for
the first time. **No thirtieth regime was needed**, a first for a session that changes
the economy: the cycle is not a verb, so there is nothing for a regime to issue.

**`SAVE_VERSION` is 19, and the plan predicted no bump.** Its reason was true about the
wrong thing -- `src/sim/cycle.gd` is genuinely stateless, but `NationState.from_dict()`
rebuilds from the dictionary alone and never sees the loader, so every content-derived
static fact on that class is already serialised. **Statelessness is a property of the
module, not of the save file.** `cycle_amplitude_rel` earns the bump (absent, every
nation runs the roster-average cycle and the reload is a different model --
`military_capability`'s case); `cycle_impulse_pct` earns nothing. Model, every constant
and the measured tables: [docs/cycle-model.md](docs/cycle-model.md).

### V1.5 — the decomposition, and why these four

Written before any code, which is where a block-shaped row belongs: V1.5 was one
line — media, scandals, unions, strikes, protests, corruption, demographics,
migration, inequality — and one line is not a session.

| | Session | Content | Reads |
|---|---|---|---|
| **V1.5a** | The delivery layer | `service_quality` as a stock converging on sustained spending, corruption as the factor that degrades **delivery**, and `effects.society` — the sixth channel, which V1.5 then owns the way V1.4 owns `effects.company`. No new content directory, no new window, no new per-nation data | — |
| **V1.5b** | ~~Demographics and migration~~ **shipped** | Two live age shares on a **measured** drift, the dependency ratio derived from them, that ratio as a **denominator** under (a)'s stock -- which is what let `pensions` join `QUALITY_KEYS` -- and migration as the second `effects.society` term. `POP_GROWTH_PCT` and `LABOUR_FORCE_SHARE` both **deleted**. `SAVE_VERSION` 17. The block's "one unmade content decision" was not one: the dataset exists | a |
| **V1.5c** | ~~Unrest: unions, strikes and protests~~ **shipped** | The grievance stock and the acting agent — a decaying output impulse, a settlement law gated on `unrest_pct`. The output-only price was **refuted by its own probe** (4.94 % of GDP, 0.42 points of approval) so a direct term was added; inequality ships as a **measured** stopgap off `SI.POV.GINI`, the dataset the row said could not exist. `SAVE_VERSION` 18 | a, b |
| **V1.5d** | ~~Media and information~~ **shipped** | The outlet register and a **per-bloc salience gain** -- the row asked for the SOURCE of a machine `salience_weights()` has run since S10, not for a machine. Press freedom as the fourth `effects.society` term with two prices. **Scandals moved to §8** and government messaging cut, both argued. The deviation is **mean-anchored**, which a measurement taken before any code forced. `SAVE_VERSION` stays **18** | a, c |

**Machine count is five, which is what splits it**: the outcome stock, the cohort
structure, the unrest agent, framing, and the scandal scheduler. Two things the
row reads as machines and that are not — **inequality is a derived read** with no
scheduler, no decision and no accumulator (`Defence.allies()`'s shape), and
**corruption is one factor at one existing site**, V1.4c's jobs-shield shape.

**(d) is the row most likely to split**, recorded here in advance the way this
page recorded V1.3e (which did split). The cut, if it fires, is **scandals → (e)**,
and the reason is architectural rather than a fourth media feature: scandals are
where §8's event schema either gets written or gets explicitly deferred.

**IT DID NOT SPLIT, AND THE CUT WENT FURTHER THAN (e).** Counted at plan time on machine
count -- V1.3e's trigger -- (d) is **one machine**, because the framing machine already
existed in `opinion.gd` and the session supplies its source rather than building it, and
press freedom is one factor at two existing sites (V1.4c's jobs-shield shape). ~28
surfaces, level with V1.5a and V1.3e. So the trigger does not fire at the session level
and there is no (e): **scandals left the block for §8 entirely**, which is a third outcome
§8's own warning box did not enumerate and which that box's own argument requires. Written
into both rows. See [docs/media-model.md](docs/media-model.md) §2.

Four calls, each of which could have gone the other way:

1. **Nothing in §5 is a verb, and that inverts V1.3a's rule.** Every V1.3 and V1.4
   session shipped a player command — a diplomatic action, a subsidy, a law, an
   ownership op. §5's nine bullets contain at most two (press freedom, government
   messaging) and both are levers on a machine that must exist first. So the rule
   for this block is not *ship a verb with the state*; it is **every session ships
   a statistic and the price it charges**, or the statistic is decorative, which is
   what V1.3a's rule was protecting against in the first place.
2. **(a) is first, and the deciding property is that it is population-independent.**
   (a)'s outputs are read by (c) and (d); (b)'s are read by nobody. (b)
   re-baselines the balance harness through `bloc.gd`'s per-capita transfer
   weighting and `companies.gd`'s labour force, and by U5b → U5c's rule the half
   carrying the unmade content decision is the half to defer — here, ten authored
   age structures with **no dataset behind them**: `tools/import_data.py` imports
   GDP, population and unemployment, and there is no age structure, fertility, life
   expectancy or Gini anywhere. Ten identical pyramids would be
   [[foreign-policy-model|the clustered `coalition_position` finding]] a block
   later, caught at design time rather than by a probe.
3. **Corruption goes to (a) rather than to (d), and the boundary is architectural.**
   "Degrading policy effectiveness" is literally `Cabinet.effectiveness()`, read by
   `opinion.gd`, so corruption belongs in the session that already touches that
   site. Grouping it with media would be a **thematic** boundary — the two share a
   table heading in [[mechanics-society]], which is a document layout — and V1.4's
   a/b line held precisely because the approval path differed and not the subject.
4. **Rule of law is §1's judiciary and leaves this block.** [docs/tiers/v1.md](docs/tiers/v1.md)
   §1 already schedules "courts that can strike down laws, a check the player
   cannot outvote", re-parked as V1.1e. Two uncontestable gates on player action is
   one machine claimed twice. Cross-referenced into **both** rows.

**The row missed eight, and all eight were found by counting.** That is instances
**fifteen through twenty-two**, and the count is now the record rather than the
exception.

*Collisions, each cross-referenced into both rows:*

- **Rule of law ↔ §1's judiciary** — call 4 above, and the fifteenth.
- **Education quality already exists.** `economy.gd`'s `_update_potential_shift()`
  has been a first-order lag on sustained education spending since S4, shared with
  infrastructure and trade openness. §5's bullet names a stock the model has had
  for six blocks, so **§5 must not build a second one** — V1.4b's collision in a
  new place, and the reason (a) ships one new stock rather than two.
- **Scandals ↔ §8.** §8's own text says the event schema is the union of the
  channels §3–7 create and that "written before them, it gets written twice" — and
  a revelation with preconditions, choices and consequences *is* §8's definition.
  Cannot be left silent, because the whole *why events are last* argument rests on
  it.
- **Inequality ↔ §6.** §6 owns brackets, wealth and capital gains — the only real
  distributional levers in the game. §5 owns the *statistic* and its political
  price; §6 owns the *instruments*. Without that split §5's index has no writer of
  its own, which is why (c) ships it as a declared stopgap read.
- **Government messaging ↔ §7's campaign phase.** The same machine in two blocks.

*Orphans — tiered V1 in [[mechanics-society]] and in no bullet of any row:*

- **Government messaging.**
- **Honeymoon and fatigue**, deferred *in code* at `opinion_constants.gd`'s
  `APPROVAL_NEUTRAL` — "time in office as its own drag is V1" — and in no row at
  all. The narrowest miss on this list and the oldest.
- **Birth rate and life expectancy**, for which no data exists.

*Three things the nine bullets assume the model does not have:*

- **"Ageing driving pension and health costs."** `spending_pct_gdp` is a
  player-set **rate**. There is no cost side, no beneficiary count and no
  per-capita benefit anywhere, so ageing cannot raise a number the player sets.
  (b)'s answer is a **required rate the set rate is measured against**, so ageing
  raises a *shortfall* — which also hands service quality its denominator.
- **"Corruption degrading policy effectiveness."** `effectiveness` multiplies
  **deltas only**, deliberately, so at that site corruption costs a do-nothing
  player exactly zero. (a) resolves it by degrading the *stock* instead.
- **"Press freedom with legitimacy costs."** There is no legitimacy quantity, and
  `bloc_offset` — the nearest — never enters `issue_salience`, so V1.3d's own
  argument says a price on it could never be named by the polling panel or by
  `elections.gd`'s attribution. (d) owns that.

**Existing content already pre-prices two of the bullets through channels that
become wrong the day the statistic exists.** `data/laws/institutional.json` prices
corruption as `other_revenue_pct_gdp: 0.1`, and `data/laws/social.json` prices
immigration as `structural_unemployment_pct: -0.05`. Re-authoring both is a cost
booked to this block rather than a surprise inside it: (a) pays the first, (b) the
second. That is V1.4b's retro-fit, found in advance this time.

### V1.5b -- demographics and migration, and the dataset the row said did not exist

**The decomposition's own reason for deferring (b) was wrong, and that is the session's
headline.** Call 2 defers it partly because ten authored age structures with *no dataset
behind them* would be [docs/foreign-policy-model.md](docs/foreign-policy-model.md)'s
clustered `coalition_position` finding a block later. But the World Bank publishes age
structure (`SP.POP.0014.TO.ZS`, `SP.POP.65UP.TO.ZS`) and 15-64 participation
(`SL.TLF.ACTI.ZS`) for all ten, on the same licence through the same loop -- and
[docs/data-sources.md](docs/data-sources.md)'s loop has always fetched `date=2015:2024`,
so a per-nation ageing **slope** cost one extra read of a series already on disk and **no
extra download**. Old-age dependency spans **LUX 0.225 to ITA 0.388**; the slopes span
**2.58x**, wider than the levels. **Twenty-third** stale-row instance.

**A cohort machine was designed and then CUT, and Luxembourg is the proof.** Nothing in
the model reads a head *count* -- `population` enters no equation in `economy.gd`, and
`firm_jobs_offset_pct()` returns before its denominator unless a firm has moved. A
uniform 15-64 bucket also predicts **Luxembourg ages fastest of the ten**; measured, it
ages **slowest**, because its working cohort is bulged young by migration and a uniform
outflow over-ages it. And fertility and life expectancy are *inputs* to a projection
whose *output* the dataset already publishes. So the drift is linear at its measured
rate, `demography_constants.gd` carries **exactly one tuned constant**, and this is
deliberately *not* `capability_target()`/`capability_step()`'s shape: those converge on a
target the player sets, and a population converges on nothing a president decides.

**The shortfall is a DENOMINATOR at one existing site.** `spending_pct_gdp` is a
player-set rate, so ageing cannot drive it; what ageing does is make the same rate buy
less. `Society.quality_target()` divides by the dependency factor, which is **exactly
1.0** at new game for all ten nations. That discharged `society_constants.QUALITY_KEYS`'s
own promise word for word -- *"It joins by becoming an entry"* -- for **one entry and
zero lines in `opinion.gd`**.

**A pre-committed tiebreaker failed for a THIRD distinct reason, and the rule is
extended.** `MIGRATION_SHARE_BETA`'s was *"strictly less legible than a saturated
corruption register, then take the largest passing candidate"* -- a genuine strict
ordering, which is exactly what V1.5a's restated rule demands. It still failed, because
**both bands are one-sided minimums**: every candidate above the threshold passes, so
"largest" returns the top row of whatever grid was swept, and widening the grid moved the
answer from 0.010 to 0.016. **The range was choosing the constant.** The rule now reads:
a tiebreaker must strictly order the survivors **and its answer must not move when the
candidate range is widened** -- which is checkable in advance by widening the grid, where
*is it a strict ordering?* is not. The corrected selector (smallest passing, since both
bands are minimums) chooses **0.0090**, *interior* to the grid, which is the evidence the
correction did something.

**The kill switch fired on `DEPENDENCY_ELASTICITY["health"]` and the entry was DELETED.**
The row asks for ageing to drive pension **and health** costs; health's widest bloc row
moves -0.07 at an elasticity of 0.15 and only **-0.51 at 1.00**, against a +-3.0 floor.
The dependency factor reaches only ~1.10 over a term, so even the largest defensible
elasticity moves a fraction of a point of GDP -- V1.4b's finding that this layer's
channels sit below the opinion model's resolution. Ageing is a health cost in the world;
it is not one this model can make a voter notice inside a term.

**Two constants were deleted and nothing replaced them but content.** `POP_GROWTH_PCT`
(one flat 0.15 for all ten, against measured ITA **-0.238** and LUX **+1.938** -- the
constant had every nation in Europe growing and one of them shrinks) and
`LABOUR_FORCE_SHARE` (0.45, whose own comment called it "measured, not a dial" -- true
for France to three digits at 0.4543, and wrong for Germany at 0.5027, with the roster
spanning ITA 0.423 to NLD 0.551).

**`SAVE_VERSION` is 17, earned twice, and the second half adds NO FIELD AT ALL.** The two
live shares are the ordinary half: absent they read 0.0, which is a different model
rather than a neutral default. The sharp half is `service_quality["pensions"]` -- a
version-16 save carries `{"health": ...}` and no `pensions` key, `.get(key, 0.0)` starts
the stock at zero against a reference that is also zero, so the deviation reads as a large
and growing **positive**: a pension system that has just been invented and is improving
fast, a windfall the player did not earn. `tests/test_save_load.gd` asserts both halves
separately, which pins that **growing a registry dictionary can earn a bump**.

**The re-run held the prediction where it counts.** 23 of 24 shared regimes are
bit-identical in GDP, growth, trend, unemployment, debt and deficit; the one exception is
`managed_subsidises`, exactly the regime the labour-force denominator was predicted to
reach. **Zero outcome changes.** The bloc transfer moved nothing, and the handoff's
assumption that cohorts re-baseline it was wrong: `Bloc.net_positions()` reads the
loader's Nation objects and is called once at new-game, never re-ticked. The nineteenth
regime is the cheap kind, and the legibility evidence is sharper than the headline --
under `managed_corrupts` the result screen now attributes `pensions` at salience 0.17,
where before V1.5b it could not appear at all. Model:
[docs/demography-model.md](docs/demography-model.md).

**`BLOC_SIZE.pensioners` stays authored, and the refusal is recorded beside it.** It is
0.24 against a measured 65+ share of 0.2215 drifting to about 0.27 -- one quantity, two
writers, the failure this project names most often. It stays because it is an
*electorate* share and excludes under-18s, because `BLOC_TURNOUT` already models the age
effect a second time, and above all because the table is read by `elections.gd` twice
plus `cabinet.gd`, `opinion.gd` and `polling_panel.gd`: a live share would move election
**results**, not just approval, and re-baseline every constant measured at S5, S10,
V1.3d, V1.4c and V1.5a inside the session that also re-baselines demographics.
`tests/test_demography.gd` pins the refusal so a later session has to come and say why.

**`tools/import_data.py` was silently deleting fields, and the diff is how it was
found.** `write_nation_file()` rebuilt each nation file from an *enumerated* key list, so
every top-level field a later session added was dropped the next time anyone ran the
import -- U6b's `leader` block and the `flag` block both already had been. Found by
diffing the ten files after an import and asking why the change was larger than the block
it claimed to add. It now rebuilds from the file's own key order, and short scalar arrays
are written back on one line so the output already matches what is committed -- which is
what makes *the diff shows only what you meant to change* a usable check at all.

### V1.5c -- unrest, and the price the probe refused to let the session ship

**The block's one true acting agent, and the session where the inverted rule and the
rule it replaced agree.** V1.3a's rule was that state ships *with a verb*; this block
inverted it into *every session ships a statistic and the price it charges*. Here the
statistic is `unrest_pct` and the verb is the union's -- a rule about live state needing
something to act on it never said the actor had to be the player.

**Its headline is that the price it was designed with does not reach a voter.** The
session committed to an OUTPUT-ONLY price: a strike writes a decaying impulse into
`economy.gd`'s growth sum, approval falls through `growth` and `jobs`, and no thirteenth
`ISSUE_KEYS` entry has to be argued. Measured on an isolated path -- grievance held at
the ceiling, every other issue identical between the runs -- fourteen years of maximum
grievance costs

```
    -4.94 % of GDP        and        -0.42 points of workers approval
```

and no candidate clears the +-3.0 floor at any scale. The reason is structural: the whole
opinion model is written in **rates and ratios**, `growth` reads `growth_annual_pct -
trend` and returns to zero once a shock is steady, unemployment mean-reverts to a
structural level a strike never writes, and every fiscal figure is a share of GDP -- so a
GDP five per cent smaller changes almost none of them. **A permanent level loss is
invisible to a model that prices changes**, which is `opinion.gd`'s own deficit-not-debt
argument read from the other side. Raising the scale would be tuning against an
arithmetic impossibility, which is exactly what V1.5b refused to do for
`DEPENDENCY_ELASTICITY["health"]` -- but V1.5b's answer there was to DELETE the term, and
that answer is not available to the session's only price. `UNREST_OPINION_SCALE` exists
because a pre-committed band said the design was wrong.

**The row's own warning is the design constraint, and it is defeated mechanically.**
*"Unrest driven by nothing the average voter does not already feel is a second approval
number with a different label"* -- so the hardship term reads **two rows of the electorate
and not six**, because `Discipline.unpopularity()` is already the six-row version and is
already consumed by `discipline.gd`, `government.gd` and `cabinet.gd`. A second one would
be `military_capability` / `potential_shift_pct` a fifth time. And two rows are still a
re-weighting, so the target carries two terms **no opinion issue reads**: the Gini drift
and the settlement stance. The row's inequality bullet is what supplies that
independence, so §5's two bullets turn out to need each other.

**Zero new weights and zero new saturation scales.** `BLOC_SALIENCE_BASE`,
`salience_weights()` and `BLOC_SIZE` already exist, so who strikes falls out of a table
written at S5 for unrelated reasons -- V1.3d's finding a second time. Workers weight
`defence` at **0.00** and `tax_vat` at **0.08**, which is exactly what `managed` moves, so
a well-governed France is structurally quiet and nothing authored that.

**The row said the inequality index "cannot be derived" and was right; it does not have
to be.** The World Bank publishes `SI.POV.GINI` for all ten on the same provider, the
same licence and the same download loop as every other figure in `imported`. Levels span
**NLD 25.7 to ITA 34.3** and **the signs differ** -- six nations growing more equal, four
less -- so the clustered `coalition_position` risk a stopgap would otherwise run does not
arise. **Twenty-fourth stale-row instance**, and V1.5b's headline one session later. The
cost is booked rather than discovered: coverage stops at 2021, 2022 or 2023 per nation,
so `import_data.py` gained a nearest-year fallback **scoped to that one series** -- a
silent fallback on GDP would turn a broken download into a quietly stale figure -- and
the year it used is written into the block. What keeps it a stopgap is that **nothing the
player does moves it**, asserted by mutating the corporate rate, every `state_share` and
every `regulation_burden` and requiring the index to be bit-identical. §6 discharges it by
turning that test red.

**The stateless version was designed and cut, and the harness decided it.**
`inequality_deviation()` was to be a pure read of the slope times elapsed months -- no
field, no save entry, `Defence.allies()`'s shape. There is no elapsed-time source that
survives: `balance_probe.gd` and `tests/test_balance.gd` both set `state.year` **after**
`GameState.new_game()`, so a reference captured at init reads year 0. The drift went to
`Demography.tick_month()` instead, which is V1.5b's own split made again -- that layer
owns measured facts about the population, and the session that prices a fact owns the
price rather than the fact.

**`settlement` is the third `effects.society` term, and a channel carrying a third
register is schema rather than luck.** Without it the only lever pointed at a strike is a
spending increase, and `society_probe.gd` table (c) established that raising a line
necessarily widens the deficit -- so the player could buy industrial peace only by opening
`public_finances`. V1.5a's `society` + `spending_pct_gdp` refusal was **narrowed from the
channel to the pair**, because its stated reason is about corruption reaching the spending
issues through the quality stock and was never true of the channel; a settlement law is
naturally a spending law, so under the wide scope every one was a load error. That is
V1.5b's own narrowing one session on, and it turns an existing red green.

**And there is NO fourth anti-double-count, which is the more interesting half.**
`society.settlement` + `structural_unemployment_pct` was written and deleted, once it was
checked against the criterion the three existing refusals use rather than against the
pattern they make: *the same act, the same landing site **and the same units***. A
settlement is in units of stance and lands on the unrest target; structural unemployment
is in points and lands on `Economy._update_unemployment()`. Two of three criteria fail.
The distinction is **one mechanism priced twice** against **two mechanisms landing on one
number**, and a rule that forbade the second would forbid `bloc_offset` beside anything.
Recorded in `law.gd` itself, because the next session to add a term will reach for a fifth
refusal by symmetry and **symmetry is not the test**.

**The probe corrected the session six times, fourteen sessions running, and four of the
six are about the measurement discipline itself.** Each is written beside the constant
that found it:

- **`UNREST_CONVERGENCE` -- a nearest-to-X tiebreaker is only as good as the grid's
  RESOLUTION.** The first grid was a doubling ladder and chose 0.08; refining to 0.01
  moved the answer to **0.07**. V1.5b's diagnostic is about widening, and this is the same
  failure under refinement.
- **`UNREST_THRESHOLD_PCT` -- a band whose ceiling is ONE regime's measured peak.**
  Against `austerity` alone the tiebreaker chose 52.0, which passes V1.5a's ordering check
  and V1.5b's widening check and is still wrong: *largest passing* means *that peak, minus
  0.8*, and at 52.0 a budget that zeroes every spending line produces no industrial action
  at all. Band (i) gained `spend_zero`; the selector is unchanged; **45.0**.
- **`UNREST_SETTLEMENT_BETA` -- V1.5b's own correction, INVERTED.** Band (i) was lifted
  verbatim from `demography_probe.gd` (*at or below where it started*) and did not
  transfer: a dependency ratio rises forever, where unrest converges on a bounded target,
  so the borrowed wording made the interval EMPTY. For a bounded stock closable means
  *stops the strikes*. Once (i) was corrected the interval became genuinely two-sided, at
  which point *smallest passing* -- V1.5b's forced answer -- **lands back on an edge**.
  The rule is extended: **two model criteria, take the midpoint; one guard rail, the guard
  rail does not select**. **12.0**.
- **`UNREST_IMPULSE_SCALE` -- a band applied to an observable the channel does not reach.**
  It failed at every candidate and the constant was right.
- **`UNREST_COOLDOWN_MONTHS`** was the oldest failure a fifth time: every candidate
  passed, so the band was a bound and not a selector. Set by argument, and it says so.
- **`INEQUALITY_BETA`'s kill switch CLEARED** at 0.40, and the surviving term is small --
  one month in thirty-six on the roster's widest riser. Recorded rather than tuned away.

**`general_strike` was cut by measurement.** Peak reachable grievance is 53.3 under
austerity, 49.6 under `spend_zero` and 80.6 under `tax_max`; a three-way split of
`[45, 100]` puts the third tier at 81.7, which no budget reaches. A label the model cannot
produce is `refused_by_partner` a fifth time, so it is deleted rather than left in a list
looking alive.

**The reachability measurement had to be redone on a harness that could survive an
election, and the probe written to catch that error had the same blind spot.** All
twenty-five shared regimes reported **zero acts**: every provocative budget commits at
month 1, meets the 2027 presidential election with its full damage and loses, and the run
stops around month 16 -- long before a stock converging at 0.07 matures. `unrest_probe.gd`
missed it because its own loop has no elections, so it ran a losing government for
fourteen years and reported twelve acts. That is V1.3f's measuring-the-wrong-state error a
**third** time in one session, and the twenty-second regime is what answers it:
`balance_probe.gd` gained a **mid-run budget switch**, which this harness has never had.
`managed_then_austerity` holds 2027 at 26.1 %, switches, reaches grievance **48.74**,
fires **two acts**, and is destroyed in 2032 at **9.7 %**. The mechanic is reachable in
play, and the threshold needed no retuning.

**The re-run is the cleanest split this block has produced.** All **25 shared regimes are
bit-identical in GDP, growth, trend, unemployment, debt and deficit**; approval moves in
all 25, worst 2.60 points, under the noise floor; **zero outcome changes**. The economics
are untouched because no shared regime ever fires an act -- the approval movement is the
grievance *stock* alone, which is what "read off the stock and not off the act" buys and
costs. **Three new regimes, the twentieth to twenty-second**, and the legibility evidence
is exact: same budget, one settlement law at month 60, and `managed_then_austerity_settles`
turns the grievance over (46.21 to 40.04), the second strike **does not happen** (2 acts to
1) and the incumbent's vote is 1.9 points higher. It still loses -- a settlement cannot
rescue a five-year austerity -- and that is the model saying the right thing.

**`SAVE_VERSION` is 18, and it is the first bump on this project's list resting on TWO
fields.** `unrest_pct` is `service_quality`'s case (absent it reads 0.0, silently ending a
crisis the player was living through) and `unrest_cooldown_months` is U6a's
`diplo_months_to_act` (absent it reads 0, 0 means act now, so a reload fires a strike in
its first month). They fail the rule by different failures, so `tests/test_save_load.gd`
asserts them separately. The test also pins the **absence** of any stored inequality index.

**`PRECONDITION_FIELDS` gained its first entry naming something the player did not do**,
and the suite caught the half-edit immediately: the whitelist and `_read_field()` are the
same list in two places, and V1.5c added one of them. Recorded in `legislature.gd` rather
than merged, because the constant is read at load time by `law.gd` and the match runs per
frame. `unrest_pct` may only ever be tested with `>=`, asserted over the whole law list --
`available()` only OPENS laws, and a `<=` precondition would make unrest an uncontestable
gate, which is call 4's "one machine claimed twice" and §1's judiciary.

### V1.5d -- media, and the source of a machine that had been running since S10

**The row asked for outlets that "frame the player's actions", and the framing machine
already existed.** `opinion.gd`'s `salience_weights()` has amplified bad news at a global
`SALIENCE_GAIN = 5.0` since S10 -- amplification with no source -- and *"bad news travels"*
is a claim about the press this project has been making for six blocks with no outlet
behind it. So V1.5d builds no machine: it makes one scalar into **six**, and the six
average back to the one. **Twenty-fifth stale-row instance**, and a **twenty-sixth** the
same day: `public_broadcasting_reform` had sat in `institutional.json` since the MVP
pricing itself as `other_revenue_pct_gdp`, which is V1.5a's `anti_corruption_agency`
verbatim -- a law describing its side effect and calling it the mechanism. The block's
**fourth booked retro-fit**.

**An outlet is five fields and the refusal is the design.** `data/outlets/<NATION>.json`,
per-nation lookup on `data/companies/`'s shape, absent file = no press = the model all ten
ran before. It names one **audience bloc**, so `BLOC_SALIENCE_BASE` already says who cares
about what and the session adds **zero new weight tables** -- V1.5c's "who strikes falls
out of a table written at S5" one session on. It carries **no authored alignment,
hostility, bias or stance**, and `outlet.gd`'s unrecognised-key error says so out loud:
alignment is derived from its position against the government's own `coalition_position`,
so **the press turns on you when your government re-forms**, and an authored one would be
a second writer of that.

**The mean anchor is the session's one model correction, and a measurement taken before
any code forced it.** The design was start-anchored -- `start_service_quality`'s idiom, the
one this project reaches for by reflex. Step 0's travel table refuted it: over 168 months
France's `coalition_position` travels **0.044** where Germany's travels 0.600 and Britain's
0.870, because France holds a majority through every election. That put the constant near
16 for Britain and near **250 for France**, which is the nation the game is about --
V1.3e's globally-anchored amity in a new place. **The pre-committed fallback was REFUSED**
(delete the alignment term, let press_freedom drive it alone) because it leaves the outlet
register inert until the player passes a law, which is the decay V1.3a's rule exists to
prevent. Anchoring on the size-weighted national mean instead makes
`sum_b BLOC_SIZE[b] * dev[b]` **exactly 0**, so the mean gain is exactly `SALIENCE_GAIN`
and every opinion constant measured since S10 keeps its calibration -- and it gives a
FRIENDLY press a channel, which a start anchor structurally could not, since `severity` is
`clampf(-sat, 0, 1)` and good news is already at zero. Without that, censorship would have
been **strictly dominated** on the framing axis, the shape this project has killed five
times.

**"Press freedom as a dial with legitimacy costs" -- the quantity was neither invented nor
dropped, because it already existed.** Legitimacy is willingness to accept your rule
outside the ballot box, which is V1.5c's grievance; its own model doc says a country can be
angry for reasons its approval figure does not contain, and `UNREST_BLOCS` is
`["workers", "students"]`. So press freedom is the **fourth `effects.society` term** with
**two prices** on V1.3c's shape. A channel carrying four registers written by four
consecutive sessions is schema rather than luck, and `_extract_society()` needed **no
change at all** -- it is generic over `SOCIETY_TERMS`, so all four of its error strings
updated themselves.

**`law.gd`'s warning worked.** That file records that the next session to add a term would
reach for a fourth refusal by symmetry. V1.5d reached, checked all four candidate pairs
against *same act, same landing site AND same units*, and every one failed. **The refusal
that IS warranted has no shape a law schema can express**: press freedom must not reach the
grievance target through both `PRESS_UNREST_BETA` and `Unrest.hardship()`, which is one
register reaching one number twice through CODE. So `Opinion.salience_weights()` takes its
gain as a **required third argument** and `unrest.gd` states the unframed one out loud --
defaulted, silence would mean "unframed" and the next caller would get it wrong by
omission with nothing going red.

**Scandals left the block for section 8, which is a THIRD outcome that section's warning
box did not enumerate.** Neither legal outcome survived inspection: "requiring a response"
is a choice list, so a non-generic scandal has no response and is then a negative framing
shock -- V1.5d's own machine with a second label; and section 8's argument for being last
is that the event schema is the union of the channels sections 3-7 create, so a schema
written at V1.5d is written before 6 and 7 create theirs. **Government messaging was cut**
as press freedom's positive direction with a different label. Both written into both rows.

**The probe corrected the session four times, fifteen sessions running, and the sharpest is
about the guard-rail rule itself.** `FRAMING_BETA` pre-committed to V1.5c's rule (e) and it
failed twice over: band (ii) turned out to be a **bound and not a selector** (0.44 at beta
7.0 against a +-3.0 ceiling), so the interval's real upper edge is the clamp -- a guard rail
-- and rule (e) then prescribes smallest-passing, which is wrong here because **rule (e)
assumes the model edge is a PLATEAU**. V1.5c's own table was lumpy; this response is linear,
so smallest-passing means *wherever the band crosses* and every refinement moves it. Rule
extended: when the model edge is a smooth crossing, neither edge selects and the interior
governs. **4.50**, midpoint of `[3.02, 6.00]`. `PRESS_UNREST_BETA` failed in the older way --
every candidate passed -- and is **set by argument** as a ratio against `SETTLEMENT_BETA`,
because a saturated censorship must open less grievance than a saturated settlement closes.

**Two reachability traps, and the second was in the control.** Band (i) was first measured
on `tax_max` from month 1, under which France loses in 2027 and the run stops at month 16 --
and it showed a discontinuity there that vanished entirely on `managed>tax_max`, the
govern-well-win-then-provoke case. The press sweep's control was worse: measured from month
1 it fired **no act at all**, so "moves the date" degenerated into "an act happens". On
`managed>austerity` at `balance_probe.gd`'s own switch month of 20 the control reproduces
that file's `managed_then_austerity` peak of **48.74 to the digit** -- two harnesses
agreeing, which is what V1.5c spent a session on.

**The balance re-run was predicted NOT to be bit-identical, came back with a diff of exactly
ZERO lines, and the wrong prediction is what caught the bug.** `balance_probe.gd` and
`tests/test_balance.gd` never called `Media.tick_month()`, so both harnesses were running
the pre-session model and their agreement was about nothing -- U6a's day-loop finding at its
simplest, and the new part is the detection method: a bit-identical re-run is the
reassuring outcome, so nothing about it invites suspicion, which is exactly why the
prediction has to be written down first. With both fixed: **all 28 shared regimes
bit-identical in GDP, growth, trend, unemployment, debt and deficit, approval moving in all
28 by at most 3.00 points, and ZERO outcome changes.** The **29th regime is the cheap kind**
(a law at a month) and is the legibility evidence -- same budget, one
`broadcasting_oversight_act` at month 24, and the worst bloc moves from **rural 45 to
students 40**: the bloc reading the paper furthest from a centrist government, and one of
the two that marches.

**`SAVE_VERSION` stays at 18**, which is not what the design pass predicted. It predicted 19
on a `start_press_stance` and was **correct about the design it was given** -- no
`start_coalition_position` is serialised, so an absent baseline recomputes against the
current government and a save reloaded after the press turned scores the hostility as new,
which is `start_bloc_burden`'s case at V1.3d. The mean anchor deleted the field and the bump
with it. Both are recorded rather than the second quietly replacing the first, and the test
pins the **absence**. Model, every constant and the measured tables:
[docs/media-model.md](docs/media-model.md).


### V1.4 — the decomposition, and why these three

Written before any code, which is where a block-shaped row belongs: V1.4 was one
line — named firms, subsidies, regulation, nationalisation, privatisation, bond
markets — and one line is not a session.

| | Session | Content | Reads |
|---|---|---|---|
| **V1.4a** | ~~The firm register and subsidies~~ **shipped** | `data/companies/`, firms as a normalised partition of a sector, the `effects.company` channel, subsidies with a computed budget line and a domestic price, the Companies window | — |
| **V1.4b** | ~~Sector regulation~~ **shipped** | `effects.company` on a **law**, a signed per-sector burden read by the two channels (a) built, a fifth `business` theme, deregulation as the negative direction rather than a repeal verb. No third channel, no budget line, no `SAVE_VERSION` bump | a |
| **V1.4c** | ~~Nationalisation and privatisation~~ **shipped** | `state_share` as a third field with a third single writer, a derived purchase price and windfall written to the **debt stock**, dividends as a computed revenue line yielding on output, and the jobs shield that is what "loss of control" turned out to mean. No `SAVE_VERSION` bump; `ISSUE_KEYS` answered **no** | a, b |

Three calls, each of which could have gone the other way:

1. **Bond markets belong to §6, not here.** A yield writes
   `debt_service_pct_gdp` against `DEBT_REAL_RATE_PCT` and shares no state with a
   firm. §6 is where inflation and the business cycle re-baseline every measured
   balance number anyway, so endogenising the rate there is **one** re-run instead
   of two — and a credit rating is that machine read at a second point, V1.3c's
   "one verb, two prices" shape, so it does not split back off. Both rows carry
   the cross-reference, so this does not become the twelfth missing row.
2. **The a/b line is architectural, not thematic.** A subsidy is an executive act
   and a regulation is a **law**: one goes through `companies.gd`'s own
   `execute()`, the other through `legislature.gd` and an assembly division. That
   is V1.3a's distinction between a diplomatic action and a law, one block later,
   and it is worth a session boundary because the approval path differs, not
   because the subject does.
3. **A firm must be smaller than a sector, or §4 IS §6.** "Subsidise a firm" and
   "sectoral investment — a lever pointed at a sector" are the same lever when a
   sector holds one named firm. So `_validate_companies()` refuses that at load,
   and the differentiator — `headcount` at the authored share — is what makes
   *which* firm a decision. The row named neither this collision nor the bond-market
   one.

Two things the cold read found that the decomposition rests on:

- **`SPENDING_KEYS` and `PORTFOLIO_KEYS` are the same list**, so a subsidy could
  not be a sixth spending line without being a sixth minister — which
  [docs/tiers/v1.md](docs/tiers/v1.md) §6 forbids. V1.3c's tariff revenue and
  V1.3g's deployment bill had already built the way out, and V1.4a is the fourth
  computed line rather than the first exception.
- **`data/companies/` was in the data-architecture tree and did not exist.** A
  plan, not a record — and now a record.

### V1.3 — the decomposition, and why these six

Written before any code, which is where a block-shaped row belongs: V1.3 was
one line — relations, diplomatic actions, trade agreements, tariffs, sanctions,
an EU-shaped bloc, nation AI foreign policy, defence as domestic politics — and
one line is not a session.

| | Session | Content | Reads |
|---|---|---|---|
| **V1.3a** | Relations and diplomatic actions | Pair-keyed relations as live state, monthly drift, a small set of player verbs with a domestic price | — |
| **V1.3b** | ~~Trade: per-partner intensity and agreements~~ **shipped** | `external_impulse_pct` made per-partner rather than one GDP-weighted aggregate; bilateral agreements with sector winners and losers at home | a |
| **V1.3c** | ~~Tariffs and sanctions~~ **shipped** | Coercion in both directions on the first **directed** state; one verb, two prices; a Laffer curve and a protectionist trade-off that fall out of two constants rather than being authored | a, b |
| **V1.3d** | ~~The bloc~~ **shipped** | EU-shaped membership as a real constraint on domestic policy, transfers, bloc-level voting where the player is one member among many; and the `ISSUE_KEYS` call a–c each deferred here, answered **yes** | a, b, c |
| **V1.3e** | ~~AI foreign policy: the interest model~~ **shipped** | Why a nation the player does not govern answers one way rather than another. Replaces **all four** stopgaps a–d shipped — the row said b–d and undercounted by one | a–d |
| **V1.3f** | ~~AI foreign policy: the acting agent~~ **shipped** | The nine pursuing their own interests *on their own initiative* — an agenda, a target, a cadence, and a surface for reading what was done to you. **The split the decomposition predicted**, taken on machine count rather than on the surface count it named | a–e |
| **V1.3g** | ~~Defence as domestic politics~~ **shipped** | Capability derived from sustained spending, deployments, defensive alliances, alliance obligations that bill you at home. **Reads a and d, exactly as the row said** — and d rather than a is what makes the obligation fire at all | a, d |

Four calls, each of which could have gone the other way:

1. **Relations ship with a verb, not alone.** A relations score with no reader
   is the failure [[scenario-model|V1.2e]] caught at design time: an axis with
   no persistent channel decays back to neutral inside a game year and is
   decorative. V1.3a ships the smallest closed loop instead — act on a
   neighbour, relations move, blocs at home react — rather than a state layer
   whose first reader arrives a session later.
2. **AI is fifth, and every session before it ships a *named* stopgap.** An AI
   with no action space to score is unbuildable, and an AI built at b is
   rescored by c and again by d. So b, c and d each ship a deterministic
   counterparty rule and **declare it as a stopgap V1.3e replaces** — the same
   shape `lose_condition: "never"` and `referendum_required` already use for a
   declared-unresolved rule. V1.3e opens with the checklist of them, so the
   debt is a list rather than a discovery.
3. ~~**The foreign-policy opinion issue is V1.3d's call, not V1.3a's.**~~
   **Answered at V1.3d: yes, and `europe` is the twelfth `ISSUE_KEYS` entry.**
   The reasons turned out to be structural rather than thematic — `bloc_offset`
   never enters `issue_salience`, so a Europe priced on it could never be named
   by the polling panel or the election result screen; a split price never clears
   the noise floor in the headline figure, and Europe is a split issue by nature;
   and a flat offset cannot become more *salient*, where a rule biting hard is
   exactly the thing that should raise how much the country argues about Europe.
   The cost was measured before it was taken and came in at **+0.39 %** on the
   ratio S10's finding was about. See [[bloc-model]]. The original wording: a–c use
   `law_bloc_offset`, the persistent channel that already exists. Whether
   foreign policy earns its own `ISSUE_KEYS` entry is decided at d, where the
   domestic politics of Europe is the mechanic rather than a side effect — and
   the cost is named in advance rather than discovered: a new issue means six
   new `BLOC_SALIENCE_BASE` rows, and [[declined]] records that *every* tuned
   opinion constant was measured against that one table.
4. **Defence stays last, and takes defensive alliances with it.** Already
   committed — a deployment with no counterparty is a spending line with a
   different label — and an alliance obligation that bills you at home needs
   both a counterparty (a) and a bloc (d).

**V1.3e is the row most likely to split**, recorded in advance rather than
discovered: if its own plan-time count comes back above V1.3a's, it splits into
an interest model and an acting agent, and the letters run to g.

Three things the cold read found that the decomposition rests on:

- **`external_impulse_pct` is already wired and deliberately quiet.**
  `economy_constants.gd`'s `TRADE_BETA` comment says so in as many words. V1.3b
  is the session that unquiets it — and every tuned economy constant was
  measured through that channel, so b is where the balance harness gets re-run,
  not a. **Half right, and the wrong half was the word "unquiets"**: b made the
  channel per-partner and directed as promised, and did re-run the harness, but
  the term stays numerically small until something perturbs a partner. See
  V1.3b's row above.
- **All ten nations already have a formed government.**
  `GameState._build_nation()` runs `Government.form()` for every nation, so each
  carries a `coalition_position` on the same two-axis space laws are scored
  against. V1.3e's interest function has authored inputs already; it does not
  need a new per-nation content class.
- **`data/eu_parliament.json` and `src/core/eu.gd` exist and are
  elections-only.** V1.3d extends that file rather than inventing a bloc.
  **Held**: `ep_seats` became the council's voting weight, which is what makes
  the file load-bearing beyond the elections it was written for.

**LimboAI was evaluated for V1.3e and declined** — see [[declined]] for the four
reasons and the condition that reopens it.

### V1.2e — start scenarios (shipped)

[docs/tiers/v1.md](docs/tiers/v1.md) §2's last item, and the one that closes
V1.2. A scenario is an authored starting state for one nation, applied once at
`GameState.new_game()` and never again — the project's answer to difficulty, and
the reason [docs/tiers/declined.md](docs/tiers/declined.md) declined a slider:
every balance number here is measured, so a multiplier over tuned constants
invalidates each measurement, while varying the starting state changes data and
no constant.

**Three axes, not §2's four.** Debt, seat composition and starting approval are
authored; **the coalition stays derived** by `Government.form()` from the seats
a scenario already authors. Authoring both would author a contradiction the
formation rule exists to resolve, and under GBR's `largest_party` the axis is
degenerate — the government is single-party by construction, so it is a field
one playable nation in three cannot use.

**The plan's named measurement ran, changed the content twice, and its first
result was an artefact.** `tools/scenario_probe.gd` initially reported the seats
axis as changing *nothing* — identical approval, deficit, debt and election
timing at every extreme. That was the regime, not the finding: `hands_off`
proposes no law, and the legislature is the only channel seats have. Split into
a legislative table and an economic one, the axis moves the amendment ceiling by
±0.06 — enough to flip reachability in **both** directions. Both seat scenarios
were then found wrong and corrected before release: `deu_grand_coalition`
cleared two-thirds by *exactly nothing* (0.667 against 0.667, on a rounding
boundary) and was widened; `gbr_hung_parliament` made amendments **easier** than
the standard start, the opposite of what it claims to be, and had its freed
seats moved onto the party both large parties exclude.

**A third of the feature was decorative and nearly shipped that way.** Every
satisfaction term is a delta against the nation's own start, so a fresh game's
approval target is exactly neutral — an authored approval written only to
`bloc_approval` decays back to 50 on a ~2.4-month half-life and is gone inside a
game year, while debt and seats persist. Caught at design time and held at its
target through `law_bloc_offset`, the channel `Government.penalise_blocs()`
already uses for a fallen government. [docs/tiers/declined.md](docs/tiers/declined.md)'s
own falsifier was otherwise measured and did **not** fire.

`SAVE_VERSION` stays at 8 — the one runtime-readable addition since V1.2b that
does not earn a bump, because a version-8 save's absent `scenario_id` reads as
"" and that is *correct* rather than silently wrong. Full account:
[[scenario-model]].

### V1.2d — system transition, and a third playable nation (shipped)

[docs/tiers/v1.md](docs/tiers/v1.md) §2's last mechanism item, built after
[[amendment-model|V1.2c]] gave it the amendment machinery to point at
`system_id` itself. **The plan's own cold read found the block as scoped
would ship to zero playable nations** — FRA and DEU both prohibit a change to
the form of the state outright (Art. 89 §5, Art. 79(3)), and every nation the
mechanic is actually about (GBR, ESP, BEL, NLD, LUX) was `playable: false`.
Corrected before any code was written: the session became transition **and**
a third playable nation, the United Kingdom, chosen because its `ordinary_law`
amendment bar settles reachability by construction rather than needing a
sweep that could come back unshippable the way Germany's did.

A transition writes a **complete** institutional bundle — `system_id` plus
`formation_method`/`censure_rule`/`dissolution_rule`/`amendment_rule`/
`term_limit`/`head_of_state`, all at once — checked against the **target**
system rather than the systems the amendment is proposed under, the cross-
check `_validate_amendments()` had to invert. A new template field,
`allowed_head_of_state_kinds`, makes the head-of-state write checkable the
same way. A seventh per-nation dispatch field,
`government.amendment.permits_system_change`, gates the whole mechanic —
France, Germany, Italy and Austria each entrench their form of state and
carry `false`.

**The restoration-direction reachability sweep needed widening mid-plan, the
same way V1.2c's Germany sweep needed sharpening.** Measured against only
GBR's actually-formed government, the ceiling was exactly that coalition's
own seat share (0.560) — below `parliamentary_republic`'s real `two_thirds`
(0.667). Widened to every 1–3-party coalition, matching the Germany sweep's
own method, the true ceiling is 0.680 — reachable, with a 1.3pp margin.
`restore_the_monarchy` shipped on the strength of the wider sweep. Full
account, including why the block earned its own session for a different
reason than the roadmap originally gave: [[transition-model]].

### V1.2c — constitutional amendment (shipped)

[docs/tiers/v1.md](docs/tiers/v1.md) §2's next item after V1.2b built the
templates it constrains. An amendment is [[legislature-model|the existing law
pipeline]] plus three additions — `constitutional: true`, a `systems` filter,
and a new `effects.institutional` channel that **sets** an institution rather
than nudging it, the only channel in the model that does. Everything else
(preconditions, cooldowns, seat-level vote resolution, the rebellion split,
the forecast) is reused unchanged.

The threshold is a **sixth** per-nation dispatch-on-a-data-string field,
`government.amendment.rule`, constrained by the template's own
`allowed_amendment_rules` — real constitutional fractions researched per
nation (3/5 for France's Art. 89 Congress vote *and*, corrected from a
plan-time table error, Spain's Art. 167 ordinary revision path; 2/3 for
Germany, Italy, Austria, Belgium, Netherlands; **3/4** for Luxembourg's real
referendum-waiving bar, added as a fifth rule rather than rounded down to an
existing tier; an ordinary majority for the UK's uncodified constitution; a
declared-unresolved mandatory referendum for Switzerland, the same shape
`lose_condition: "never"` already gives it).

**The plan named a measurement to run before any content was authored, and it
changed the plan.** A live sweep of `spatial_support()`/`coalition_bonus()`
against each nation's real starting seats, cohesion and discipline found
France's real `three_fifths` clears with room to spare (0.660 achievable
against 0.600 needed) but Germany's real `two_thirds` is **unreachable even
at the best possible moment in a term** (0.519 achievable against 0.667
needed) — the unmodelled Bundesrat co-requirement stacked on six-party
fragmentation. The response, decided rather than tuned around: Germany keeps
its real threshold, and no amendment content this session names
`parliamentary_republic` in its `systems` list. A named trigger — an
upper-house model or a grand-coalition start scenario — could raise the
ceiling later; until then the mechanic is honestly unshipped there rather
than shipped against a nation that can never pass it.

Also new: the load-bearing template cross-check V1.2b built for a nation's
*flat* fields now runs for every value a constitutional amendment could ever
*write* — a violating amendment fails to load, the same discipline a bad
nation file already gets. Article 49.3 cannot force a constitutional
amendment through, matching the real Article 89 procedure's lack of an
executive bypass. `SAVE_VERSION` 6 → 7 for `amendment_rule`, which — unlike
every other V1.2b institutional field — is itself mutable at runtime.

Full account: [[amendment-model]]. Content is
[docs/tiers/v1.md](docs/tiers/v1.md) §2.

### V1.2b — political system templates, head of state, term limits (shipped)

[docs/tiers/v1.md](docs/tiers/v1.md) §2's headline feature, built once there
was a working institutional layer to generalise. Most of what a template would
declare, nations already declared flat — `formation.method`, `censure`,
`dissolution.rule`, `election.system` — so the template earns its keep only on
what nations could not express before: the **head of state** (five
constitutional monarchies now say so, where nothing did before), a **named
lose condition** (`elections.gd`'s run-ending branch was dispatched on the
structural flag `has_executive`; now on `lose_condition`), and an **enforced
term limit** (France's two-term rule; `terms_served` had been tracked and read
by nothing).

The template is a **constraint, not a defaults table** — no inheritance, no
override resolution, so there is nowhere for a half-understood institutional
state to come from. `data_loader.gd` fails at startup if a nation's flat
formation/censure/dissolution value falls outside its declared template's
allowed set, which is what makes the template load-bearing rather than
decorative. Four templates, matching the roster
(`semi_presidential_republic` FRA, `parliamentary_republic` DEU/ITA/AUT,
`constitutional_monarchy` GBR/ESP/BEL/NLD/LUX, `directorial_republic` CHE) —
§2's other two named templates, absolute monarchy and one-party state, have no
nation in a ten-nation Western European roster to attach to, and are deferred
with a named trigger rather than authored unattached.

Enforcing France's term limit found a real collision with the balance
harness's long-horizon check, and a real (not a bug) divergence along the way:
moving that check to Germany, as planned, found that a do-nothing German
budget does not survive three elections either — the chancellor's party
erodes under 50% and loses "largest party" status by the second one, a
previously-measured France/Germany divergence surfacing again in a new place.
Full account: [[political-systems]].

Content is [docs/tiers/v1.md](docs/tiers/v1.md) §2; the model is
[[political-systems]].

### V1.2a — a second playable nation (shipped)

**V1.1e is not next.** After V1.1d shipped, the user asked not to spend another
session deepening the French assembly: four sessions running (V1.1a–d) each added
another layer of institutional detail to one nation, which reads as narrowing.
The scope-alignment pass took that as settled and picked the breadth move
instead. V1.1e is still buildable and still in order — it is re-parked below, not
cancelled.

Why this one rather than diplomacy or the political-system templates: it was the
cheapest breadth per unit of work, because **the content already existed for ten
nations**. All ten had authored `data/nations/*.json` and `data/parties/*.json`,
a real electoral system, a real formation and censure rule (`DEU.json` carries
`"censure": "constructive_absolute"`), and V1.1c's dissolution rule as ten-nation
data. `GameState.new_game(loader, player_id)` was already parameterised; the only
hardcoded player nation under `src/` was `PLAYER_NATION_ID` in `src/ui/main.gd`
(now `main.gd`'s `pending_player_id`, set by the menu's nation-select panel,
defaulting to France only for a scene built directly rather than through it —
see [docs/decision-log.md](docs/decision-log.md)).
[docs/scope.md](docs/scope.md) already calls France-only "debt with a known due
date", and every further block adds more of it.

**Shipped.** Germany is playable, chosen for maximum institutional contrast with
France. The two shared things a second player nation made wrong:

- **`data/policy_defaults.json` was one file for every nation.** Retired —
  every nation's `fiscal` block now carries its own `tax_rates_pct`,
  `spending_pct_gdp` and `other_spending_pct_gdp`, sourced per nation with
  France as the anchor. See [docs/data-architecture.md](docs/data-architecture.md).
- **`opinion_constants.gd`'s bloc weights are one global table.** Stayed that
  way — a measured decision, not a restated assumption. See
  [docs/tiers/declined.md](docs/tiers/declined.md).

The nation-select screen is one list on the existing main menu, so it rode with
this block rather than triggering a U block. **U5 stays reserved** for the
dashboard tab V1.1d deferred.

Full account, including the roadmap-row correction and the mid-build fix to the
balance probe's extreme regimes: [docs/decision-log.md](docs/decision-log.md).
Content is in [docs/tiers/v1.md](docs/tiers/v1.md) §2; the models built so far
are [[government-model]], [[discipline-model]], [[dissolution-model]] and
[[cabinet-model]].

### Re-parked, still in order

| Block | Where it sits now |
|---|---|
| ~~**V1.1e** Upper house and judiciary~~ | **Built**, and it was the LAST session of the V1 tier. Deferred on a stated preference rather than a dependency, and picked up when another France-institutions session was wanted. The judiciary half carried §5's "rule of law" with it, exactly as the handoff said it would. [[docs/upper-house-model.md]], [[docs/judiciary-model.md]] |
| **V1.1f** Referendums | ~~Deferred toward V1.7, which brings campaigns.~~ **Built at V1.7c**, and it was `nation.gd`'s own `KNOWN_AMENDMENT_RULES` stopgap rather than a new machine. |

**Two V1-tiered mechanics are orphaned and were found by V1.8's final sweep of the tier
column: `Embassies` and `Foreign aid`** ([[mechanics-foreign-policy]]), in no row of
[[v1]] and in none of `data/diplomatic-actions/`'s fourteen verbs — **instance
forty-nine**. Recorded rather than built, because V1.8 was the last session of the tier
and widening it to two unplanned verbs is the scope creep every decomposition on this page
exists to prevent. Both are cheap where they land: a fifteenth and sixteenth entry in a
directory that has served five sessions, on the existing `effects.relations` channel, so
neither needs a session of its own. Cross-referenced into [[v1]] §3 and §8.

**`ns.term_months` says 60 while the first election is 41 months out** was found
in the U3 audit and fixed in V1.1c: `nation_state.gd`'s comment tying `term_months`
to the legislative block was the bug, not either clock — both numbers were always
right for their own schedule. See [[government-model|the two clocks]].

V1.1c left one thing on the table, recorded rather than quietly carried:

- **`INCUMBENT_SWING`.** Discipline erosion made the censure branch fire, but no
  regime that *wins* its presidential election ever gets unpopular enough to
  reach it — so censure is live for the sixteen months before May 2027 and not
  after. V1.1c's own measurement (a 57-seat spread in what a snap election
  returns, swept across the approval range a player can hold while still in
  office) found dissolution did not need this term touched, but that measured
  something different from sustained low-approval *survival*, which is still an
  [[election-model]] question and still the same lever cohabitation has been
  waiting on since V1.1a. Left as found; not this block's or the next one's
  problem unless one of them needs it.

---

## Per-session: plan, model, effort

**Plan first** asks whether the session should be designed in plan mode before any
code is written. The test is not size — it is **how expensive the decision is to
reverse**. A schema or a simulation model that turns out wrong is rewritten along
with everything that reads it. A map renderer that turns out wrong is rewritten
alone.

**Model and effort** follow the same logic. Opus 5 at high effort is for open
design judgement — deciding what the model *should be* when several plausible
answers exist. Sonnet 5 at low or medium effort is for executing a decision that
is already made, which is most sessions once the docs are written.

| Session | Plan first | Model | Effort | Why |
|---|---|---|---|---|
| V1.1c Dissolution | **Yes** *(corrected)* | Opus 5 to plan, Sonnet 5 to build | High → Medium | Originally logged **Light / Medium**, flagged in advance as known wrong — "reads the schedule schema [[electoral-systems]] already settled" assumed the dissolution rule was already in that schema; it was not, and adding it was S1 class. The cold count at plan time found thirteen surfaces: a ten-nation schema addition, six state fields plus a save-version bump, a new sim module, a tick change, two panels, five test files, two probe regimes, eight docs. Third correction on this table's own record; see [[decision-log]]. |
| V1.1d Cabinet | **Yes** *(corrected)* | Opus 5 to plan, Sonnet 5 to build | High → Medium | Logged **High → Medium** on "ministers are a schema that departments, opinion and events all read — S1 class." The cold count at plan time found ~fourteen surfaces against that reading — V1.1c's own thirteen, plus a new content class (named individuals) and a dashboard tab. **Corrected by cutting scope, not raising effort** — the first correction on this table's record to resolve that way rather than by moving to a higher tier: portfolio → party (not named individuals), loyalty → resignation only (not a second hostility() term), UI → the existing Government panel (not a new tab). Cut to eleven surfaces, Medium held. Fourth correction on this table's own record; see [[decision-log]]. |
| V1.7a The campaign phase | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **The missing-row failure again, and by now it is the record rather than the exception**: this table stops at V1.5a and carries no row for any V1.5b-d, V1.6a-f or V1.7 session. Authored at plan time rather than read. The cold count came to ~24 surfaces - a new sim module and its constants, a new content class and directory, four NationState fields across four sites, the loader, `vote_share()`, the budget line and its panel row, a new window plus three wiring points in `main.gd`, a test file, a probe, two balance regimes across two harnesses, a screenshot flag and five docs - which is V1.3a's ~22 with two more, so **High**, and it held. The decision that was expensive to reverse was not the code: it was **where the campaign lands**, and two of the three candidates had to be refused before the third was found. |
| V1.7c Referendums and the electoral system | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | This table STILL carries no row for the session being planned - the missing-row failure is the record rather than the exception, and V1.7b's row was the first that could be read rather than authored. Authored at plan time. The cold count came to ~30 surfaces, above V1.7b's ~25: a new sim module and its constants, a schema split in `law.gd`, a widened `Legislature.tick_month` across twelve call sites, four serialised fields and a version bump, two new content classes in existing files, a diary row, two panels, a new probe, a new test, two balance regimes and two screenshot flags. **Machine count is ONE** - the referendum - because `electoral_systems.gd` already ships all five methods with a dispatch, which is why the row did not split. Held. What the count did NOT predict is that both halves of the row would be wrong about the BAR rather than the mechanism, which is instance forty-three. |
| V1.7b Campaign promises | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | Authored at plan time rather than read, because this table still carries no row for any V1.5b-d, V1.6a-f or V1.7 session but V1.7a's - the missing-row failure is the record rather than the exception. The cold count came to ~25 surfaces: a new sim module and its bounds, a new content class and directory, two `NationState` fields across four sites, the loader, a tick call wired into THREE harnesses, a panel section, a test file plus its `run_tests.sh` entry, a probe, three balance regimes across two files, a screenshot flag and six docs - V1.7a's ~24 with one more, so **High**, and it held. The decision that was expensive to reverse was not the code: it was **where the trust price lands**, which is this page's own pre-registered split trigger, and the plan's named escalation (a reachable breach unable to clear the poll floor without saturating the `bloc_offset` clamp) did **not** fire - the reachable full-term breach lands at 3.4 to 5.8 points against a floor of 3.0 and uses at most 30 % of the clamp. What the count did NOT anticipate is that the *first* dominance test and the *first* balance regime pair would both be measuring the wrong thing; both were caught by the probe, and neither cost a tier. |
| V1.8 Events | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **The missing-row failure one last time, and by now it is the record rather than the exception**: this table stops at V1.7b and the only thing to read was the V1.2-onward block cell. Authored at plan time. The cold count came to **~36 surfaces** -- eight new files, ~28 edits -- above V1.7c's ~30 and V1.7a's ~24, below U6a's ~40 and U6b's ~46. **ONE MACHINE, so V1.3e's split trigger does not fire**: fire → pending → choose → apply is one pipeline, which is V1.3d's own rule about proposal → vote → rule-in-force → constraint, the applier is an extraction from `Legislature.apply()`, and the notification surface is the column U5a built *for this*. First block since V1.1 not to decompose. **High on reversibility**, the test the preamble names: a `SAVE_VERSION` bump, a content schema a V2 tier inherits, and a full 43-regime re-baseline were all on the line. Held. **What was challengeable was the SECTION, and it did not hold** -- its two bullets are tiered in no `mechanics-*.md` table at all and every event-shaped mechanic that is tiered there is Someday (instance forty-four), which is what turned the session from an authoring exercise into a design one: an event is an **occasion**, not a mechanic. Four cuts declared and all four taken -- no map layer, no AI chooser, no corruption-scaled hazard, no new `PRECONDITION_FIELDS` entry. **The plan's escalation trigger 4 FIRED and was honoured by the response the plan named**: a career of defaults saturated `bloc_offset`, every regime converged on the same floor, and `tests/test_balance.gd` caught it as *managing the budget did not beat ignoring it*; magnitudes came down and the clamp did not move. **The probe corrected the session five times, twenty sessions running, and THREE of the five were corrections to the CHECK rather than to the model** -- E0's own deficit sign was backwards before any content existed, E2's band was written on an axis the channel does not reach in one step, E3's dominance rule counted an active choice beating the DEFAULT as a violation when that is the design, E3 decided a verdict on a ninth-decimal difference and so stayed silent, and E1's cadence clause passed every candidate from 3 to 20. What the count did not anticipate is that a **per-decision band and a career bound are two different constraints** and that the first would drive the content into the second -- V1.6f's *a bill is not a cost* in a new place. The screenshot pass earned its keep for the **twentieth** session running with four bugs, two of them the tool's, one of which had been silently degrading `--build` and `--campaign` since V1.6f and V1.7a. Twenty-third correction on this table's own record, and the eleventh to be an *addition* to it |
| V1.1e Upper house **and judiciary** | **Yes** *(corrected)* | Opus 5, plan and build in one session | **High** | **The TWENTY-FOURTH correction on this table's own record, and the first to be wrong about SCOPE rather than about size.** The row read *Light / Sonnet 5 / Medium -- a second chamber is the existing vote resolution run twice with different composition*, and it named ONE of the three things the session owns: the block is upper house **and judiciary**, and the judiciary half additionally inherits section 5's rule-of-law statistic, handed to it at V1.5's decomposition. *Run twice with different composition* is right about the resolver and silent about the two decisions that ARE the session -- where the second composition comes from, and what its verdict does. The cold count came to **~40-45 surfaces**: ten new files, ~30 edits, a ten-nation schema addition, a `SAVE_VERSION` bump, a change to the verb at the centre of the game that ~25 call sites reach, and a full re-baseline. High on reversibility, the test the preamble names. **Machine count is arguably TWO and it did not split**, on V1.8's own argument: bill → assembly → second chamber → court is ONE PIPELINE, which is V1.3d's rule, and in France the two are connected -- the Conseil constitutionnel is referred under Art. 61 by sixty senators, so the court is the upper house's remaining weapon once it has been overridden. **What the count did not anticipate is that the probe would delete a constant and a content field, and then a TEST would delete the model's central claim** -- see the session note below. |
| V1.2a Second nation | **Yes** *(held)* | Opus 5 to plan, Sonnet 5 to build | High → Medium | Logged **High → Medium** on a scope-alignment-time count of roughly ten surfaces, with an explicit flag to challenge it cold and to treat the bloc-weight call as the thing that could blow the tier up to an S1-class schema session. The cold count at plan time found **sixteen**, not ten — two of the logged surfaces did not apply (no `SAVE_VERSION` bump; most `FRA` literals in `tests/` were intentional France-specific assertions, not things needing parameterising) against three the log missed (the tax-erosion reference, the loader's playable-count check, the balance probe's absolute-figure regimes). Bloc weights were measured rather than moved into data — see [[declined]] — which kept the tier at Medium rather than raising it. Fifth correction on this table's own record, and the second (after V1.1d) that held its tier once corrected rather than moving up or down; see [[decision-log]]. |
| V1.2b Political systems | **Yes** *(held)* | Opus 5 to plan, Sonnet 5 to build | High → Medium | Logged **Medium** on a plan-time count of seventeen surfaces — one above V1.2a's sixteen — on the reasoning that no new tuned constant and no new model needed deciding, only a fifth instance of a dispatch-on-a-data-string pattern already built four times. Held: the two open design questions (constraint vs defaults table, four templates vs §2's five) were resolved at plan time, and the one place a mechanical rename could have been a behaviour change — the lose-condition dispatch — was flagged in advance and caught nothing wrong, though a different collision surfaced instead (see below). Sixth correction on this table's own record, and the third that held its tier once corrected. |
| V1.2c Constitutional amendment | **Yes** *(held)* | Opus 5 to plan, Sonnet 5 to build | Medium | Logged **Medium** on a plan-time count of ~eighteen surfaces — one above V1.2b's seventeen — on the same reasoning: no new model, a sixth instance of the dispatch-on-a-data-string pattern, real constitutional fractions rather than tuned constants. Held, with one condition stated in advance rather than discovered: if the plan's own named reachability measurement came back showing an amendment unreachable for a playable nation, that was a model decision escalating to Opus, not a Sonnet tuning call. The measurement fired — Germany's real two-thirds is unreachable — and the build session's own response (leave the real threshold, author no content against it) matched the plan's stated response closely enough that no escalation was needed; the plan-time rough estimate itself needed a live-state re-measurement to sharpen from "marginal/erodes to unreachable" to "unreachable even at term start", and a table error (Spain grouped at two-thirds instead of its real three-fifths) surfaced during that same pass, before any content was authored against the wrong number. Seventh correction on this table's own record, and the fourth that held its tier once corrected. |
| V1.2e Start scenarios | **Yes** *(held)* | Opus 5, plan and build in one session | Medium | Logged **Medium** on a plan-time cold count of ~20 surfaces — between V1.2c's ~18 and V1.2d's ~21 — on the reasoning that a scenario adds one new value type, one new validator in a pattern built four times, and two optional sim arguments, with no new tuned constant and no new model. Held. Two things the count got right in advance: `new_game()`'s ~50 call sites made a defaulted third parameter mandatory rather than optional, and the coalition axis was cut at plan time rather than discovered mid-build. One thing it did not: the plan treated an authored `bloc_approval` as a single write, and it needed a second (`law_bloc_offset`) or the axis would have decayed to nothing inside a game year — found at design time from `INERTIA_RATE`, before content existed, which is the earliest any correction on this table has been caught. The plan's own named escalation trigger (the reachability sweep coming back too narrow) did **not** fire; a different measurement problem did, and the response the plan named for it — split the report rather than trust the first number — resolved it without escalating. Ninth correction on this table's own record, and the fifth that held its tier once corrected. |
| V1.2d System transition | **Yes** *(corrected)* | Opus 5, plan and build in one session | Medium | Logged **Medium** on a plan-time count of ~21 surfaces — three above V1.2c's ~eighteen, for the seventh dispatch-on-a-data-string field, the inverted target-side cross-check, and a new template field. **Corrected at plan time, not at build time**: a cold read of the scope found it would ship to zero playable nations, and the session's scope grew to include a third playable nation before any code was written — the eighth correction on this table's own record, and the first caught before the plan was even finalised rather than during or after the build. The plan's own named escalation trigger (a reachability sweep coming back unreachable) fired once, for restoration, and resolved by widening the sweep rather than escalating — the response the plan itself named in advance. |
| U5a The ruler's shell | **Yes** *(authored)* | Opus 5, plan and build in one session | Medium | **This table had no U-track row at all** — every entry on it is S-track, and U1–U4 shipped without one. Recorded because that is a different gap from the missing V1.3b row: V1.3b was a session the decomposition forgot to tier, whereas the U-track was never on this table in the first place, which quietly encoded that UI work does not need the discipline. It does: U2's and V1.1c's corrections are the two the preamble names, and U2 is a U block. The count came in at **~28** surfaces, above V1.2d's ~21 and below V1.3b's ~33. Medium rather than High on the reversibility test the preamble actually names — a layout that turns out wrong is rewritten alone, and no simulation model, tuned constant or save field is at risk. Held, with one flag stated in advance: the pinnable window manager is new machinery rather than a rearrangement and was the one place the estimate could break. It did not, because `window_frame.gd` was given no knowledge of any panel and the panels were not edited — every `setup()` and every signal connection survived the move from dock to window untouched. Two cuts were declared and both taken: the map's real treatment and the minimap went to U5b, the calendar and its roster to U6. What the count missed was smaller than any correction on this table and was caught by looking rather than reasoning: the map's opening zoom and the windows' maximum height were both wrong on a 1080p screen and both invisible to a headless suite. Twelfth correction on this table's own record, and the second (after V1.3b) to be an *addition* to it |
| U5b The world map | **Yes** *(corrected at plan time)* | Opus 5, plan and build in one session | Medium | Second U-track row, and the first to inherit a written content row rather than a tier. The *Next* table's U5b cell listed five things; counting them cold made them **four separate new machines** — a raster pipeline, a world-geometry import pass, the minimap widget, and a layer system — at ~22 surfaces weighted heavier than U5a's ~28. U5a's own count held only because its one new machine, `window_frame.gd`, was given no knowledge of any panel; nothing in this row had that property. **Corrected at plan time, not at build time**, on the same test V1.2d's correction used: the layer system was cut to **U5c** because it was the only part carrying an unmade design decision *and* the only part reading sim state, so deferring it past V1.3c buys tariffs and sanctions in the same session instead of reopening the machinery for them. Remaining count ~17, three machines, held. What the count missed was not a surface at all and was found by watching a clock rather than by reasoning: Godot VRAM-compresses the 14.6-megapixel raster on any run with no `.godot/`, which is precisely the fresh clone `tools/run_tests.sh` exists to be fast in, and the first headless test of the run sat for the best part of ten minutes building an artefact nothing reads — the bytes are decoded from the `.jpg` directly. Fixed by committing a `.jpg.import` with `importer="keep"`. Thirteenth correction on this table's own record |
| U5c The map layers | **Yes** *(authored)* | Opus 5, plan and build in one session | Medium | **This table had no U5c row.** Third instance of the missing-row failure V1.3b recorded, and unlike U5b there was not even a content row's tier to inherit — the U5a decomposition wrote content for U5b, U5c and U6 and a tier for none of them. The cold count came in at **~13 surfaces**, the *smallest* on this table: three new files, nine edits, one conditional that turned out not to be needed (`ui_theme.gd` was not touched — the eight existing label variations carried the legend). Against U5b's ~17, V1.2e's ~20, U5a's ~28, V1.3b's ~33. **Medium rather than Low on reversibility, which is the test the preamble names and which barely fires here**: a ramp that turns out wrong is rewritten alone — no sim model, no tuned constant, no save field, and nothing downstream reads a colour. What keeps it off Low is that it is the session paying down U5b's deferred design decision, and one of its three calls was explicitly staked on a frame rather than an argument. **The count missed three surfaces and all three came from counting rather than from the row**, which lists three features and names none of them: the player's own nation has no value on either data layer, hover distorted the datum it was pointing at, and the map went stale because nothing redrew it monthly. The named escalation trigger — *a data ramp unreadable at any alpha, so terrain variance rather than alpha is what defeats it* — did **not** fire; what the screenshot pass did catch was smaller and was the same class of error as U5b's own: the relations ramp's warm end was set at 80, so the top resting tier of 68 landed only 40 % along the warm half and washed out. Domain tightened to 72, and resolution put where the game actually sits. Fourteenth correction on this table's own record, and the third to be an *addition* to it |
| V1.3b Trade: per-partner intensity and agreements | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **This table had no V1.3b row.** It stopped at V1.3a, so unlike every correction above this one is not a challenge to a logged estimate — it is an estimate authored at plan time with nothing to challenge, and the handoff convention's *read the row, count the surfaces yourself* had no row to read. Recorded because a missing row is a different failure from a wrong one, and the decomposition wrote per-session content and dependencies for all six without writing their tiers. The cold count came in at **~33 surfaces** — the largest on this table, eight above V1.3a's ~25, against V1.2d's ~21 and V1.2e's ~20. As with V1.3a the count is not what set the tier; the preamble's test is reversibility, and **both halves fire, the second for the first time in this block**: `w(A,B)` is schema-shaped with three downstream readers (c scales it, d reads it, e's interest function reads it), so a wrong weight function is rewritten with three sessions; and this is the first session to put **already-measured constants at risk** rather than add new ones, since every economy constant was tuned with this channel at zero and [[economy-model]]'s divergence argument had to be left standing. Held. Four cuts were declared in advance and the first was taken before any code: the separate `data/trade-agreements/` content type (terms ride the diplomatic action), then `economy_panel.gd`, a `Trade.tick_month()`, and a second agreement instance — the last three were not needed. Both named escalation triggers were GBR-shaped and stated before the model was built; **the first fired** and was resolved by the measurement it named rather than by escalating. Eleventh correction on this table's own record, and the first to be an *addition* to it. |
| V1.3c Tariffs and sanctions | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **This table had no V1.3c row either.** Fourth instance of the missing-row failure V1.3b recorded — V1.3b had none, U5b inherited a content row's tier, U5c had neither, and this had only the decomposition's content cell. The handoff convention's *read the row, count the surfaces yourself* again had no row to read, so the tier below is authored rather than challenged. The cold count came in at **~30 surfaces** — six new files, ~24 edits — against V1.3b's ~33, V1.3a's ~25, V1.2d's ~21 and U5c's ~13. As with V1.3a and V1.3b the count is not what set the tier; the preamble's test is reversibility, and **both halves fire**: the directed register is schema that V1.3d reads (a bloc setting external tariffs collectively reads exactly this), V1.3e scores as action space and V1.3f inherits the pattern for alliance obligations — so a wrong directed key is rewritten with three sessions; and it puts already-measured economy constants at risk through a new additive term in the growth equation and a new revenue line. Held. Three cuts were named in advance and **none was taken** — the map layer shipped, `sanction` shipped as a second kind, and the nation panel's readout shipped. What the count did not anticipate was that the probe would correct the *model* twice rather than merely set constants: an authored tariff rate cut as one intensity written twice, and damage read off the wrong weight making high severity strictly dominated. The named escalation trigger **fired on the first sweep and was resolved by the second of those corrections** rather than by escalating, which is the response the plan itself named. Two things the plan got wrong and the build found: `Budget.recompute()` needed a `state` parameter (three call sites, all of which had it), and the budget panel's "now" column was a month stale for the new line — caught by a test, not by looking. Fifteenth correction on this table's own record, and the third to be an *addition* to it. |
| V1.3d The bloc | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **Fifth instance of the missing-row failure V1.3b recorded**, and by now the pattern is the record rather than the exception: V1.3b had no row, U5b inherited a content row's tier, U5c had neither, V1.3c had only the decomposition's content cell, and this had the same. The tier below is authored rather than challenged. The cold count came in at **~39 surfaces** — eight new files, ~31 edits — the **largest on this table**, against V1.3b's ~33, V1.3c's ~30, V1.3a's ~25 and U5c's ~13. The count is again not what set the tier: the preamble's test is reversibility and both halves fire hard. A twelfth `ISSUE_KEYS` entry is read by S5 opinion, S6 attribution, S9 saves and three panels, and it puts the S10-measured salience table at risk — the second time in this block that already-measured constants were on the line, and the first time the *opinion* ones were. What kept ~39 surfaces inside one session is that the machine count is **three, not four**: U5b's lesson is that machines break an estimate, and proposal → vote → rule-in-force → constraint is one pipeline rather than two. Held. Three cuts were declared in advance and **all three were taken** — no bloc map layer, no separate rules content type, no accession mechanic. What the count missed was found the way U5a's was, by looking at a frame: the panel printed `deficit_pct_gdp <= 3.0` at a player, and its own budget section fell below the fold at the minimum height it shipped with. Both were one edit. The named escalation trigger — whether a bloc rule is legible at all — did **not** fire, at 2.47× the noise floor. Sixteenth correction on this table's own record, and the fourth to be an *addition* to it. |
| V1.3e AI foreign policy: the interest model | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **Sixth instance of the missing-row failure V1.3b recorded**, not the fifth — V1.3b had none, U5b inherited a content row's tier, U5c had neither, V1.3c and V1.3d had only the decomposition's content cell, and this had the same. The tier below is authored rather than challenged. **What was challengeable was the decomposition row itself, and it was wrong three ways**: it named three stopgaps where four shipped (V1.3a's no-reaction is the first, not a precursor); its split trigger — *a plan-time count above V1.3a's ~25* — had already fired on V1.3b (~33), V1.3c (~30) and V1.3d (~39) without any of them splitting, so it was a test that could not fail; and the tier table had no row at all. The cold count came in at **~28 surfaces** — five new files, ~23 edits — against V1.3d's ~39, V1.3b's ~33, V1.3c's ~30, V1.3a's ~25 and U5c's ~13. **The row split, and the count is not what decided it**: judged on machines, the interest model is *one* with four readers that all exist today, where the acting agent is a second — a scheduler, a target selector, new serialised state and a surface. U5b's lesson, applied where the row's own arithmetic test would have said the opposite. High on reversibility, the test the preamble names: V1.3f scores its entire action space against this function, so a wrong interest model is rewritten with f — V1.3a's own argument. Held. Three cuts were declared and all three taken: no agenda, no grievance ledger, no new content type. The named escalation trigger — the nine still behaving alike, measured as cross-nation L1 below the no-op line — did **not** fire, at 1.7×. What the count missed was all UI and all found by looking: the nation panel's verbs below the fold, and a partner-refused treaty rendering as a live button. Seventeenth correction on this table's own record, and the fifth to be an *addition* to it |
| V1.3f AI foreign policy: the acting agent | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **Seventh instance of the missing-row failure V1.3b recorded**, and this session's own plan found it by counting rather than by being told — the tier table stopped at V1.3e and the decomposition row was the only cell to read. **The decomposition row was challenged and held**, unlike V1.3e's, which was wrong three ways: the four nouns it names — an agenda, a target, a cadence, a surface for reading what was done to you — are exactly the four pieces built. The cold count came in at **~33 surfaces** — **no new files at all**, ~33 edits — level with V1.3b's ~33, against V1.3d's ~39, V1.3c's ~30, V1.3e's ~28 and V1.3a's ~25. **The surface trigger would have fired and the machine count is what mattered, exactly as V1.3e's correction said**: one machine, the agent, of which the scheduler and the target selector and the readout are parts rather than peers. No split. High on reversibility: a scheduler is the block's last new serialised state and V1.3g's alliance obligations inherit the pattern. Held. Three cuts were declared in advance and **all three taken** — no AI-to-player agreement inbox (the second machine that would have forced a split), no new content type, no map layer. **What the count did not anticipate is that the probe would correct the *model* four times rather than set constants**, which is now six sessions running and the highest count yet: interest-as-an-addend as a goodwill ratchet, unpriced friendly concessions, an unbounded and sign-inverted `third_party_effects()` that only an agent could expose, and a sweep that measured new-game when the binding state is month 24. The named escalation triggers were three; **trigger 1 (GBR, the fifth time) fired twice and was resolved by a model change both times**, trigger 2 fired once, trigger 3 never. What the count missed was found by looking at a frame, for the fourth session running: `act_reason()` computed, stored and read by nothing. Eighteenth correction on this table's own record, and the sixth to be an *addition* to it |
| U6a The president's diary | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **NINTH instance of the missing-row failure V1.3b recorded**, and the plan found it by counting rather than by being told, for the third session running — the tier table stopped at V1.3g and the U5a decomposition's one-line U6 cell was the only thing to read. **That cell was challenged and did not hold, three ways.** Its two promises contradict each other: "no new effect channel" and "politicians, celebrities, journalists, business, foreign leaders" cannot both be true, because a foreign leader is the face of a nation `data/nations/` already ships and a **journalist has no target that exists**, so meeting one *is* a new channel — U6b authors political faces only and the rest went back to [[v1]] §4 and §5, which already say they inherit the roster. Its framing was also wrong about which half is hard: "S-track, not U — the surface is the easy half" reads the roster as the cost, and the surface is where both this session's real problems were. The cold count came in at **~40 surfaces and FOUR machines** — a content roster, a scheduler at a new tick resolution, a scarce-time model and a calendar grid — the **largest on this table**, above V1.3d's ~39, V1.3b's and V1.3f's ~33, V1.3g's ~34, V1.3c's ~30, V1.3e's ~28 and U5c's ~13. **Split, on machine count, which is V1.3e's trigger and the third session to use it**; the cut is U5b → U5c's, deferring the half carrying the unmade content decision. U6a alone: ~26 surfaces, three machines. **High on reversibility, the test the preamble names, and it fires for a reason none of V1.3's rows had**: this is the first thing in the project to read a resolution finer than a month, and the whole balance harness is a month loop with no clock — so a wrong tick placement is not caught by any existing regime and is rewritten with every session that ever books anything. Held. **The session's one tuned constant was DELETED by its own probe**, which no session on this table has done before: the band was fixed before the sweep, the sweep found it structurally unreachable rather than mis-tuned (the median month offers 27 legal acts asking 124 days, so every budget bound in 100 % of months), and the constant went the way of `AGREEMENT_ACCEPT_MIN` rather than being tuned until it looked alive. **The probe corrected itself twice — both times V1.3f's measuring-the-wrong-state error, in the file written to avoid it** — and a panel test found the third and sharpest: 31 % density over fourteen years hides that a **new game's next twelve months are completely empty**, which is the one page every player sees. Two things the plan got wrong and the build found: booking cannot go on `nation_panel.gd` (a second button narrows an autowrapping label and grows the row, at the panel that has paid for that fold twice), and `upcoming()` filtered to unfired entries so the strip's own resolved-entry styling was dead code — caught by looking at a frame, for the **sixth session running**. A third came from a test that had never run: `test_state_copy.gd`'s array probe pushes a float sentinel, every copied Array on either state object had been untyped until now, and the three existing `Array[Dictionary]` fields were all excluded for unrelated reasons — so the branch reported "shared with the copy" for a field that is duplicated correctly. Twentieth correction on this table's own record, and the eighth to be an *addition* to it |
| U6b The people | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **TENTH instance of the missing-row failure V1.3b recorded**, and the plan found it by counting rather than by being told, for the fourth session running. **The decomposition cell was challenged and did NOT hold** — it says the session "authors the roster", and the roster half already existed: ~70 named people were live as loose strings across `data/nations/`, `data/parties/`, `data/laws/amendments.json` and three serialised `NationState` fields, with **every nation file writing one person's name twice** and `party.gd` documenting that duplication as a *convention*. The real job was making a person first-class the way a party already is. Cold count **~46 surfaces** — the largest on this table, above U6a's pre-split ~40 and V1.3d's ~39 — of which ~25 are ONE mechanical re-key, V1.3a's own reading of its `bloc_offset` rename. **ONE machine**, so V1.3e's split trigger does not fire: the register is the machine, the window is its surface, and the derivation had no scheduler, no decision and no new serialised state. High on reversibility, the test the preamble names: a person-id vocabulary is read by [[v1]] §4 and §5 forever and it re-keys three save fields. Held. **The probe corrected the model once and itself twice, which is nine sessions running.** A flat ordered bench picked by rank made adding one portfolio renumber every minister a party already had — 22 department changes in one run for reasons about nobody; replaced by a **shadow cabinet** keyed by portfolio, which makes churn structurally impossible rather than damped and is the more legible model besides. Then the probe's own election counter reported **zero elections for every nation over fourteen years**, which is impossible, and churn was gated on it; and the first cast-size table had no vacancy column, so a collapsed government read the same as a thin roster. **The kill switch FIRED and was honoured**: 6 distinct people against a pre-committed floor of 12, and a perfectly healthy single-party GBR at 7 with zero vacancy across three elections — so the minister bench was **cut before it was authored**, U6a's currency deletion one session on, and `cabinet-model.md`'s deferral is recorded as still correct rather than reversed. Three cuts declared in advance and all three taken: no attribute on a person, no bench for the seven non-playable nations, no re-namespacing of party ids. A fourth was taken mid-session and not planned: **`src/core/people.gd` was deleted before it was written**, because with the bench cut a name lookup is a dictionary read and every panel already holds the loader. What the count did not anticipate was found by running a check rather than by looking at a frame: **`tools/check_names.sh` iterates `git ls-files`, so the first run over the new register passed with zero hits and zero files scanned** — the largest exposure that check has ever had was, for one run, not being checked at all. **The re-run is bit-identical across all fourteen regimes with no fifteenth needed**, which the plan predicted on checkable grounds and which is a first for this run of sessions: U6a and V1.3g each needed a new regime because each added a verb, and a name is not a decision. Twenty-first correction on this table's own record, and the ninth to be an *addition* to it |
| U6c The project marker layer | **Yes** *(authored)* | Opus 5, plan and build in one session | **Low** | **The missing-row failure again, and by now it is the record rather than the exception**: this table stops at U6b, and the only thing to read was V1.6f's own split paragraph plus [[projects-model]] §1's three-machine table. The cold count came in at **~16 surfaces and TWO machines** - two new files, ~11 edits - against U5c's ~13, U5b's ~17, V1.6e's ~22 and U6a's ~40. Held. **Low on reversibility, which is the test the preamble names, and it is the first Low on this table**: no simulation model, no tuned constant, no save field, no new effect channel and nothing downstream that reads a marker - a glyph that turns out wrong is rewritten alone. The one thing that could have raised it was the content decision, and that is exactly what the row got wrong. **The row was challengeable and did not hold - instance thirty-nine, and it is in a phrase this page used three times.** *"Per-project geography as content"* forces a lon/lat into `effects.project`, and `data/project-actions/` is a **global flat list**, so all ten nations would build the rail spine at one point on the planet; the only repair is to make that directory per-nation, which reopens the global-list call V1.6f made freely. **Geography is per-NATION**, on an optional `project_sites` block in `data/nations/*.json` - U6b's rule verbatim - so the action list stays global and `src/core/project_action.gd` was **not edited at all**. The handoff offered the `project_name` exception as precedent for a coordinate; it was not needed. **Two cuts were declared in advance and both were taken**: no fifth `LAYERS` entry (already settled by `map_view.gd`'s own header, and as a layer it would read exactly 0.0 for nine of the ten forever), and no site content for the seven nations that cannot build - `data/companies/`'s coverage rule, with the absent-block path pinned by a test. **What the count missed was the wording, and the screenshot pass found it for the sixteenth session running**: the hover read *"12 of 96 months"* against a project with twelve months LEFT, which a player reads as twelve done. Worded exactly as `projects_panel.gd` words it now, so two surfaces on one register cannot disagree about which number that is. Twenty-second correction on this table's own record, and the tenth to be an *addition* to it |
| V1.5a The delivery layer | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **ELEVENTH instance of the missing-row failure V1.3b recorded**, and the plan found it by counting rather than by being told, for the fifth session running — the tier table stopped at U6b and V1.5 had no decomposition to inherit a content cell from either, so this is the first row since V1.3b with *nothing* to read. **What was challengeable was the §5 row itself, and it was wrong eight ways** — five collisions and three orphans, listed under *V1.5 — the decomposition*, of which the sharpest is that **bullet 9 asks for a machine the project has built three times under three names**: `military_capability`, and `potential_shift_pct` twice. The cold count came in at **~28 surfaces** — five new files, ~23 edits — level with V1.3e's and U5a's ~28, against U6b's ~46, U6a's ~40, V1.3d's ~39, V1.3g's ~34, V1.3b's and V1.3f's ~33, V1.3c's ~30 and U5c's ~13. **ONE machine**, so V1.3e's split trigger does not fire at the session level: the stock is the machine, corruption is one factor at an existing site, and there is no scheduler, no decision and no new accumulator. High on **reversibility**, the test the preamble names, and both halves fire: `effects.society` is schema (c) and (d) read, so a wrong channel is rewritten with two sessions; and this is the first session since V1.3d to put an **already-measured opinion constant** at risk, because `QUALITY_SCALE_PP` and `SPEND_SCALE_PP` land on the same issue and their ratio *is* the double-count answer. **The re-run was predicted NOT to be bit-identical, and predicted before it ran** — every session since V1.3d has been, because each channel read exactly 0.0 until a player *command* fired, where this one's trigger is the budget slider, which the regimes move |
| V1.3g Defence as domestic politics | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **EIGHTH instance of the missing-row failure V1.3b recorded**, and the plan found it by counting rather than by being told, for the second session running — the tier table stopped at V1.3f and the decomposition row was again the only cell to read. **The decomposition row was challenged and held**: capability, deployments, defensive alliances and obligations are exactly the four things built, and its "reads a, d" was right in a way it could not have known — **d is what makes g fire at all**. The cold count came in at **~34 surfaces** — six new files, ~28 edits — level with V1.3b's and V1.3f's ~33, against V1.3d's ~39, V1.3c's ~30, V1.3e's ~28 and V1.3a's ~25. **The surface trigger would have fired again and the machine count again decided it**: ONE machine, the commitment, of which the pact is the cause and the capability stock the price — and V1.3e's test (*is there a second thing with a scheduler, a decision, new serialised state and a surface?*) answers no **precisely because** the accept/refuse obligation surface was cut, which is the second machine V1.3f cut once already. No split. **Four cuts declared in advance and all four taken**: no obligation inbox, no Military window, no `has_budget` lift, no economy reader for capability. **The probe corrected the model three times, which is seven sessions running**: the nine never coerce each other, so the obligation is unreachable without the COUNCIL and the first run reported zero for the wrong reason; the headline approval figure cannot move on a `defence` price at all, because five blocs of six weight that issue at zero, so the test moved to the rural row rather than the constant moving; and the first opinion table measured **half the price**, having set the load and not the bill that widens the deficit every bloc does weight. Of five named escalation triggers, **one fired** — GBR unable to ally, for the sixth time in the block, resolved by a sweep that put `PACT_ACCEPT_MIN` at 1.00, *below* the trade-agreement bar and inverting the argument that set it. **The clamp was measured and found SLACK**, which is a first for this block: the worst reachable obliged bill is 0.586 against a guard rail of 2.00. What the count did not anticipate was found by looking at a frame for the **fifth session running**, and this time the bug was in the tool: `--defence --open budget` showed an em dash against a live 0.498 bill, because hiding a window frame does not clear the child panel's own `visible`, so every panel spends its one refresh on frame 1 and never rebuilds — every state-mutating screenshot flag since V1.3c had been capturing pre-mutation figures and getting away with it. The nation panel's fold reappeared at the same panel one session after V1.3e paid for it, and **height alone could not fix it**. **The re-run is bit-identical across every shared regime**, which the plan did not predict and table (h) explains: four new verbs entered `data/diplomatic-actions/` and changed no AI choice, because `state_visit` wins 90 pairs of 90 on being the only verb priced at exactly zero. Nineteenth correction on this table's own record, and the seventh to be an *addition* to it |
| V1.3a Relations and diplomatic actions | **Yes** | Opus 5, plan and build in one session | **High** | Logged **High** on a decomposition-time cold count of ~22 surfaces — one above V1.2d's ~21 — but the count is not what moves the tier. V1.2c, V1.2d and V1.2e each held Medium on the same stated reasoning: *no new model, no new tuned constant, an nth instance of a dispatch pattern already built n−1 times.* All three are false here. V1.3a is a new model (`docs/diplomacy-model.md`), new tuned constants (drift rate, action magnitudes), and the first state in the project that is neither per-nation nor global. What sets the tier is **reversibility**, which is the test this table's own preamble names: a pair-key schema that turns out wrong is rewritten along with everything V1.3b–f reads off it. The surfaces counted: `data/relations.json`, `src/core/relations.gd`, `data/diplomatic-actions/*.json`, `src/core/diplomatic_action.gd`, `src/sim/diplomacy.gd`, `src/sim/diplomacy_constants.gd`, `data_loader.gd` load plus cross-file validation, `GameState.relations` across `to_dict`/`from_dict`/`duplicate_state`, `SAVE_VERSION` 8 → 9 and `save_manager.gd`'s refusal path, `NationState` cooldowns and last-result, `main.gd`'s tick insertion, `nation_panel.gd`, `map_view.gd` colouring (the cut candidate), five test files, `tools/diplomacy_probe.gd`, and five docs. Counted by the **decomposition** session rather than by the one about to build — which by this table's own record is the estimate most likely to be wrong. Challenge it cold. **Challenged, and held.** The cold count at plan time came in at **~25**, three above the logged ~22, and High held on the reversibility test rather than on the count. Two of the logged surfaces were wrong in opposite directions: `data/relations.json` does not exist (starting values are derived, so it became ten `neighbours` arrays plus a mutuality check), and the `bloc_offset` rename logged as "nearly free" was ~30 edit sites across five code files, four test files and eight docs. Both cuts were named in advance; **the map-colouring cut was taken and the content cut was not** — four actions shipped, not three. The escalation trigger did not fire. Tenth correction on this table's own record, and the sixth that held its tier once corrected. |
| ~~V2.1a The panel system~~ | **Yes** | Opus 5, plan and build in one session | **High** | **BUILT. The first row on this table written BEFORE the session, and read cold it was wrong in five places and silent in four.** The estimate said ~14 surfaces, 2 new files and "all fifteen" registered panels; counted, `src/ui/` is **41 files** (not 25), `register()` knows **fourteen**, and the session came to ~18 surfaces and 3 new files. **The machine count held and the session did not split.** **High on reversibility was right and is the whole argument for the row** -- a primitive set that turns out wrong is rewritten along with twenty-five panels that read it -- and what the count missed is where the work was: **five hand-written lists of panel names, not one**, including `tests/test_shell.gd::EXPECTED_PANELS` at **seven of fourteen**, which is not a refresh bug at all but a check that had silently covered half of what it appeared to since U5a. **The row's own "what to challenge" was the session's sharpest result and it went the other way**: the fold contract CAN be expressed without giving up on a test, because `tests/test_nation_panel.gd`'s standing claim that a headless suite cannot see a fold was right in its observation and wrong in its diagnosis -- the layout runs, the minimum-size cache lags one invalidation, and *impose a width, let a frame pass, then read* is exact to the pixel. **The one new visual rule was split in two** because it was doing two jobs and because half of it already existed unthemed: `ui_theme.gd` had styled `ProgressBar` and never `VScrollBar`. The screenshot pass earned its keep for the **twenty-first** session running with three bugs, two of them live and older than the session -- `fit_within()` spent the whole band on the scroll so every full window overflowed by ~50px, and a window is sized from its content as it was before the refresh that fills it. One flag was written and **deleted** as a no-op (the viewport stretch makes a window resize meaningless), U6a's currency one tier on. Twenty-fourth correction on this table's own record, and the twelfth to be an *addition* to it |
| ~~V2.1b The twenty-five panels~~ | No | Sonnet 5 | **Low → Medium** | **BUILT.** The row was wrong on the count twice and on the effort once, and read cold that is **the twenty-fifth correction on this table's own record**. There are **19** `*_panel.gd` and **sixteen** were left, not twenty-two or twenty-five; **`map_view.gd`, one of the three files it said would not fit one context together, is not a panel and builds no rows.** *Low* assumed pure substitution: what it did not name is two kit changes forced by panels (PLAIN meaning body text, a figure's caption wrapping), two retained tables rebuilt as ledgers, and one panel needing re-composition. **The one-or-two question is answered ONE, and the trigger declared in advance did not fire** -- exactly one panel could not be re-plumbed, and ordering rather than height fixed it. What the row could not have known is where the work was: **four panels had no private helper at all** and built sixty-six raw Labels inline, so V2.1a's own check would have called them clean forever -- `check_names.sh`'s U6b failure in a third place, inside the test written to end it. **The handover was a stale read**: section 7's two numbers are a cold panel's minimum, and the fix booked against them was written, measured, and deleted
| ~~V2.1c Navigation and the resting screen~~ | **Yes** | Opus 5, plan and build in one session | **Medium** | **BUILT, and the row's real question was answered by a MEASUREMENT rather than by the argument it invited.** *Prove the map still carries it* held: `tools/nav_probe.gd` ran fourteen years with nothing ever opened and found the resting screen silent in **42 of 74 pending-months** for a president who never touches a card and **64 of 74** for one who reads a card and closes it -- a council vote and an open campaign window silent in **100 %**, having no card at all. So the response is one mark on the cluster where the answer is given, **no plate and nothing new on the map**, and `dashboard.gd` stays deleted. **Medium was right and the effort landed somewhere the row did not name**: the cluster grammar cost almost nothing because the capacity table **refused the question it was asked** -- the bar may use 1384px of 1920 and the widest plausible drawer uses half of it, so width cannot force a fifth cluster or choose one, and the four hold on grammar. What the row could not have known is the **seventh hand-written list of panel ids**: `_unhandled_input()` bound six of fourteen windows and `test_shell.gd` held the same six as a literal, invisible to `test_panel_kit.gd`'s scanner because they were ids and keycodes in `tests/`. **Instance fifty-two is in the row's own wording** -- of its five surfaces to place, the day agenda is a ribbon and a city is reached by clicking the map. Twenty-sixth correction on this table's own record
| ~~V2.2a The import and the register~~ | **Yes** *(authored)* | Opus 5, plan and build in one session | **Low - Medium** | **BUILT, and this is the missing-row failure in its PUREST form: not a row that was wrong, a row that was ABSENT.** This table stopped at V2.1c, so the tier/model/effort call was authored at plan time with nothing to challenge -- the fifty-plus instance, and the first where there was no text to read at all. The cold count came to **~36 surfaces, ~14 new files and four machines** across two tracks, so **the block split** on the rule that cut V1.6e, V1.6f and U6c, and this session is (a). **Low-Medium on reversibility was the reason for Opus and it was the right axis**: the region LEVEL and the two-level share schema are what V2.4, V2.5, V2.6, V2.7 and V2.8 all read, so getting the level wrong means re-importing and re-authoring every downstream reference. **And the level was the decision the row could not have contained** -- it says NUTS 2, and NUTS 2 for France is the regions abolished in 2016 while NUTS 1 for Switzerland is one country, so the level is per nation and it is a measurement. **The row's Britain problem was half wrong in the direction that mattered**: regional GDP is absent at every year, regional POPULATION is complete for all ten at 2019, and the register only ever needed population -- so V2.2a needed no second source and the gap passes to V2.5 with the ONS probe recorded. **What the count did not anticipate is that the one measured constant would have to be measured THREE TIMES**, and that all three corrections would come from reading the generated file rather than from a check: 607 `PPLX` districts, a London naming twenty of its own boroughs, and thirty-six arrondissements GeoNames codes inconsistently. The first answer was wrong by 29 %. Each is now an assertion in `tests/test_geography.gd` rather than a paragraph. **No screenshot pass, for the first time since U5a** -- there is no UI, and that is the split working rather than a gap. Twenty-seventh correction on this table's own record, and the thirteenth to be an *addition* to it |
| ~~V2.2b The map and the two panels~~ | **Yes** *(authored)* | Opus 5, plan and build in one session | **Medium** | **BUILT, and for once there WAS a row to read: the V2.2 split table's (b) cell, the first session since V2.1a to inherit one.** Held. The cold count came to **~19 surfaces, 4 new files** -- the loader load, a draw module, two panels, the map's three new passes and a hit test, two flags, one test, five docs -- against U6c's ~16 and V2.2a's (a)-half ~22. **Medium on reversibility, the preamble's own test for a map session** (*a map renderer that turns out wrong is rewritten alone*), and it held: no sim model, no tuned constant in `src/sim/`, no save field, `SAVE_VERSION` stays 27. **The four design calls were all made at plan time by the player** (regions-as-the-fill at every zoom, keys T/V, all ten nations' crosses clickable, the full 581 above the threshold) and none was revisited. **What the row could not contain were three findings, and all three came from the project's own discipline rather than from the build**: the first draft of `CITY_MIN_ZOOM` sat at 2.2, ABOVE the opening Europe fit, which computes to ~2.1 on 1080p -- the volume clause was measured FOR the ~1000 px opening fit, so a threshold above it would ship 581 cities the default frame never shows, and the correction came from computing the fit, not from taste (V1.5b's endpoint-of-the-range diagnostic, applied to a constant nobody swept); the markers' source-purity check **fired on this session's own doc comment**, because its extraction swallows the next function's comment and the city doc legitimately named what it must not reach -- the test was the authority and the function moved; and the two-pass fill/hairline draw is load-bearing because **the roster carries an enclave of EACH direction** (Berlin outpopulates Brandenburg; Bremen is a third of Niedersachsen), so no single fill-and-stroke order renders both -- a fact in the data, found by reading it. **Two handoff notes were stale and both said the same thing**: `screenshot.gd`'s dirty list was deleted at V2.1a (registering IS the whole job), and the month-136 warning was inherited by nothing. **The screenshot pass returned** after V2.2a's skip and judged three frames clean. Twenty-eighth correction on this table's own record, and the fourteenth to be an *addition* to it |
| ~~V2.3 The face of power~~ | **Yes** *(authored)* | Opus 5, plan and build in one session | **Low - Medium** | **BUILT, and the missing-row failure in its purest form a second time: the table stopped at V2.2b, and the only V2.3 text anywhere was the block line.** Tier/model/effort authored at plan time, V2.2a-style. The cold count came to **~32 surfaces, 5 new code/recipe files** (generator client, duotone pass, workflow JSON, resolver, test) plus **71 committed rasters and 16 more at-icons SVGs**, against V2.2b's ~19 and V2.2a's (a)-half ~22. **ZERO sim machines -- no scheduler, no decision, no serialised state, nothing under `src/sim/` -- so V1.3e's split test does not fire**, and `SAVE_VERSION` stays 27 with no balance re-run (drawing is not a verb, U6c and V2.2b running). **Low-Medium on reversibility held, with the honest caveat the row must carry: the project's largest asset decision BY COUNT** (71 binaries against the fonts' five and the map's one; measured **1.77 MB total, largest single file 33.9 KB**, so the Blue Marble's 2.5 MB stays the largest binary by far). **Three calls the doc left open, all taken by the player at plan time**: portraits come from the author's local ComfyUI through a committed recipe (Juggernaut X Hyper; the PNGs canonical where the machine drifts) with the **likeness policy "evokes, never depicts"** -- described archetypes, never a name; **a missing portrait is SILENT in game**, the silhouette relocated to `portrait.gd` as the shared fallback, with stale art the refused direction; and the author's own mid-session "background per situation" became a **nation-hue band**, display-side, the map's own PALETTE. **The player rejected the first wall on sight -- "too lookalike" -- and the correction is the row's sharpest finding: a prompt that pinned everything but the seed made 71 near-siblings, because "one crop, one eyeline" constrains the FRAME and the FACE is where variety lives**; the recipe now varies seven traits per person, each decorrelated by its own hash of the id, and the duotone pass still erases frame drift. The build also paid two tool-side taxes worth recording: a `_comment` key added to an API-format workflow is a 500 on current ComfyUI (recipe notes live in the client now), and icons travel on `register()` itself so the drawer, the title bar and the test all read one source -- the keycode lesson applied one session early. **The screenshot pass is this row's honest gap: no vision path survived in the session that built a wall of faces** -- the frames were captured, not judged, and the author holds the verdict |
| V2.4a The day becomes real | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **The first row on this table written BEFORE its session since V2.1a**, per the author's standing instruction to decompose heavy blocks at plan time rather than on the machine-count trigger alone. Authored at plan time with the V2.4 decomposition note in [[docs/tiers/v2.md]] §4 to challenge. Cold count: **~22 surfaces and THREE machines** -- travel duration with day-block occupancy (a `Diplomacy.travel_days()` over the V2.2 register's capital coordinates, the entry carrying `travel_days` so `calendar.gd` stays a leaf), a meeting-unlock register (`GameState.met_months`, a stamp read as a level so no accumulator decays), and the ribbon surface under the action bar. **High on reversibility, the preamble's own test**: the booking-entry schema and the pair register are read by every session that ever books or treaties, and U6a's day dispatch becomes load-bearing for the first time. Predicted in advance: **`SAVE_VERSION` stays 27** (absent `met_months` = never met, absent `travel_days` = day-only block, both true of every old save), and the re-run is **bit-identical** because the meeting gate is inert for the nine -- `state_visit` already wins 90 of 90 pairs and pacts are unreachable by the agenda. Scarcity is **occupancy only**, the author's call: no ceiling constant, U6a's currency stays deleted, and the probe's job is to verify block conflicts actually bind for a booking player | **BUILT, and the row's effort call held while its bit-identity prediction did not**: the meeting gate reaches the nine after all -- a pair on state_visit cooldown used to fall through to the treaty verbs, and the gate seals that hole until the pair has met. One regime of the re-run moved (managed_imposes_tariffs), last digits only, zero outcome changes; the mechanism is in [[docs/calendar-model.md]] §12. The probe's own findings: the occupancy band PASSED at 35 % unplaceable (and 76 % of wants conflict at their preferred day before the scan finds room -- the first run measured 0 % because it fired each visit the moment it booked, letting this month's visits erase each other's occupancy), the window's clauses hold only on [12, 24) with 12 the smallest passing and stable on the widened grid, and 280 km/day is interior to its grid on the Rome anchor. Two live bugs found on the way, both older than the session: main.gd and balance_probe.gd read `result.get("ok")` off execute(), whose contract is `applied` -- every kept diplomatic arrival since U6a fired its effects and was recorded as refused -- and LUX's capital was "Luxembourg City" against the register's "Luxembourg". SAVE_VERSION stays 27, both predicted absences pinned |
| V2.4b The scenes | **Yes** *(authored)* | Opus 5, plan and build in one session | **Medium-High** | The second half, whose step 0 is a gate rather than a build: **`dialogue_manager` must prove it runs headless before any content is authored**, because `tools/run_tests.sh` is `--headless --script` and an addon that cannot init there would break the suite the moment it is committed. The author chose adoption over the in-house events shape knowingly -- the priced cost is a committed `addons/` and the project's **first stated exception to the no-autoloads rule**, both recorded in CLAUDE.md's Gotchas rather than left to be re-derived. Cold count: **~20 surfaces and TWO machines** -- the summit surface (a leaf `summits.gd`, content in `data/summits/`, effects through the existing extracted applier so no new channel, chained off a state visit's arrival in the orchestrator) and the `interrupt` class (one boolean on a closed key list, a pause path on `clock.paused` which exists since the MVP, and a **reload re-raise** so a save mid-crisis cannot dodge the question). Predicted: `SAVE_VERSION` stays 27, re-run bit-identical (no regime books a visit), and V1.8's non-modal argument is pinned as a test that holds for every event *without* the flag -- the reversal is the flagged class only | **BUILT, and the step-0 gate earned its keep before anything else happened**: `dialogue_manager` instantiated and compiled a dialogue clean under `--headless --script`, the addon landed whole (790 KB, 122 files, MIT), `DialogueManager` entered the committed `project.godot` as the project's FIRST stated no-autoloads exception -- and the same commit cleaned the per-machine `MCPRuntimeServer` line out of the committed tree, where it had crept into HEAD undocumented. The summit is ephemeral by construction: drawn deterministically off the meeting stamp, applied through the shared applier, serialising NOTHING -- `SAVE_VERSION` stays 27 and `tests/test_summits.gd` pins the absence. The sidecar contract (every response priced, every price behind a real response, channels shared with law and event only) is refused loudly at load. **The re-run moved where the prediction said it would not -- but not because of the summits**: `blackout_night`, the shipped interrupt crisis, is a HAZARD that draws on debt >= 95 %, which most managed regimes hold, and its default applies bloc_offset unanswered; ~990 output lines wobbled, every one a margin or a last digit, ZERO verdict flips -- V1.8's re-run reason exactly. Two compile gotchas worth the ink: dialogue_manager TITLES reject spaces (the first draft's `~ Raise the Rhine shipping tolls` failed to compile; snake_case titles, human labels), and a new script cannot type its own return -- CLAUDE.md's first gotcha, caught by script_check at line 32 |
| V2.5 The economy from below | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | Authored at plan time per the standing instruction, with [[docs/tiers/v2.md]] §5 and its warning box to challenge. **High on reversibility** because the region level is what V2.6 (people move) and V2.7 (network and resources) both read, and the definitional swap in `economy.gd` is the spine. Cold count from the plan's own File Structure table: **~24 surfaces, 4 new files, ONE machine** -- one machine is why V1.3e's split trigger does not fire and the block is not decomposed. Predictions, written before the build: **`SAVE_VERSION` 28 on one field** (`region_gdp_eur_bn` -- absent, the sum is 0.0 and the country has no economy); **the re-run bit-identical in every printed figure** (the zero-mean deviation leaves only the second-order Jensen term, ~1e-9 relative per month); **no new regime** (no verb, and every regime exercises the new code through `Economy.tick_month()`); no new map layer (`LAYERS` stays 4); no verb at all | **BUILT, and the plan-time calls held with two corrections the plan could not have contained.** The bit-identity prediction held at the figure level and told the truth at the bit level: **143 of 144 runs identical in every printed figure**, one run (`tax_zero_DEU`) differing by a single debt digit on a `%.1f` rounding boundary -- the predicted Jensen term reaching a print edge -- and **zero outcome changes**. The gate held: all twelve ITL1 figures were NOT obtainable (ONS carries ten of twelve, and an index besides), so the proxy branch was taken honestly and **Britain has no regional divergence at all**, recorded as a bound with the number beside it. Two findings the plan had no way to name: **the plan's own decomposition test was a real red** -- the Okun term is zero-mean in GDP weights, so its population-weighted mean is a 0.0037-point residual, and the test now asserts the two exact halves separately rather than one approximate figure; and **`GameState.duplicate_state()` dropping the register collapsed the budget projection to the residual alone** (a France losing 98 % of its output in the panel's own forecast), which `tests/test_budget.gd` caught the same day the spine moved. The Dutch vintage sibling (`NL31`↔`NL35`, `NL33`↔`NL36`, proven by population equal to the person) and Switzerland's mix-only fallback (branch GVA absent for the country; GDP and unemployment fully measured) are both measured joins the plan's gate never anticipated. `test_geography.gd`'s refusal was **narrowed without ever going red** -- the one reader takes the register as data and preloads nothing, so the marker is the field contract now. The screenshot pass returned for the twenty-first time and found **no bug**, V1.6c's clean-sheet precedent. Twenty-ninth correction on this table's own record, and the fifteenth to be an *addition* to it |
| V2.6a People move | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **There was no V2.6 row on this table**, so the tier/model/effort call was authored at plan time with the V2.6 decomposition note in [[docs/tiers/v2.md]] §6 to challenge -- the missing-row failure in its purest form a THIRD time (V2.2a first, V2.3 second). Cold count: **~28 surfaces, 4 new files, ONE machine** -- the migration machine itself, one expression applied twice with different denominators; one machine is why the block still split rather than the machine count, the split cutting on the tier's own shape: (b) and (c) are different conservation laws, not more of this one. **High on reversibility**, the preamble's own test: the two share registers are read by both panels, the map and every later sited session, and the tier's *a city is to population what a firm is to sector output* call is what this session makes live. Predictions, written before the build: **the re-run bit-identical AT THE BIT LEVEL** (sharper than V2.5's -- no national quantity moves, no population share enters any equation outside `migration.gd`, so a single moved digit is a defect, not a rounding boundary); **no new regime**, no verb; **`SAVE_VERSION` 29 on two fields** (both share registers -- absent, every city has a population of zero); no map layer. The one value deliberately unset: `MIGRATION_RATE := 0.0` at Task 2, measured at Task 8 -- the project's own order, a constant is measured not guessed, and the machine is inert until then | **BUILT, and the predictions held with one defect caught in the band's own clause.** The bit-identity prediction held at its sharpest: **1582 of 1582 printed lines byte-for-byte identical** between baseline `d8a1baa` and `dcbc42d`, zero outcome changes, zero digits moved -- the probe's only diff was per-machine addon noise (24 lines on the worktree side, 3 on head), one contiguous block AFTER the last `invariants: OK` line, checked for a third stray line (V1.7c's gotcha) and none found; method honesty recorded because the plan said BOTH sides from worktrees and only the baseline was one, so the noise did not cancel -- it was isolated instead. **The band defect: clause (ii) read `SHARE_DRIFT_MAX` (0.05), so the upper crossing restated the guard rail** -- the clamp-measuring failure V1.5c, V1.6c and V1.6e each named, caught mid-task; the ceiling was re-measured from Europe (`tools/region_drift.py`, Eurostat `demo_r_pjangrp3` 2014-2025 over exactly the register's roster: **0.0164, AT13 Wien**, largest not mean) and the rate re-swept **0.0273 -> 0.0102**, interval [0.0081, 0.0123], stable at 0.0002 and 0.0001 steps, interior on all four grids. **The ceiling is GENEROUS, not like-for-like** -- it measures TOTAL population-share change (fertility, mortality, international migration) while the model moves only internal migrants with both residuals frozen -- and headroom (the measured ceiling over the band's upper edge: 0.0164/0.0123 = 1.333) is a third, with the runner-up (ES30 Madrid, 0.009858) BELOW the 0.0110 collapse threshold: a re-measured ceiling under that is a kill switch to honour. **The realism was bought at a price worth naming**: the shipped rate sits only 1.26x above the clause-(i) crossing (DEU binds at 0.00126 against the 0.001 floor) and visible movement fell to under two-fifths of the defect's (FRA's month-60 mover 0.0051 against 0.0131). Two structural bounds with numbers beside them: **Britain migrates on named employers alone** (region column exactly 0.0000 at every rate -- V2.5 §8's `moved 0.000` inherited as predicted) and **Luxembourg is ONE region holding ONE city**, `pull - mean` exactly 0.0 at both levels, unable to move at any rate whatever. `SHARE_DRIFT_MAX` stays 0.05, now honestly a guard rail: worst realised drift 0.0137 (FRA), slack 0.0363, ~3x the ceiling; realised partition drift **6.66e-16** against a 1e-12 ABSOLUTE tolerance, ~1500x -- the first suite run in which the flow executed at all, every closure check before it having been vacuous under the zero-rate early return. **`SAVE_VERSION` is 29 on two fields, and the plan said the constant lives in save_manager.gd -- it lives in `src/core/game_state.gd:426`**; the bump verified load-bearing (strip either register from a round trip: size 0, no re-seed), and the absence that STAYS red is a stored city POPULATION -- a head count is `population x share x share`, and storing one is a second answer. The review also found **`tests/test_summits.gd` authored at V2.4b and NEVER registered in `run_tests.sh`**, hard-pinning `SAVE_VERSION` 27 -- silently red for two versions; registered, and the audit says all 73 test files are in the runner. **The screenshot pass returned and found NO BUG** -- `--move` the block's one new screenshot flag, four frames judged, a clean sheet for the third time after V1.6c and V2.5. Thirtieth correction on this table's own record, and the sixteenth to be an *addition* to it |
| V2.6b A place for what happens | **Yes** *(authored)* | Opus 5, plan and build in one session | **Medium-High** | Authored at plan time per the standing instruction, with the V2.6 decomposition note in [[docs/tiers/v2.md]] §6 to challenge -- this row has never been read cold, and the receiving session counts and challenges it before accepting it. The content: **unrest sited and campaign meetings sited**, both *a national quantity acquires a place*, both deciding **where** by reading V2.6a's live shares -- one shape, not two, which is the whole reason they are one session. Plan-time count: **~18 surfaces, 2-3 new files, ONE shape applied twice**. **Medium-High on reversibility** because the siting shape is schema: V2.9's sited disasters (*an event with a place, which V1.8's schema cannot express*) will read whatever "a place" means after this session, so a wrong shape is rewritten with a later session. The political price V2.6a declined is this session's to charge: a demonstration happens where the people are, and the people are now somewhere. Predicted in advance, to be challenged: **`SAVE_VERSION` stays 29** if sites are derived from live shares each month and stored nowhere; the re-run is the first in three sessions that may legitimately move, because unrest and campaign effort are national quantities that enter opinion -- whether siting moves the national aggregate is exactly the session's first measurement |
| V2.6c Natural change | **Yes** *(authored)* | Opus 5, plan and build in one session | **Medium-High** | Authored at plan time per the standing instruction, with the V2.6 decomposition note to challenge cold. The content: **birth rate and life expectancy**, §0's freed row, arriving with the mechanism that reads it. **A DIFFERENT CONSERVATION LAW from V2.6a's** -- internal migration is zero-sum nationally and natural change is not, so the closure properties asserted in [[docs/migration-model]] do not transfer and the re-run cannot be predicted bit-identical from them. **The step-0 gate is the session's first act, and it can cut the session**: whether REGIONAL age structure is obtainable from Eurostat `demo_r_pjangrp3` (already fetched at V2.2a) -- without it, births and deaths only re-split one measured `pop_growth_pct` into two, which is exactly what V1.5b refused with evidence, and the honest outcome is a recorded bound rather than an authored machine. Plan-time count: **~12 surfaces, 2 new files** if the gate passes. **Medium-High on reversibility**: population is the spine since V2.5 -- a head count enters the economy through the region sums -- so a wrong natural-change term moves every figure the re-run pins, which is the preamble's own test for high, discounted by the gate's real chance of cutting the session to a measurement |

> [!note] V1.2b's plan got a real collision wrong, and the build found it
> The plan assumed enforcing France's term limit could move the balance
> harness's long-horizon three-election survival check to Germany "unchanged
> from V1.2a's numbers." Running it found Germany's own do-nothing budget does
> not survive three elections either — a real, previously-measured divergence,
> not a bug. The build session caught this by running the harness rather than
> reasoning from the plan's own text, and rewrote the check to assert what its
> name actually promises. See [[political-systems]] and [[decision-log]].

Every V1.2+ block gets a plan, on Opus 5. By then there is enough built that
changes ripple.

> [!tip] These are starting points
> If a session marked Sonnet stalls — repeated failed attempts, a bug that will
> not localise — escalate to Opus rather than grinding. The cost of one wrong
> model choice is minutes; the cost of grinding is a session.

> [!note] The effort column has been wrong before, in one direction
> U3 is the counterexample: counted at plan time, Medium held. The count is the
> discipline, not the correction. S7 was written High → Low and built at Medium.
> The tell each time is the same:
> the estimate counted the headline artefact (fifteen law templates) and not the
> wiring around it (vote resolution, four effect channels, a third UI surface,
> two tests). When in doubt, count the surfaces the session has to touch, not the
> feature it is named after. See [[decision-log]].

## Session handoff

Every session runs in a **fresh chat**. Context from building S3 is dead weight
when starting S4, and a long session degrades before it ends.

That only works if the handoff is written down, so **the last thing every session
does, after the commit, is output a copy-ready prompt for the next one** — a
prompt, in a code block, ready to paste with nothing to edit.

### Keep it short, and put nothing in it that a doc already says

A handoff carries **only what is written nowhere else**: a gotcha, a rejected
approach, a version pin, a thing that surprised the session. If a line of it
restates [CLAUDE.md](CLAUDE.md) or this file, delete the line — a prompt that
duplicates a document is a second copy that drifts, and the copy is the one that
will be believed.

Anything load-bearing enough to want in the prompt belongs in a doc **instead**.
Write it there, and let the prompt say which doc to read.

Past **fifteen lines**, the surplus is duplication. Treat the length as the test.

The prompt contains:

- Which session, and the instruction to do that one only.
- Which docs to read first.
- What is written nowhere else, if anything. Often nothing.
- The instruction to verify against that session's done-when list before claiming
  done, and to write the next handoff after the commit.

### The effort call belongs to the receiving session, not the handing-off one

The prompt does **not** argue the plan / model / effort row. It says: *read the
row, count the surfaces yourself, challenge it before accepting it.*

This is not a preference, it is what the record shows. The effort column has been
corrected twice, and **both corrections came from the session about to do the
work, reading the row cold at plan time** — U2's, and V1.1c's. Neither came from
the handoff that preceded it, and the preceding session shipped both times
without noticing. A session writing its own successor's estimate is doing it at
the point of worst context degradation, on the subject it is least able to be
objective about.

> [!tip] A cold read is worth buying before a plan-first session
> Both catches above came from a fresh chat that had built nothing and read the
> repo from scratch. Before a session marked **Plan first: Yes**, a short
> throwaway chat that reads only the roadmap and the code and reports what the
> row misses costs little and has a hit rate of two for two. Not worth it
> routinely.

If the handoff prompt is hard to write because the session ended in a messy
state, that is the signal — finish or revert the mess before writing it, not
after.

---

## V1.2 onward

Deliberately coarse. These are not broken into sessions until the block before
them is done, because the shape of each depends on what the previous one turns
out to need. Full detail in [docs/tiers/v1.md](docs/tiers/v1.md).

| Block | Rough content |
|---|---|
| **V1.2 Political systems** | ~~Additional playable nations **first**, then system templates as data, constitutional amendment, monarchy ↔ republic transitions, start scenarios~~ — **all shipped, block closed at V1.2e** |
| **V1.3 Diplomacy and trade** | ~~Relations, diplomatic actions, trade agreements, tariffs, sanctions, EU-shaped bloc, nation AI foreign policy, **defence as domestic politics**~~ — **decomposed into six sessions, V1.3a–f**, before any code. The table and the argument are under *Next* above |
| **V1.4 Companies** | ~~Named fictional firms, subsidies, regulation, nationalisation, privatisation, bond markets~~ — **decomposed into three sessions, V1.4a–c**, before any code, and **all three are shipped**. Bond markets moved to V1.6, which claimed the same mechanism. The table and the argument are under *Next* above |
| **V1.5 Society** | Media, scandals, unions, strikes, protests, corruption, demographics, migration, inequality — **decomposed into four sessions, V1.5a–d**, before any code. Rule of law left the block for §1's judiciary (V1.1e), and inequality's *instruments* are §6's. The table and the argument are under *Next* above |
| **V1.6 Economic depth** | ~~Inflation, business cycle, tax brackets to a target of five taxes, sectoral investment, infrastructure — sector count stays at three — **plus bond yields and the credit rating**, handed over by V1.4's decomposition~~ — **decomposed into five sessions, V1.6a–f**, before any code, **became six**, and **ALL SIX ARE SHIPPED — the block is COMPLETE**. (e) split on TRACK rather than on shape — *visible on the map* is a U-track surface — and (f) then split **on the same rule**, shipping the sim half and leaving the marker layer to **U6c** - **built, so §6 is complete to its last clause**, and the session that found the *per-project geography* wording to be instance thirty-nine. The table and the argument are under *Next* above |
| **V1.7 Campaigns** | Campaign phase, binding promises, electoral system choice, referendums - **decomposed into three sessions, V1.7a-c**, before any code, and **(a) and (b) are shipped**. The cell named four items where section 7 carried three bullets and neither count was right: **referendums have no bullet in that section at all** (instance forty-one) and they join electoral-system choice in (c), because a referendum is the amendment machine's own declared-unresolved rule and an electoral system is a seventh `effects.institutional` key - one shape, not two. Machine count is **two**. The table and the argument are under *Next* above |
| **V1.8 Events** | ~~Data-defined events with preconditions, choices, consequences — last, on purpose, and re-argued rather than assumed~~ — **built in ONE session and the V1 tier is COMPLETE**. The cell was right that it should be last and wrong about what would be there when it arrived: the section's own two bullets are tiered in no `mechanics-*.md` table (instance forty-four) and every event-shaped mechanic that is tiered there is **Someday**, so an event had to be an **occasion** rather than a mechanic. The union-of-channels argument is right about the timing and wrong about the shape (forty-six), the orphaned V1 "Decree / executive order" is discharged here (forty-eight), and two more V1 orphans are recorded rather than built (forty-nine). Model: [docs/events-model.md](docs/events-model.md) |

Three of those cells changed in the scope-alignment pass rather than in a build
session. The arguments are in [docs/tiers/v1.md](docs/tiers/v1.md) and
[[decision-log]]; the short version is that defence is scheduled thin and only
where it has a counterparty, the economy's granularity numbers are now decided
rather than open, and Events stays last for a better reason than the one
originally written — with a named condition that would move it.

### Two dashboard tabs waiting on a model

Neither exists, and neither gets a tab until it has something behind it. Recorded
here so the omission is a decision rather than an oversight.

| Tab | Blocked on | Today |
|---|---|---|
| **Military** | **V1.3f** specifically, now that V1.3 is decomposed — capability, deployments, alliance obligations. No longer an open-ended "no model exists", and no longer a whole block away: it is one named session, and the tab is that session's own UI call | One `defence` spending line under Budget, its opinion issue, and a Defence portfolio |
| **Demographics** | **V1.5b** specifically, now that V1.5 is decomposed — cohorts, the dependency ratio, migration. No longer a whole block away, and inequality is not part of it: that statistic is V1.5c's and its instruments are §6's | One field, `population`, under Economy |

Both are cheaper than they were: U5a replaced the tab rail with four themed
clusters and a sub-row, so neither needs a bar redesign. A new surface is one
`register()` in `main.gd` and one line in `_build_action_bar()`'s list.

### U5b, U5c and U6 — the sessions U5a split off, and the one U5b split off

All were part of the same request and are scheduled rather than parked.

| Session | Content |
|---|---|
| ~~**U5b** The map~~ | **Built.** A world satellite raster (NASA Blue Marble, public domain, plate carrée — already `map_view.gd`'s projection, so it dropped onto the existing transform with no reprojection step), Natural Earth world borders at 1:110m, the minimap in the slot `clock_cluster.gd` reserved at its final size, nation labels. Non-simulated countries render and are **not clickable** — `_nation_at_lonlat()` iterates the roster's dictionary alone, so that is structural rather than a filter. The repo's first large binary asset, 2.5 MB, with its provenance in [[data-sources]] under the same rule the at-icons exception states |
| ~~**U5c** The map layers~~ | **Built**, and built *before* V1.3c rather than after — asked for, the way U5a was. That spends the second of the two reasons the row gave for deferring it (one session colouring tariffs too), and the mitigation is the shape the session shipped in: `src/ui/map_layers.gd` is a **registry**, so V1.3c's sanctions layer is one entry in `LAYERS` plus one branch in `_value()`/`ramp()` and touches `map_view.gd`, `map_legend.gd` and `main.gd` not at all. The first reason — the unmade design decision — is what the session paid down; the three calls are below |
| ~~**U6a** The president's diary~~ | **Built**, and the row above split to build it. Booking is a scheduling skin over the verbs that already exist and it is **optional** rather than a replacement, because nothing in `src/sim/` reads a day so a deferral buys nothing. The costing-days half was measured and **cut**. What the session is actually judged on is the half the row never named: election day, the European election, the presidential term, the council's next proposal and its pending vote, the dissolution lockout and every cooldown expiry are dated state the game has carried for sessions with no surface that shows any of it. Model: [[calendar-model]] |
| ~~**U6b** The people~~ | **Built.** And the row was wrong about what the work was: the roster half already existed — ~70 people were authored as loose strings in FIVE places, and **every one of the ten nation files wrote a person's name twice**, so the session was a migration into `data/people/` rather than an authoring exercise. Only **five** names are new, the pretenders for the five republics, which fixed a live content bug: `amendments.json` authored one king inline and the Restoration Act applies to any `parliamentary_republic`, so every republic in Europe restored the same man. A person is an **id and a name and nothing else** — `role`, `title` and `party_id` were all cut before the file was written, because the reference that owns each relationship already states it, which makes "no mechanism on a person" true by construction. The `SAVE_VERSION` bump [[v1]] §5 booked did land, 13 → 14, but on a **re-key** rather than a new field. **Ministers did not**: the probe cut the bench before it was authored. `verb_key()` is unchanged and U6a's `person_id` hatch was not needed. Model: [[people-model]] |

Beyond V1: [docs/tiers/someday.md](docs/tiers/someday.md), not scheduled, and
[docs/tiers/declined.md](docs/tiers/declined.md), decided against with a route
back.
