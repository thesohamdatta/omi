import 'package:flutter/foundation.dart';

import 'package:omi/utils/enums.dart';

/// Semantic state of the audio producer for a capture session.
enum CaptureSourceState { starting, live, blocked, stalled, off }

/// Semantic state of the transcription path for a capture session.
enum CaptureTranscriptionState { connecting, ready, degraded, off }

/// Semantic state of local audio durability.
enum CaptureDurabilityState { available, unavailable, pending, unknown }

/// Derived user-facing interpretation of capture.
enum CaptureHealth { capturing, degraded, off }

@immutable
class CaptureHealthEvidence {
  const CaptureHealthEvidence({
    required this.source,
    required this.transcription,
    required this.durability,
    this.recordingId,
    this.sourceReason,
    this.sourceLastOutputAt,
    this.transcriptionReason,
    this.durabilityReason,
  });

  final CaptureSourceState source;
  final CaptureTranscriptionState transcription;
  final CaptureDurabilityState durability;
  final String? recordingId;
  final String? sourceReason;
  final DateTime? sourceLastOutputAt;
  final String? transcriptionReason;
  final String? durabilityReason;
}

@immutable
class CaptureHealthResult {
  const CaptureHealthResult({
    required this.health,
    required this.source,
    required this.transcription,
    required this.durability,
    this.recordingId,
    this.reason,
    this.lastEvidenceAt,
  });

  final CaptureHealth health;
  final CaptureSourceState source;
  final CaptureTranscriptionState transcription;
  final CaptureDurabilityState durability;
  final String? recordingId;
  final String? reason;
  final DateTime? lastEvidenceAt;

  bool get isCapturing => health == CaptureHealth.capturing;
  bool get isDegraded => health == CaptureHealth.degraded;
  bool get isOff => health == CaptureHealth.off;
}

/// Deep module containing the semantic rules for mobile capture health.
///
/// The interface is intentionally small: callers provide evidence and receive
/// one immutable result. This module owns no capture behavior or I/O.
class CaptureHealthProjection {
  const CaptureHealthProjection();

  CaptureHealthResult project(CaptureHealthEvidence evidence) {
    switch (evidence.source) {
      case CaptureSourceState.live:
        return CaptureHealthResult(
          health: CaptureHealth.capturing,
          source: evidence.source,
          transcription: evidence.transcription,
          durability: evidence.durability,
          recordingId: evidence.recordingId,
          reason: _downstreamReason(evidence),
          lastEvidenceAt: evidence.sourceLastOutputAt,
        );
      case CaptureSourceState.starting:
        return CaptureHealthResult(
          health: CaptureHealth.degraded,
          source: evidence.source,
          transcription: evidence.transcription,
          durability: evidence.durability,
          recordingId: evidence.recordingId,
          reason: evidence.sourceReason ?? 'starting',
          lastEvidenceAt: evidence.sourceLastOutputAt,
        );
      case CaptureSourceState.blocked:
        return CaptureHealthResult(
          health: CaptureHealth.degraded,
          source: evidence.source,
          transcription: evidence.transcription,
          durability: evidence.durability,
          recordingId: evidence.recordingId,
          reason: evidence.sourceReason ?? 'source_blocked',
          lastEvidenceAt: evidence.sourceLastOutputAt,
        );
      case CaptureSourceState.stalled:
        return CaptureHealthResult(
          health: CaptureHealth.degraded,
          source: evidence.source,
          transcription: evidence.transcription,
          durability: evidence.durability,
          recordingId: evidence.recordingId,
          reason: evidence.sourceReason ?? 'source_stalled',
          lastEvidenceAt: evidence.sourceLastOutputAt,
        );
      case CaptureSourceState.off:
        return CaptureHealthResult(
          health: CaptureHealth.off,
          source: evidence.source,
          transcription: CaptureTranscriptionState.off,
          durability: evidence.durability,
          recordingId: evidence.recordingId,
          reason: evidence.sourceReason ?? 'off',
          lastEvidenceAt: evidence.sourceLastOutputAt,
        );
    }
  }

  String? _downstreamReason(CaptureHealthEvidence evidence) {
    switch (evidence.transcription) {
      case CaptureTranscriptionState.connecting:
        return evidence.transcriptionReason ?? 'transcription_connecting';
      case CaptureTranscriptionState.degraded:
        return evidence.transcriptionReason ?? 'transcription_unavailable';
      case CaptureTranscriptionState.ready:
      case CaptureTranscriptionState.off:
        return evidence.durability == CaptureDurabilityState.unavailable
            ? (evidence.durabilityReason ?? 'local_durability_unavailable')
            : null;
    }
  }
}

/// Maps lifecycle/control state only. It cannot prove that the producer is
/// emitting audio, so a recording lifecycle state never manufactures `live`.
CaptureSourceState captureSourceStateForRecording(RecordingState state) => switch (state) {
      RecordingState.initialising => CaptureSourceState.starting,
      RecordingState.record => CaptureSourceState.starting,
      RecordingState.deviceRecord => CaptureSourceState.starting,
      RecordingState.systemAudioRecord => CaptureSourceState.starting,
      RecordingState.pause => CaptureSourceState.off,
      RecordingState.stop => CaptureSourceState.off,
      RecordingState.interrupted => CaptureSourceState.stalled,
      RecordingState.error => CaptureSourceState.blocked,
    };

/// Builds source evidence using observed audio output as the authority for
/// `live`. Lifecycle state is supporting context only.
CaptureHealthEvidence captureHealthEvidenceForAudioOutput({
  required RecordingState recordingState,
  required bool hasAudioOutput,
  DateTime? lastAudioOutputAt,
  String? recordingId,
}) {
  final lifecycle = captureSourceStateForRecording(recordingState);
  final source = hasAudioOutput
      ? CaptureSourceState.live
      : lifecycle == CaptureSourceState.off || lifecycle == CaptureSourceState.blocked
          ? lifecycle
          : lifecycle == CaptureSourceState.stalled
              ? CaptureSourceState.stalled
              : CaptureSourceState.starting;

  return CaptureHealthEvidence(
    source: source,
    transcription: CaptureTranscriptionState.connecting,
    durability: CaptureDurabilityState.unknown,
    recordingId: recordingId,
    sourceReason: source == CaptureSourceState.starting ? 'awaiting_audio_output' : null,
    sourceLastOutputAt: lastAudioOutputAt,
  );
}
