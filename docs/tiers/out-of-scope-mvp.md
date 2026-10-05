---
title: Out of Scope for MVP
tags:
  - tier
  - scope
---

# Out of Scope for MVP

An explicit list, not an implication. If it is here, it does not get built in the MVP phase, and a session that starts drifting toward one of these is off-plan.

Each entry says *why*, because "not yet" without a reason erodes the moment something feels easy.

## Cut, with reasoning

| Excluded | Why |
|---|---|
| **Interactive diplomacy** — negotiations, treaties, relations scores, diplomatic actions | The single biggest cut. Neighbours exist at MVP as economic context, not as counterparties. Diplomacy needs an AI that can evaluate offers, which is a whole subsystem, and the domestic loop must be proven fun before another one is layered on. Lands in [[v1]]. |
| **Trade agreements** | Same reason. Passive trade volumes feed growth; negotiating them is [[v1]]. |
| **Private companies** | Explicitly deferred. The MVP economy is aggregate sectors. Named firms with subsidies, regulation and nationalisation are a rich system that would dominate MVP development time. [[v1]]. |
| **Changing the political system** — monarchy to republic and back | A headline pitch feature, and it requires the institutional layer to be *stable* before it can be made *swappable*. Building it into a system that only has one instance is speculative abstraction. [[v1]]. |
| **Dissolving the assembly / snap elections** | Depends on confidence votes and coalition mechanics that do not exist at MVP. Also, an escape hatch from the fixed-term clock undermines the one pressure the MVP has. [[v1]]. |
| **Coalitions and confidence votes** | Requires party AI that can bargain. The MVP assembly votes on bills by ideology alignment, which is enough for laws to be a real obstacle. [[v1]]. |
| **Upper house / judiciary** | A second veto point before the first one is tuned. [[v1]]. |
| **Referendums** | Needs campaign mechanics and question authoring to be interesting. [[v1]]. |
| **Cabinet and ministers** | Adds a management layer on top of a loop that does not yet exist. [[v1]]. |
| **Central bank and monetary policy** | France is in the eurozone. It does not set its own interest rate, so the realistic version of this mechanic is *not having it*. Genuinely out until non-euro playable nations exist. [[someday]]. |
| **War and military** | Enormous scope, and orthogonal to "survive re-election". Split since: the *domestic politics* of defence — capability, deployments, alliance obligations billed at home — is scheduled thin in [[v1|V1.3]], where relations exist to point it at. Warfighting itself stays [[someday]]. |
| **Espionage** | Same. [[someday]]. |
| **Media outlets and press freedom** | Opinion at MVP moves from material conditions directly. A media layer that mediates that is a refinement of a system that must work first. [[v1]]. |
| **Corruption** | Same reasoning — a modifier on systems that do not exist yet. [[v1]]. |
| **Regional autonomy, separatism** | Regions are imported as map geometry but carry no simulation state at MVP. Per-region modelling multiplies entity count and data authoring immediately. [[someday]]. |
| **Multiple playable nations** | France only. Every additional playable nation multiplies balancing and content, and the political-system layer needed to make, say, Germany play differently is itself [[v1]]. |
| **Campaign phase and promises** | The election at MVP is a resolution step, not a playable phase. [[v1]]. |
| **Events system** | Tempting, because scripted events make an unfinished game feel alive. That is exactly the risk: events can paper over a loop that is not actually working. Deferred until the systemic loop stands on its own. [[v1]]. |
| **Localisation** | English only. Translation before content is settled means translating it twice. |
| **Audio and music** | Not a mechanic. |
| **Tutorial and onboarding** | You cannot teach a design that is still moving. |
| **Modding support** | The JSON data layer means the game is *incidentally* moddable, which is fine. Building documented mod APIs and a loader for hypothetical modders is textbook speculative work. |
| **Achievements, statistics, meta-progression** | Wrapping paper. |

## The rule this list exists to enforce

Every item above is a real feature that would make the game better. That is precisely why the list is written down: the danger is never the bad idea, it is the good idea arriving four months early and pushing the playable loop past the horizon.

The MVP loop closes at **session S6** of the . Nothing on this page gets built before then.

---

Related: [[scope]] · [[mvp]] · [[v1]] · [[someday]] · [[declined]]
