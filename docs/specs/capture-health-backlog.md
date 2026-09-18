# Break V1 into vertical slices

This issue is the implementation backlog for the capture-health contract specified in `docs/specs/capture-health-contract.md`.

## Child issues

### 1. Typed mobile projection
Implement the smallest typed projection over existing capture/transcription/sync state. No behavioral capture rewrite.

### 2. Transcription transport evidence
Add transport outcome evidence using the existing `recording_id`. Keep telemetry non-authoritative and side-effect free.

### 3. Mobile status surface
Consume the projection from the primary capture UI and replace ambiguous status wording with one truthful sentence plus optional detail.

### 4. Agent context adapter
Expose the projection to the existing context packet/agent context path with bounded freshness and reason fields.

### 5. Desktop parity
Map existing macOS/Windows health signals to the same semantics without changing their capture engines.

## Dependency order

1 -> 2 -> 3 -> 4 -> 5

Each slice should be independently testable and reviewable.


# V1: Add a typed mobile capture-health projection

## Goal

Turn existing mobile capture, transcription, and sync evidence into one deterministic typed projection without changing capture behavior.

## Scope

Primary files to inspect:
- `app/lib/services/capture/capture_controller.dart`
- `app/lib/services/capture/recording_lifecycle_telemetry.dart`
- `app/lib/providers/capture_provider.dart`
- `app/lib/providers/sync_provider.dart`
- existing WAL state/services

Add only the smallest new projection/seam needed to represent:
- source states: `starting | live | blocked | stalled | off`
- aggregate: `capturing | degraded | off`
- transcription substate
- sync substate
- detail/reason
- existing `recording_id`
- freshness timestamp(s)

Do not replace existing providers or controllers.

## Acceptance

- deterministic mapping of healthy/degraded/paused/stalled states
- local capture can remain healthy when transcription transport is unavailable
- upload/processing state is not confused with source capture
- deliberate pause is not a failure
- no new UUID/session identity
- projection has no network/LLM dependency

## Required tests

At minimum:
- all sources live
- source blocked + another live
- source stalled
- user paused
- audio live + transcription unavailable
- upload pending
- upload accepted + processing pending
- no source active

## Verification

Run focused Flutter tests for the touched seams and `dart format` only on touched Dart files.


# V1: Add mobile transcription transport outcome evidence

## Goal

Close the observability gap where mobile capture can continue locally while the transcription socket is unavailable, without minting another recording identity.

## Scope

Use existing `recording_id` as the correlation key.

Instrument the existing transcription socket connect/reconnect lifecycle so the projection can distinguish:
- transport connecting
- transport active
- transport failed/unavailable

Do not add a new UUID.

Do not make telemetry affect capture behavior.

Prefer the existing analytics/telemetry path and existing closed enums.

## Acceptance

- connect success is observable
- permanent/temporary connection failure is observable
- reconnect attempts remain associated with the same `recording_id`
- stale generation cannot emit for a replaced recording
- telemetry failure cannot change capture success/failure
- no raw audio/transcript content is emitted

## Required tests

- connection success
- connection failure
- reconnect under same recording_id
- stale connection completion after stop/new session
- analytics emitter throwing does not affect capture

## Verification

Run capture socket generation/recovery tests and the relevant mobile verification lane.


# V1c: Surface capture health in the mobile UI

Consume the V1 projection from the main capture status surface.

Do not rewrite capture controls.

Acceptance:
- healthy capture remains visually simple
- degraded capture names the affected stage/source
- no false "Listening" when transcription is explicitly unavailable
- paused remains a deliberate paused state
- copy goes through existing localization

Add widget tests for each display state.

# V1d: Add capture health to agent context

Feed the capture-health projection into the existing context packet path.

Acceptance:
- includes state, freshness and bounded reason
- no raw transcript, audio, screenshot or credentials
- stale source evidence is explicit
- packet size/provenance contracts remain intact
- no second transcript or memory store

Add hermetic packet tests.

# V1e: Align desktop health semantics

Map existing macOS and Windows capture health signals to the same semantic vocabulary used by mobile.

Do not rewrite platform capture engines.

Acceptance:
- equivalent runtime conditions produce equivalent semantic health
- platform-specific UI remains unchanged unless needed
- existing macOS capture-health tests remain green
- Windows capture tests cover the adapter mapping
