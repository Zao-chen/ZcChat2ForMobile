import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_mobile/src/models/app_models.dart';
import 'package:zcchat2_for_mobile/src/services/pcm_voice_segmenter.dart';
import 'package:zcchat2_for_mobile/src/services/speech_session_policy.dart';

void main() {
  test('speech config round-trips wake settings and character keywords', () {
    const SpeechInputConfig speech = SpeechInputConfig(
      enable: true,
      wakeEnabled: true,
      autoSend: true,
      baiduApiKey: 'api',
      baiduSecretKey: 'secret',
    );
    final SpeechInputConfig decodedSpeech = SpeechInputConfig.fromJson(
      speech.toJson(),
    );
    expect(decodedSpeech.enable, isTrue);
    expect(decodedSpeech.wakeEnabled, isTrue);
    expect(decodedSpeech.autoSend, isTrue);

    const CharacterAssetConfig character = CharacterAssetConfig(
      prompt: 'prompt',
      speechInput: CharacterSpeechConfig(
        wakeWords: <String>['小助手'],
        endWords: <String>['结束对话'],
      ),
    );
    final CharacterAssetConfig decodedCharacter = CharacterAssetConfig.fromJson(
      character.toJson(),
    );
    expect(decodedCharacter.speechInput.wakeWords, <String>['小助手']);
    expect(decodedCharacter.speechInput.endWords, <String>['结束对话']);
  });

  test('app config copy helpers preserve speech settings', () {
    final AppConfig initial = AppConfig.initial().copyWithSpeechInput(
      const SpeechInputConfig(enable: true, wakeEnabled: true),
    );
    final AppConfig providerChanged = initial.copyWithProvider(
      LlmProviderType.deepSeek,
      const ModelProviderConfig(apiKey: 'key'),
    );
    final AppConfig vitsChanged = providerChanged.copyWithVits(
      const VitsConfig(apiUrl: 'http://localhost'),
    );

    expect(vitsChanged.speechInput.enable, isTrue);
    expect(vitsChanged.speechInput.wakeEnabled, isTrue);
  });

  test('speech session follows wake, continuous and end flow', () {
    final SpeechSessionPolicy policy = SpeechSessionPolicy();

    expect(
      policy.consumeAutomaticRecognition(
        text: '今天天气怎么样',
        wakeWords: const <String>['小助手'],
        endWords: const <String>['结束对话'],
      ),
      SpeechRecognitionDecision.ignore,
    );
    expect(policy.isSessionActive, isFalse);

    expect(
      policy.consumeAutomaticRecognition(
        text: '小 助手，今天天气怎么样？',
        wakeWords: const <String>['小助手'],
        endWords: const <String>['结束对话'],
      ),
      SpeechRecognitionDecision.submit,
    );
    expect(policy.isSessionActive, isTrue);

    expect(
      policy.consumeAutomaticRecognition(
        text: '再讲一点',
        wakeWords: const <String>['小助手'],
        endWords: const <String>['结束对话'],
      ),
      SpeechRecognitionDecision.submit,
    );
    expect(
      policy.consumeAutomaticRecognition(
        text: '好的，结束 对话。',
        wakeWords: const <String>['小助手'],
        endWords: const <String>['结束对话'],
      ),
      SpeechRecognitionDecision.submitAndEnd,
    );
    expect(policy.completeOutput(), isTrue);
    expect(policy.isSessionActive, isFalse);
  });

  test('pcm segmenter keeps pre-roll and completes after trailing silence', () {
    final PcmVoiceSegmenter segmenter = PcmVoiceSegmenter(
      speechRmsThreshold: 500,
      preRollBytes: 8,
      minimumVoicedBytes: 8,
      trailingSilenceBytes: 8,
      maximumSegmentBytes: 200,
    );
    final Uint8List silence = _pcm(<int>[0, 0]);
    final Uint8List speech = _pcm(<int>[4000, -4000]);

    expect(segmenter.process(silence).event, PcmVoiceSegmentEvent.none);
    expect(segmenter.process(speech).event, PcmVoiceSegmentEvent.started);
    expect(segmenter.process(speech).event, PcmVoiceSegmentEvent.none);
    expect(segmenter.process(silence).event, PcmVoiceSegmentEvent.none);
    final PcmVoiceSegmentResult completed = segmenter.process(silence);

    expect(completed.event, PcmVoiceSegmentEvent.completed);
    expect(completed.pcm, isNotNull);
    expect(completed.pcm!.length, greaterThanOrEqualTo(20));
    expect(segmenter.isCapturing, isFalse);
  });

  test('pcm segmenter discards speech shorter than minimum', () {
    final PcmVoiceSegmenter segmenter = PcmVoiceSegmenter(
      speechRmsThreshold: 500,
      preRollBytes: 4,
      minimumVoicedBytes: 12,
      trailingSilenceBytes: 4,
      maximumSegmentBytes: 200,
    );

    expect(
      segmenter.process(_pcm(<int>[4000, -4000])).event,
      PcmVoiceSegmentEvent.started,
    );
    expect(
      segmenter.process(_pcm(<int>[0, 0])).event,
      PcmVoiceSegmentEvent.discarded,
    );
  });
}

Uint8List _pcm(List<int> samples) {
  final Uint8List bytes = Uint8List(samples.length * 2);
  final ByteData data = ByteData.sublistView(bytes);
  for (int index = 0; index < samples.length; index += 1) {
    data.setInt16(index * 2, samples[index], Endian.little);
  }
  return bytes;
}
