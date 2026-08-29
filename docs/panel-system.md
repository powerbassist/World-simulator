---
title: The panel system
tags:
  - model
  - ui
---

# The panel system — V2.1a, V2.1b and V2.1c

The primitives every panel builds its body out of, the sweep that keeps them
fresh, and the contract that says a panel's verb has to be on screen.

**V2.1a built the kit and migrated three panels. V2.1b migrated the other
sixteen, gave six more panels a declared verb, and turned the fold contract from
a report into a test. V2.1c settled navigation and answered the resting screen
with a measurement.** Sections 1–6 are V2.1a's and stand; section 7 is rewritten
by the measurement that answered it, sections 8–12 are V2.1b's, and sections
13–17 are V2.1c's.

Related: [[ROADMAP]] · [[v2]] · [[engine-decision]]

## 1. Why a system rather than another round of fixes

`src/ui/` is **41 `.gd` files and 11 701 lines**, of which **19 are `*_panel.gd`**
and **14 are registered windows**. Nine of those panels carried **twenty-six**
private row helpers between them — `_header`, `_heading`, `_line`, `_add_line`,
`_row`, `_figure`, `_caption`, `_trend`, `_right`, `_build_column` — most of them
byte-identical and none of them agreeing on the edges.

Three shipped bugs came out of that, and **all three are edges rather than
typos**, which is the argument for a primitive instead of a fourth round of
per-panel corrections:

| Session | Bug | Killed by |
|---|---|---|
| V1.6b | `%+.1f` copied from the neighbouring row onto a quantity whose whole reachable range is 0.145 points, printing `+0.0` against a live figure | `PanelKit.delta()` |
| V1.6d | `Budget.snapshot()` never carried `gini_effective`, the panel read it with `.get(key, 0.0)`, and the row printed a confident **0.00** against a live 31.80 | `PanelKit.figure_text()` |
| V1.6f | two value columns each sizing to their own widest row until one extra clause pushed the pair past the window edge | `PanelKit.ledger()` |

A test that only checked that `row()` makes a row would have passed with all
three of them still in, which is why every assertion in
`tests/test_panel_kit.gd` is about an edge.

## 2. The kit is static and it is not a base class

`src/ui/panel_kit.gd` is `extends RefCounted` with every function static —
`trends.gd` and `ui_theme.gd`'s shape. All nineteen panels already
`extends PanelContainer`, so a hierarchy would buy nothing: the dirty sweep is
duck-typed on `has_method("mark_dirty")` and finds them without one, and
[[ROADMAP|CLAUDE.md]] lists abstract base classes among the things this project
does without. Migration is therefore a call-site substitution rather than a
re-parenting, which is what makes V2.1b mechanical.

Six primitives, where the row named five. `line()` is the sixth and five panels
had already written it.

- `section(parent, heading)` — the tracked heading and the box the rows go in,
  returning the **body** because no caller wants the heading back
- `heading(parent, text)` — a section label with no body, for a panel that runs
  one column
- `line(parent, text, tone)` — a wrapping sentence
- `row(parent, left, right, tone)` — caption left, value right; the commonest
  shape in the interface, built by hand in eleven panels
- `figure(parent, value, caption, tone)` — a large number over its caption
- `ledger(parent, rows)` — an aligned table

`Tone` is `PLAIN / GOOD / BAD / DIM`, and the kit never infers it from the sign.
A falling deficit and a falling approval are both negative and only one of them
is good news; `trends.gd` has carried `worse_when_rising` per figure since U3 and
`tone_for(value, worse_when_rising)` reads it rather than guessing.

### The one behavioural rule

**A missing key is an em dash and an error, never a zero.** `figure_text()`
separates three cases the old `.get(key, 0.0)` collapsed into one:

| Case | Prints | Errors |
|---|---|---|
| key absent from the snapshot | `—` | yes |
| key present and `null` | `—` | no — a snapshot saying "not applicable" |
| key present and `0.0` | `0.00` | no — a genuine zero |

A default that hides a missing key is worse than a crash, because a crash gets
fixed and a plausible number gets quoted.

And `delta()` **widens its own precision until the printed number is not a lie**,
up to `DELTA_MAX_PLACES = 4`. V1.6b's row was not wrong about the number; it was
wrong about how many places that number lives in, and the caller should not have
to get that right per quantity.

### `AUTOWRAP_WORD`, measured rather than chosen on taste

The panels disagreed — twenty-eight `AUTOWRAP_WORD` against eleven
`AUTOWRAP_WORD_SMART` — and the probe says why it matters beyond appearance. The
economy panel's own reported minimum height is **928px under WORD and 2602px
under WORD_SMART**, on identical content at an identical width, because
WORD_SMART takes far more break opportunities when asked to measure against a
width it has not been given. A panel that claims to need 2602px for 928px of
prose is a panel §4's contract would read a fold into that is not there. The
quieter mode is also the honest one.

## 3. The derived registry, and the five lists it deleted

`WindowManager.register()` has known every panel since U5a. Five separate places
kept their own copy of that knowledge, and each was written by copying the last:

| Where | Held | Drifted |
|---|---|---|
| `main.gd::_mark_all_dirty()` | 14 | `_people_panel` missing from U6b until V1.4a |
| `tools/screenshot.gd::_mark_panels_dirty()` | 14 | `_projects_panel` and `_campaign_panel` missing from V1.6f and V1.7a until V1.8 |
| `tests/test_shell.gd::EXPECTED_PANELS` | **7** | never updated at all since U5a |
| `tools/screenshot.gd::PANEL_BY_WINDOW_ID` | 5 | id → member map, for `--blank` |
| — | | |

All five are gone. `window_manager.gd` gained `panel_ids()`, `panels()` and
`mark_all_dirty()`; the three sweeps call it, `test_shell.gd` iterates the
registry, and `--blank` reads `frame(id)._content`.

**The interesting one is `EXPECTED_PANELS`**, because it was not a refresh bug
and nobody was looking for it. It held **seven of fourteen**, so bloc, calendar,
people, companies, projects, campaign and dispatches — every surface added since
U5a — were never checked for registration, reachability, exclusivity or cluster
routing. That is `check_names.sh`'s U6b failure and `run_tests.sh`'s
`test_companies.gd` failure in a third place: **a check that silently covers less
than it appears to.** All seven pass now they are checked, which is luck rather
than design.

`tests/test_panel_kit.gd` forbids the sixth: **no file under `src/ui/` or
`tools/` may name three or more panel variables inside one literal**, arrays and
dictionaries both. Two is a legitimate pair; three is a list, and a list drifts.
The dictionary half is not decoration — `PANEL_BY_WINDOW_ID` was a dictionary,
and a scanner that only read arrays would have called that file clean while it
held the longest list of the five.

## 4. The fold contract

Since U5a every panel has sat inside a `ScrollContainer`, so **nothing has been
unreachable** — the V1.3e, V1.3g and V1.6e failures are all about
**discoverability**. The player could always scroll. They had no reason to think
there was anything to scroll to.

### The mark is split in two, because one rule was doing two jobs

- **"There is more below" is the scrollbar's job**, and `ui_theme.gd` themes
  `VScrollBar` and `HScrollBar` as of this session. It had been on the engine
  default — a light grey slab on `#0A1020` navy — since U5a.
- **The brass hairline along the plate's bottom edge fires only when the panel's
  primary action is below the fold.** That is a thing a scrollbar structurally
  cannot say, and it is exactly the failure that has cost five screenshot passes.

Brass therefore keeps one meaning: *the state's own material marks what matters*.
It does not become a second word for the scrollbar, and [[v2|§2 of the tier]] has
already reserved the next spend of it for cities on the map.

> [!note] The bottom edge was already spoken for once
> `ui_theme._cluster_box()` has drawn a brass bar along the **bottom** edge since
> U5a — the action bar's "you are here" marker, whose own comment says the marker
> sits on the edge the control is anchored to. A Button in the bottom bar and a
> window plate are far enough apart that this is a decision rather than a
> collision, but it is recorded as a decision.

`PLATE_FOLDED` is a separate type variation rather than a mutation of `PLATE`, so
`tests/test_ui_theme.gd`'s standing assertion — the plate draws on its top edge
and nowhere else — is untouched and still means what it meant.

### A panel declares its own verb

`primary_action() -> Control`, duck-typed through `has_method()` — `mark_dirty()`'s
idiom exactly. A panel with nothing to press implements nothing and never draws
the mark. There is no base class and no registry of which panels have verbs.

The rule is **the first enabled verb**, not the most important one: a panel whose
first verb has scrolled off is already a panel whose verbs are hidden, and
deciding between two is a judgement this contract does not need to make.

Four panels declared one at V2.1a — `nation_panel` and `government_panel` because
they are the two the record names, `projects_panel` because it was migrated, and
`companies_panel` because V1.6e photographed it at the top of a body whose rows
were out of sight. **V2.1b added the other six**: `bloc`, `budget`, `calendar`,
`campaign`, `events` and `law`. Ten of fourteen; the four that declare nothing —
overview, economy, society and people — are readouts with nothing to press.

Two shapes, and which one a panel uses is decided by whether its verbs survive a
refresh. `budget` and `calendar` build theirs once in `_ready()` and hold a member;
`bloc`, `campaign`, `events` and `law` rebuild theirs on every refresh and record
the first enabled one in build order, which is `projects_panel`'s `_primary` idiom.
Build order is layout order, so *the first enabled verb* needs no second rule.

## 5. THE STEP-0 FINDING: a fold IS measurable headless

`tests/test_nation_panel.gd` has recorded since V1.3e that it is not:

> "…inside a single-frame headless harness the layout never runs, so an
> autowrapped label reports the height it would need at ONE WORD PER LINE: 1312px
> against a true ~700 … So a fold is a thing this suite structurally cannot see."

**The observation was right and the diagnosis was wrong**, and `tools/fold_probe.gd`
is the measurement. Its three tables:

**(a)** Every panel's `size` equals its own combined minimum, so a layout pass
*did* run, and the minimum does not move between frame 2 and frame 12. Four of
fourteen report taller than U5a's 886px band.

**(b)** Width set and read inside one call — what a single-frame harness does:

| state | reported min.y | lines |
|---|---|---|
| no width imposed at all | 81 | 187 |
| width 1840, read immediately | 3924 | 1 |
| width 900, read immediately | 18 | 2 |
| width 600, read immediately | 39 | 2 |
| width 420, read immediately | 39 | 3 |
| width 300, read immediately | 60 | 4 |

Each height is the answer for the **previous** row's width. The minimum-size
cache lags one invalidation; `get_line_count()` is current and
`get_combined_minimum_size()` is not.

**(c)** Width set on one frame and read on the next:

| width | min height | lines | per line |
|---|---|---|---|
| 1840 | 18 | 1 | 18 |
| 900 | 39 | 2 | 20 |
| 600 | 39 | 2 | 20 |
| 420 | 60 | 3 | 20 |
| 300 | 81 | 4 | 20 |

Monotone in the width, every height an exact multiple of its own line height.

**So the rule is one sentence: impose a width, let a frame pass, then read.**
Which is what a multi-frame harness does anyway — `test_nation_panel.gd` runs two
frames and imposes no width, and that is the whole of why it could not see one.
`tests/test_panel_kit.gd` and `tests/test_window_frame.gd` are both staged around
it. What that file recorded stands as a description of *itself*; it is not a
property of the engine.

### The contract is measured before it is enforced

`test_panel_kit.gd` prints the table and fails only on the **machinery** — a
panel that declares a verb must get a truthful answer out of the frame, and the
frame's variation must agree with it. Whether every panel currently satisfies the
contract is a different question, and re-composing the ones that do not is
V2.1b's job by name: **V1.3g proved height alone does not fix a fold**, so a
session that turned this red here would be forced into a redesign it is not
scoped for.

Measured at the shipped band, the sharpest row is **Politics: its Dissolve button
clears the fold by twenty-one pixels.** One added row in the header block hides
the panel's own verb, which is the state `nation_panel.gd` was in twice.

## 6. What the screenshot pass found, and two of the three were live bugs

The twenty-first consecutive pass to earn its keep.

**`fit_within()` spent the whole band on the SCROLL**, then the title bar, the
container separation and the plate's two content margins were added on top — so
**every window that filled its band overflowed it by about fifty pixels**. The
Politics window ran 945px into an 886px band at the shipped size, and because
`clamp_into_parent()` only constrains **position**, its last row sat under the
bottom furniture with nothing saying so. A second pass takes the excess off the
scroll; reading the difference back is one subtraction where adding up the chrome
is four lookups that go stale the day the theme changes.

**Theming the scrollbar made it disappear.** A `StyleBoxFlat` with no content
margins has a minimum size of zero, so the first version gave `VScrollBar` a
colour and a width of **0px** and it vanished from every panel at once — worse
than the engine default it replaced. The content margins *are* the bar's width;
`BAR_WIDTH_PX` is 10.

**A window is sized from its content as it was before the refresh that filled
it.** `window_manager.open()` marks the panel dirty and places the window in the
same call, and the panel does not rebuild until its own `_process` runs on the
next frame. `window_frame._process()` now re-fits when the content minimum has
moved since the fit.

**The tool's own bug** was a `--fold` flag that resized the window to 1280×720 to
force the mark. It did nothing: `project.godot` sets a 1920×1080 viewport with
`stretch/mode="canvas_items"`, so the layout is always at 1080 whatever the window
is. The flag was **deleted** rather than fixed — once `fit_within` was correct the
mark fires on `--open politics` at the shipped size, and a flag that does nothing
the panel does not already do is noise. U6a's deleted day budget, one tier on.

## 7. THE HANDOVER WAS A STALE READ, and V2.1a's own finding is what it missed

V2.1a handed this session two numbers and the claim that
`get_combined_minimum_size()` is **not the truth in either direction**:
`economy_panel` reporting **928px for roughly 500px** of rendered prose and opening
with a third of its band empty, `people_panel` reporting **520px** and rendering
about **550** with its last four rows clipped.

`tools/panel_extent_probe.gd` asks the question directly — every registered panel's
reported minimum against the bottom of the lowest thing it actually draws — and the
answer is that the minimum is exact:

| panel | cold | warm | drawn | warm − drawn |
|---|---|---|---|---|
| overview | 1154 | 436 | 436 | 0 |
| economy | 928 | 424 | 424 | 0 |
| politics | **4725** | 945 | 945 | 0 |
| diplomacy | 1669 | 860 | 860 | 0 |
| budget | 520 | 520 | 520 | 0 |
| the other nine | — | — | — | 0 |

**Cold differs from warm in 4 of 14. Warm differs from drawn in 0 of 14.**

A *cold* panel has never been shown, so it has never been laid out at the width it
will really have, and its minimum is the answer for a width nothing will ever draw.
That is **§5's own finding one level up** — the minimum-size cache lags one
invalidation, applied to the panel instead of to the Label — and V2.1a found the
rule and did not turn it on its own handover. `tools/fold_probe.gd`'s table (a)
takes exactly that cold read, which is where both numbers came from.

So **no correction shipped, and one was written and deleted to make sure.** The
plan booked a structural fix in `window_frame.gd`: a `ScrollContainer` allows
horizontal scrolling by default and therefore gives its child the child's own
minimum width, so disabling it would force the content to the scroll's width and
make every autowrapping Label measure honestly. It was written, measured against the
table above, changed **nothing in any of the fourteen**, and was deleted — U6a's day
budget and V2.1a's `--fold` flag, a third time. The window already corrects itself:
`open()` sizes the frame from a cold panel and `_process()` re-fits when the content
minimum moves, which is V2.1a's own fix doing the work its §7 said was missing.

`tests/test_panel_kit.gd` pins the property rather than the numbers — every panel's
reported minimum equals its drawn extent, measured with the frames shown and a frame
passed. Mutation-checked: with `frame.show()` commented out the check reports
*diplomacy reports 1836px and draws 2236px*.

**One thing on that list WAS real and it is not a measurement error.**
`people_panel` authored `custom_minimum_size.y = 520` against a register that runs
to about 700 at a new game, so the window opened with the Abroad list cut through
the middle of a row and three hundred pixels of the usable band empty underneath.
Height is the right answer *here* and the wrong one for a fold: a fold is a verb
below the line and V1.3g proved height does not fix one, where this is a readout that
was simply smaller than the band it is allowed to occupy. 700 — calendar's figure,
well inside the ~886px band. **The general version stays deleted**: a window that
grows to the band whenever its content wants more is a rule about every panel, and
five panels legitimately author a height shorter than their content and scroll
inside it.

## 8. V2.1a's row, counted cold

V2.1a's ROADMAP row was written by the previous session rather than authored at
plan time — a first on this project, done because the missing-row failure is
recorded four times in almost identical words. Read cold:

| Row claim | Counted |
|---|---|
| "25 files and ~11 700 lines" | **41 files**, 11 701 lines, 19 `*_panel.gd` |
| "register() already knows all **fifteen**" | **fourteen** |
| "~14 surfaces, 2 new files, ~12 edits" | ~18 surfaces, 3 new files, ~15 edits |
| "one machine" | holds — one kit and two small structural fixes; **no split** |
| "`_mark_all_dirty()` has been wrong twice" | true historically; both lists were **correct on the day**, so the fix is prophylactic |

Four things it did not name, all found by counting: `screenshot.gd`'s second
list, `test_shell.gd`'s third and stale one, that the fold lives in
`window_frame.gd` rather than in `ui_theme.gd`, and that the affordance it wanted
to invent already existed and had simply never been themed.

## 9. V2.1b — the sixteen, counted cold

| Row claim | Counted |
|---|---|
| "the twenty-five panels" / "22 panels" | **19** `*_panel.gd`, three migrated at V2.1a, **sixteen left** |
| "`budget_panel.gd` (625), `map_view.gd` (599), `calendar_panel.gd` (596) are the three that will not fit one session's context together" | **`map_view.gd` is not a panel** and builds no rows. The three largest remaining are `budget` 625, `law` 610, `government` 610 |
| "Mechanical and high-volume" | The volume held — about 215 call sites over ~6 100 lines. **Mechanical did not**: see §10 |
| Effort **Low** | **Medium.** Two kit changes and a re-composition the row does not name |
| "What to challenge: whether this is one session or two" | **One.** One machine, one grammar, no new state. The split trigger was declared before the work and did not fire: exactly one panel needed re-composition rather than re-plumbing, and ordering fixed it |

**Four panels had no private helper at all and were the ones that most needed
migrating.** `law` (27 raw Labels), `calendar` (13), `election` (13) and `polling`
(13) built every row inline, so V2.1a's *does this file still define `_row`?* check
would have called all four clean forever. That is `check_names.sh`'s U6b failure and
`EXPECTED_PANELS` at seven of fourteen **in a third place, inside the test written to
end it** — a check that silently covers less than it appears to. The second assertion
is what closes it: every `src/ui/*_panel.gd` must name `PanelKit`, and the file list
is a directory scan rather than a sixth hand-written list of panel names.

**Two shapes are deliberately NOT banned.** `government_panel._right()` and
`settings_panel._add_row()` build a **cell inside somebody else's GridContainer** —
the party table carries per-cell tooltips and colours, which `ledger()` cannot, and
every kit primitive that draws prose autowraps, so a kit call in a fixed two-column
grid reports a one-word minimum width and lets the column collapse. **The kit owns
whole rows and whole tables; a cell inside another grid is the panel's own.**

## 10. Two kit changes, both forced by a panel rather than chosen

**`Tone.PLAIN` on `line()` means the panel's own body text.** Every tone resolved
through `_variation(tone, UiTheme.CAPTION)`, so even PLAIN printed small and dim —
harmless for V2.1a's three callers, which all wanted the DIM default, and wrong for
the forty-five plain body lines `government_panel` and `nation_panel` build between
them. A literal substitution would have silently shrunk and dimmed the two panels
this project's record names most often. One word: `_variation(tone, "")`, which is
`row()`'s existing convention arriving at the primitive that did not have it.

**A figure's caption wraps.** `PanelKit.figure()`'s caption had no autowrap and
`overview_panel._figure()`'s did, and that column is about **110px** wide — V1.5a
already paid for a caption that could not wrap there by having two of them run to
eight lines. A caption that cannot wrap does not overflow; it widens its column.

**Two tables were RETAINED and are now rebuilt.** `polling_panel` held two
dictionaries of live Label references and updated them cell by cell; `budget_panel`
held a `_figures` dictionary of Label pairs. Both are `ledger()` calls now, and both
had the V1.6f shape the ledger exists to kill — four and three columns each carrying
their own `custom_minimum_size.x`. The budget one also kills a bug rather than a
risk: `_set_figure()` **returned silently on a key with no `FIGURE_ROWS` entry**, so
V1.3g's `_set_figure("deployments", …)` wrote into nothing for three sessions and
V1.4a then documented a line that was not on the panel. An unknown key is a
`push_error` now — V1.6d's rule pointed at the writer instead of at the reader.

## 11. The fold contract is a test, and the panel that failed it could not be fixed by height

V2.1a printed the table and failed only on the machinery, because turning it red
with a panel still folded would have forced a redesign it was not scoped for. With
ten panels declaring a verb, one failed:

| panel | verb bottom | band | |
|---|---|---|---|
| politics | **865** | 826 | **BELOW THE FOLD** |
| budget | 503 | 520 | reachable |
| calendar | 658 | 700 | reachable |
| diplomacy | 373 | 826 | reachable |
| companies | 366 | 560 | reachable |
| projects | 223 | 560 | reachable |
| legislature | 153 | 560 | reachable |
| bloc, campaign, events | — | — | no verb offered at month 1 |

**Politics holds 945px of content against an 826px band, so no height exists that
would have fixed it** — V1.3g's finding, stated as an arithmetic impossibility rather
than as a rule of thumb. The verbs moved **above** the readout instead: Dissolve and
Reassign now sit directly under the title, and the verb stays reachable whatever the
body grows to, where 39px of headroom would have been one added row from failing
again. Politics reads **73** against 826 now, and the report is an assertion —
mutation-checked by putting the body back on top, which turns it red.

**Three panels report no verb at month 1 and that is honest rather than a gap.**
`bloc` has no proposal before the council, `campaign` is outside the run-up and
`events` has nothing pending — the panel really has nothing to press. The screenshot
pass reaches all three through `--bloc`, `--campaign` and `--event`, which set exactly
those states, and all three clear the fold in the captured frame.

## 12. What the twenty-second screenshot pass found

**One bug, and it was the readout's** — `people_panel`'s clipped row, §7's last
paragraph. No bug in the tool, which is the second clean sheet it has had (V1.6c was
the first) and is reported as such rather than dressed up.

What the pass confirmed rather than found: prose that was body text is still body
text on Politics and Diplomacy (§10's first change, visible or it would not be), the
budget's now/proposed columns are one measurement, the diary's month strip reads as
tracked brass capitals, and Economy opens at 424px full rather than at 928px a third
empty — §7's first number, on screen.


---

# Navigation and the resting screen — V2.1c

Sections 13–17 are V2.1c's. V2.1a settled what a panel is and V2.1b migrated all
nineteen onto it; what was left unsettled is **how the player reaches one, and what
they are looking at when none is open.**

## 13. V2.1c's row, counted cold

| Row claim | Counted |
|---|---|
| "five more surfaces to place — city, region, day agenda, energy, climate" | At most five and at least three. [[v2]] §4 describes the day agenda as **"a ribbon, not a grid"**, and §2 reaches a city by **clicking the map**, `_project_at_screen_point()`'s shape — so two of the five arrive as something other than a drawer entry. **Instance fifty-two, and the first of the V2 tier** |
| "a cluster is one line in `_build_action_bar()`" | Holds. `action_bar.gd` still never sees a panel |
| "Medium rather than High — the cluster grammar is reversible" | Holds, and the session spent its risk elsewhere: the two structural edits are the keyboard map and the window-open mark, and both **delete a list** rather than add a rule |
| "whether the resting screen should show anything at all" | **Measured rather than argued.** It shows nothing new; the *bar* grows one mark. See §15 |

Three things the row does not name, all found by counting:

1. **The keyboard was a hand-written list of panel ids in a seventh place.**
   `main.gd::_unhandled_input()` matched **six** keycodes against six window ids, so
   the eight windows added since U5a — diplomacy, bloc, calendar, people, companies,
   projects, campaign, dispatches — had no key at all, and `tests/test_shell.gd` held
   **the same six** as a literal dictionary. A list cannot test a list.
   `test_panel_kit.gd`'s no-hand-written-list check could see neither: it scans
   `src/ui/` and `tools/` for panel **variable** names, and these were ids and
   keycodes in `tests/`.
2. **`WindowManager.opened` and `closed` had no consumer at all**, from U5a until this
   session — `message_stack.card_activated`'s case at V1.8, in a second place.
3. **Four routes exist and only one of them marked itself**: the bar 14 of 14, the
   keyboard 6 of 14, a map marker (U6c) 1, a message card (V1.8) 1.

## 14. The four routes, and what the registry now owns

`register(id, title, content, key := KEY_NONE)`. The manager holds the map,
`shortcut(id)` and `id_for_key(key)` read it, `_unhandled_input()` is one lookup, and
`register()` **push_error**s on a key already taken. All fourteen windows have a
letter; the six U2 bound to tabs still open the six panels they opened. Adding a
surface stays *one `register()` and one line in `_build_action_bar()`*, which is the
property U5a and V2.1a each defended.

The tooltip on a drawer entry names the letter — `top_bar.gd`'s SAVE and MENU buttons
have done that since U5a — and `main.gd::_entry()` **reads it off the registry**, so
the letter on the tooltip and the letter the key press uses cannot disagree.

`tests/test_shell.gd` iterates `panel_ids()`, asserts no key is bound twice, and keeps
three of U2's letters as a **floor** in `FOUNDING_PANELS`' idiom rather than as the
list.

**Where you are is now marked whatever put you there.** `show_active(id)` lights the
cluster holding the open window and marks its entry inside the drawer;
`clear_active()` unlights, and on a close the mark moves to whatever is still open,
because a pinned window is still where the player is. The two marks are the theme's
existing pressed style and a brass icon — **no new theme variation and no new visual
rule** — so `tests/test_ui_theme.gd` is untouched.

## 15. THE RESTING SCREEN, MEASURED — and it ships one mark and no plate

`tools/nav_probe.gd` ran the real game for fourteen years with **nothing ever opened**,
counting months in which a decision was in front of the player against months in which
anything on screen said so. The message column is the only route a pending thing has
ever had: `MAX_CARDS` is 6, the **oldest** is dropped, the player can dismiss any of
them, and nothing is ever re-pushed.

| pending | months | unseen, never touching a card | unseen, dismissing each card once read |
|---|---|---|---|
| event | 32 | **0** | 22 |
| bloc vote | 18 | **18** | 18 |
| campaign window | 24 | **24** | 24 |
| referendum, dissolution | 0 | — | — |
| **total** | **74** | **42 (57 %)** | **64 (86 %)** |

Two readings, and the second is the sharper. V1.8's card does its job **while it is
there**: an event is spoken for in all 32 of its months for a president who never
touches a card, and in 10 of 32 for one who reads the card and closes it — *the only
trace of a crisis with a deadline is one click of an X away from nothing*. And a
council vote and an open campaign window are silent in **100 %** of their months either
way, because no caller of `message_stack.push()` has ever pushed one.

**The response is a mark on the cluster and nothing else.** `src/ui/pending.gd` returns
**window ids**; `action_bar.gd` turns them into clusters, because `_entries` is already
the only thing that knows where a window lives. The mark is the cluster's own icon in
brass — §4's rule, *the state's own material marks what matters*, reused rather than
joined by a second one. No plate is added, `hud.gd::is_over_furniture()` does not move,
and nothing is drawn on the map: what the mark says is **where the answer is given**,
which is navigation rather than a second readout. U5a deleted `dashboard.gd` on purpose
and the map is still the resting screen.

**What is not in `pending.gd` is the design.** The test for an entry is that it awaits
*the player*, not that it is interesting: a dissolution already called and an election
already scheduled are consequences in flight with no button behind them, and
`ns.dissolution_pending` was measured (0 months in the probe's run) and then refused
**on the rule rather than on the number**. A later block adds a line there rather than
a branch anywhere else.

## 16. The cluster grammar, and where V2's surfaces land

The row asks what the four clusters mean once V2 adds five surfaces, and the first
question — *do four still fit?* — is arithmetic. `nav_probe.gd` table (a) opens each
drawer at its shipped size and at +1, +2 and +3 entries and measures against the width
the bar may actually use, which is not the viewport: **1384px of 1920**, the rest
belonging to the left stack and the clock.

| cluster | entries | width | headroom |
|---|---|---|---|
| state | 7 → 10 | 546 → 725 | 838 → 659 |
| economy | 4 → 7 | 345 → 524 | 1039 → 860 |
| society | 1 → 4 | 87 → 266 | 1297 → 1118 |
| world | 2 → 5 | 182 → 361 | 1202 → 1023 |

**0 rows of 16 come near the edge.** The widest drawer this game could plausibly grow
uses **half** the room it has, so width does not force a fifth cluster and cannot
choose one either — a measurement refusing the question it was asked, and the decision
reverts to grammar.

**The four hold, and the rule is that a cluster is the domain of the DECISION rather
than the shape of the object.** So:

| V2 surface | Lands | Why |
|---|---|---|
| Region (§2, §5) | Economy | its content is regional GDP, unemployment and sector mix, and §5 makes the spine regional |
| City (§2) | Economy | the same content one level down. The **route** is a click on the map; the drawer entry is the way in for a player who does not know that |
| Day agenda (§4) | State, if it is a window at all | §4 calls it a ribbon, and the diary is already State's |
| Energy (§8) | Economy | a mix, its bill and an import dependency |
| Climate (§9) | Society | emissions and accords are a price society pays, and Society is the one cluster with a single entry |

**A fifth "Territory" cluster was considered and refused**, with the trigger that would
reverse it recorded beside the refusal: a place is not a domain of government, so a
cluster of places would be the only one on the bar answering *what is this about?* with
a noun rather than a portfolio. Reverse it if V2.2 ships more than two place surfaces,
or if any drawer passes the measured width — both counts rather than opinions.

## 17. What the twenty-third screenshot pass found

**No bug in the readout, and one in the code it was about to ship** — which is a first
in the other direction. `show_pending()` reached `Icon.load_icon()`, which opens an SVG
off disk and rasterises it **on every call**, and it is refreshed on the same path as
the clock, so the bar was re-reading four files a day. Both tints are rasterised once
at `add_cluster()` now and the mark is a texture swap. The frame before and after is
identical to the pixel, which is exactly why this class of bug needs saying: **a
screenshot pass structurally cannot see it.**

What the pass confirmed, each in its own frame: the State cluster's icon in brass with
a crisis pending and nothing open; DISPATCHES marked inside the drawer with its window
open; **State marked for a pending crisis while Economy is marked for the open budget**,
so the two marks read apart at a glance; The Union marked when the council divides; and
the mark **gone** the month the crisis is answered (`--event-answered`), which is the
half a mark is worthless without.

The tool gained `--cluster <id>`, which pulls a drawer open so a frame can show the
entry mark as well as the cluster mark.
