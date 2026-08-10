import 'dart:math' as math;
import 'dart:typed_data';

enum PcmVoiceSegmentEvent { none, started, completed, discarded }

class PcmVoiceSegmentResult {
  const PcmVoiceSegmentResult(this.event, [this.pcm]);

  final PcmVoiceSegmentEvent event;
  final Uint8List? pcm;
}

/// 面向 16 kHz、单声道、16-bit little-endian PCM 的轻量语音切段器。
///
/// 移动端使用能量门限完成本地切段，只有完整语音片段会发送给 ASR。
class PcmVoiceSegmenter {
  PcmVoiceSegmenter({
    this.speechRmsThreshold = 900,
    this.preRollBytes = 9600,
    this.minimumVoicedBytes = 10240,
    this.trailingSilenceBytes = 22400,
    this.maximumSegmentBytes = 640000,
  });

  final double speechRmsThreshold;
  final int preRollBytes;
  final int minimumVoicedBytes;
  final int trailingSilenceBytes;
  final int maximumSegmentBytes;

  final List<int> _preRoll = <int>[];
  final BytesBuilder _segment = BytesBuilder(copy: false);
  bool _capturing = false;
  int _voicedBytes = 0;
  int _silenceBytes = 0;

  bool get isCapturing => _capturing;

  PcmVoiceSegmentResult process(Uint8List pcm) {
    if (pcm.length < 2) {
      return const PcmVoiceSegmentResult(PcmVoiceSegmentEvent.none);
    }

    final bool containsSpeech = _rms(pcm) >= speechRmsThreshold;
    if (!_capturing) {
      _appendPreRoll(pcm);
      if (!containsSpeech) {
        return const PcmVoiceSegmentResult(PcmVoiceSegmentEvent.none);
      }

      _capturing = true;
      _segment.add(Uint8List.fromList(_preRoll));
      _preRoll.clear();
      _voicedBytes = pcm.length;
      _silenceBytes = 0;
      return const PcmVoiceSegmentResult(PcmVoiceSegmentEvent.started);
    }

    _segment.add(pcm);
    if (containsSpeech) {
      _voicedBytes += pcm.length;
      _silenceBytes = 0;
    } else {
      _silenceBytes += pcm.length;
    }

    if (_segment.length >= maximumSegmentBytes) {
      return _complete();
    }
    if (_silenceBytes < trailingSilenceBytes) {
      return const PcmVoiceSegmentResult(PcmVoiceSegmentEvent.none);
    }
    if (_voicedBytes < minimumVoicedBytes) {
      reset();
      return const PcmVoiceSegmentResult(PcmVoiceSegmentEvent.discarded);
    }
    return _complete();
  }

  void reset() {
    _preRoll.clear();
    _segment.takeBytes();
    _capturing = false;
    _voicedBytes = 0;
    _silenceBytes = 0;
  }

  PcmVoiceSegmentResult _complete() {
    final Uint8List bytes = _segment.takeBytes();
    _capturing = false;
    _voicedBytes = 0;
    _silenceBytes = 0;
    _preRoll.clear();
    return PcmVoiceSegmentResult(PcmVoiceSegmentEvent.completed, bytes);
  }

  void _appendPreRoll(Uint8List pcm) {
    _preRoll.addAll(pcm);
    final int overflow = _preRoll.length - preRollBytes;
    if (overflow > 0) {
      _preRoll.removeRange(0, overflow);
    }
  }

  double _rms(Uint8List pcm) {
    final ByteData data = ByteData.sublistView(pcm);
    final int sampleCount = pcm.length ~/ 2;
    if (sampleCount == 0) {
      return 0;
    }

    double sumOfSquares = 0;
    for (int index = 0; index < sampleCount; index += 1) {
      final int sample = data.getInt16(index * 2, Endian.little);
      sumOfSquares += sample * sample;
    }
    return math.sqrt(sumOfSquares / sampleCount);
  }
}
