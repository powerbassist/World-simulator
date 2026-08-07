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

**V1.4 is decomposed into three sessions, V1.4a–c, and V1.4a is built.** The
argument, the three calls it made, and the per-session table are under *V1.4 — the
decomposition* below. Order: (a) the firm register and subsidies, (b) sector
regulation, (c) nationalisation and privatisation.

**V1.4a's own finding is the one worth carrying forward, and it is about content
rather than about firms.** The jobs channel's whole spread comes from two authored
headcounts: subsidising a retailer over a bank moves **0.229 points** of
unemployment, subsidising one industrial firm over another moves **0.010**, and
nothing in `src/sim/` says "services". A firm layer is more than a sector lever
exactly to the extent that firms sharing a sector are authored *differently* — so
the differentiator is the field to argue about when V1.4b and V1.4c add theirs, and
a firm with no rival is refused at load time rather than shipped as a lever that
moves nothing.

**The decomposition also caught the row double-booking twice where the prompt
named once.** Bond markets belonged to §6, and a subsidy pointed at a firm *is*
§6's sectoral investment unless a firm is smaller than a sector. That is the
eleventh missing-row instance, and the second found by counting rather than by
being told.

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

### V1.4 — the decomposition, and why these three

Written before any code, which is where a block-shaped row belongs: V1.4 was one
line — named firms, subsidies, regulation, nationalisation, privatisation, bond
markets — and one line is not a session.

| | Session | Content | Reads |
|---|---|---|---|
| **V1.4a** | ~~The firm register and subsidies~~ **shipped** | `data/companies/`, firms as a normalised partition of a sector, the `effects.company` channel, subsidies with a computed budget line and a domestic price, the Companies window | — |
| **V1.4b** | Sector regulation | Rules that cost margin and buy an outcome, as **laws** — the assembly divides on them, so this reaches the channel from the other side | a |
| **V1.4c** | Nationalisation and privatisation | Ownership as firm state, a purchase cost, a privatisation windfall, dividends as a computed revenue line, the permanent loss of control — and the `ISSUE_KEYS` question | a, b |

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
| **V1.4 Companies** | Named fictional firms, subsidies, regulation, nationalisation, privatisation, ~~bond markets~~ — **decomposed into three sessions, V1.4a–c**, before any code. Bond markets moved to V1.6, which claimed the same mechanism. The table and the argument are under *Next* above |
| **V1.5 Society** | Media, scandals, unions, strikes, protests, corruption, demographics, migration, inequality |
| **V1.6 Economic depth** | Inflation, business cycle, tax brackets to a target of five taxes, sectoral investment, infrastructure — sector count stays at three — **plus bond yields and the credit rating**, handed over by V1.4's decomposition |
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
| **Demographics** | V1.5 — ageing, migration, inequality | One field, `population`, under Economy |

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
