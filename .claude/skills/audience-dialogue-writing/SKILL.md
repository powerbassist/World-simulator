---
name: audience-dialogue-writing
description: Use when writing or reviewing the words people speak in a Nation Simulator audience, phone call or visit - a `data/audiences/*.dialogue` title (talk lines, openings, levers, closes), a stance or trait override, or a gate line that calls the conversation "ridicule", "pas d'âme", filler or generic. Covers the player's menu line and the person's answers in Dialogue Manager syntax. Not for deciding which line types exist or when they appear (strategy-sim-design-decisions, Gameplay's menu) and not for panel layout (godot-bureau-ui).
---

# Audience dialogue writing

A conversation line in this game is a small piece of the world. The player picks it from a
menu because something is true right now (a bill reaches the floor, a plant closes, a region
tops the jobless table), and the person's answer tells him something he did not know about
that world or about her. A line that only sounds good is filler; the author's verdict on
filler is "ridicule" and "pas d'âme".

The game picks a line the way Valve's response system picks a bark: the most specific line
whose conditions hold, with general lines as the fallback (Ruskin, GDC 2012, via Short's
write-up). So the writer's contract is simple: **a line may say only what its condition
makes true, plus what its slots carry.** Everything below follows from that.

## Inputs, before writing

| Input | Where | What it gives you |
|---|---|---|
| The line type and its condition | Gameplay's menu (`.superpowers/sdd/audience-talk-menu.md` in the Gameplay worktree), later `data/audiences/talk_lines.json` | what is guaranteed true when the line shows: the only facts you may state |
| The two answers the menu names | the same row's "She answers" column | what each answer must tell the player |
| Who can say it | the file: `default.dialogue` is spoken by every kind; a stance file by that stance; a trait override by that trait | how much voice the line may carry |
| The person's data | `data/people/<NATION>.json`: `kind` (politician, executive, press_owner, judge, activist, regional_figure, union_leader), `traits`, `wants`, `spouse_id`; feelings bands in `src/ui/feelings.gd` (rapport cold to close, loyalty disloyal to devoted, grudge annoyed or resentful) | what may differ between speakers |
| The slots | below | the only facts that change per scene |

If the condition is not written down, ask for it. A line written against a guessed condition
invents facts the scene will contradict.

## The slots, and what each one is

The wiring (`src/ui/audience_talks.gd`, `audience_scene.gd`) passes one dictionary per line.
Write against what it carries, not what the mockup shows.

| Slot | Carries | Write it as |
|---|---|---|
| `{{name}}` | the person's full shown name ("Hélène Vasseur") | the speaker prefix of her lines; never inside a sentence |
| `{{president}}` | the player's full name ("Daniel Moucron") | rarely. "Not this week, Daniel Moucron" is what ships, and nobody addresses a president that way. At most once per title, never in the player's line |
| `{{ask}}` | the request's object, as a noun phrase | "the matter of {{ask}}" works; "your {{ask}}" may not |
| `{{bill}}` `{{plant}}` `{{region}}` `{{third}}` | proposed by Gameplay (the talk menu), not wired yet | a name used as a noun: "the {{bill}}", "the plant at {{plant}}" only once Interface says it carries a town |
| `{{date}}` | proposed, format not fixed | write sentences that survive both "May" and "15 May 2026": "on {{date}}" breaks the first, "in {{date}}" the second. Prefer a sentence that does not need the preposition, or ask Interface for the format first |

The mockup's "How is your family, Hélène?" uses a first name the slots do not carry. A
`{{first}}` slot, or a title slot ("Madame la ministre"), is Interface's to add; until then do
not address the person by name in the player's line.

## The player's line

One sentence, said by a head of state to a person across a desk. It is a question or an
offer, it names the object once (through its slot), and it carries the reason the line exists.

- Good: `"The {{bill}} reaches the floor within three months: where do your people stand?"` (one sentence, the condition as its reason, a question any kind of person can answer with a fact; "your deputies" would fit a party leader only)
- Not this: `"Tell me honestly. What do you make of {{third}}?"` (two sentences; "honestly" is stage business)

About 70 characters in English. French runs 20 to 35 % longer, and the menu row has one line.

## Her answers

Each answer title holds **two or three `%` variants**, so the same person seen twice does not
repeat herself (the repo's `default.dialogue` carries two to six per title). Each variant:

1. **One or two sentences, about 160 characters at most.** CK3's writers found a character
   event holds "about three paragraphs of copy and 3-4 options" before it looks wrong
   (Dev Diary #75); an audience answer is one beat of that.
2. **A fact the player learns**, about the world or about her: a count, a price, what she
   wants, where she stands, whom she listens to. Take it from the menu row's answer column.
3. **The yes and the no differ in what they tell him, not in mood.** If the bill's yes names
   a count, the no must tell him something too (that she does not know her own people, or
   will not say before the vote), not "ask me again later".
4. **Her stance, said plainly**, in the register of French politics: a deputy, a union
   secretary, a CEO talking to the President. Formal, direct, specific.

What the answer may assert:

| Safe | Not safe in `default.dialogue` |
|---|---|
| what the condition guarantees (the bill is on the floor, the plant closes) | family members (the person may have no child; `spouse_id` may be empty) |
| what the slots carry | another person's character ("{{third}} is ambitious": their traits are data, and may say otherwise) |
| her own position, her want | a buyer, a rival offer, a foreign subsidy, a number: unless the condition or a slot provides it |
| the relationship as the band allows it (a warm answer only behind a warm gate) | her clothes, her house, her past; facts about her that no field holds |

When a good answer needs a fact no slot carries, write the sentence without it and add a line
to the PR body asking for the slot. Do not invent the fact.

## Voice: who may say this line

- **`default.dialogue`** is spoken by a judge, a union secretary and a CEO alike. Its voice
  comes from the office and the situation, not from a personality. Keep it plain; the
  specificity comes from the slot and the fact.
- **A stance file** (`oppose`, `demand`, `sponsor`, `defend`, `want`) overrides a title where
  the stance changes what she says. Write it only where the meaning changes.
- **A trait override** (Gameplay's row 12, trait-keyed titles) is where personality lives.
  The test: **two people of different traits must not be able to say the same line.** An
  ambitious politician's answer that a principled one could say word for word is a default
  line in the wrong file. This test applies to stance and trait files; inside the default it
  cannot, because the default is shared by design.

Never let a line talk about the interface ("as your briefing says", "on your screen"), the
mechanics ("my loyalty"), or the turn ("we have time for one more question").

## Shapes that read as filler

These are the shapes the author has called ridiculous. Check each draft against them; the
`humanizer:humanizer` skill has the full list.

| Shape | Example | Instead |
|---|---|---|
| The quip ending: a joke closing an answer | "...which is once more than they know." | end on the fact |
| Not X but Y | "Not a cheque, a priority." | say what she wants: "Put {{region}} first in the next budget." |
| A triad by reflex | "clever, ambitious, and not quite as loyal" | one claim the data supports |
| A row of fragments | "No staff, no agenda." | a sentence |
| A saying | "A dinner at the residence is never only a dinner." | what she fears: "people will read it as a deal" |
| The generic appeal | "we must work together", "for the good of the country" | what working together would cost or buy her |
| Empty politeness as the no | "All well, thank you." | a refusal that tells him where he stands: "We are not yet at family, {{president}}." |

## Dialogue Manager syntax, as this repo uses it

```
~ talk_bill
{{president}}: The {{bill}} reaches the floor within three months: where do your people stand?
=> END

~ talk_bill_yes
% {{name}}: Most of mine are with you. The ones who are not have told me why, and they will tell you before they tell the press.
% {{name}}: You have most of my people. I will not lean on the rest, and I will not hide them from you either.
=> END
```

- A title is `~ <id>`; the talk lines are `talk_<id>`, `talk_<id>_yes`, `talk_<id>_no`
  (Gameplay's naming). One title per file; a stance file overrides the default title by title
  (`src/ui/dialogue_lines.gd`), so an override title must keep the default's name exactly.
- `% ` before a line makes it one of the title's random variants (equal weight). Every
  variant must pass every check above on its own.
- `{{slot}}` is replaced from the scene's dictionary. A slot the wiring does not pass prints
  empty: check the slot table before using one.
- `=> END` closes every title.
- **No game conditions in the file.** When a line shows is a rule in
  `data/audiences/talk_lines.json` (Gameplay's design, AGENTS.md rule 1: a test can count it
  headless). The `.dialogue` file holds words only.
- English is the source text. The menu wants this answer to "name a count"; no slot carries
  one yet, so the example says "most" and the PR asks for a `{{count}}` slot.

## Checking a line

1. **Compile.** `python tools/suite_runner.py --ci tests/test_audience_scene.gd` compiles every
   file under `data/audiences/` through the addon and checks the default carries every title
   the scene asks for. A new title family (the talk lines) needs its titles added to that test
   when the scene starts asking for them (Interface's change).
2. **Slots.** Every `{{...}}` in the file is in the slot table above, and every proposed slot is
   named in the PR body.
3. **Read it aloud as three speakers.** For a default line: a union secretary, a CEO, a judge.
   If one of them could not say it, it belongs in a stance or trait file.
4. **The swap test** for stance and trait files: put the line in the mouth of the other trait
   or stance. If it still fits, rewrite it until it does not.
5. **The guarantee test.** Underline every fact in the answer. Each one comes from the
   condition, a slot, or the person's own stance. Anything else goes.
6. **The yes and no test.** Read the two answer titles side by side and write, in one line
   each, what the player learns from each. If the two lines are the same, rewrite the no.
7. **French later.** The i18n lints (`tests/test_i18n_lint.gd`, `tools/i18n_extract.py`) do not
   read `.dialogue` files. Dialogue Manager has its own translation path:
   `locale/translations_pot_files` in `project.godot` lists the summit files only today.
   Registering the audience files is a committed `project.godot` change, which is the parent's
   call. Until then, write English that a translator can carry: no puns, no idioms that only
   work in English, one sentence per thought.

## Common mistakes

| Mistake | What to do instead |
|---|---|
| A family detail, a buyer, a rival's trait made up to make the answer vivid | the guarantee test: only what the condition, a slot or her stance supplies |
| One line per title | two or three `%` variants, each passing on its own |
| Two-sentence player lines with a run-up ("Tell me honestly.") | one sentence, the question itself |
| `{{president}}` as a vocative in every answer | once per title at most, or not at all |
| The no answer as a polite nothing | a refusal that says where she stands |
| A joke to end on | end on the fact; the author's word for jokes here is "ridicule" |
| Writing the condition into the text ("Since your loyalty is low...") | the condition is the reason the line shows, not its content |

## Sources

- Elan Ruskin, *AI-driven Dynamic Dialog through Fuzzy Pattern Matching*, GDC 2012
  (gdcvault.com/play/1015528; slides at Valve's CDN, too large to fetch). Read through Emily
  Short's write-up (emshort.blog, 2012-03-16): lines are matched against world state, the most
  specific applicable rule wins, and general rules are the fallback.
- Emily Short, *Beyond Branching: Quality-Based, Salience-Based, and Waypoint Narrative
  Structures* (emshort.blog, 2016-04-12): salience picks "the dialogue that best fits our
  current situation"; start with broad lines and add specific ones.
- Paradox, *Crusader Kings 3 Dev Diary #75: In the Event of Court Events* (forum.paradoxplaza.com):
  the copy budget of a character event, and characters chosen by trigger with no guarantee
  that the copy stays accurate, the reason for the guarantee test here.
- `dialogue-systems` skill, gamedev-skills/awesome-gamedev-agent-skills (Apache-2.0): line IDs
  from day one, game state outside the text, costs on the choice. Read as data; nothing copied.
- `interactive-fiction` skill, jwynia/agent-skills (frontmatter `license: MIT`; the repo has
  no LICENSE file): its meaningful-choice test (distinct options, a consequence the player can
  perceive, a choice that says something about the person making it) is the source of the yes
  and no test. Read as data; nothing copied.
