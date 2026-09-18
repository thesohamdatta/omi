# Capture Health: Shared Engineering Context

## Problem

Omi can successfully begin capture while the user has no single trustworthy answer about what is actually happening in the pipeline.

The failure is not limited to one transport. Mobile already has separate state for capture, transcription, and WAL/sync. Different surfaces can therefore observe different facts and accidentally reduce them to an ambiguous recording boolean.

The first implementation target is not a new capture system. It is a truthful semantic projection over existing production signals.

## User outcome

During an active mobile recording, Omi should be able to answer:

> What is Omi actually capturing right now, and what part of the pipeline is not working?

The answer must distinguish capture from downstream transcription and local durability.

## Domain vocabulary

### Capture source

The component currently responsible for producing audio for the active recording.

A capture source is **live** only when current evidence says it is producing audio. Being requested, constructed, or connected is not sufficient.

### Capture health

A derived interpretation of current capture-source evidence.

Capture health is not independently mutable state and does not own capture behavior.

The first aggregate values are:

- `capturing`
- `degraded`
- `off`

### Transcription transport

The path that carries captured audio to a transcription service.

Transport state is separate from capture health.

### Transcription readiness

Whether the current transcription path is usable, which is stronger than the existence of a socket object.

### Local durability

Whether captured audio is safely retained locally for later synchronization.

A locally durable recording can remain capture-healthy while transcription is temporarily unavailable.

### Recording identity

The existing `recording_id` owned by `RecordingLifecycleTelemetry`.

It is the correlation identity for the active mobile recording. It is not a concurrency generation.

### Concurrency generation

The internal `CaptureSessionOwner` generation used to reject stale asynchronous work.

It must not become a second analytics identity.

## Existing evidence

The implementation must consume existing production facts rather than recreate them:

- `CaptureController` exposes recording state and the active recording identity.
- The phone microphone path already reports actual recording progress and stall/interruption conditions.
- `RecordingLifecycleTelemetry` already creates and owns `recording_id`.
- The transcription service already exposes socket connection state and the controller tracks transcription readiness separately.
- WAL/sync already distinguishes local work from uploaded work and reconciled/synced work.
- `CaptureSessionOwner` already provides the concurrency fence needed for stale async completions.

## Core invariant

Do not treat these as equivalent:

```
capture requested
capture source producing
transcription connected
transcription accepting audio
audio locally durable
upload accepted
server processing complete
```

Each is a different fact.

## V1 boundary

The first vertical slice is a pure semantic projection.

It should:

1. consume existing capture/transcription/local-durability evidence
2. derive a small typed result
3. preserve bounded reason/freshness information
4. preserve the existing `recording_id`
5. remain free of network, LLM, database, and capture-control behavior

The projection should be usable by both a later mobile UI adapter and a later agent-context adapter.

## Why the first slice excludes upload/processing

Upload and server processing already have their own state model and reconciliation lifecycle.

Coupling those into the first live capture projection would create a cross-pipeline state machine before the basic semantic seam is proven.

The initial projection may expose local durability as a fact, but it does not need to become authoritative for server processing.

## State precedence

The semantic interpretation should follow these rules:

1. Deliberate user pause is `off/paused`.
2. A requested capture with no producing source is not healthy; return `blocked` or `stalled` with a reason.
3. A producing source plus a required failed/stalled source is `degraded`.
4. A producing source with a usable transcription path is `capturing`.
5. A producing source with unavailable/reconnecting transcription remains `capturing`, but the transcription substate is `degraded` and local durability should be surfaced when available.

This avoids the misleading implication that transcription failure means audio capture itself stopped.

## Freshness

A state that only says "started" is insufficient evidence of liveness.

Where the underlying source already provides output timestamps or stall detection, the projection should preserve that evidence.

A later source watchdog may transition:

```
live -> stalled
```

The projection must not manufacture liveness timestamps when no producer-side evidence exists.

## Privacy

Health data may contain:

- closed enum/state values
- bounded reason codes
- timestamps
- the existing opaque recording identity where already permitted

Health data must not contain:

- transcript text
- raw audio
- screenshots
- credentials
- arbitrary device identifiers
- unrelated personal content

## Non-goals

Do not use this change to:

- rewrite capture
- redesign CaptureSessionOwner
- replace CaptureController
- replace WAL/sync
- add backend health APIs
- modify firmware or BLE protocol
- add a new UUID
- add a second transcript store
- introduce a new model/provider
- build a new memory/task architecture
- make analytics authoritative for runtime health

## Success condition

A deterministic test can provide a fixed set of existing production facts and obtain the same semantic health result every time.

A later UI and agent adapter can consume that same result without implementing their own capture-state interpretation.

