extends RefCounted

## Calendar constants, U6a. Next to the other eight *_constants.gd files and not
## in data/, per docs/engine-decision.md Rule 1.
##
## THIS FILE CONTAINS NO TUNED CONSTANT, and that is the session's headline
## rather than an omission. U6a's probe (tools/calendar_probe.gd) measured a
## monthly budget of the player's days against a band fixed before the sweep ran,
## and the band was structurally unreachable: the median month offers 27 legal
## acts asking 124 days, so EVERY budget from 4 to 24 bound in 100 % of months.
## A ceiling that always binds is a cap, not an allocation, and the calendar over
## it is a queue rather than a diary. The currency was DELETED rather than left
## unused -- the treatment V1.3e gave AGREEMENT_ACCEPT_MIN and SUPPORT_SIGMA,
## because a tuned constant nothing reads is a number a later session finds and
## reasons from. Full tables in docs/calendar-model.md.
##
## Everything below is a BOUND -- a limit that keeps a register finite or a
## refusal legible. None of it was swept, and none of it is balance.

## How far ahead a booking may be made. Twelve months is the strip the panel
## draws, so the horizon and the surface agree by construction: the player can
## book anything they can see and nothing they cannot.
const BOOKING_HORIZON_MONTHS := 12

## How long a resolved appointment stays in the register before tick_month()
## prunes it. Matches the horizon for the same reason -- the strip looks twelve
## months back as well as forward, so a resolved act stays visible for exactly as
## long as its own page is reachable.
const RESOLVED_KEPT_MONTHS := 12

## How many dates beyond the horizon the strip lists under "later". Bounded
## because it is a footer rather than a second strip: the nearest few are what
## make a new game's diary non-empty, and the twentieth cooldown expiry three
## years out is noise. Not swept -- see later() for why this section exists at
## all, which is a measurement rather than a taste.
const LATER_SHOWN := 4

## A hard cap on the register, so a save file cannot grow without bound however
## the player behaves. Twelve months of horizon at a plausible ceiling of a dozen
## live bookings a month, doubled: this is a guard rail, not a play limit, and
## tests/test_calendar.gd asserts a player hitting it gets a refusal reason
## rather than a silent drop.
const MAX_APPOINTMENTS := 288

## Statuses an entry can carry. `booked` is the only one due() will fire.
const STATUS_BOOKED := "booked"
const STATUS_DONE := "done"
const STATUS_REFUSED := "refused"
const STATUS_CANCELLED := "cancelled"

## The three bookable verbs. A booking is a scheduling skin over a command that
## already exists, so this list is exactly the set of player commands worth
## deferring -- Budget.commit() is the core loop and deferring it would be
## hostile, Bloc.cast_vote() is a duty with its own deadline, and
## Dissolution.dissolve() already carries a lockout that is its own schedule.
const KIND_DIPLOMATIC := "diplomatic"
const KIND_LAW := "law"
const KIND_RESHUFFLE := "reshuffle"

const KINDS := [KIND_DIPLOMATIC, KIND_LAW, KIND_RESHUFFLE]

## Kinds of fixed date the diary reads off state the game already carries. These
## are labels for a surface, not behaviour: nothing in src/sim/ branches on them.
const FIXED_ELECTION := "election"
const FIXED_EP_ELECTION := "ep_election"
const FIXED_EXECUTIVE := "executive"
const FIXED_HEAD_OF_STATE := "head_of_state"
const FIXED_COUNCIL_PROPOSAL := "council_proposal"
const FIXED_COUNCIL_VOTE := "council_vote"
const FIXED_DISSOLUTION := "dissolution_lockout"
const FIXED_COOLDOWN := "cooldown"
