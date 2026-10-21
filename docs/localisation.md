---
title: Localisation
tags:
  - ui
  - localisation
  - tooling
---

# Localisation

V5.1b's plumbing. Everything a player reads can be translated; English and French
ship; the player picks in Settings (a `[display] language` key in
`user://settings.cfg`, applied before any scene is built). This page is the contract
the content work translates against. Code lives in `src/ui/strings.gd`; the worklist
tool is `tools/i18n_extract.py`; [[tooling]] has the commands.

## The one idea: English is the key

There is **no English table**. The msgid of a UI string is the English text itself
(`tr("Save the game")`), and a data row's English is the row's own field. A language
is a table *from* that English *to* its translation, and every miss shows the English.
An English table would be an identity copy to keep in step with every edit; instead
`python tools/i18n_extract.py` reports a translation whose English went away
(**stale**) and an English string with none yet (**missing**).

The price: editing an English string in `src/ui` orphans its French row until the
table is touched. `--check` fails on a stale key, and `--todo fr` lists what is
untranslated, so the drift is listed rather than silent.

## Two kinds of text, two tables

**UI text** (in `src/ui`): `data/i18n/<lang>/ui.json`, flat `{"English msgid": "traduction"}`.
Underscore keys (`"_note"`) are ignored.

**Row text** (laws, events, the programme, actions ...): the English stays in the
row in `data/<kind>/*.json`; `data/i18n/<lang>/<kind>.json` holds only overrides, keyed
`<id>.<field>`. `<kind>` is the data directory (`laws`, `events`, `programme`,
`campaign-actions`, `diplomatic-actions`, ...). A nested field is dotted; a list of
rows that carry an `id` is walked by id, so an event choice is
`<event id>.choices.<choice id>.label` (and `.summary`).

```json
// data/i18n/fr/laws.json
{ "single_term_reform.name": "Loi sur le mandat unique" }
```

Which fields are prose is one table, `TRANSLATABLE` at the top of
`tools/i18n_extract.py`. People, parties, outlets, firms and places are proper nouns
and are not in it; a language that wants them adds the kind and the field there.
`data/summits/*.dialogue` go through `dialogue_manager`'s own translation mechanism
(`translations_pot_files` in `project.godot`) -- do not build a parallel path for them.

The accessor is `Strings.row(kind, id, field, english) -> String`: the table's entry
if the current language has one, else `english`. **Every display of a row's text goes
through it (V5.1b3)**, by one of these, all in `src/ui/strings.gd`:

| Accessor | Key | For |
|---|---|---|
| `row_name(kind, row)` / `row_summary(kind, row)` | `<id>.name` / `<id>.summary` | a loaded row (`Law`, `GameEvent`, an action, a `BlocProposal`, an `Org`) or a row Dictionary (a programme entry) |
| `law_name(law)` / `law_summary(law)` | the same, kind `laws` | laws |
| `choice_label(event_id, choice)` / `choice_summary(...)` | `<event id>.choices.<choice id>.label` | an event's choices |
| `record_event_name(record)` / `record_choice_label(record)` | the same keys, from the record's ids | the desk and the ledger: a record copies the English it was made with beside the ids, and that copy is the fallback, so an old save's event the data dropped still reads |
| `noun(kind, actions, effect, id_key, id, noun_field, english)` | `<action id>.effects.<effect>.<noun_field>` | an action's authored NOUN -- an effort's, a pledge's, a project's name. The sim names the thing by its effect id (`ground_game`), the table keys it by the action's id (`start_ground_game`), so the action is found by the effect id |
| `record_action_name(record)` | `<action_id>.name` in `diplomatic-actions`, else in `bloc-proposals` | agreements, pacts, measures and foreign acts: most copy a diplomatic action's name, an org's common external measure a bloc proposal's (keyed by the proposal's id); the two kinds' ids never collide |
| `row(kind, id, field, english)` | as given | a sim record that copies a row's name beside its id: a council's pending, last and ratifying proposal (`proposal_id`), an adopted rule (keyed by proposal id), the programme's results (`entry_id`) |

`tests/test_i18n_rows_lint.gd` fails a read of a row's English outside these
(`.law_name`, `.event_name`, `.action_name`, `.proposal_name`, `.summary`, the sim's
`Campaign/Pledges/Projects.name_of(`, `.get("name" | "summary" | "label" | "choice_label" |
"event_name" | "action_name" | the nouns)` and the same keys indexed, `.capitalize()`). A
read that is not a row's text -- a UI dictionary's own label, a language's name, a city or
a party (proper nouns), a composed bill's or tax's name -- ends `# i18n: row-ok <why>`.
`python tools/i18n_extract.py --check` fails a TRANSLATABLE field that no `src/ui` line
displays through an accessor (it prints `callers N` per table): "240/240 translated" once
meant nothing on screen. `tests/test_i18n_rows.gd` gives one row of every kind a French
text in a fixture table and requires it on screen.

**An id made into a word** (a bloc, a sector, a portfolio, a vote, an event category or
severity, an energy branch, a programme group, a tax) goes through `src/ui/labels.gd`
(`Labels.bloc(id)` ...), DateText's pattern: the English in a marked table, translated
there; never `id.capitalize()`.

## Rules for `src/ui` text

1. **The caller wraps.** `label.text = tr("Save")`, `PanelKit.line(root, tr("..."))`.
   PanelKit and every builder pass text through untouched -- a helper that also
   translated would translate twice and nothing could tell a wrapped literal from a
   forgotten one. In a `static func` there is no `tr()`: use `Strings.t("...")`.
2. **`tests/test_i18n_lint.gd` fails on a bare English literal in `src/ui`**, two ways.
   *At a text sink* (known by shape, so a single lowercase word counts there): `.text =`,
   `tooltip_text =`, `PanelKit.*(`, `register(id, "...")`, `add_item(`, the settings, menu and
   action-bar builders, the drawer's `_entry`, the message stack's `push`, the reading helpers
   (`_line`, `_reading`, `_out`, `_row`), `_queue_effect`, `.report(` -- the first argument and
   those after a comma, a ternary branch, a `+` and the English default of `.get("k", "...")`
   on a line that assigns text. *Anywhere else*, a literal that reads as prose: a space
   and any word of two letters or more (V5.1b3: it once wanted two such words side by
   side, and "A resignation", "Answering a grievance." and " (you)" walked through), a
   capitalised word, an all-capitals heading, a word beside a `%`
   placeholder, a dash and a word -- in a return, an append, an argument, a continuation
   line, a var. A key or an id is never prose by this test (no space, lower case), and a
   comparison, a `match`, a call that takes a name (`get_node`, `has`, `connect`,
   `begins_with` ...), a log call and a dictionary key are not text. It reads one line at a
   time, and pins its own shapes in `_self_check()`. What it cannot see is a single
   lowercase word away from a sink (`"month" if n == 1 else "months"` is wrapped by hand).
   A literal that is not prose to a player (a node name, a developer message) carries
   `# i18n: ok`; `dev_*.gd`, `vendor/` and `grade.gd` (a shader) are outside it.
3. **Placeholders keep their order.** `%` cannot reorder, so a translation uses the
   same `%d %s %.1f` in the same order as its English; `test_strings.gd` checks every
   entry. Write the English so that order is possible in French (do not build a
   sentence out of fragments joined with `+` -- one string, one `%`).
4. **A sentence is whole, and a count picks the form with `tr_n`.** Never splice a short
   English word into a translated frame (`"%d %s" % [n, "month" if n == 1 else "months"]`,
   `"month%s"`, `"party(s)"`, `"%s the stance" % ["Raises" if up else "Lowers"]`): the
   French noun, verb or agreement is not the English one. A count that picks the form is
   `tr_n("%d month left", "%d months left", n) % n` (`Strings.tn(...)` in a `static func`),
   both literals on one line; a choice between two meanings is two whole sentences
   (`T("Raises %s by %.1f points.") if v > 0.0 else T("Lowers %s by %.1f points.")`).
   The lint fails a ternary of two short literals inside a format argument. A plural msgid's
   table entry is a LIST of forms under the singular msgid -- two for English and French
   (`plural_forms` in `languages.json`; French counts 0 and 1 as the first form) -- each with
   the singular's placeholders, because the caller formats whichever form is picked.
5. **A const table of prose cannot call `tr()`.** Keep the English in the const, wrap
   at the use site (`tr(CAPTIONS[key])`), and end each line that holds msgids with
   `# i18n: msgid` so the extractor lists them and the lint leaves them alone (the lint
   fails prose in a class-level `const`/`static var`/`enum` without it). The marker takes
   field names (`# i18n: msgid label caption`) or `last` (a `["id", "Text"]` pair); see
   the worklist section.
6. **No homonyms yet.** One English string, one translation. When two meanings of the
   same word need two translations, that is the moment to add `tr(msgid, context)`
   support to the loader and the table format; `Strings` reads no context today.

## Dates and numbers

Neither is translated text, and both differ by language, so each has ONE formatter in `src/ui`:

- **Dates: `DateText`** (`src/ui/date_text.gd`). The twelve month names live there (English,
  `# i18n: msgid`, wrapped at the use site) and so does every date shape: `day_month_year`
  ("01 JAN 2026", "01 JANV 2026"), `month_year`, `day_month`, `month` (three letters),
  `month_long`. No panel indexes a month table (`tests/test_date_text.gd` fails one that does):
  the Diary once printed `JAN` beside a clock that said `JANV`.
- **Figures with decimals: `Num`** (`src/ui/num.gd`). `Num.f(value, places)` and `Num.fs(value,
  places)` (signed) print the language's decimal separator (`decimal` in `languages.json`: `.`
  for English, `,` for French). The format keeps a `%s`: `tr("Rate %s%%") % Num.f(rate, 2)`, so
  the msgid a translator sees is `Rate %s%%`, not `Rate %.2f%%`. A raw `%.1f` / `%+.2f` in
  `src/ui` fails `tests/test_i18n_lint.gd` (`%.0f` and `%d` print no decimal and are fine). No
  thousands separator is shown anywhere, so `Num` has none. A panel reaches `Num` through its own
  preload, or through `PanelKit.Num` where the file has no line to spare under the size ratchet.

## What `tr()` does and does not do

`tr()` returns a plain String. A `Label` given `tr("Save")` keeps the text of the
language it was **built** in, so changing language does not re-translate a panel that
is already built (a bare literal would re-translate live; that is why the lint wants
`tr()`, which can be extracted, and why the switch is documented rather than hidden).

- The language is applied before any scene is built (`SettingsPanel.apply_saved`,
  called by the menu and by the game), so a language chosen in the main menu reaches
  everything.
- Chosen **in game**, the Settings screen rebuilds itself and says, on the screen,
  that windows opened afterwards follow the new language and a reloaded game follows
  it everywhere. A full live switch is the shell's work (V5.1c re-homes the windows).

## The fit sweep

French runs about a third longer. `tests/test_i18n_fit.gd` opens every registered
window and checks that its content's minimum width fits the band a window may take
(1620 px of the 1920 px layout; wider and the right-hand figures are cut off, the
failure V5.1a found by eye) -- once in English and once
under the engine's own pseudolocalization (`TranslationServer.pseudolocalization_enabled`,
expansion ratio 0.35: accents, brackets, +35% length on every string that reaches `tr()`),
a stand-in that exists before the translations do. It also found a class of bug no
English run can: a translated string used as a dictionary key or compared with `==`
(the codemod wrapped `_columns["government"]` once; the pseudo run reported 24
"invalid access" errors). **Never use a `tr()` result as a key, or compare text a
panel has shown, against an English literal** -- compare against `tr("...")` or, better,
against state. Real French fit is each translation PR's check, with
`tools/screenshot.gd -- --lang fr`.

## The worklist, for the translator

```bash
python tools/i18n_extract.py --todo fr > worklist.json   # what fr has not translated
# ... fill every "fr" slot ...
python tools/i18n_extract.py --apply worklist.json       # writes data/i18n/fr/*.json
python tools/i18n_extract.py --check                     # CI: stale, empty, placeholders, duplicate ids
python tools/i18n_extract.py                             # coverage per language and table
```

`--todo` writes one JSON file, the language's slot empty and the English beside it:

```json
{"lang": "fr",
 "ui":   {"Save the game": {"en": "Save the game", "fr": ""}},
 "rows": {"laws":   {"single_term_reform.summary": {"en": "Limit the Presidency ...", "fr": ""}},
          "events": {"com_gas_squeeze.choices.freeze_the_tariff.label": {"en": "Freeze the household tariff", "fr": ""}}}}
```

A PLURAL msgid (`tr_n`) lists as `{"en": "%d month left", "en_plural": "%d months left",
"fr": ["", ""]}`: fill every form of the list (a language's `plural_forms`; French has 2: 0 and 1,
then the rest). `--apply` writes the list under the singular msgid, refuses a list of the wrong
length or with an empty form, and checks the placeholders of every form against the singular:

```json
"%d month left": ["%d mois restant", "%d mois restants"]
```

`--apply` writes every filled slot into `data/i18n/<lang>/ui.json` (the `ui` group) or
`data/i18n/<lang>/<kind>.json` (a `rows` group); entries already in a table are kept and
a filled slot overwrites its key; an empty slot is skipped. It **refuses**, and names, a
slot whose placeholders (`%d %s %.1f ...`) differ from the English in kind or order, and a
key whose English has gone away (stale). Exit 1 if it refused anything.

`# i18n: msgid` on a line of a const table marks it for the extractor: the literals that
are *values* are msgids, the dictionary keys (`"health": "Health"` -> `Health`) are not.
`# i18n: msgid label` lists only the values of the key `label` (a table whose rows also
hold ids and numbers, like the boot stages). `--check` also fails when one row id appears
in two files of the same kind (the second would overwrite the first silently), and when a
`TRANSLATABLE` field has rows but no display caller in `src/ui` (the accessors it counts:
`CALLER_FIXED` and the call parser in the tool).

A row key with a nested path is the dotted field: an action's noun is
`start_ground_game.effects.campaign.effort_name`, `pledge_full_employment.effects.pledge.pledge_name`.

Adding a language: a line in `data/i18n/languages.json` and a `data/i18n/<code>/` folder
(`--todo <code>` builds the first worklist). The Settings row, the loader and the tests
pick it up.

## The HUD must fit in every language

The command bar's drawer is the one HUD piece whose width is not fixed (nine entries with
icons: 1053 px in English, 1195 in French, in a row that also holds the legend and the
clock). When its labels do not fit the lower row it drops to icons, the label staying as the
tooltip (`ActionBar._fit_drawer`), and `tests/test_i18n_fit.gd` opens every cluster in
English, French, the pseudolocale and across a live switch. The lint treats the drawer
(`_entry(id, label)`) and the message stack's `push(title, body)` as sinks, *including a
first argument*, a ternary branch (`else "..."`) and the English default of
`.get("key", "...")` on a line that assigns text.

## What is NOT done (V5.1b3's edge)

Every prose literal the lint can see is wrapped or marked, and every row field in
`TRANSLATABLE` has a display caller (`python tools/i18n_extract.py` prints both). V5.1b3
added the action nouns (`effects.campaign.effort_name`, `effects.pledge.pledge_name`,
`effects.project.project_name`) and the orgs (`name`, `summary`) to `TRANSLATABLE`; an
org's name is translated where French has a usual form and kept where it is a true
proper noun -- the translator's call, row by row.

What is still English on a French screen, and why: names the data holds that are not in
`TRANSLATABLE` -- a country outside the roster (the map outlines), a commodity good, a
roster nation's name, a city, a party, a firm, a person; names the game composes (a
drafted bill, a custom tax); and English the SIM writes: its constant label tables
(`OpinionK.ISSUE_LABEL`, the bloc constraint and operator labels, a chamber's name) and a
literal such as coercion's "Retaliation". The extractor reads `src/ui` and `data/` only,
so those wait on a decision about where their English lives.

What the lint cannot see: a lone lowercase word away from a sink; a short fragment that
reaches a format string through a variable rather than a ternary inside the argument; a
fragment appended with `+=` (` -- kept only if %s is ratified at home` is its own msgid with
edge spaces, the translator's to fit). Every count that picks a form and every
two-way verb in a sentence is now a whole sentence (V5.1b2): `tr_n` for counts, one
sentence per branch for choices; a sentence with a FIXED plural word ("... %d months ...")
still shows "1 months" in English when the count is 1 -- a pre-existing edge, converted to
`tr_n` as each shows.

`tools/screenshot.gd -- --lang fr` stages the game in French; `--menu` ignores it,
because the menu applies the saved language when it comes up.

Recurring French terms and typography for the translation work: [[glossary-fr]].
