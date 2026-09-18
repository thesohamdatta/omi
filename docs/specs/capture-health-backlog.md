# Capture Health Implementation Tickets

These tickets implement the refined capture-health contract as tracer-bullet vertical slices.

## Ticket 01: Prove the pure mobile capture-health projection

**What to build**

When given a fixed set of existing mobile capture facts, Omi deterministically produces a truthful semantic capture-health result. The result is usable without running the capture system.

**Blocked by**

None. This is the frontier ticket.

**Acceptance criteria**

- [ ] A producing source with usable transcription is `capturing`.
- [ ] A producing source with unavailable/reconnecting transcription remains `capturing`, with explicit transcription degradation.
- [ ] A blocked or stalled required source while another required source is live is `degraded`.
- [ ] A deliberate pause is `off/paused`.
- [ ] A requested capture with no producing source reports blocked/stalled with bounded reason.
- [ ] Existing `recording_id` can be carried without creating another identity.
- [ ] The projection has no network, LLM, database, timer, socket ownership, capture-control, or analytics side effect.
- [ ] Tests exercise the public projection boundary and are hermetic.

**Verification**

Run the focused projection test file, Dart formatting for touched Dart, then the app test lane relevant to the changed package.

## Ticket 02: Prove transcription transport truth without changing capture identity

**What to build**

During a live recording, Omi can observe whether the transcription path is connecting, usable, unavailable, or reconnecting, while the recording continues to use the existing `recording_id`.

**Blocked by**

- Ticket 01

**Acceptance criteria**

- [ ] A successful transcription connection produces observable transport evidence.
- [ ] A failed connection produces bounded failure evidence.
- [ ] Reconnection keeps the same `recording_id`.
- [ ] A stale async connection result cannot publish state for a newer recording.
- [ ] Telemetry cannot change capture success/failure when its emitter throws.
- [ ] No transcript/audio/content payload is included in transport evidence.
- [ ] The projection consumes this evidence without becoming the owner of the socket.

**Verification**

Run focused capture ownership/generation and transcription lifecycle tests, then the relevant mobile verification lane if the user path changes.

## Ticket 03: Surface one truthful status in the primary mobile capture UI

**What to build**

The main mobile capture status tells the user the current capture condition in one lightweight sentence, with a more specific detail only when something is degraded.

**Blocked by**

- Ticket 02

**Acceptance criteria**

- [ ] Healthy capture remains visually simple.
- [ ] Transcription degradation does not claim that audio capture stopped.
- [ ] Source degradation identifies the affected source/stage.
- [ ] Deliberate pause remains a deliberate paused state, not an error.
- [ ] Copy is localized through the existing localization system.
- [ ] Existing capture controls and ownership behavior are unchanged.
- [ ] Widget tests cover healthy, degraded, paused, and unavailable-transcription states.

**Verification**

Run the focused widget tests, Dart formatting, and the app's mobile user-journey verification required for UI changes.

## Ticket 04: Reuse the same health projection in agent context

**What to build**

The existing agent/context packet can report current capture health and freshness using the same semantic projection as the mobile UI, without exposing captured content.

**Blocked by**

- Ticket 03

**Acceptance criteria**

- [ ] Context contains aggregate health, relevant substate, freshness, and bounded reason.
- [ ] It does not contain transcript text, raw audio, screenshots, credentials, or unrelated personal data.
- [ ] Stale source evidence is distinguishable from missing historical evidence.
- [ ] Existing context packet provenance, size, TTL, and retention contracts remain intact.
- [ ] No second transcript, memory, or capture store is introduced.
- [ ] Hermetic packet tests cover normal and degraded capture.

**Verification**

Run focused context packet tests and the relevant agent-context contract checks.

## Ticket 05: Align desktop adapters with the mobile semantic vocabulary

**What to build**

Existing macOS/Windows capture-health signals map into the same semantic vocabulary without rewriting their capture engines.

**Blocked by**

- Ticket 04

**Acceptance criteria**

- [ ] Equivalent runtime conditions map to equivalent semantic health.
- [ ] Existing macOS capture-health and status-honesty tests remain green.
- [ ] Windows adapter behavior is covered by hermetic tests.
- [ ] Platform capture ownership remains unchanged.
- [ ] No new cross-platform runtime owner is introduced.

**Verification**

Run focused desktop adapter tests plus existing macOS/Windows component verification.

## Dependency graph

01 Projection
   ↓
02 Transcription transport evidence
   ↓
03 Mobile status surface
   ↓
04 Agent context
   ↓
05 Desktop parity

## Ticketing rules

Each ticket must answer: What can I demonstrate when this ticket is complete?

Implementation follows the repository's TDD discipline:

`test at agreed public seam -> minimal implementation -> repeat -> review`

Do not batch an entire test suite before implementation. Do not add abstractions without a demonstrated need.

The ticket list is intentionally smaller than the original backlog because the pure projection is now the shared semantic seam.

## Repository constraints

- Reuse the existing `recording_id`.
- Preserve `CaptureSessionOwner` as the stale-work authority.
- Do not modify firmware or BLE protocol.
- Do not add a backend service or schema.
- Do not make analytics authoritative.
- Keep hermetic tests free of network, live services, sleeps, and real devices.
- Follow `AGENTS.md` Definition of Done, including focused verification, real user-path verification where applicable, and `make preflight` before PR merge.