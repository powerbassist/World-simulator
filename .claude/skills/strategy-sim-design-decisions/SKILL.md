---
name: strategy-sim-design-decisions
description: Use when a design call is due on a Nation Simulator panel, decision surface, scene or loop - a play-gate line says a surface is "unclear", "déroutant", "informative only, no decisions inside" or "nothing to do", a spec proposes a fix and the question is whether it is the right one, or a new verb, card or scene is being specified. Not for layout or type (godot-bureau-ui) and not for tuning a number (balance_probe).
---

# Strategy-sim design decisions

Audit the player's experience, not the designer's intention. The player meets the game
from the far end: the feeling first, then the behaviour, and the rules last (Hunicke,
LeBlanc, Zubek, *MDA*, 2004: "from the player's perspective, aesthetics set the tone,
which is born out in observable dynamics and eventually, operable mechanics"). A gate
line like "déroutant" is an aesthetic report; the job is to walk it back to the step and
the rule that produced it, then say the smallest change that fixes that step.

Sources are listed at the end. Each step names the one it leans on.

## Inputs, before anything

| Input | Where | If absent |
|---|---|---|
| The gate line, verbatim, with its id | `.superpowers/sdd/*gate-report*.md`, `docs/someday.md` ("Carried from ...") | ask for it; a design call without a player's words is a guess |
| The surface, in the project's words | `docs/design/decision-surfaces.md`: MODAL scene, CARD (holding or quiet), NOTE, and the interruption budget (4 uninvited modal stops + 6 holding cards a year) | name it before writing |
| The rule as it stands | the spec section (`docs/design/*.md`, `git show origin/main:...` when the file is only on main), the panel file under `src/ui/` | `NOT ASSESSED - NO RULE`: do not infer the rule from the complaint |
| The planned fix, if any | the spec's options; the board `.superpowers/sdd/*board*.md` | say "no fix planned", then design one |

Record FOUND or ABSENT for each. A section whose input is ABSENT is `NOT ASSESSED`,
not estimated.

## Step 1 - Walk the path

One row per step the player takes on the surface, from the moment it appears to the
moment the game answers. Coarse enough to read, fine enough to locate a problem.

| # | The player sees | does / decides | the game returns | what it unlocks |

Include the step *before* the surface (how the player got there: a card, a tab, a map
click) and the step *after* (where the result lands: a register, a note, nothing).
Most "déroutant" verdicts live in those two rows.

## Step 2 - Friction per step

For each row, what slows, blocks or confuses, and which kind it is:

- **Productive**: a real cost or tradeoff the player can see and weigh. Keeps it.
- **Harmful**: dead time, an unreadable requirement, a hidden rule, a result that
  never shows. Removes or surfaces it.
- **Mixed**: a good idea at the wrong intensity or without its reason on screen. Tunes
  it; never deletes it on a first pass.

Rate each: intensity (low / medium / high), visibility (obvious / partly hidden /
opaque), fairness as felt (fair / borderline / unfair). A mild friction that is opaque
is more dangerous than a strong one the player understands.

Then the **stack**: which rows sit on the same screen or the same minute. A verdict
like "déroutant" is nearly always a stack, not one row; say which rows stack. The
**breakpoint** is the row where a tradeoff turns into opacity or a wait turns into dead
time.

Meier's four knobs are the ones that move friction without touching the rule
(GDC 2012): how much information the player has, how much time, how many choices,
and what feedback follows. Name which knob each fix turns.

## Step 3 - Is there a decision, and is it interesting

For every choice the surface offers, Meier's test (GDC 2012): it is not a decision if
the player would always take the first option or might as well pick at random. An
interesting one has at least two of these, and the player can *see* them:

| Property | The question to ask on this surface |
|---|---|
| Tradeoff | what does the option cost that the player wanted to keep? is the cost on screen? |
| Situational | would the same option be right in another month or region? what state makes it right now? |
| Persistent | does the choice still matter in a year? did the player have the information to know that? |
| Risk against reward | is the downside shown beside the upside, in the same unit? |
| Short against long | does the surface offer a quick small thing and a slow big thing, or only one kind? |
| Personal | can two players choose differently and both be right? |

A surface with figures and no row in this table is "informative only" (G6's words).
The fix is a verb with a tradeoff, not more figures.

**Feedback is the half most often missing.** "The worst thing you can do is just move
on" (Meier). After the choice: what does the player see change, in what unit, on which
surface, and when? If the answer is "loyalty +0.05 in a register", the decision was made
blind, whatever its tradeoff.

## Step 4 - Goals and the clock

Civilization layers short, medium and long goals at once (Meier). Fill the table for the
game as the gate saw it, not as the roadmap promises it:

| Horizon | Present on this surface | Strength | Main issue |
|---|---|---|---|
| This month | | | |
| This year (a process, a bill through its stages, a project) | | | |
| The term (the programme, the election) | | | |

Then three questions:

- **Immediacy**: on opening the game, how many clicks to a thing worth doing? Does the
  briefing or the strip name it, or does the player tour the tabs? ("pas grand chose à
  faire" is this row failing, not a content shortage.)
- **Return trigger**: what dated unfinished thing pulls the player into next month?
  A deal with a date, a stage with a deadline, a vote on a day. If nothing on the
  surface carries a date, the surface ends when it closes.
- **Safe stop**: can the player leave the surface knowing nothing urgent is pending?

## Step 5 - Can the player see why

Three sourced rules, checked against the surface's text and figures:

1. **The reason beside the number.** Harris, on Democracy 4's voters: the real
   challenge is "explaining these systems to players"; he added a scatter of voters by
   party so that an outlier is a visible loyal voter, not a mystery. Every figure the
   player is asked to act on needs its reason within one hover or one line: "11.2 %,
   1.5 times the nation's", "30-70 %: you barely know her".
2. **Distribution, not just the headline.** Harris shows voter approval distribution,
   not only intention: a 49.9 % that reads as zero seats is the headline lying. When a
   surface shows one number for a crowd (a bloc, a region, a chamber), ask whether the
   spread is what the player needs.
3. **Effect before commit, cause after.** On this project that is the effects strip
   before Commit (G4) and the consequence card after (G10); a verb without a strip is a
   fail here. Paradox's Victoria 3 UX diary (#29) is reported to state the same three
   principles (cause-and-effect feedback, actions apart from information, immediate
   effects visible); the forum is bot-gated and the wording is from a search summary,
   so the rule stands on the project's own surfaces, with Paradox as corroboration.

MDA's tuning note closes the step: if a figure "requires complex calculations", the
player loses the sense of investment, and with it the standing of the whole surface.

## Step 6 - The output

Write, in this order:

1. **Target**: surface, gate line, inputs FOUND / ABSENT.
2. **Path and friction map** (steps 1 and 2), then the stack and the breakpoint in two
   sentences.
3. **Decision test** (step 3): which rows pass, and the feedback line.
4. **Goals** (step 4): the horizon table and the immediacy answer.
5. **Legibility** (step 5): the three rules, pass or fail, with the figure named.
6. **Against the planned fix**: which harmful rows it removes, which productive row it
   touches (it must not), which mixed row it leaves untuned.
7. **Minimal fix**: one change, one surface, one knob (information / time / choices /
   feedback), with the sim numbers it moves and the budget it spends (a new modal stop
   or holding card counts against 4 + 6 a year).
8. **Broader direction**: the version a later block would build, in three lines.
9. **Not verified**: what was inferred, what the code was not read for.

Two to five findings. A long bag of weak observations is a fail of this step. A full
audit runs 500 to 700 words per surface. When the brief sets a cap below that, items 1,
2, 3, 6 and 7 keep their tables and items 4, 5 and 8 become one line each.

## Guards - fail loudly

- **The platformer test.** Reread the minimal fix with "jump" in place of the verb. If
  it still reads as advice, it is generic and the step that produced it is redone with
  the surface's own steps and figures.
- **Content lives in data** (AGENTS.md rule 1). A fix that says "if the nation is France"
  or hard-codes a person's answer is refused; it becomes a field in `data/` read by a
  general rule.
- **`src/sim` never knows the UI** (rule 2). A fix that has the sim push to a panel,
  hold the clock itself or read a widget is refused; the UI reads `GameState`, intent
  goes back as a command.
- **A number needs a measurement.** A fix that moves a sim figure names the probe that
  will measure it (`tools/balance_probe.gd`, `decision_surfaces_probe.gd --density`) and
  says "re-baseline to the author" (every moved number is accepted by the author).
- **The budget.** A fix that adds a stop says which of the 4 + 6 it spends. Scenes the
  player books are outside the budget; an uninvited one is not.
- **No new register for a feeling.** Grudge and loyalty are the two channels; a fix that
  wants a third number says why the two cannot carry it.

## Common mistakes

| Mistake | What to do instead |
|---|---|
| Diagnosing from the spec's own "why it confuses" paragraph | walk the path from the gate line; the spec is an input, not the audit |
| Removing the only tension to remove the confusion | classify first: the row with the tradeoff is productive, keep it and show it |
| Answering "nothing to do" with more content | step 4: immediacy and a dated return trigger on a surface that exists |
| A fix that is a list of figures | step 3: a verb with a cost, or the panel stays "informative" |
| "The player will understand after the tutorial" | step 5: the reason beside the number, on the surface, now |
| Recommending a modal because the author said "pop-up" | `decision-surfaces.md`: the finding was scarcity and noise, not missing pop-ups |

## Sources

- Hunicke, LeBlanc, Zubek, *MDA: A Formal Approach to Game Design and Game Research*,
  GDC Game Design and Tuning Workshop 2001-2004 (users.cs.northwestern.edu/~hunicke/MDA.pdf):
  the designer / player direction, "experience-driven (as opposed to feature-driven)
  design", the tuning note on complex calculations.
- Sid Meier, *Interesting Decisions*, GDC 2012 (gdcvault.com/play/1015756; read through
  Game Developer's write-up): the not-a-decision test, the properties table, the four
  knobs, pacing, "the worst thing you can do is just move on", cut a third.
- Cliff Harris, positech.co.uk/cliffsblog: "Modelling voter happiness in a video game is
  interesting, but also horrendous" (2020-10-21) and the protest-votes post (2021-10-25):
  explaining the system is the challenge; distribution over headline; voters are not
  rational consumers.
- Paradox, Victoria 3 Dev Diary #29 *User Experience* and #30 *User Interface*: the
  forum needs a human verification, so #29's principles come from a search summary
  (unverified wording) and PCGamesN's report (nested tooltips, learning while playing).
- The project's own playtest corpus: `.superpowers/sdd/v5.3-0-gate-report.md`,
  `v5.2-gate-close-report.md`, `docs/someday.md` "Carried from the V5.1 closing gate",
  `docs/design/decision-surfaces.md` (the budget and the surfaces table).
