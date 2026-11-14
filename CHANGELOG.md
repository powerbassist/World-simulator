# Changelog

What changed for a player, build by build, newest first. The format is
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the versions are
[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html): `0.<tier>.<block>`, and a
build handed to the author to play before its block closes is a pre-release of it,
`0.5.3-gate.1`, `0.5.3-gate.2`. Major version 0 means what SemVer says it means: anything
may change, and a save from an earlier build is refused, never converted. The tier names
in the headings are the design's (docs/tiers/); the engineering record behind each line,
with its measurements, is docs/history.md.

## [Unreleased]

The lines waiting for the next cut are the files in changelog.d/ (AGENTS.md, "Versions and
changelog"). `python tools/changelog.py notes` prints them as the cut will.

## [0.5.3-gate.2] - 2026-11-10 (V5.3 a + b)

### Added

- Before you commit, each spending lever and tax rate shows its effect on the balance in billions a year, and the Budget table has a "change" column.
- You can counter a price ask by 5, 10 or 15 percent, or counter a closing plant's buyer, with the odds of acceptance shown as a range, but the other side may walk away, and an inbox card tells you if a bill you then pass on that firm starts nothing.
- Struggling firms now announce plant closures, and you can let the plant close, look for a buyer, or rescue it for a fixed term priced on its jobs, while the firm's chief asks to see you and a running rescue shows on the Industry tab and in the Budget.
- Each spending line on the Budget opens to show its sectors, such as hospitals and primary care, with each sector's share and a figure, and you can move a share of the line from one sector to another at no cost.
- Sector figures now drift each month with money and need, and a slipping sector is marked on the Budget with its reason and a trend line, reaches you in the briefing, and offers a raise or a share move to fix it.
- When your worst-off region falls well behind the nation, an inbox card that does not stop the clock points you to it, and its page names its one problem and offers a regional development fund of 1 to 3 percent of the region's output a year, with its cost, who it pleases or angers and its effect on local unemployment shown before you start it and tracked while it runs.
- You can put one sector first in a region, which lowers that region's unemployment at the other regions' expense for 36 months, renewable once.
- On an open bill you can pick its size on the nine laws that have one, address the nation to sway the vote, and commission a poll at three price tiers whose result arrives as a card on its day, and the Assembly forecast now counts the bill's size and your address.
- In a month where nothing else happens, someone asks to see you or a minor event arrives, and inbox cards that do not stop the clock point you to a backbench bill awaiting your stand, a treaty to ratify, or a council vote yours can swing.
- The front page now arrives with a short headline sting, which plays quieter when it starts over a voice line.
- The inbox's notes have a "Clear all" button.

### Changed

- The Industry tab is rebuilt around an In progress list and three sector cards showing output, jobs and trend against the nation, with one Act button per firm whose options show their cost, who they please or anger, why one is greyed, and a confirmation before a break-up.
- Taking a stake, nationalising (now also a firm the state already part-owns), breaking up or privatising a firm no longer happens at once: it runs over months in stages, shows its price range first, can be stopped, and asks you one question at its key stage.
- An audience is now a deal that shows what the person wants and what they give, votes on a bill or their silence, with the cost of each answer shown before you choose.
- A request now shows as a chip on each day it offers in the Diary, and a click books that day, replacing the side column and dragging.
- People now start the game warm or wary toward you depending on how far their party's ideas are from yours, and a person's card shows rapport and loyalty as a number from -100 to +100.
- Poland, Czechia and Bosnia and Herzegovina now start under the government their scenario names instead of one built around the largest party.
- France, Germany, Britain and Poland now have four or five firms of realistic size per sector, with new company chiefs who have voices and portraits, and a break-up is offered only on a firm that is large within its sector.
- Britain's regions now differ in output and unemployment instead of all reading the same.
- A word a minister gives on your behalf is now kept far more often, depending on your cabinet's strength and loyalty, and the person does not ask again about it for a while.
- Animations are easier to notice: figures roll more slowly, colour flashes last longer, and new inbox cards are tinted as they arrive.
- Saves from earlier builds no longer load.

### Fixed

- The Economy panel's headline now labels GDP and growth, and its budget balance matches the top bar.
- Leaders shown on the map, in Diplomacy, the People list, your portrait card, visits, audiences and summits are now whoever holds the office, not the person from the start of the game.
- Sliders on the Budget, the Tax Code and the regional fund now draw their track.

## [0.5.3-gate.1] - 2026-10-31 (V5.3 block 0, readability and feeling)

### Added

- The chief of staff's monthly briefing: three priorities, each with a Go, and what last month's choices did.
- Audiences that speak, outcome tones, a mood badge, graphic front pages and visible motion.
- Music that follows the tension, stings, and 78 voiced lines.
- Booking in the Diary grid.

### Changed

- Every tab and the inbox carry about a third less text.

## [0.5.2] - 2026-10-30 (V5.2, people who talk)

### Added

- Audiences with levers and topics, the phone, visitors, and twelve more summit scenes.
- Faces for the chiefs of the firms and for the politicians, in five moods, with backdrops behind them.
- Charts on five panels; front pages and speakers.
- Dismissing a minister, the Diary as a month grid, and votes shown with their counts.

### Changed

- Requests never hold the clock.
- Relations read as feelings, and a plant shows its progress.

## [0.5.1] - 2026-10-23 (V5.1, the shell)

### Added

- A new look: graphite panels and one accent taken from the played nation's flag.
- A docked workspace under a domain sidebar, a title bar, a folding figure strip and an inbox.
- Glossary terms with tooltips, an A-Z Glossary tab, and F1 to walk the terms on screen.
- A country box on a click on the map, and its actions on a right click.
- A text size setting, F11 for fullscreen and a resizable window.
- The embassies the nations already hold.

### Changed

- The month end no longer freezes the screen.
- Another nation's approval is a range with its source, not the true figure.
- Saves from earlier builds no longer load.

### Fixed

- Buttons that did nothing on a held click.
- A freeze when placing a plant outside your country.
- Buttons stretched across the whole width of a panel.

## [0.5.0] - 2026-10-20 (V5.0, foundations)

### Changed

- The month end takes about half the time, with identical outcomes.

### Fixed

- A crash on save, then menu, then load.
- An 11-second month end.

## [0.4.0] - 2026-10-18 (V4, the world wants things)

The first tier recorded here; its record is the close-out section of docs/tiers/v4.md, and
the tag `v4-end` marks it.
