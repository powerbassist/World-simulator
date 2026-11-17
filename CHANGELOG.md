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

## [0.5.3-gate.3] - 2026-11-17 (V5.3 rework 2 and the void pass)

### Added

- The Finances screen's autumn lines (creating and abolishing a tax) now read in French.
- More of the Finances screen reads in French: the "of which" breakdowns, the share moves between sectors, and the inequality line.
- The Finances screen (the books, the line editor, the bill's footer and its sheet) now reads in French when the game is in French.
- The firm sheet and the sector programme on the Sectors screen read in French when the game is in French.
- French glossary: every term and its explanation now read in French when the game is in French.
- The names of the 60 traded goods, the debt and GDP figures on the strip, and the Table a bill button now read in French.
- The Majority tab (government type, censure, dissolution, amendment and election rules, partners, the second chamber and the court) and the People tab's Dismiss, Government, The bench and Activists now read in French.
- The People screen (roster groups, government offices, the See them and fill-an-office buttons) now reads in French.
- Tax names, budget domains, power-station kinds and the Sectors and Finances leftover lines now read in French, and billions of euros are written Md€ everywhere.
- The Regions screen (its map chips, region sheet, development fund and region list) now reads in French.
- The Sectors screen reads in French when the game is in French.
- Regional figures in the four playable nations now ask for a development fund in their own region.
- A corner of the main menu shows which build you are playing.
- The Bills tab can be narrowed to one shelf of the statute book (taxes, work, housing and ten more, each with its count) and searched by words from a law's name or summary.
- A Books tab opens the Finances domain: one sentence for what comes in, what goes out, the deficit and the debt, the two-year ranges, and the books drawn to one scale, revenue by kind of tax on the left and spending by line on the right, the deficit standing as the part of spending above revenue. Small taxes fold into one line, and what no row sets says so.
- Finances now has a bill sheet you open before tabling: it lists only the rows you changed with their before and after, what each does to the books a year and who it pleases or angers, the spending, revenue and deficit totals, how the Assembly would divide, and where the system allows it, a forced passage with the censure it would meet. Table and Withdraw are on the sheet too.
- In your country's autumn month the Books page lets you put a tax that is not in force into the autumn finance bill, or abolish one that is, from its row. The sheet and the footer name each creation and abolition and price it with the rest of the bill, and a creation or abolition already at vote is locked.
- Under "Other revenue" and "Other spending", a line names the parts the player did not set (the Union, deployments, subsidies, investment, public works, regional aid, plant rescues, energy, tariffs, dividends) and opens to their figures.
- The Bills page opens on the goals you are judged on (the deficit, unemployment, a bloc, your promises) and lists what would move the one you pick, best first, with whether the Assembly would pass it and, greyed, why something cannot be tabled now; the old list of laws is one press away.
- an Interface size setting beside Text size: Auto, 100 %, 90 %, 80 % or 75 %.
- On the Majority tab, a governing party's name opens its offices in People; a party holding none says so.
- The Bills tab shows an order paper while a bill is before the Assembly: this month's vote and up to three bills queued behind it, each with the day it is voted. Drag a queued bill to reorder it, or right-click it to move it or take it out.
- While a bill is before the Assembly, a law's page offers to queue it for the next free month, and says why it cannot be proposed meanwhile. Right-clicking a law in the list offers the same choices.
- Chips and a search box pick a group of people (the government, party leaders, regions, the press, unions, the bench, activists, abroad).
- The government is the roster's first group, one row per office with the party that holds it, what it delivers and how loyal the party is; a vacant office says it counts half until you fill it.
- A row's verbs sit under it and on a right click: see someone who asked on their first free day, call them, and on an office fill it, give it to another party or dismiss it; a verb you cannot use is greyed with the reason.
- The programme's file lists how past terms' programmes ended, and the Presidency page's programme lane carries the same record in its tooltip.
- Each sector tab has a firm sheet beside it: the firm, its jobs and worth, a plant closure with its answers, and the verbs the State can use on it.
- State aid now says what it costs per job a year and as a share of a tax point, and how many jobs it gains at the firm and costs its rivals, before you grant it.
- A plant closure says how much unemployment rises in its region when the plant shuts.
- A sector programme is chosen on a slider or by typing its price, and goes into the finance bill to be voted at the end of the month.
- Right-click a firm to see its verbs with their prices, call its chief, or show it on the map.
- A Sectors section with one tab each for agriculture, industry and services: how each sector is doing against the nation, what it makes good by good (price over the year, trade this month, which major makes it), and its major firms.
- A sector tab with something waiting on you shows an hourglass and a count, and its row opens the firm where you answer it.
- Opening Regions now frames your country on the map beside a narrower panel, each region tinted by its jobless rate against the nation with the figure printed on it; chips switch the map to output per head or the last year's change.
- Clicking one of your regions on the map opens its sheet, and the open region is outlined.
- An opened region shows its jobless change over the last year against the nation's, who speaks for it and what their voice is worth if you fund it, where unrest would land and how many people left.
- The development fund's preview now says what the other regions lose and names the figure who would speak for you.
- After you answer a decision, its page lists what is still on your desk, each one a button that opens it.
- An Agenda with no programme for the term offers a way to plan the campaign.
- France, Germany, Britain and Poland now levy the taxes they really levy, at their real rates, with fifteen new kinds such as fuel duty, carbon tax and inheritance tax that you can see and move in the Tax Code.
- A plant closure raises unemployment in its own region, and the rise fades over a few years.
- A regional figure who wanted a development fund now speaks up for the government once when one opens in their region, a boost among workers and students that fades over about two years.

### Changed

- A decision's buttons carry a short label of their own, and the full wording heads each choice.
- In French, unrest is now called "Tensions" in the interface, the same word as its glossary entry.
- Loading a game rebuilds the whole screen from the save, so nothing of the game you left (a picked line, an open question, a half-typed search, a map view) carries over. A load takes about a second longer, and lands on the map.
- Continue and Load from the main menu start straight in the saved game instead of building a new game first.
- A sector programme you cannot table now says why in the game's own words.
- The Assembly's seats are no longer drawn on the Bills tab; point at a vote's forecast bar to see them by party.
- On the Books tab, a tax or a spending line opens where you click its name: a slider, a box for the exact figure (a fuel duty of 0.67 shows as 0.67), what the move books a year and who it is for, and every change you make joins one draft that the footer tables as the month's finance bill, or adds to a bill already before the Assembly.
- A tax already in the bill before the Assembly shows where it is going and is locked until the bill is withdrawn, and the footer can open or withdraw that bill.
- A tax row or a spending line in the goal panel now opens that row on the Books tab.
- A spending row of the Books now opens its sectors under its slider: a bar for each sector, why a slipping one slips, one "Raise to" button that moves the slider, and the move of a share between two sectors.
- A share move takes effect at once: the footer says so ("Apply the moves"), and beside a bill it adds how many moves apply now and when the rest is voted. A bill the Assembly refuses no longer takes the move back, and its card says so.
- A line with a slipping sector is marked "(!)" on its closed row, and the briefing, the Agenda and the polling page now open the Books where they opened the Budget.
- The B key opens the Books.
- Dispatches is now the Folder: one list of what waits for your answer, everything decided (the clock's own answers too) and the news, with the chosen item's page beside it.
- Answering on the Folder never stops the clock.
- The chief of staff's monthly card is gone; clicking his face opens the Presidency page, which carries his read, his mood, what is also due this month and what your choices did.
- The inbox keeps decisions and requests; news is one line, "News: N", that counts what landed since you last read it and opens it in the Folder.
- After you answer a decision, the inbox stays over your tab while a request still waits.
- The chief of staff no longer stops the game at the start of each month: his first priority sits beside "requests waiting" at the top of the screen, and his remark shows under it for a few seconds when he has something new to say.
- Click the chief to open his monthly briefing; the game pauses only while you read it.
- The briefing lists only real priorities; a quiet month names just the next election.
- The month's consequence and sector notes always arrive in the inbox.
- on a desk monitor larger than 1080p, the interface now keeps its 1080p size by default and the extra room goes to the map, instead of everything being drawn bigger; a dense laptop screen keeps the larger interface.
- A law's page now shows what it does, its price with each bloc and the polls you can commission, and Propose puts it to the vote at once instead of opening a second window first.
- Pointing at a vote's forecast bar shows the for, against and undecided counts above the Assembly's seats.
- The Politics tab is gone. The government's seats, majority, censure, Article 49.3, partners and opposition, and "How this republic works" now sit in Parliament's new Majority tab, beside Bills.
- Dissolve has one home, the Majority tab; Bills no longer carries a second one.
- A briefing about your majority opens the Majority tab; one about a minister's office opens the office rows in People, where you reshuffle.
- The Legislature tab is now called Bills.
- The People tab is one roster sorted by who needs you: a request waiting, a promise falling due, a grudge turning hostile, then everyone else by standing; each row says what they hold, how they feel, what they want now, what you owe them and how well you know them.
- The Presidency's overview is one page: your chief of staff's read with a Go on each priority, then the term drawn as a timeline from the past year to the next vote, with your approval, each programme goal against its target and its deadline, and the majority.
- What used to be pinned in the Outliner now sits on the overview page under "Open now"; the Outliner tab is gone.
- The term's programme is now chosen on its own file in the Folder: the offer by group on the left, the chosen entry's text and its Choose on the right.
- The Agenda tab is gone; the Agenda keeps the Diary, and a running programme is followed on its lane on the Presidency page.
- Pressing play before choosing a programme opens its file in the Folder, once.
- After you choose, the file shows the programme you booked and says the clock runs again, with a way to its lane.
- Closing the programme's inbox card no longer hides the offer: its file stays in the Folder until you choose or the clock runs past the term's start.
- Mid-term with no programme, the Presidency page's programme lane says when the next one can be chosen and opens the campaign.
- Going to a running programme from the chief's read now lands on its lane, focused.
- The Industry section is now the Sectors overview; its programmes and firm verbs are where they were.
- The Territory domain is now called Regions, and its regions are listed worst first.
- A short page is now a panel as tall as its content over the map, instead of a full-height page with empty space below.
- The Agenda, Diplomacy and Energy pages are narrower, so the map shows beside them.
- A figure now sits next to its label instead of at the far right edge of a wide page.
- The audience is rebuilt as three cards, Grant, Counter and Refuse, where Counter offers your word for a later date picked to the day, a struck deal opens a short conversation, and Refuse ends the meeting showing what it cost.
- Taking a visitor's money now also gives them your word as Grant does, the other answers wait until you take or leave it, and the chance of it being found out is read up to the next vote.
- The top bar is now a three-month horizon showing your bookings and what falls due, with pause and speed buttons as icons beside the date, and each figure shows which way it moved; approval moves to your portrait card.
- The monthly briefing is now a folder that lists the month's decisions, and clicking an event or request in the inbox opens it as a page with each choice's effects on its card.
- Commit on the Budget or the Tax Code now tables a finance bill that the Assembly votes on at the month's end, and the Tax Code lets you withdraw it before the vote.
- If a person refuses your counter-offer of a later date, you are no longer bound to anything; it only costs one of the audience's attempts.
- Every window that dims the game now also blurs it.
- Saves from earlier builds no longer load.
- Each tax's slider in the Tax Code now stops at the lowest rate that tax allows, and a finance bill that would move a rate outside its range is refused instead of landing.
- A sector programme and a regional development fund now go into the finance bill: they are voted at the end of the month and start only if it passes.
- State aid to a firm is priced by the firm, a share of its payroll a year: a subsidy or a rescue now costs millions a year, not billions, and its growth follows the money.
- Aid to a small firm earns a political credit in proportion to its jobs.
- Plant closures are rarer and larger, thousands of jobs each.
- A request whose wish you already met while it waited (a fund opened in the region, say) now closes without costing you the person's goodwill, instead of counting as a refusal.
- Someone you turned down about a post or a regional fund no longer comes back with the same request until that post or fund changes hands.

### Removed

- The Tax Code tab and its X key; the tax rates are set on the Books tab, and the income brackets are a setting of the income tax's row.
- The Budget tab. Its levers, its Commit and Revert, its table and the revenue-against-spending history chart are gone; the Books rows and footer replace them.
- The "Monthly briefing" option in the settings.
- The "Who matters now" cards at the top of People; their order is now the roster's.
- The overview's four small charts and its "moving" column; the approval line now lives on the term's timeline.
- The Commodities tab. Its goods are listed in the sector tabs, and a good short of demand is marked there.
- The recipe list of what makes what.
- The sector priority, the share-of-output chart and the reach and named-jobs rows are gone from the regions screen.
- You can no longer propose a tax of your own from the Tax Code.
- The audience screen no longer offers Argue, Pressure or a lie.

### Fixed

- Smaller firms no longer repeat a word in their names, and in the four playable nations their names fit their sector.
- The largest service firms below the majors no longer all employ exactly 25 000 people.
- Six districts, among them a Paris quarter listed as the city of "Gare", are no longer shown as cities.
- Firms of the nations you do not play no longer carry a word of another sector in their names.
- the 'Dotted words explain themselves' note no longer comes back after you load a save once you have read it.
- A tax abolished or created while the finance bill's sheet is open now shows on the sheet before you table it.
- Clicking "Abolish this tax" updates the row at once, and a second click no longer takes the abolition back.
- A tax already in force at 0 % that a bill raises no longer reads as a new tax.
- After loading another nation's game, the Regions tab tints that nation's regions on the map and a click on one opens it.
- A capital that sits inside another region is no longer painted with both regions' tints.
- Clicking a city on the map opens it without the map jumping back to your own country.
- Loading a game with the Regions tab open frames the loaded country, and "All regions" after a city frames it again.
- A region opened from its inbox card stays centred instead of the map jumping back to the whole country.
- The Regions map's measure goes back to unemployment after a load instead of keeping a measure the save cannot show.
- The goods table's trade column says its figure is the yearly pace of this month's trade.
- A goods filter on a good that left the table no longer empties it.
- The programme slider keeps its drag, keeps the keyboard focus on a step, shows the price and the programme's name live while you drag, and a click that moves nothing picks nothing.
- "Put it in the finance bill" says why it is unavailable while a programme already runs.
- Loading a game clears the sector tabs' filter, chosen firm and programme pick from the game you left.
- When the chief of staff speaks after another voice, his line is no longer cut and his words are back on screen while he talks.
- The chief of staff's note in the title bar updates after any decision you take, including in an audience or putting a programme in the finance bill, and shows the loaded game's note right after a load.
- Loading a game no longer puts a note from the game you left into the new inbox.
- The Save/Load window no longer cuts off a saved game's Delete button when the list scrolls, in French at a larger text size.
- Save names show in full and exactly as typed, never translated.
- When you amend a finance bill, the sheet's spending, revenue and deficit now count the whole bill the Assembly will vote on, the same bill its seat forecast is for.
- On an amended finance bill, the Books deficit line and the two-year ranges now count the whole bill, as the sheet and the footer do.
- In French, the glossary tooltip lines "Your value" and "See also" are translated, and the A-Z bar files an accented word under its plain letter (Économie under E).
- A summit conversation keeps its effects whatever language its answers are read in.
- At larger text sizes the programme list names one welcoming group and a count, so the entry's text keeps its room beside it.
- The political support shown for state aid now matches what a small firm actually earns you.
- The development fund's preview no longer runs off the side of the regions panel.
- The figures printed on the regions map are larger, bold and on a dark backing, so roads and city markers no longer hide them.
- Starting a regional fund now says on the region's sheet that it is in the finance bill and when the bill is voted, and the button cannot be pressed twice.
- A region whose fund already runs no longer promises that its figure will speak for you when a fund opens.
- The scroll bar no longer sits flush against the text of a scrolled panel; there is a small clear gap between them in every panel.
- A region's own figures (its sheet, the table, the map tint, the fund strip) now include a closed plant's rise in unemployment, as the closure card says.
- Rescuing a failing firm now shows the political credit it will actually earn.

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
