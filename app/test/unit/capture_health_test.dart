import 'package:flutter_test/flutter_test.dart';

import 'package:omi/services/capture/capture_health.dart';
import 'package:omi/utils/enums.dart';

void main() {
  const projection = CaptureHealthProjection();

  test('live source with ready transcription is capturing', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        source: CaptureSourceState.live,
        transcription: CaptureTranscriptionState.ready,
        durability: CaptureDurabilityState.available,
        recordingId: 'recording-1',
      ),
    );

    expect(result.health, CaptureHealth.capturing);
    expect(result.reason, isNull);
  });

  test('live source stays capturing when transcription is degraded', () {
    final result = projection.project(
      const CaptureHealthEvidence(
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

  test('deliberate off source is off without a failure', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        source: CaptureSourceState.off,
        transcription: CaptureTranscriptionState.off,
        durability: CaptureDurabilityState.unknown,
      ),
    );

    expect(result.health, CaptureHealth.off);
    expect(result.reason, 'off');
  });

  test('requested startup is degraded until source is live', () {
    final result = projection.project(
      const CaptureHealthEvidence(
        source: CaptureSourceState.starting,
        transcription: CaptureTranscriptionState.connecting,
        durability: CaptureDurabilityState.unknown,
        sourceReason: 'starting',
      ),
    );

    expect(result.health, CaptureHealth.degraded);
    expect(result.reason, 'starting');
  });

  test('existing recording identity and freshness are preserved', () {
    final timestamp = DateTime.utc(2026, 9, 19, 0, 0, 1);
    final result = projection.project(
      CaptureHealthEvidence(
        source: CaptureSourceState.live,
        transcription: CaptureTranscriptionState.connecting,
        durability: CaptureDurabilityState.pending,
        recordingId: 'same-recording-id',
        sourceLastOutputAt: timestamp,
      ),
    );

    expect(result.recordingId, 'same-recording-id');
    expect(result.lastEvidenceAt, timestamp);
  });

  test('lifecycle record state cannot claim live capture without audio evidence', () {
    final result = captureHealthEvidenceForAudioOutput(
      recordingState: RecordingState.record,
      hasAudioOutput: false,
      recordingId: 'recording-4',
    );

    expect(result.source, CaptureSourceState.starting);
    expect(result.recordingId, 'recording-4');
    expect(result.sourceReason, 'awaiting_audio_output');
  });

  test('observed audio output is sufficient to claim live capture', () {
    final timestamp = DateTime.utc(2026, 9, 19, 0, 1, 2);
    final result = captureHealthEvidenceForAudioOutput(
      recordingState: RecordingState.record,
      hasAudioOutput: true,
      lastAudioOutputAt: timestamp,
      recordingId: 'recording-5',
      transcription: CaptureTranscriptionState.ready,
      durability: CaptureDurabilityState.available,
    );

    expect(result.source, CaptureSourceState.live);
    expect(result.sourceReason, isNull);
    expect(result.sourceLastOutputAt, timestamp);
    expect(projection.project(result).health, CaptureHealth.capturing);
  });

  test('explicit stop remains off even without audio evidence', () {
    final result = captureHealthEvidenceForAudioOutput(
      recordingState: RecordingState.stop,
      hasAudioOutput: false,
      recordingId: 'recording-6',
    );

    expect(result.source, CaptureSourceState.off);
  });

  test('interrupted lifecycle remains stalled until recovery evidence arrives', () {
    final result = captureHealthEvidenceForAudioOutput(
      recordingState: RecordingState.interrupted,
      hasAudioOutput: false,
      recordingId: 'recording-7',
    );

    expect(result.source, CaptureSourceState.stalled);
  });

  test('all lifecycle states are conservative about live evidence', () {
    for (final state in RecordingState.values) {
      final result = captureHealthEvidenceForAudioOutput(
        recordingState: state,
        hasAudioOutput: false,
      );

      expect(result.source, isNot(CaptureSourceState.live), reason: 'state=$state');
    }
  });
}
