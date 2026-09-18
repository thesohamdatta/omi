# Capture Health Contract

## Status

Refined after repository inspection and second-pass domain review.

## Objective

Make mobile capture status trustworthy without creating a second capture system.

The first slice must let Omi answer:

> What is Omi actually capturing right now, and what part of the pipeline is not working?

The answer is derived from existing production evidence. It is not a new source of truth.

## User-visible scope

The first implementation covers the live mobile capture path.

It must distinguish:

- capture source health
- transcription transport/readiness
- local durability

It may expose bounded freshness and reason information.

Upload admission, server-side processing, memory promotion, task systems, and desktop parity remain later integration work.

## Domain model

### Capture source

The producer of audio for the active recording.

A source is live only when current evidence indicates that it is producing audio. Requested/constructed/connected does not prove liveness.

### Capture health

A derived semantic result:

- `capturing`
- `degraded`
- `off`

Capture health owns no runtime behavior.

### Transcription transport

The path that can carry captured audio toward transcription.

### Transcription readiness

Whether the current transcription path is usable. Socket existence alone does not establish readiness.

### Local durability

Whether captured audio is safely retained locally for later synchronization.

### Recording identity

The existing `recording_id` owned by `RecordingLifecycleTelemetry`.

Do not create another recording UUID or analytics identity.

### Concurrency generation

The internal `CaptureSessionOwner` generation used to reject stale asynchronous work.

Generation is not recording identity and must not become a new analytics field.

## Existing authoritative evidence

The projection must consume existing production facts:

- `CaptureController.recordingState`
- `CaptureController.activeRecordingId`
- existing phone-microphone recording/stall/interruption signals
- `TranscriptSegmentSocketService.state`
- existing transcription-readiness state in `CaptureController`
- existing WAL/local-durability state
- existing `CaptureSessionOwner` generation fencing

Analytics is observational. It must never become runtime truth.

## Core rules

The following are distinct facts:

1. capture was requested
2. capture source is producing
3. transcription transport is connected
4. transcription path is ready
5. captured audio is locally durable
6. upload was accepted
7. server processing completed

The first slice must not collapse these facts into one boolean.

## State derivation

### Deliberate pause

If the user has deliberately paused the active capture:

`health = off`, `reason = paused`.

Pause is not failure.

### Requested but no source is producing

Return:

`blocked` or `stalled`

with the bounded source reason.

A source entering `initialising` is not sufficient to claim healthy capture.

### Source producing, downstream degradation

If a source is producing but transcription is unavailable or reconnecting:

`health = capturing`

with transcription substate `degraded`.

If local durability is available, retain that fact.

Transcription failure must not be represented as capture failure when audio is still being captured safely.

### Source degradation

If a required capture source is blocked or stalled while another required source is live:

`health = degraded`.

### Healthy capture

When the active source is producing and the transcription path is usable:

`health = capturing`.

## Pure projection boundary

The first implementation should expose a small pure boundary equivalent to:

`input evidence -> semantic capture-health result`

It must have:

- no network calls
- no LLM calls
- no database writes
- no timers
- no socket ownership
- no capture-control methods
- no analytics side effects

The result may include:

- aggregate health
- source state
- transcription substate
- local durability substate
- bounded reason code
- freshness timestamps
- existing `recording_id`

Exact type names are implementation details and should be chosen to fit existing Dart conventions.

## Freshness

A source cannot be marked live merely because startup succeeded.

Where producer-side timestamps or stall signals exist, preserve them.

Do not invent timestamps for evidence the underlying producer does not provide.

A later watchdog may transition:

`live -> stalled`

The first slice may consume existing stall signals without adding a new watchdog.

## Correlation and stale work

The projection must use the existing `recording_id` for correlation.

`CaptureSessionOwner` remains the authority for stale asynchronous work.

A socket reconnect retains the same `recording_id`.

A stale completion from an earlier recording must not mutate or publish health for the current recording.

## Privacy

Health data may contain:

- closed states
- bounded reason codes
- timestamps
- existing opaque `recording_id` where already permitted

Health data must not contain:

- transcript text
- raw audio
- screenshots
- credentials
- arbitrary device names or serial numbers
- unrelated personal content

## Non-goals

This change must not:

- rewrite capture
- redesign `CaptureSessionOwner`
- replace `CaptureController`
- replace WAL/sync
- add a backend health endpoint
- modify firmware or BLE protocol
- add a new UUID
- add a second transcript store
- make analytics authoritative
- redesign memory/task architecture
- implement desktop parity
- introduce a large cross-pipeline state machine

## Test-first acceptance

The first implementation is accepted when deterministic hermetic tests prove at least:

1. live source + usable transcription -> `capturing`
2. live source + unavailable transcription + local durability -> `capturing` with degraded transcription
3. source blocked/stalled while another required source is live -> `degraded`
4. deliberate pause -> `off/paused`
5. requested capture with no producing source -> blocked/stalled with reason
6. existing recording identity is preserved across transcription reconnect
7. stale completion cannot affect a newer recording

Tests must exercise the agreed public projection seam, not private implementation details.

## Integration path

After the pure projection is green:

1. add transport outcome evidence at the existing transcription lifecycle seam
2. connect the projection to the primary mobile status surface
3. reuse the projection in agent context
4. align desktop adapters

Each later slice must preserve the same semantic contract.

## Verification

Before PR merge:

- focused mobile unit tests
- relevant capture ownership/generation tests
- `dart format` on touched Dart files
- the component test runner
- relevant mobile verification lane for user-facing UI
- `make preflight`
- verification evidence recorded in the PR

No live service or LLM dependency belongs in hermetic tests.

## Review gates

Review the resulting change on two independent axes:

### Standards

Does the implementation follow Omi's engineering rules, testing conventions, ownership boundaries, privacy requirements, and maintainability expectations?

### Specification

Does the implementation actually satisfy the behavioral contract above, without missing requirements or adding unrelated behavior?

A passing standards review does not imply a passing specification review, and vice versa.

## Success condition

The same semantic projection can drive both a later mobile UI and a later agent context adapter, so neither surface has to guess what the capture pipeline is doing.
