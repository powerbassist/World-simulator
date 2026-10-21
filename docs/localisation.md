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
if the current language has one, else `english`. The display site passes the row's
English it already holds. (Wired today, through `Strings.law_name(law)` / `law_summary(law)`: the law names in
the Legislature window, the bill briefing, the diary and the message log; each further
site is one call -- the extractor's `--todo` lists
the keys, and a site not yet wired shows English, which is the safe failure.)

## Rules for `src/ui` text

1. **The caller wraps.** `label.text = tr("Save")`, `PanelKit.line(root, tr("..."))`.
   PanelKit and every builder pass text through untouched -- a helper that also
   translated would translate twice and nothing could tell a wrapped literal from a
   forgotten one. In a `static func` there is no `tr()`: use `Strings.t("...")`.
2. **`tests/test_i18n_lint.gd` fails on a bare literal at a text sink** (`.text =`,
   `tooltip_text =`, `PanelKit.*(`, `register(id, "...")`, `add_item(`, the settings,
   menu and action-bar builders, the message stack's `push`). It reads one line at a
   time. A literal that is not prose (a glyph, a unit) carries `# i18n: ok`.
   `dev_*.gd` is English by design.
3. **Placeholders keep their order.** `%` cannot reorder, so a translation uses the
   same `%d %s %.1f` in the same order as its English; `test_strings.gd` checks every
   entry. Write the English so that order is possible in French (do not build a
   sentence out of fragments joined with `+` -- one string, one `%`).
4. **Plurals.** Use `tr_n(singular, plural, n)` or two whole sentences; do not write
   "item(s)". French counts 0 and 1 as singular.
5. **A const table of prose cannot call `tr()`.** Keep the English in the const, wrap
   at the use site (`tr(CAPTIONS[key])`), and end each line that holds msgids with
   `# i18n: msgid` so the extractor lists them and the lint leaves them alone.
6. **No homonyms yet.** One English string, one translation. When two meanings of the
   same word need two translations, that is the moment to add `tr(msgid, context)`
   support to the loader and the table format; `Strings` reads no context today.

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

`--apply` writes every filled slot into `data/i18n/<lang>/ui.json` (the `ui` group) or
`data/i18n/<lang>/<kind>.json` (a `rows` group); entries already in a table are kept and
a filled slot overwrites its key; an empty slot is skipped. It **refuses**, and names, a
slot whose placeholders (`%d %s %.1f ...`) differ from the English in kind or order, and a
key whose English has gone away (stale). Exit 1 if it refused anything.

`# i18n: msgid` on a line of a const table marks it for the extractor: the literals that
are *values* are msgids, the dictionary keys (`"health": "Health"` -> `Health`) are not.
`# i18n: msgid label` lists only the values of the key `label` (a table whose rows also
hold ids and numbers, like the boot stages). `--check` also fails when one row id appears
in two files of the same kind (the second would overwrite the first silently).

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

## What is NOT done (V5.1b's edge)

The lint covers the sinks listed in rule 2, not every string: a survey of unwrapped
prose-like literals in `src/ui` (2026-10-21) found about 870 more, in messages built
by `+` or `%` away from a sink, returns of sentence fragments, dict values, `push_error`
text (English by design) and const tables not yet marked. The next passes widen the
lint's sink list one pattern at a time (a lint that grows red is the worklist), mark
the const tables with `# i18n: msgid`, and translate. The chrome seeded in French by
V5.1b is the menu, settings, top bar, window titles, action bar, common buttons and the
map layers; the rest of the backlog (laws, events, bodies of the panels) is the content
child's, from `--todo fr`.

`tools/screenshot.gd -- --lang fr` stages the game in French; `--menu` ignores it,
because the menu applies the saved language when it comes up.
