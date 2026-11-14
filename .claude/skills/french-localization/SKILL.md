---
name: french-localization
description: Use when translating Nation Simulator text into French or reviewing a French translation - a row of data/i18n/fr/*.json, an i18n_extract worklist, a draft from tools/translate_api.py (this file is its system prompt), glossary terms, event text, audience or summit dialogue, UI strings, law categories or tax kinds. Covers the game's fixed French terms, French typography with non-breaking spaces, vous, placeholders and glossary marks, length, and a person's voice. Not for writing the English (audience-dialogue-writing) and not for the i18n plumbing in src/ (docs/localisation.md).
---

# French localization

The player is the President of France, and the French version is the game's home language.
It should read like the French of political journalism and official texts: precise, sober
and idiomatic. The test for every row is whether a reader of *Le Monde* could take it for a
sentence written in French, not translated into it. This file is read both by a person
translating in a session and by the API that drafts rows (`tools/translate_api.py` sends it
as the system prompt), so every rule here is stated for either reader.

## What you receive, what you return

Each row comes with its context: the table (`ui`, `events`, `glossary`, `laws`, ...), its key
(for `ui` the key is the English itself), and the source files that show it. A whole event or
a whole person file arrives together. Read the group before translating any row of it, so that
one event's title, text and choices use the same words.

Return the French for every field you are given, in the format the tool asks for, and nothing
else: no notes, no alternatives, no English left in a slot. If a row cannot be translated
faithfully (its English is ambiguous, or a placeholder cannot sit anywhere in a French
sentence), say so in the tool's rejection channel. Never guess silently.

## Tokens: copy them exactly

The game rebuilds the text from these tokens. A token that is lost, renamed or reordered
breaks the line on screen, and `tools/i18n_extract.py --check` refuses the row.

| Token | Rule |
|---|---|
| `%s` `%d` `%.0f` `%.1f` ... | Same tokens, **same order** as the English. Godot fills them by position, so if French wants the figures the other way round, rebuild the sentence around the order. |
| `%%` | A literal percent sign. Keep `%%` and put a non-breaking space before it: `%.0f %%` written with U+00A0. |
| `{{name}}` `{{president}}` `{{ask}}` ... | Dialogue variables: same names, same count, untranslated. |
| `[g=id]word[/g]` | A glossary mark. Keep `[g=id]` and `[/g]` exactly, with the id unchanged. Translate only the word between them, using the termbase word for that id: `[g=approval]Approval[/g]` becomes `[g=approval]Popularité[/g]`. |
| A plural list | A `tr_n` row has two French forms: the first for 0 and 1, the second for 2 and more. Each form keeps the singular's placeholders. |
| Line breaks, leading or trailing spaces | Keep them where the English has them. |

Never translate: ids and keys (`fuel_duty`, `prog_jobs_first`), the names of people,
parties, firms, outlets, places and nations (all fictional or proper nouns, and none is in
the translatable tables), file paths, or anything inside `{{ }}`. Dates and figures arrive
already formatted (`DateText`, `Num`), so leave a `%s` that carries a date or a decimal as it
is: the game writes the French date and the decimal comma itself.

## Typography

Use **U+00A0 (non-breaking space)** everywhere French typography wants a space the line
must not break on. This is the existing French table's convention (185 such spaces): the
narrow U+202F is not used, so do not introduce it.

| Where | Write |
|---|---|
| Before `:` `;` `!` `?` | U+00A0: `Dette : %s %% du PIB` |
| Before `%` and `%%` | U+00A0: `%.0f %%` |
| Inside guillemets | `« ` and ` »`, each with U+00A0 inside, for every quotation, including a quoted law title. Never `"..."`. |
| Before a unit or currency | U+00A0: `3 Md€` and `12 M€` (bn EUR, m EUR), `2 ans` |
| Thousands in a figure you write out | U+00A0 between groups: `25 000` |
| Apostrophe | The straight `'` (`L'Assemblée`), as the table already uses |
| Dash | ` — ` with spaces, as in the English; never a hyphen for a dash |
| Capitals | Sentence case: `Code des impôts`, not `Code Des Impôts`. ALL-CAPS headings stay all caps and keep their accents: `ÉLECTIONS ANTICIPÉES`. |
| Ellipsis | `…` |

## Register: vous

**Proposal (the parent rules):** everyone who speaks to the President says *vous*. That
includes the chief of staff, ministers, party leaders, union secretaries, firm chiefs,
foreign leaders and journalists. It is how the Élysée and every ministry actually speak,
even between colleagues of thirty years, and the game's existing French already uses *vous*
(12 rows against 1 *tu*). The only exceptions are the President's spouse and a lover in a
private scene (the affair lines): they say *tu*, which is exactly what makes those lines
private.

Address in speech: `Monsieur le Président`, or `Madame la Présidente` if the slot or the line
says so. Where the English uses `{{president}}` as a form of address, keep the variable;
never add a title the English does not have. The game's own interface speaks to the player in
*vous* too (`Votre mandat`, `vos électeurs`). Keep one register throughout a row: pronouns,
possessives and imperatives (`Choisissez`, never `Choisis`) all match.

## The termbase

These words are fixed. One English term gets one French term everywhere: the glossary tooltip,
the Agenda and an event must agree, or the player meets three names for one thing. Where the
existing table already shipped a word, the termbase keeps it.

**Institutions and the vote**

| English | French |
|---|---|
| the Assembly | l'Assemblée (l'Assemblée nationale where the text names France's) |
| bill (government's) | projet de loi; `texte` when the bill is already named |
| bill (a party's or member's) | proposition de loi |
| law | loi |
| finance bill | projet de loi de finances; once voted: loi de finances |
| the autumn finance bill | le projet de loi de finances d'automne |
| censure motion | motion de censure |
| forcing a bill (France, Art. 49.3) | engager la responsabilité du gouvernement (le 49.3) |
| referendum | référendum |
| snap election | élections anticipées |
| term (of office) | mandat |
| seats | sièges |
| majority, absolute majority | majorité, majorité absolue |
| coalition | coalition |
| whip, party line | consigne de vote |
| the President | le chef de l'État / la présidence (gender-free, as the table already does) |
| Prime Minister | Premier ministre (Première ministre for a woman) |
| head of government | chef du gouvernement |
| chief of staff | directeur de cabinet / directrice de cabinet |
| minister, cabinet | ministre, gouvernement |
| reshuffle | remaniement |
| programme | programme |
| pledge (the player's promise to the voters) | engagement |
| promise, word (to a person) | promesse, parole |
| deal | accord |
| audience | audience |
| summit | sommet |
| embassy | ambassade |

**The economy and the budget**

| English | French |
|---|---|
| approval | popularité |
| poll | sondage |
| bloc (of voters) | bloc |
| workers, pensioners, urban, rural, business, students | Ouvriers, Retraités, Urbains, Ruraux, Entreprises, Étudiants |
| unrest | tensions sociales (in a title or a short label: Tensions) |
| deficit, debt, GDP | déficit, dette, PIB |
| growth, unemployment, inflation | croissance, chômage, inflation |
| spending (a budget line), revenue | dépenses, recettes |
| health, education, defence, pensions, infrastructure | Santé, Éducation, Défense, Retraites, Infrastructures |
| bond yield, credit rating | taux d'emprunt, note souveraine |
| Tax Code | Code des impôts |
| tax rate | taux d'imposition (of one tax: le taux de l'impôt sur ...) |
| firm, plant, closure | entreprise, site (usine for a factory), fermeture |
| sector: agriculture, industry, services | agriculture, industrie, services |
| region, regional fund | région, fonds régional |
| Agenda, Diary, Inbox | Feuille de route, Calendrier, Courrier |
| Glossary | Glossaire |

**Feelings (a person's register, `src/ui/feelings.gd`)**

| English | French |
|---|---|
| rapport: cold, wary, neutral, warm, close | froid, méfiant, neutre, chaleureux, proche |
| loyalty: disloyal, uncertain, loyal, devoted | déloyal, hésitant, loyal, dévoué |
| grudge: annoyed, resentful | agacé, rancunier |

For a person, these adjectives agree with the person: chaleureuse, rancunière.

**Taxes (`data/taxes/`)**

| id | French |
|---|---|
| income, corporate, vat | impôt sur le revenu, impôt sur les sociétés, TVA |
| capital_gains, wealth | impôt sur les plus-values, impôt sur la fortune |
| inheritance_tax, property_tax | droits de succession, taxe foncière |
| fuel_duty, carbon_tax | accise sur les carburants, taxe carbone |
| tobacco_duty, alcohol_duty, sugar_drinks_levy | droits sur le tabac, droits sur l'alcool, taxe sur les boissons sucrées |
| air_passenger_tax, plastic_packaging_tax | taxe sur les billets d'avion, taxe sur les emballages plastiques |
| high_income_surcharge, transactions_tax | contribution sur les hauts revenus, taxe sur les transactions financières |
| digital_services_tax, bank_levy | taxe sur les services numériques, taxe bancaire |
| windfall_tax, retail_tax | taxe sur les superprofits, taxe sur le chiffre d'affaires de la grande distribution |

**Law categories (`Labels.LAW_CATEGORY`)**

| English | French |
|---|---|
| Taxes, Work, Welfare and health | Impôts, Travail, Protection sociale et santé |
| Education and culture, Housing | Éducation et culture, Logement |
| Energy and environment, Business | Énergie et environnement, Entreprises |
| Farming and the countryside, Justice and transparency | Agriculture et monde rural, Justice et transparence |
| Constitution and the state, Elections, Media | Constitution et institutions, Élections, Médias |
| Europe and migration | Europe et migrations |

A term the termbase lacks: choose the word an official French text would use, use it the same
way across the whole group, and list it in the PR body as a proposed addition. Never translate
one English term two ways inside one table.

**A glossary `term` is the bare word** a player meets in prose: `participation`, not
`participation (dans une entreprise)`. It is shown as a heading and inside `[g=]` marks, so a
gloss in brackets breaks both. The `definition` does the explaining.

## Length

French runs longer, and the interface is tested at **+35 %** (`tests/test_i18n_fit.gd`):

- A label, a button or a column header keeps to its English length plus a third. Prefer the
  short French word (`Recettes`, not `Recettes de l'État`).
- A button is an **infinitive**: `Proposer`, `Valider`, `Annuler`, `Fermer`.
- A status is a noun or a participle: `Adopté`, `Rejeté`, `En attente`.
- An empty state is `Aucun …` / `Aucune …`.
- A sentence may be restructured but never padded: drop `veuillez`, `il convient de`, `afin
  de` where a verb does the job.

## Meaning before words

Translate what the sentence means in the game, then check that the French says it. Watch for:

- **English verbs used in a game sense.** "The blocs that weigh this tax" means the blocs for
  which it counts (`les blocs qui accordent du poids à cet impôt`). It does not mean they weigh
  it down (`qui pèsent cet impôt` is wrong).
- **Calques.** Avoid `faire du sens` (write `avoir du sens`), `adresser un problème` (write
  `traiter`), `en charge de` (write `chargé de`), `supporter` meaning to back (write
  `soutenir`), and `opportunité` meaning a chance (write `occasion`).
- **The President's gender is unknown.** Prefer `la présidence`, `le chef de l'État` or `vous`
  to an agreed adjective (`Vous êtes élu` would assume a man). When a sentence cannot avoid it,
  use both forms, as the table already does: `le président ou la présidente`.
- **Figures and dates are slots.** Never write `1,3 %` into a row where the English has
  `%s%%`, because the figure arrives formatted.

## A person's voice

Dialogue (`data/audiences/*.dialogue`, summit spoken lines, event speakers) carries a person,
not just information. Keep the line's register and its length. A curt English line stays
curt; a formal one stays formal. Translate the stance, not the words: an English understatement
becomes a French understatement, never a louder line. Do not add a joke, an idiom or a flourish
the English does not have. French political speech prefers the plain statement (`Je ne voterai
pas ce texte.`) over the clever one. The voice skill for the English is
`audience-dialogue-writing`; its rules (no filler, no generic appeal, the line says something
about the world) hold in French too.

**Voiced lines: French text, English voice.** A line that has a recorded voice is shown in French
as a subtitle while the English recording plays (the author's call). Translate the text as text:
do not shorten it to match the audio, and do not change its meaning to match the recording's
intonation.

**Not yet: summit responses.** The player's choice lines in `data/summits/*.dialogue` stay in
English until `summit_panel.gd` stops reading a choice's effects by its English text. The
extractor keeps them out of the `ui` source. Summit spoken lines and titles may be translated.

## Before you return a row

1. Every token of the English is in the French, the same number of times and in the same order.
2. Every space before `:` `;` `!` `?` `%`, inside `« »` and before a unit is U+00A0.
3. Every term in the termbase is the termbase's French, and it is the same term across the group.
4. *Vous* throughout, apart from the spouse or lover in private.
5. A label is no longer than its English plus a third; a button is an infinitive.
6. Read it aloud as French: if a sentence only makes sense to someone who knows the English
   behind it, rewrite it.
7. A glossary `term` is a bare noun, with no brackets.

## Gates (for the session that applies the rows)

```bash
python tools/i18n_extract.py --apply <worklist.json>
python tools/i18n_extract.py --check
python tools/suite_runner.py --ci tests/test_i18n_lint.gd tests/test_i18n_fit.gd tests/test_i18n_rows_lint.gd
```

Each translation PR carries a sample table (English, French, about twenty rows) for the author
and lists any termbase additions it proposes.

## Sources

- The game's own French table (`data/i18n/fr/ui.json`): its 716 shipped rows set the termbase's
  existing words, the U+00A0 convention and the *vous* register.
- `localize-fr` from i18n-agent/i18nstack (MIT), read as data: its typography table, its rule of
  infinitive buttons and *Aucun* empty states, and its list of calques were the starting
  checklist. Nothing is copied.
- `docs/localisation.md`: the key scheme, the plural forms, the worklist commands and the API
  draft gates.
