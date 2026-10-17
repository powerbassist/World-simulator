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

Related: [[v2]] · [[engine-decision]]

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
AGENTS.md lists abstract base classes among the things this project
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
ever had: `MAX_CARDS` is 6, the **oldest unprotected card** is dropped (a card is protected when it carries answer buttons or was pushed with `protect`, as the term-start programme card is; the oldest of all goes only when every card is protected), the player can dismiss any of
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

## 18. The front door and the ceremony (V3.6)

The 2026-09-05 playtest's verdict on the menu was **"menu shows none of the
game"**, and the row that answered it is three small machines on surfaces that
already existed.

**The plate is the game's own map, not a copy of it.** `menu.gd` already ran
`DataLoader.load_all()` (New Game needs the roster); what V3.6 adds is a real
`map_view.gd` over a real throwaway `GameState.new_game(loader, "FRA")` --
month 0, built and discarded in `_ready()` -- under a 45 % scrim of the old
background colour. The refused alternative was a reduced static drawer reading
only the loader: it would have duplicated the lon/lat->screen projection that
map_view's own header calls "the one transform drawing, hit-testing and the
minimap all share", and two copies of that predicate is how one of them
quietly stops agreeing with the other. Month 0 is clean by construction -- the
unrest ring needs grievance past the threshold, the campaign ring a running
effort, markers and plants non-empty registers, and all four are empty before
the first tick. The plate is mouse-dead (`MOUSE_FILTER_IGNORE`, set AFTER
`add_child` because map_view's own `_ready()` claims STOP and would clobber an
earlier assignment), has no `_process`, and never redraws: the door is a
window, not a second game. The boot cost was measured before the decision was
final (tools/menu_boot_probe.gd, threshold declared first): `new_game()` adds
**20 ms** against a 300 ms degrade clause, so the plate holds.

**The tally is a reveal, never a recompute.** `show_results()` records each
bar's final at build time and starts it empty; a Tween (time-based, never
frame-counted) walks the bars to the recorded finals with an 0.08 s stagger,
1.2 s each. The verdict, the ledger numbers and the attribution are complete
on the frame the animation starts -- information first, ornament second. Any
click on the plate finishes the tally instantly through `_gui_input()`;
Space or Enter on the focused footer button dismisses outright. The button's
press is deliberately NOT routed through the skip path: a click that lands on
Continue is a dismissal the player meant, and a ceremony that could eat that
click would be a ceremony that ate a result. The test found the float trap the
design implied: `bar.value` round-trips a 32-bit property, `final` is a 64-bit
double, so "settled" is a 0.005 tolerance, not an equality.

**The sting is synthesized, which dissolves the asset obligations.** The
project's first sound is `src/ui/sting.gd`: a D-chord toll (D3-A3-D4, 1.4 s,
-8 dB, 12 ms attack) generated as PCM into an `AudioStreamWAV`, cached in a
static. No licence to read, no attribution file to keep true, no `.import` to
commit, no bus layout in `project.godot`, no fresh-clone loading question --
the fonts' bytes-not-`load()` discipline exists because a font cannot be
generated; a chord can. Two builds are byte-identical and the test pins it.
One `AudioStreamPlayer`, self-freeing on `finished`, gated at play time by
`SettingsPanel.sound_enabled()` -- read from `settings.cfg` per call so the
in-game pause menu's change governs the very next sting with no second wiring
path. Default On; the settings screen's own header claimed "there is no audio"
and that sentence was rewritten in the same commit.

**The told line.** One sentence on the verdict's attribution and nowhere else
on a double-election panel (the test counts once): the V3.0 probe's route 3,
in the game's voice -- approval prices change, not level, so a term that ran
the country better can poll worse than one that did nothing. The probe's three
design routes remain the author's open call; the line states the bound, it
does not resolve it.

**Two test findings worth keeping.** The double-election panel counts its text
at the geometry frame, not the show_results frame, because the previous
panel's sections are `queue_free()`d but not yet reaped in the same frame --
the fold finding again, a same-frame read answering for the last frame. And
`ConfigFile` has no per-key erase, so "the default fires on an absent key" is
tested by rebuilding the file without the audio section.

## 19. The strip (V4.8a)

The top bar is a HOST over one register, `src/ui/strip_readings.gd`: `ORDER`
is the strip, `CAPTIONS` its words, `INPUTS` the `NationState` fields each
reading declares, and `read(id, state, loader)` returns
`{text, tip, visible, alert_window, lines}` (plus `caption` for the programme,
whose name is its caption, clipped at 104 px). `lines` is the structured tip
(§20); `tip` is those lines joined. A new reading is a register entry,
never a branch in `top_bar.gd`.

**The tooltip contract.** A tip surfaces a figure an existing query computes
-- `Trends.delta` / `approval_delta`, `Elections.attribution`,
`Inflation.inflation_deviation`, `Government.majority_seats`, the org and queue
registers -- and never recomputes one. An unknown change is a dash.

**The alert contract.** `alert_window` is set only on a threshold the game
already holds; the figure takes `FigureAlert` and the tip ends "Open
<Title> (<key>)." -- the frame's title and bound key, read from the window
manager by `main.gd` once every window is registered (an id would have said
"events" for Dispatches).

**The walker.** `tests/test_strip_readings.gd` perturbs every declared input and
requires the reading to move, checks dashes for absence, alert windows against
`main.gd`'s registrations, and the strip's size at worst-case text WITH the game
theme (unthemed, it measured 44 px where 50 was drawn). The strip must stay
inside `window_frame.gd`'s `TOP_MARGIN`, which is what keeps the 826 px band.

## 20. The two-level tip and the outliner (V4.8b)

**A tip is lines, and a line may open a child.** `read()` returns `lines:
[{text, child_id}]`; `tip` is `"\n".join` of their texts, so the popup that draws
the lines and the plain tip a test reads (`top_bar.tip_of(id)`) are one source.
`strip_children.gd`'s `child(reading_id, child_id, state, loader)` answers a
`child_id` with `{title, lines}` -- lazily, at the hover, never on the per-day
refresh. Depth is two and stops there. Seven lines open a child: an approval
issue (the operands `Opinion.issue_satisfaction` subtracts -- where the figure
stands against the term's start -- plus the salience and satisfaction the line
already prints), the debt path (`Trends.entry_at`, a dash where history is
short), the coalition's parties, every running programme entry, the desk's
queue, the rules in force, the goods under the shortage line. GDP, unemployment,
inflation, unrest and the vote have none: nothing decomposes them, and a child
that invented a breakdown would be the recompute the contract forbids.

**The popup** (`tip_popup.gd`) replaces Godot's tooltip on the strip, which cannot
be hovered into. `tooltip_text` stays empty on the figures (a non-empty one draws
a second tooltip beside ours; `test_top_bar_desk.gd` pins it). One dismissal rule,
`stays_open(over_figure, over_l1, over_l2)`, and a grace window for the diagonal
move; `OPEN_DELAY_S` is the dwell. Both are felt numbers with no simulation
meaning. Level 2 sits flush beside level 1 and flips left at the screen edge. A
day tick refreshes a stationary popup's text in place -- rebuilding rows under the
pointer would fire exit/enter pairs and flicker the child. **A wrapping Label
reports its minimum height for the width it had before layout, so a panel sized on
the frame it is built is several times too tall (the first windowed capture showed
a 600 px popup round three lines); the popup re-fits for two frames after layout.**

**The walker's level 2** (`test_strip_readings.gd`): every `child_id` a staged
state raises resolves to a titled, non-empty breakdown; every `OpinionK.ISSUE_LABEL`
key has one; an unknown id and a child under the wrong reading resolve to nothing;
the children move when the input they report moves (the issue probe reads line 0
only -- the satisfaction line below it moves with the same input and hid a
hard-coded operands line, which the mutation check caught).

**The outliner** (`outliner_readings.gd`, `outliner_panel.gd`) is a register by the
strip's shape: `SECTIONS`, `CAPTIONS`, `INPUTS`, `read(section, state, loader)` ->
`{title, rows, visible}`, a row being `{text, tone, window}`. Nothing in it is
player-chosen, so it adds no save field: agenda (the entries the content `pinned`),
firms in trouble (`Industry.failing` and `Industry.pending_bid` -- the two states
`pending.gd` already marks), supplies short (the shortage line, worst first, the
strip's order), people you watch (a grudge, or loyalty turned against the term).
An empty section is hidden, never a row of zeros. `ROW_CAP` rows a section, then
"+N more". It is a window (`"outliner"`, key Q, one `register()` and one action-bar
line), not a HUD plate: a plate moves the frames the 826 px band is measured
against. A row click asks `main.gd` to open the window that answers it. **People
left the strip here** -- a count of people the term has moved is a margin note, not
a standing figure -- and `tests/test_surfaces_people.gd`'s scan now reads
`outliner_readings.gd`.

## 21. Message settings and the legend's grades (V4.8c)

**The register** (`src/ui/message_settings.gd`, static): per event category
(`EventsK.CATEGORIES`), four switches -- `notify` (the Dispatches mark,
`pending.gd`), `feed` (the Dispatches ledger), `popup` (the message_stack decision
card), `pause` (the arrival pause). Each holds a SEVERITY THRESHOLD, 1..3 or
`OFF` (4): it fires for an event at or above it. A category has no severity of its
own, so a per-category boolean could not make "defaults banded by severity" mean
anything. Defaults are one band per switch, the same for every category: notify,
feed and popup at All (what the game did before), **pause at Major+ (author's
call, 2026-10-17)**. An empty dictionary reads as the defaults everywhere.
Persisted in `user://settings.cfg` under `[messages]` (`<category>.<switch>`),
absent key -> default, out-of-band -> clamped. Not a save field: no
`SAVE_VERSION` move. `main.gd` caches it at boot and re-reads it when the settings
screen closes, because `Pending.window_ids` runs on the per-day path.

**THE CONTRACT, KEPT BY NAME: the lapse guard.** The arrival pause existed because
a decision that expired unseen was "Decided for you" in both playtests
(2026-09-05). Pause off defers that pause; it does not remove it. `_unseen_events`
now maps id -> holds-the-clock: an arrival that meets its pause band enters `true`
(pauses, as before), a quiet one enters `false`. `_guard_lapses()` runs every
month after the countdowns move: an unanswered quiet entry with `months_left <= 1`
(`Events._tick_countdowns` answers it by default on the next tick) turns `true`,
the clock stops, and its decision card is pushed if the popup band suppressed it.
Every live decision card's "N months to answer" is re-read each month
(`_refresh_decision_bodies`): a quiet card ages under a running clock, which no
card did before. The two clock checks read `_unseen_holds()`, not emptiness; every erase door is
unchanged (an answer, a dismissed card, an id leaving the desk). Interrupt events
ignore the register: the flag is content saying "until answered".

**What each switch leaves alone.** The desk in Dispatches shows every entry: it is
where a decision is answered. The ledger hides a filtered record and SAYS SO ("N
records hidden by your message settings") -- a ledger that shrank silently reads as
lost history. The notify mark still lights for an interrupt and for a decision in
its last month, the guard's band. The "Decided for you" card is not filtered: it
is the evidence of a lapse, and muting it would hide the failure the guard exists
for.

**The screen.** `settings_panel.gd` draws a MESSAGES grid below the display rows:
a category per row, a band picker per switch (`BAND_LABELS`, index = threshold -
1). `messages_from_controls()` is what it saves.

**The legend's grades.** On the Political layer only, three count rows above the
caption -- playable, simulated, outlines -- from `Roster.counts(loader)`, which
counts THROUGH `Roster.grade()` over the nation files and the outline register.
No swatch: every nation is its own colour, so a grade has no colour to promise
(and the political layer's no-swatch pin stands). `MapOutlines.profile_of` stays
the hover readout.

**Instruments.** `tests/test_message_settings.gd`: the register (every cell, the
defaults, Major+ pinned), the file round-trip (absent file, other sections kept,
clamp), the settings grid (36 pickers showing the stored bands), and the contract
driven through the machine's own `_tick_countdowns` with the game's rule that a
paused clock ticks no month -- the quiet decision must stop the clock with one
month left and never leave the desk by default. `tests/test_map_layers.gd` counts
the grades WITHOUT `Roster.grade` (the nation flag and the outline register) and
pins the rows to the Political layer. Mutation-checked: guard one month late,
guard call removed, quiet arrivals kept out of the unseen set, pause default at
All, notify's last-month clause dropped, the hidden-records line dropped, the
picker index off by one, the outline count dropped, the rows left up on Relations
-- each failed its own line.

## 22. The loading screen and the motion vocabulary (V4.9a)

**The boot, measured before it was designed.** Menu -> New Game used to be one
`add_child(main)`: the window froze with the menu still up. Measured at 41
nations (`tools/boot_stages_probe.gd`, windowed, two runs, 2026-10-17):

| stage | what | measured | on the bar |
|---|---|---|---|
| scene | `main.tscn` and every script it preloads, compiled on a loader thread | 1.28-1.38 s | 1300 ms |
| data | `DataLoader.load_all()` | 0.36 s | 360 ms |
| world | `GameState.new_game()` | 0.07 s | 70 ms |
| network | `Net.warm_step()`, a few region rows per frame | 4.9-5.2 s | 5000 ms |
| enter | `main.gd`'s `_ready()` -- the map, the panels | 0.76-0.82 s | 780 ms |

7.5-7.7 s in all. The network table is two thirds of it -- `network.gd`'s comment
said ~2 s, written at 29 nations; at 41 it is 4.4 s headless (the comment now
says both). The bar's fill is
completed weight over total weight (`BootStages.STAGES`), so it moves at the
speed the work does; the probe prints measured beside weight, and a drifted stage
is fixed by copying the column back. No tween on the bar.

**The shape: the same work, moved earlier, not duplicated.** `src/ui/boot_stages.gd`
builds the loader and the state across frames and hands them to `main.gd` as
`pending_loader` / `pending_state`; `main.gd` takes them when set and builds its own
when not -- so every test and tool that loads `main.tscn` directly boots exactly as
before (the `pending_load_slot` precedent: one path to keep correct). `main.gd`'s
`_ready()` stayed synchronous ON PURPOSE: thirty tests instantiate it and read it
two frames later, and an awaited `_ready()` would have made every one of them a
timing question. `Net.warm_step(graph, budget_usec)` is the one `src/sim/` diff:
`warm()` in row-sized slices, building the same table in the same key order
(`tests/test_network.gd` pins rows, order and foreign sums against `warm()`).

**Two stages cannot show inside themselves, and the bar says so rather than
inventing a pace.** Godot reports no progress inside the scene compile (a script's
preloads are not tracked dependencies) -- the bar holds at 0 with COMPILING THE
GAME for ~1.3 s while frames keep drawing. Enter is main.gd's own `_ready()`: the
loading screen draws ENTER's label at its true position (~90 %) on the frame
before, then the window is busy for ~0.8 s, then the screen sits over the game at
100 % and fades off it (0.3 s). A time-based estimate inside either was refused:
it is the "fake tween" the tier doc rules out.

**Per-frame budget, measured:** 30 ms of work per frame spent ~1.2 s of an 8.1 s
boot drawing frames; 50 ms (~20 fps, `loading_screen.gd` `BUDGET_USEC`) halves it.
A loading screen needs to look alive, not to run at 60 fps.

**Input.** The screen is opaque, STOP on the mouse and holds the keyboard focus,
so a menu button focused behind it cannot start a second game on Enter; the menu
also refuses a second `_start_game()` while one boot runs. It moves itself to the
root before the menu frees, so the fade outlives the menu.

**The motion vocabulary** (`src/ui/motion.gd`, static). Every tween is time-based
(Godot's Tween on process delta -- V3.6's tally discipline), keeps running under a
paused tree, and is decorative ONLY: nothing waits on it, nothing gates input, the
final value is what a reader sees the moment motion is off.

| verb | where | what | why that long |
|---|---|---|---|
| `open` | `window_manager.open()`, on the way in only | fade + grow from 0.97 about the centre, 0.16 s | under ~0.1 s reads as flicker, over ~0.25 s a window you asked for is slow |
| `arrive` | `message_stack.push()` | fade, 0.24 s (the stack owns layout, so no scale) | news, not a request: a touch longer than a window |
| `roll_text` | the strip's twelve figures | each number in the reading rolls to its new value, 0.3 s | settled before the next day tick at speed 3 |
| `pulse` | the clock's date, once per day | brass to its own colour, 0.22 s | the beats' rhythm IS the speed; a paused date is dimmed to 0.55 instead |

**A long frame must not eat the motion -- found by the sequence capture, not the
suite.** The Budget window's first frame takes ~0.4 s to build its content; a
self-running tween took its whole 0.16 s fade inside that one frozen frame, so the
window "appeared" exactly as before, on the heavy windows where opening matters
most (`tools/motion_frames.gd` logged alpha 1.00 two frames after opening). Motion
now steps its own tweens from `SceneTree.process_frame` with each frame's delta
capped at `MAX_STEP_S` (1/30 s) -- still time-based, never frame-counted, the
standard max-delta guard. Re-captured: alpha 0.67 two frames in, 1.00 settled.

**Review pass 1 (2026-10-17), bar "changes what a player sees" -- five fixed, one
left.** (1) A new reading equal to the value shown mid-roll returned early and let
the roll finish on its OLD target: a roll is now STOPPED where it stands before the
new one starts. (2) The clock's refresh finished the running beat to set its alpha,
so a second refresh the same day (a month boundary, any command) cancelled that
day's pulse: the beat now tweens the colour channels only, and alpha is the
clock's. (3) The loading screen's reveal was a self-running tween started right
after the game's ~0.8 s build frame, which it spent whole: it now goes through
`Motion.fade_out()` and the clamped stepper. (4) The menu's map plate is hidden
when the loading screen goes up, so it costs the boot no frames. (6) Tests for
each, mutation-checked. Left: (5) a first-opened window grows about the centre of
the size it had before its content resized -- cosmetic, and not visible in the
windowed capture.

`roll_text` is built on two pure functions, `same_template()` and
`interpolate_text()`: a reading rolls only when its words, its count of numbers and
each number's decimals are unchanged; a sign flip, a changed shape or a grouped
figure ("1,234", which would roll group by group) snaps. A mid-roll text is a real
intermediate value, never a garbled one.

**Off switch.** `[display] motion` in `user://settings.cfg` (absent = ON, the V3.6
default rule), a Motion row on the settings screen. `Motion.enabled()` reads it at
play time, cached against `SettingsPanel.revision` (bumped on every save) so the
strip's dozen figures per day do not each read the file. Under `--headless` motion
is OFF unless `Motion.override` forces it: every other test reads labels the
moment they are set. `Motion.finish(node)` is the skip path (completes the tween,
final values applied) -- V4.9b's election night is the first ceremony that needs it.

**Refused, with the reason.** A close animation (a fading window stays visible
and clickable for its duration, and `open_ids()` and every test read `visible` the
moment `close()` returns). An awaited `main.gd` `_ready()` (above). Rolling any
figure outside the strip (V5 reworks the panels; the vocabulary survives it, the
call sites will not). Reusing the menu's own loader for the game (0.36 s saved,
against a loader object shared by a discarded viewer state -- not worth a second
owner of content).

**Instruments.** `tools/boot_stages_probe.gd` (the bar's truth, windowed and
headless). `tests/test_boot_stages.gd`: the stage table matches what `step()`
handles, the bar never goes back and sits at exactly enter's share at enter, every
stage is shown and timed, the network is warm at ready, `main.gd` TAKES the loader
and state it was handed (a main that rebuilt them still boots, twice as slowly),
a load carries its slot and builds the throwaway state for main's default.
`tools/motion_frames.gd` (windowed): SEQUENCE captures to `reports/motion_frames/`
-- the loading screen at first frame, past 30 % and 60 %, at enter, and fading off
the game; a window at open, two frames in, settled -- with the window's alpha
logged per shot. (`tools/screenshot.gd` forces motion OFF so its single frames are
always settled.) `tests/test_motion.gd`: the pure roll and template cases, off under
headless, `finish()` lands each verb on its final values, an interrupted roll ends
final, a 300 ms frame does not finish an opening, `open` settles on wall-clock time
without `finish()`, the window manager opens
through it and does not re-run on a raise, the clock beats on a day and not on its
first date or while paused. `tests/test_menu.gd` now drives its three starts one
after another through the loading screen (opaque, focused, monotonic) and refuses
a double start. Mutation-checked: `Motion.open` removed from the window manager,
`main.gd` ignoring `pending_state`, the delta clamp removed -- each failed its own
line.

`tools/menu_boot_probe.gd` (the 300 ms degrade clause on the menu plate) is
untouched by this block: the loading screen runs after the menu, not inside it.

## 23. Election night and the map's crossfade (V4.9b)

**Election night is V3.6's tally grown into the count.** The plate opens titled
ELECTION NIGHT with every figure at zero; the player's regions declare one at a
time, smallest population first; every table's vote shares roll to the running
count, the seats and bars fill by the share of the electorate counted; a ticker
names the latest region ("7 of 13 regions declared -- latest, Bretagne."); and
only when the last region is in does the title become the verdict, the verdict
lines and the attribution fade in, and the sting sounds. The held-back lines are
HIDDEN during the count, not transparent: the first windowed capture showed a
transparent verdict keeping its ~200 px above the table as a dead hole, so the
verdict now lands on top of the table when it comes. Nothing about the result
is recomputed: the tables are BUILT at their finals, the night resets their
display and interpolates back, and at the end of the count the shares are the
result's own dictionary (`ElectionNight.shares_at()` returns it, not a sum that
agrees with it).

**The regions are derived, and the author chose that at the plan gate.** The model
has one national vote share per party. Two options were put: every region reports
the national shares (honest, and thirteen identical rows), or a DERIVED swing. The
author took the swing. `Elections.regional_shares()` (pure, in `src/sim/`, no state)
tilts the incumbent per region by `-REGION_SWING x jobs salience x
(relative unemployment - 1)`, capped at `REGION_TILT_MAX`, divides the tilts by their
population-weighted mean, and lets the other parties share the rest in their
national proportions -- so every party's population-weighted share over the
regions IS its national share (`tests/test_elections.gd`, 1e-12). Measured at
France's opening: the incumbent runs 24.4-28.0 % by region around a national
26.5 % (jobs salience 0.165). Display only: nothing reads it back.

**Seats are not projected.** A running vote share could be fed to
`ElectoralSystems.allocate()` for a running seat projection; it was not, because a
projection that swings the seat count mid-night and then lands somewhere else is a
second, wrong answer on screen. Seats and bars come in proportionally to the
electorate counted, ending on the result's seats.

**Pacing** (`motion.gd`): `DECLARE_S` 0.28 s a region, the whole count capped at
`NIGHT_MAX_S` 4.5 s (France's thirteen take 3.64 s; Italy's twenty-one are
squeezed into the cap). Through `Motion.run()`, the verb this block added: a
callback from t = 0 to 1 over the clamped stepper, one call at t = 1 when motion is
off or the node is finished -- so the settled plate and the skipped plate are the
same code path.

**Every way out lands somewhere honest** (`tests/test_election_night.gd`):

| exit | what happens |
|---|---|
| a click anywhere on the plate | `skip()`: the count finishes, the verdict shows and settles |
| the footer button mid-count | reads Skip count and skips; after the reveal it reads Continue / Leave office and dismisses, ignoring presses for 0.4 s after a skip so a double click cannot dismiss an unseen verdict |
| the mouse wheel | scrolls; only a left or right click skips |
| a second result replacing the plate | the old count is retired the same way (`_night_id`) |
| motion off (setting, `--headless`) | the plate opens settled, verdict and all |
| time | the verdict comes after the count's own duration, on wall-clock time |

The footer button is live throughout, so a defeated player always has a control.

**Review pass 1 (2026-10-17), bar "changes what a player sees" -- three fixed, one
left.** (1) The footer read Continue / Leave office from the count's first frame:
it told the verdict the night held back, and pressing it on a defeat sent the
player to the menu having seen neither the result nor why. It reads Skip count
until the reveal now. (2) Any pressed mouse button skipped, the wheel included,
so scrolling the double-election plate ended the count. (3) A nation with no
population shares would have shown the count full from frame one; regions then
count equally. Left: `screenshot.gd --tally` runs with motion on throughout, so
its settled frame can catch a strip figure mid-roll (a tool, not the game).
Each fix has a test, mutation-checked. Pass 2 was clean at the bar: it found only three
lines of prose still describing the old mid-count dismissal.

**The map's crossfade.** `map_view.set_layer()` fades the roster fills from what
was ON SCREEN (mid-fade included) to the new layer's over `LAYER_S` 0.3 s. Only the
fill fades: strokes, the hover mark and the legend switch at once, because they say
which layer is up. A second toggle mid-fade starts from the mid-fade colour
(`tests/test_map_view.gd`). V4.10's modes go through the same `set_layer()`.

**Refused.** Lighting the regions on the map as they declare (the plate covers
the middle of the screen, and V5 reworks both); reordering the table rows as the
lead changes (rows jumping under a reader's eye); a running seat projection
(above).

**Instruments.** `tools/motion_frames.gd` gained two sequences: `layer_*` (toggle,
mid-crossfade, settled) and `night_*` (start, a third, two thirds, the verdict's
first frame, settled). `tools/screenshot.gd --tally` turns motion on for its
mid-count frame. Mutation-checked: the dismissal not retiring the count, the count
not reset before it runs, declaration order reversed, the crossfade not starting
from the screen, the regional tilt not renormalised -- each failed its own test.

## 24. The synthesized sound set (V4.9c)

**Every sound is generated, none is recorded** -- the author's call at the tier
signing (2026-09-13), with V3.6's sting as the house style: additive sine
partials under exponential envelopes, rendered to 16-bit mono PCM into an
`AudioStreamWAV`. No binary, no licence, no `.import`, no fresh-clone question.
A session wanting a recording re-opens every obligation `sting.gd`'s header lists.

**Four files, one job each.** `src/ui/sound_constants.gd` holds every recipe and
level with its reason (the `*_constants.gd` rule, audio edition).
`src/ui/synth.gd` renders a recipe -- pure, static, node-free, so a worker can
run it. `src/ui/sound.gd` is the one door for one-shots (`Sound.cue(parent, id)`,
`Sound.event_sting(parent, severity)`), with a stream cache and the worker
warm-up. `src/ui/sound_bed.gd` is a node: a looping bed that fades in, answers
the settings while it plays, and fades out. `sting.gd` stays as the name the
election plate calls; its recipe moved to `ELECTION`, byte-identical (SHA-256
pinned in `tests/test_sound.gd`, taken from the pre-move code).

**The vocabulary.**

| sound | where it plays | recipe | heard peak |
|---|---|---|---|
| bed `menu` | the front door, under everything | open D (D2 A2 D3 A3 E4), 16 s loop, 2 s fades | -38.6 dBFS |
| bed `game` | the desk | A minor low (A1 E2 A2 C3), 16 s loop, 3 s fades | -39.9 dBFS |
| `open` / `close` | a window opening / closing (`window_manager.gd`) | E6+B6 / B5+F#6 ticks, 80-90 ms | -29.6 / -32.4 |
| `pause` / `resume` | the clock paused / resumed BY HAND (`main.gd`) | A5 to E5 falling / rising, 0.24 s | -32.6 |
| `declare` | each region declaring on election night | G6, 50 ms | -34.7 |
| `event_1/2/3` | a month's arrivals, at the worst severity NOTIFY lets through | minor bell E5 / major two-strike G4 then D5 / critical D minor low chord | -21.3 / -19.2 / -14.2 |
| `election` | the verdict's reveal (V3.6) | D3-A3-D4 toll, 1.4 s | -10.3 |

**The level ladder** is the set's one rule: beds < UI cues < event stings
(minor < major < critical) < the election sting, nothing above V3.6's -8 dB. It
is measured on the RENDERED samples (player level + the buffer's own peak), not
on the recipe numbers -- the first cut failed it twice (a bed as loud as the
quietest tick; the major sting quieter than the minor), and the test caught both.
The table's figures are from `wave` + numpy FFT over exported files (2026-10-17);
the FFT's top bins land on each recipe's pitches.

**Restraint is the design.** A sound marks only a change V4.9a's motion already
marks. No click sound on every button. A window displaced by an open is part of
one gesture -- one `open`, no `close` -- and `close_all()` (key M) is one `close`.
A pause the game takes (an arrival, the lapse guard) makes no pause cue: its sound
is the event sting. Two crises in one month are ONE sting, at the worse severity:
two on one frame would only be louder. The sting follows the **NOTIFY** band
(author's call, 2026-10-17): it is a notification, so a category set not to notify
arrives silent. On election night the last region declares with the verdict's
sting rather than a tick a frame before it -- and that same rule silences a skip,
because `skip()` lands the count in one step at t = 1 (a separate `_skipping` flag
was written, then deleted when the mutation check proved it dead).

**Click-free, by test.** Every one-shot starts on a zero sample (an attack ramp,
and a late partial carries its own) and ends under 2 % of full scale in its last
5 ms -- the first major and critical cuts (0.95 s, 1.3 s) ended on a click and
were lengthened to 1.2 s and 1.8 s. A bed is seamless only if every partial and
every swell completes a WHOLE number of cycles in its loop, so its frequencies sit
on the 1/16 Hz grid (D2 is 73.4375, not 73.42); the test checks the grid and that
the seam's jump is no bigger than the bed's ordinary steps.

**Cost, measured 2026-10-17 (this machine, GDScript, best of three):**

| render | ms |
|---|---|
| the eleven one-shots together | 193 (critical alone 80, election 43, ticks 1-6) |
| bed `menu` / `game` | 359 / 287 |

Hoisting the partials into typed arrays (TAU x hz and -decay are the very
subexpressions the products evaluated first, so no float changed -- the hash
held) cut both by ~45 %. Still too much for a frame, so nothing renders on the
main thread in play: each bed renders on a `WorkerThreadPool` task and swells in
when done (the menu's first frame pays nothing -- `tools/menu_boot_probe.gd`'s
number), and `Sound.warm()` renders the one-shot set on a worker as the game
opens, so the first crisis does not stall its own frame. A cue asked for before
the warm-up finishes renders itself on the spot. Every task is waited on before
its owner leaves (`SoundBed._exit_tree`, `main.gd`'s `_exit_tree` ->
`Sound.settle()`).

**Settings.** `[audio] enabled` (V3.6) governs everything; `[audio] ambient`
(new, default ON -- author's call) governs the beds alone, because a loop is the
one sound a player may want off while keeping the cues. Both are read at play
time; a bed watches the settings screen's `revision` counter (motion.gd's
pattern) and fades out or back in the moment the pause menu saves. Absent key ->
default, so no file or save field moves.

**Headless.** Cues play into the Dummy driver, so the wiring is countable in the
suite. Beds and the warm-up do not run under `--headless` (the suite builds
`main.tscn` some thirty times and would spend a worker each time on sound nobody
hears); `SoundBed.override` and `Sound.warm(true)` are the tests' doors.

**Instruments.** `tests/test_sound.gd` (suite-exclusive: it writes the audio
keys): the hash pin, determinism, length, no clip, zero start, quiet tail, the
ladder, the bed grid and seam, severity lookup, the worker warm-up rendering what
the main thread would, the settings gate, the window gestures, pause by hand, the
month's one sting at the worst severity and its NOTIFY band, election-night ticks
against a skip, and a bed's swell, Ambience off (faded, not cut), back on, and
`fade_out()`. Mutation-checked: an off-grid bed partial, a displaced window's
close cue, the NOTIFY gate removed, the Ambience gate removed, the sting's synth
perturbed -- each turned the test red.

**Review pass 1 (2026-10-17), bar "changes what a player hears or sees" -- three
fixed, three left.** (1) The sting obeyed the NOTIFY band for an interrupt, which
the register ignores everywhere else (`pending.gd`): an interrupt now always
stings. (2) The Dispatches window an interrupt opens played its open tick on top
of the sting; the game's own open is quiet now (`open(id, quiet)`). (3) Ambience
off then on overlapped two copies of the bed; a bed keeps ONE player for its life,
faded to silence and stopped on off, faded back up on on -- and the test now
waits for the stop, which the first version never checked (the mutation survived
until it did). Left: the game bed cuts rather than fades when the game scene is
freed (a scene change frees the player with it, and a re-parented tail would add
its own gap); the per-cue settings read (a ~0.1 ms file read, inaudible); and the
night test's exact tick count (cannot skip a beat at today's step cap).

**Not verified here, and cannot be:** how it SOUNDS. The suite proves levels,
pitches, seams and wiring; the ear is the author's. The rendered files (levels
baked in, each bed twice so the seam is inside the file) were sent for listening.

**Refused:** voice, licensed music, a composed score (the tier's refusal); a click
on every button; a volume ladder in settings (two switches are every level the set
needs today); per-category sting toggles beyond the message bands that already exist.
