import 'package:flutter_test/flutter_test.dart';

import 'package:omi/services/capture/capture_health.dart';

void main() {
  const projection = CaptureHealthProjection();

  test('live source with ready transcription is capturing', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        captureRequested: true,
        source: CaptureSourceState.live,
        transcription: CaptureTranscriptionState.ready,
        durability: CaptureDurabilityState.available,
        recordingId: 'recording-1',
      ),
    );

    expect(result.health, CaptureHealth.capturing);
    expect(result.source, CaptureSourceState.live);
    expect(result.transcription, CaptureTranscriptionState.ready);
    expect(result.durability, CaptureDurabilityState.available);
    expect(result.recordingId, 'recording-1');
    expect(result.reason, isNull);
  });

  test('live source stays capturing when transcription is degraded', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        captureRequested: true,
        source: CaptureSourceState.live,
        transcription: CaptureTranscriptionState.degraded,
        durability: CaptureDurabilityState.available,
        recordingId: 'recording-2',
        transcriptionReason: 'transcription_unavailable',
      ),
    );

    expect(result.health, CaptureHealth.capturing);
    expect(result.transcription, CaptureTranscriptionState.degraded);
    expect(result.reason, 'transcription_unavailable');
  });

  test('stalled source is degraded with its reason', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        captureRequested: true,
        source: CaptureSourceState.stalled,
        transcription: CaptureTranscriptionState.ready,
        durability: CaptureDurabilityState.available,
        sourceReason: 'no_audio_evidence',
      ),
    );

    expect(result.health, CaptureHealth.degraded);
    expect(result.source, CaptureSourceState.stalled);
    expect(result.reason, 'no_audio_evidence');
  });

  test('deliberate pause is off and never treated as failure', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        captureRequested: true,
        source: CaptureSourceState.live,
        transcription: CaptureTranscriptionState.ready,
        durability: CaptureDurabilityState.available,
        recordingId: 'recording-3',
        paused: true,
      ),
    );

    expect(result.health, CaptureHealth.off);
    expect(result.reason, 'paused');
    expect(result.source, CaptureSourceState.off);
    expect(result.transcription, CaptureTranscriptionState.off);
  });

  test('requested capture with no producing source is not healthy', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        captureRequested: true,
        source: CaptureSourceState.starting,
        transcription: CaptureTranscriptionState.connecting,
        durability: CaptureDurabilityState.unknown,
        sourceReason: 'starting',
      ),
    );

    expect(result.health, CaptureHealth.degraded);
    expect(result.reason, 'starting');
  });

  test('not requested is off without inventing a failure', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        captureRequested: false,
        source: CaptureSourceState.off,
        transcription: CaptureTranscriptionState.off,
        durability: CaptureDurabilityState.unknown,
      ),
    );

    expect(result.health, CaptureHealth.off);
    expect(result.reason, 'not_requested');
  });

  test('existing recording identity is preserved by the projection', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        captureRequested: true,
        source: CaptureSourceState.live,
        transcription: CaptureTranscriptionState.connecting,
        durability: CaptureDurabilityState.pending,
        recordingId: 'same-recording-id',
      ),
    );

    expect(result.recordingId, 'same-recording-id');
  });

  test('recording state adapter maps current production states', () {
    final evidence = captureHealthEvidenceFromRecordingState(
      captureRequested: true,
      recordingState: RecordingState.record,
      transcription: CaptureTranscriptionState.ready,
      durability: CaptureDurabilityState.available,
      recordingId: 'recording-4',
    );

    expect(evidence.source, CaptureSourceState.live);
    expect(evidence.captureRequested, isTrue);
    expect(evidence.recordingId, 'recording-4');
  });
}
