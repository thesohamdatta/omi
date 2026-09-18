import 'package:flutter/foundation.dart';

import 'package:omi/utils/enums.dart';

/// Semantic state of a capture source.
enum CaptureSourceState { starting, live, blocked, stalled, off }

/// Semantic state of the transcription path used by the active capture.
enum CaptureTranscriptionState { connecting, ready, degraded, off }

/// Semantic state of local recording durability.
enum CaptureDurabilityState { available, unavailable, pending, unknown }

/// User-facing aggregate interpretation of the active capture pipeline.
///
/// This is derived state. It does not start, stop, reconnect, upload, or mutate
/// any runtime owner.
enum CaptureHealth { capturing, degraded, off }

/// Immutable evidence presented to [CaptureHealthProjection].
///
/// The producer owns the facts. The projection only interprets them.
@immutable
class CaptureHealthEvidence {
  const CaptureHealthEvidence({
    required this.captureRequested,
    required this.source,
    required this.transcription,
    required this.durability,
    this.recordingId,
    this.sourceReason,
    this.sourceLastOutputAt,
    this.transcriptionReason,
    this.durabilityReason,
    this.paused = false,
  });

  final bool captureRequested;
  final CaptureSourceState source;
  final CaptureTranscriptionState transcription;
  final CaptureDurabilityState durability;
  final String? recordingId;
  final String? sourceReason;
  final DateTime? sourceLastOutputAt;
  final String? transcriptionReason;
  final String? durabilityReason;
  final bool paused;
}

/// Immutable semantic result shared by later UI and agent adapters.
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

/// Pure semantic projection for current mobile capture evidence.
///
/// Deliberately contains no I/O and no runtime ownership. This keeps the seam
/// cheap to test and prevents a status surface from becoming a second capture
/// controller.
class CaptureHealthProjection {
  const CaptureHealthProjection();

  CaptureHealthResult project(CaptureHealthEvidence evidence) {
    if (evidence.paused) {
      return CaptureHealthResult(
        health: CaptureHealth.off,
        source: CaptureSourceState.off,
        transcription: CaptureTranscriptionState.off,
        durability: evidence.durability,
        recordingId: evidence.recordingId,
        reason: 'paused',
        lastEvidenceAt: evidence.sourceLastOutputAt,
      );
    }

    if (!evidence.captureRequested) {
      return CaptureHealthResult(
        health: CaptureHealth.off,
        source: CaptureSourceState.off,
        transcription: CaptureTranscriptionState.off,
        durability: evidence.durability,
        recordingId: evidence.recordingId,
        reason: 'not_requested',
        lastEvidenceAt: evidence.sourceLastOutputAt,
      );
    }

    switch (evidence.source) {
      case CaptureSourceState.blocked:
      case CaptureSourceState.stalled:
        return CaptureHealthResult(
          health: CaptureHealth.degraded,
          source: evidence.source,
          transcription: evidence.transcription,
          durability: evidence.durability,
          recordingId: evidence.recordingId,
          reason: evidence.sourceReason ?? _defaultSourceReason(evidence.source),
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

      case CaptureSourceState.off:
        return CaptureHealthResult(
          health: CaptureHealth.degraded,
          source: evidence.source,
          transcription: evidence.transcription,
          durability: evidence.durability,
          recordingId: evidence.recordingId,
          reason: evidence.sourceReason ?? 'source_off',
          lastEvidenceAt: evidence.sourceLastOutputAt,
        );

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
    }
  }

  String? _downstreamReason(CaptureHealthEvidence evidence) {
    switch (evidence.transcription) {
      case CaptureTranscriptionState.degraded:
        return evidence.transcriptionReason ?? 'transcription_unavailable';
      case CaptureTranscriptionState.connecting:
        return evidence.transcriptionReason ?? 'transcription_connecting';
      case CaptureTranscriptionState.ready:
      case CaptureTranscriptionState.off:
        return evidence.durability == CaptureDurabilityState.unavailable
            ? (evidence.durabilityReason ?? 'local_durability_unavailable')
            : null;
    }
  }

  String _defaultSourceReason(CaptureSourceState source) => switch (source) {
        CaptureSourceState.blocked => 'source_blocked',
        CaptureSourceState.stalled => 'source_stalled',
        CaptureSourceState.starting => 'starting',
        CaptureSourceState.off => 'source_off',
        CaptureSourceState.live => '',
      };
}

CaptureHealthEvidence captureHealthEvidenceFromRecordingState({
  required bool captureRequested,
  required RecordingState recordingState,
  required CaptureTranscriptionState transcription,
  required CaptureDurabilityState durability,
  String? recordingId,
  String? sourceReason,
  DateTime? sourceLastOutputAt,
  String? transcriptionReason,
  String? durabilityReason,
  bool paused = false,
}) {
  final source = switch (recordingState) {
    RecordingState.initialising => CaptureSourceState.starting,
    RecordingState.record ||
    RecordingState.deviceRecord ||
    RecordingState.systemAudioRecord => CaptureSourceState.live,
    RecordingState.pause => CaptureSourceState.off,
    RecordingState.stop => CaptureSourceState.off,
    RecordingState.interrupted => CaptureSourceState.stalled,
    RecordingState.error => CaptureSourceState.blocked,
  };

  return CaptureHealthEvidence(
    captureRequested: captureRequested,
    source: source,
    transcription: transcription,
    durability: durability,
    recordingId: recordingId,
    sourceReason: sourceReason,
    sourceLastOutputAt: sourceLastOutputAt,
    transcriptionReason: transcriptionReason,
    durabilityReason: durabilityReason,
    paused: paused,
  );
}
