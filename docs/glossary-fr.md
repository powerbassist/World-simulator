---
title: French glossary
tags:
  - localisation
  - content
---

# French glossary

The recurring terms of `data/i18n/fr/`, so every translation PR says the same thing.
Part of [[localisation]]; the worklist tool is `tools/i18n_extract.py`. Add a row when a
term recurs in a second PR; change a row only with a sweep of the tables.

## Typography

- A non-breaking space (U+00A0) before `%`, `;`, `:`, `!`, `?`, `»` and after `«`; `%` and the
  following word are also joined (`0,53 % du PIB`): the extractor's placeholder regex reads
  `% d` as a `%d`, so a plain space after `%` is refused.
- Decimal comma in prose (`0,53 %`); placeholders keep their `%.2f` and order.
- `«` `»` for quoted button names; `·` and `—` kept as in the English.
- Units: `Md€` (milliard d'euros), `Md` alone where the English says `bn`, `M` for millions, `pt`/`pts`.
- Plural suffix placeholders (`%d day%s`) stay as `%d jour%s`; the code supplies `s`.

## Institutions and politics

| English | Français |
| --- | --- |
| President | président(e) de la République (chef de l'État in compact text) |
| Assembly / National Assembly | Assemblée / Assemblée nationale |
| Legislature | Législature |
| second chamber | seconde chambre |
| the Council (an organisation's) | le Conseil |
| bill (government) | projet de loi |
| bill (member's) | proposition de loi |
| Propose (button) | Proposer |
| draft (verb, a bill) | rédiger |
| censure motion | motion de censure |
| Article 49.3 | l'article 49.3 |
| snap election | élections anticipées |
| dissolution | dissolution |
| constitutional amendment | révision constitutionnelle |
| Constitutional court | Conseil constitutionnel |
| treaty / ratification | traité / ratification |
| veto | blocage (« veto » only for a named veto) |
| qualified majority | majorité qualifiée |
| coalition | coalition |
| bloc | bloc |
| Agenda | Feuille de route |
| Diary | Calendrier |
| Dispatches | Dépêches |

## Economy and state of the world

| English | Français |
| --- | --- |
| approval | popularité |
| polls / polling | sondages |
| unrest | tensions sociales (heading: Agitation) |
| unemployment | chômage |
| inflation | inflation |
| debt service | service de la dette |
| the public account | les comptes publics |
| subsidy | subvention |
| side-payment | compensation |
| goodwill (diplomatic) | crédit |
| vote trade / bargain | troc de voix / marchandage |
| IOU (owed vote) | dette (de vote) |
| programme (state) | programme |
| pledge | engagement |
| firm | entreprise |
| goods / commodities | biens / matières premières |
| mix (energy) | mix |
| severity | gravité |
