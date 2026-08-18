# Roadmap

Build order for Nation Simulator. Short, scoped sessions — **one clear objective
each**, git commit at every session boundary.

This document is **forward-looking**. What shipped is one line each in the table
below; the corrections made along the way are in [[decision-log]]; the models are
in the model notes.

Scope reference: [docs/scope.md](docs/scope.md) · [docs/tiers/mvp.md](docs/tiers/mvp.md) · [docs/tiers/v1.md](docs/tiers/v1.md) · [docs/tiers/declined.md](docs/tiers/declined.md)
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

MVP done-when checklist: [docs/tiers/mvp.md](docs/tiers/mvp.md). All boxes ticked.

---

## Next

**V1.6 is decomposed into five sessions, V1.6a-e, before any code, and (a) is built.**
The argument, the four calls it made and the two rows it caught are under *V1.6 - the
decomposition* below. Order: (a) the business cycle, (b) inflation, (c) bond yields and
the credit rating, (d) five taxes and brackets, (e) sectoral investment and
infrastructure projects - and **(e) is recorded in advance as the row most likely to
split**, the device this page used for V1.3e and V1.5d.

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

**V1.1e** (upper house and judiciary) stays re-parked rather than cancelled.

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

### V1.6 - the decomposition, and why these five

Written before any code, which is where a block-shaped row belongs: V1.6 was five
bullets plus an obligation inherited from V1.4c, and one line is not a session.

| | Session | Content | Reads |
|---|---|---|---|
| **V1.6a** | ~~The business cycle~~ **shipped** | A **stateless** deterministic shock over all ten nations, into `economy.gd`'s growth sum. Amplitude **fitted** to France's measured growth volatility, per-nation spread **imported**, common share **measured twice**. `SAVE_VERSION` **19**. Re-baselined V1.5c's two constants and found them unchanged | - |
| **V1.6b** | ~~Inflation~~ **shipped** | A stock on the **unemployment gap**, not the output gap -- the row's three named inputs are one quantity written three times AND the measurement refuted the survivor. No nominal layer. Two prices: a growth addend and the **thirteenth `ISSUE_KEYS` entry**, the first YES after five noes. Three constants measured, two swept. `SAVE_VERSION` **20** on three fields of four | a |
| **V1.6c** | Bond yields and the credit rating | `DEBT_REAL_RATE_PCT` becomes an anchor, not the rate. Reads debt, deficit, `unrest_pct` and (b)'s inflation; the rating is that machine read at a second point. **Inherits V1.4c's obligation WHOLE**, not halved -- see below | a, b |
| **V1.6d** | Five taxes and brackets | Capital gains and wealth as `TAX_KEYS` 4 and 5, brackets *within* income. Discharges V1.5c's declared Gini stopgap by turning `tests/test_unrest.gd` red on purpose, through a **second field** rather than a second writer | - |
| **V1.6e** | Sectoral investment and infrastructure projects | The block's one genuine new player verb, on `sector_output` itself, with no employment term | a, d |

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
| **V1.1e** Upper house and judiciary | Unchanged and unblocked. Deferred on a stated preference, not a dependency — pick it up when another France-institutions session is wanted. |
| **V1.1f** Referendums | Deferred toward V1.7, which brings campaigns. |

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
| V1.1e Upper house | **Light** | Sonnet 5 | Medium | A second chamber is the existing vote resolution run twice with different composition. |
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
| V1.5a The delivery layer | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **ELEVENTH instance of the missing-row failure V1.3b recorded**, and the plan found it by counting rather than by being told, for the fifth session running — the tier table stopped at U6b and V1.5 had no decomposition to inherit a content cell from either, so this is the first row since V1.3b with *nothing* to read. **What was challengeable was the §5 row itself, and it was wrong eight ways** — five collisions and three orphans, listed under *V1.5 — the decomposition*, of which the sharpest is that **bullet 9 asks for a machine the project has built three times under three names**: `military_capability`, and `potential_shift_pct` twice. The cold count came in at **~28 surfaces** — five new files, ~23 edits — level with V1.3e's and U5a's ~28, against U6b's ~46, U6a's ~40, V1.3d's ~39, V1.3g's ~34, V1.3b's and V1.3f's ~33, V1.3c's ~30 and U5c's ~13. **ONE machine**, so V1.3e's split trigger does not fire at the session level: the stock is the machine, corruption is one factor at an existing site, and there is no scheduler, no decision and no new accumulator. High on **reversibility**, the test the preamble names, and both halves fire: `effects.society` is schema (c) and (d) read, so a wrong channel is rewritten with two sessions; and this is the first session since V1.3d to put an **already-measured opinion constant** at risk, because `QUALITY_SCALE_PP` and `SPEND_SCALE_PP` land on the same issue and their ratio *is* the double-count answer. **The re-run was predicted NOT to be bit-identical, and predicted before it ran** — every session since V1.3d has been, because each channel read exactly 0.0 until a player *command* fired, where this one's trigger is the budget slider, which the regimes move |
| V1.3g Defence as domestic politics | **Yes** *(authored)* | Opus 5, plan and build in one session | **High** | **EIGHTH instance of the missing-row failure V1.3b recorded**, and the plan found it by counting rather than by being told, for the second session running — the tier table stopped at V1.3f and the decomposition row was again the only cell to read. **The decomposition row was challenged and held**: capability, deployments, defensive alliances and obligations are exactly the four things built, and its "reads a, d" was right in a way it could not have known — **d is what makes g fire at all**. The cold count came in at **~34 surfaces** — six new files, ~28 edits — level with V1.3b's and V1.3f's ~33, against V1.3d's ~39, V1.3c's ~30, V1.3e's ~28 and V1.3a's ~25. **The surface trigger would have fired again and the machine count again decided it**: ONE machine, the commitment, of which the pact is the cause and the capability stock the price — and V1.3e's test (*is there a second thing with a scheduler, a decision, new serialised state and a surface?*) answers no **precisely because** the accept/refuse obligation surface was cut, which is the second machine V1.3f cut once already. No split. **Four cuts declared in advance and all four taken**: no obligation inbox, no Military window, no `has_budget` lift, no economy reader for capability. **The probe corrected the model three times, which is seven sessions running**: the nine never coerce each other, so the obligation is unreachable without the COUNCIL and the first run reported zero for the wrong reason; the headline approval figure cannot move on a `defence` price at all, because five blocs of six weight that issue at zero, so the test moved to the rural row rather than the constant moving; and the first opinion table measured **half the price**, having set the load and not the bill that widens the deficit every bloc does weight. Of five named escalation triggers, **one fired** — GBR unable to ally, for the sixth time in the block, resolved by a sweep that put `PACT_ACCEPT_MIN` at 1.00, *below* the trade-agreement bar and inverting the argument that set it. **The clamp was measured and found SLACK**, which is a first for this block: the worst reachable obliged bill is 0.586 against a guard rail of 2.00. What the count did not anticipate was found by looking at a frame for the **fifth session running**, and this time the bug was in the tool: `--defence --open budget` showed an em dash against a live 0.498 bill, because hiding a window frame does not clear the child panel's own `visible`, so every panel spends its one refresh on frame 1 and never rebuilds — every state-mutating screenshot flag since V1.3c had been capturing pre-mutation figures and getting away with it. The nation panel's fold reappeared at the same panel one session after V1.3e paid for it, and **height alone could not fix it**. **The re-run is bit-identical across every shared regime**, which the plan did not predict and table (h) explains: four new verbs entered `data/diplomatic-actions/` and changed no AI choice, because `state_visit` wins 90 pairs of 90 on being the only verb priced at exactly zero. Nineteenth correction on this table's own record, and the seventh to be an *addition* to it |
| V1.3a Relations and diplomatic actions | **Yes** | Opus 5, plan and build in one session | **High** | Logged **High** on a decomposition-time cold count of ~22 surfaces — one above V1.2d's ~21 — but the count is not what moves the tier. V1.2c, V1.2d and V1.2e each held Medium on the same stated reasoning: *no new model, no new tuned constant, an nth instance of a dispatch pattern already built n−1 times.* All three are false here. V1.3a is a new model (`docs/diplomacy-model.md`), new tuned constants (drift rate, action magnitudes), and the first state in the project that is neither per-nation nor global. What sets the tier is **reversibility**, which is the test this table's own preamble names: a pair-key schema that turns out wrong is rewritten along with everything V1.3b–f reads off it. The surfaces counted: `data/relations.json`, `src/core/relations.gd`, `data/diplomatic-actions/*.json`, `src/core/diplomatic_action.gd`, `src/sim/diplomacy.gd`, `src/sim/diplomacy_constants.gd`, `data_loader.gd` load plus cross-file validation, `GameState.relations` across `to_dict`/`from_dict`/`duplicate_state`, `SAVE_VERSION` 8 → 9 and `save_manager.gd`'s refusal path, `NationState` cooldowns and last-result, `main.gd`'s tick insertion, `nation_panel.gd`, `map_view.gd` colouring (the cut candidate), five test files, `tools/diplomacy_probe.gd`, and five docs. Counted by the **decomposition** session rather than by the one about to build — which by this table's own record is the estimate most likely to be wrong. Challenge it cold. **Challenged, and held.** The cold count at plan time came in at **~25**, three above the logged ~22, and High held on the reversibility test rather than on the count. Two of the logged surfaces were wrong in opposite directions: `data/relations.json` does not exist (starting values are derived, so it became ten `neighbours` arrays plus a mutuality check), and the `bloc_offset` rename logged as "nearly free" was ~30 edit sites across five code files, four test files and eight docs. Both cuts were named in advance; **the map-colouring cut was taken and the content cut was not** — four actions shipped, not three. The escalation trigger did not fire. Tenth correction on this table's own record, and the sixth that held its tier once corrected. |

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
| **V1.6 Economic depth** | ~~Inflation, business cycle, tax brackets to a target of five taxes, sectoral investment, infrastructure — sector count stays at three — **plus bond yields and the credit rating**, handed over by V1.4's decomposition~~ — **decomposed into five sessions, V1.6a–e**, before any code, and **(a) is shipped**. The table and the argument are under *Next* above |
| **V1.7 Campaigns** | Campaign phase, binding promises, electoral system choice, referendums |
| **V1.8 Events** | Data-defined events with preconditions, choices, consequences — last, on purpose, and re-argued rather than assumed |

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
