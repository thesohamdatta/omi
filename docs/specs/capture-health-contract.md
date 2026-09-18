# Capture Health Contract

## Status

Design specification for the first vertical-slice implementation.

## Goal

Make Omi's capture state trustworthy and understandable without replacing existing capture, WAL, sync, transcription, device, or agent infrastructure.

The contract separates five facts:

1. capture source health
2. transcription transport/readiness
3. local durability (WAL)
4. upload/sync state
5. server-side processing state

The user-facing state is derived from those facts. No surface should invent its own `isRecording` or `isHealthy` meaning.

## Scope

First phase covers the mobile capture path and the existing macOS semantic reference.

In scope:
- typed mobile capture-health projection
- existing `recording_id` as correlation key
- transcription transport outcome evidence on the existing mobile socket path
- deterministic scenario tests
- primary mobile status surface
- model-facing context adapter in a later slice

Out of scope:
- firmware changes
- BLE protocol changes
- new backend service
- new database
- new UUID/session identity
- LLM provider changes
- memory/task architecture changes
- sync protocol replacement
- capture rewrite

## Reference implementation

macOS Context for Claude already provides the semantic reference:

Per source:
- `starting`
- `live`
- `blocked`
- `stalled`
- `off`

Aggregate:
- `capturing`
- `degraded`
- `off`

The implementation also preserves per-source reason and last-output time, and tests that a live microphone cannot hide a dead screen.

Mobile should adopt the semantics, not copy the macOS implementation.

## Correlation

Use the existing `recording_id`.

For live mobile capture it is already sent as `client_conversation_id` to `/v4/listen`.

Do not add:
- `session_generation` analytics fields
- another recording UUID
- another cross-platform durable identity

Capture ownership/generation remains an internal concurrency boundary.

## Evidence model

Mobile evidence comes from existing components:

- `CaptureController`
- `CaptureProvider`
- `RecordingLifecycleTelemetry`
- `SyncProvider`
- WAL state
- transcription socket lifecycle

Transport and task success must remain distinct.

Example:

```
audio bytes flowing
    + recording_id
    + socket unavailable
    + WAL available
= capture healthy, transcription degraded, local durability active
```

That must never render as a simple `Listening` state with no qualifier.

## Derived state precedence

The projection uses this conceptual order:

### User deliberately paused

Result:
`off` / `paused`

### No source is producing and capture was requested

Result:
`blocked` or `stalled`, with source reason.

### At least one source is producing and a required source is blocked/stalled

Result:
`degraded`

### Sources producing and transcription path ready

Result:
`capturing`

### Sources producing but transcription transport unavailable

Result:
`capturing` with transcription substate `degraded` and explicit local-buffering explanation.

### Local WAL exists and upload is pending

Result:
`captured locally` with sync substate `pending`.

### Upload accepted but processing continues

Result:
`synced` with processing substate `processing`.

The display layer chooses concise copy from these typed facts. The projection must not collapse meaningful degradation into a green/healthy boolean.

## Freshness

A source is only considered `live` while it is producing current evidence.

Every source may carry `lastOutputAt`.

A watchdog timeout may transition:
`live -> stalled`.

Starting a source does not prove liveness.

A transport reconnect does not mint a new recording identity.

## Privacy

Health context may contain:
- enum states
- bounded reason codes/details
- timestamps
- opaque recording id where already permitted

It must not contain:
- transcript text
- raw audio
- screenshots
- window contents
- credentials
- device serial/name where not already contractually required

## Vertical slices

### V1: mobile semantic projection

Deliver:
- `CaptureHealthState`
- `CaptureHealthProjection`
- adapters from existing capture/transcription/sync evidence
- socket transport outcome evidence
- scenario fixtures and tests

Acceptance:
- healthy capture -> `capturing`
- one failed required source + another live -> `degraded`
- deliberately paused -> `off/paused`
- local audio + broken transcription -> explicit degraded transcription state
- stale callbacks do not change the current recording
- same `recording_id` survives socket reconnect

### V2: user-facing mobile status

Deliver:
- single primary capture status component
- existing controls remain unchanged
- degraded detail shown only when needed

Acceptance:
- no false `Listening` when transcription is explicitly unavailable
- user can identify the failing stage without opening logs
- layout remains lightweight

### V3: agent context

Deliver:
- add capture health to existing context packet builder
- include state + freshness + reason
- preserve existing packet size/provenance controls

Acceptance:
- agent can distinguish stale screen evidence from lack of historical evidence
- agent never gets raw content from health packet

### V4: desktop parity

Deliver:
- semantic adapters for existing macOS/Windows health signals
- no capture implementation rewrite

Acceptance:
- equivalent runtime conditions map to equivalent semantic health

## Required test scenarios

1. all sources live
2. mic live, screen blocked
3. screen stalled
4. mic stalled
5. all sources off
6. user pause
7. storage unavailable
8. storage opening while sources are live
9. audio live, transcription unavailable
10. audio live, transcription reconnecting
11. local WAL pending upload
12. upload accepted, server processing pending
13. stale callback after stop
14. stale callback after new recording begins
15. device disconnect/reconnect
16. account switch during capture

## Verification

Before merge:
- focused mobile capture unit tests
- capture recovery/generation tests
- new semantic projection tests
- macOS CaptureHealth and status-honesty tests
- relevant mobile verification harness
- relevant preflight checks
- no live LLM dependency in CI

## Review checklist

- [ ] No second source of truth for capture
- [ ] Existing recording_id reused
- [ ] No new dependency
- [ ] No backend schema migration
- [ ] No firmware changes
- [ ] Failure reason remains actionable
- [ ] Intentional off is not treated as failure
- [ ] Stalled means no recent evidence, not merely started
- [ ] Transport success and capture success are distinct
- [ ] Model-facing packet is bounded and privacy safe
- [ ] Existing ownership/session fences remain authoritative

## Success criterion

After V1, the system can answer one question reliably:

"What is Omi actually capturing right now, and what part is not working?"

The answer must be consistent enough for a user interface and an agent to consume the same underlying facts without guessing.
