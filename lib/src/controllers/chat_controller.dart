import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:record/record.dart';

import '../models/app_models.dart';
import '../models/anime_plugin_models.dart';
import '../repositories/app_repositories.dart';
import '../services/app_logger.dart';
import '../services/baidu_speech_service.dart';
import '../services/llm_service.dart';
import '../services/openai_compatible_llm_service.dart';
import '../services/pcm_voice_segmenter.dart';
import '../services/speech_session_policy.dart';
import '../services/vits_service.dart';

enum SpeechInteractionState {
  disabled,
  waitingForWake,
  capturing,
  recognizing,
  waitingForReply,
  continuousReady,
  ending,
}

class ConversationController extends ChangeNotifier {
  ConversationController({
    required this.characterRepository,
    required this.settingsRepository,
    required this.conversationRepository,
    required this.services,
    required this.vitsPlayback,
  });

  final CharacterRepository characterRepository;
  final SettingsRepository settingsRepository;
  final ConversationRepository conversationRepository;
  final Map<LlmProviderType, LlmService> services;
  final VitsPlayback vitsPlayback;

  bool isLoading = true;
  bool isSending = false;
  bool showContinueButton = false;
  bool isRecording = false;
  bool isRecognizing = false;
  bool isSpeechSessionActive = false;
  SpeechInteractionState speechState = SpeechInteractionState.disabled;
  String pendingInputText = '';
  String selectedCharacter = 'test';
  CharacterAssetConfig characterAssetConfig = const CharacterAssetConfig();
  CharacterRuntimeConfig runtimeConfig = const CharacterRuntimeConfig();
  AppConfig appConfig = AppConfig.initial();
  ContextHistory history = const ContextHistory(history: <String>[]);
  AnimePluginRegistry animePluginRegistry = const AnimePluginRegistry.empty();
  String currentMood = 'default';
  String currentDisplayText = '';
  File? currentTachieFile;
  String _rawReply = '';
  int _streamSynthCursor = 0;

  AudioRecorder? _audioRecorder;
  final BaiduSpeechService _speechService = BaiduSpeechService();
  final SpeechSessionPolicy _speechSessionPolicy = SpeechSessionPolicy();
  final PcmVoiceSegmenter _voiceSegmenter = PcmVoiceSegmenter();
  bool _isStartingRecording = false;
  bool _isStoppingRecording = false;
  bool _stopRequestedDuringStart = false;
  bool _captureStreamActive = false;
  bool _automaticListening = false;
  BytesBuilder? _recordingBytes;
  StreamSubscription<Uint8List>? _recordingStreamSubscription;

  AudioRecorder get _recorder => _audioRecorder ??= AudioRecorder();

  Future<void> initialize() async {
    await reload();
  }

  Future<void> reload() async {
    isLoading = true;
    notifyListeners();

    await _stopCaptureStream();
    _speechSessionPolicy.reset();
    isSpeechSessionActive = false;
    await vitsPlayback.stop();
    selectedCharacter = await characterRepository.getSelectedCharacter();
    characterAssetConfig = await characterRepository.loadCharacterAssetConfig(
      selectedCharacter,
    );
    runtimeConfig = await characterRepository.loadCharacterRuntimeConfig(
      selectedCharacter,
    );
    appConfig = await settingsRepository.loadAppConfig();
    history = await conversationRepository.loadHistory(selectedCharacter);
    animePluginRegistry = await characterRepository.loadAnimePluginRegistry();
    currentMood = 'default';
    currentTachieFile = await characterRepository.resolveTachieFile(
      selectedCharacter,
      currentMood,
    );
    AppLogger.info(
      'conversation.config.reloaded',
      fields: <String, Object?>{
        'character': selectedCharacter,
        'provider': runtimeConfig.provider.name,
        'model': runtimeConfig.modelSelect,
        'credential_configured': appConfig
            .providerConfig(runtimeConfig.provider)
            .apiKey
            .isNotEmpty,
      },
    );

    isLoading = false;
    await _resumeAutomaticListening();
    notifyListeners();
  }

  Future<void> sendMessage(
    String input, {
    bool resumeSpeechListening = true,
  }) async {
    final String userInput = input.trim();
    if (userInput.isEmpty || isSending) {
      return;
    }

    final ModelProviderConfig providerConfig = appConfig.providerConfig(
      runtimeConfig.provider,
    );
    final bool configIncomplete =
        providerConfig.apiKey.isEmpty ||
        runtimeConfig.modelSelect.isEmpty ||
        (runtimeConfig.provider == LlmProviderType.custom &&
            providerConfig.baseUrl.isEmpty);
    if (configIncomplete) {
      currentMood = 'default';
      currentDisplayText = runtimeConfig.provider == LlmProviderType.custom
          ? '请先在设置页配置服务商、API Key、Base URL 和模型。'
          : '请先在设置页配置服务商、API Key 和模型。';
      showContinueButton = true;
      isSending = false;
      currentTachieFile = await characterRepository.resolveTachieFile(
        selectedCharacter,
        currentMood,
      );
      notifyListeners();
      return;
    }

    await _stopCaptureStream();
    await vitsPlayback.stop();
    if (runtimeConfig.provider == LlmProviderType.custom) {
      final LlmService? customService = services[LlmProviderType.custom];
      if (customService is CustomLlmService) {
        customService.updateBaseUrl(providerConfig.baseUrl);
      }
    }
    final LlmService service = services[runtimeConfig.provider]!;
    final List<String> moods = await characterRepository.getTachieMoodNames(
      selectedCharacter,
    );

    isSending = true;
    showContinueButton = false;
    currentMood = 'default';
    currentDisplayText = '...';
    _rawReply = '';
    _streamSynthCursor = 0;
    notifyListeners();

    try {
      final String contextMessage = await conversationRepository
          .buildUserMessageWithContext(userInput);
      AppLogger.info(
        'chat.request.started',
        fields: <String, Object?>{
          'provider': runtimeConfig.provider.name,
          'model': runtimeConfig.modelSelect,
          'input_characters': userInput.length,
          'context_characters': contextMessage.length,
        },
      );
      await for (final ChatStreamEvent event in service.chatStream(
        ChatRequest(
          apiKey: providerConfig.apiKey,
          model: runtimeConfig.modelSelect,
          systemPrompt: _buildSystemPrompt(moods),
          userMessage: contextMessage,
        ),
      )) {
        _rawReply = event.rawText;
        if (event.displayedChinese.isNotEmpty) {
          currentDisplayText = event.displayedChinese;
        }
        if (_canUseVits && appConfig.vits.sentenceSplit) {
          _queueStreamVitsSegments();
        }
        if (!event.isCompleted) {
          notifyListeners();
        }
      }

      final ParsedCharacterReply? parsed = ParsedCharacterReply.tryParse(
        _rawReply,
      );
      if (parsed == null) {
        AppLogger.warning(
          'chat.response.invalid',
          fields: <String, Object?>{'reply_characters': _rawReply.length},
        );
        currentMood = 'default';
        currentDisplayText = _rawReply.trim().isEmpty
            ? '模型返回格式无效，请检查角色提示词或切换模型。'
            : '模型返回格式无效：${_rawReply.trim()}';
      } else {
        AppLogger.info(
          'chat.request.completed',
          fields: <String, Object?>{
            'mood': parsed.mood,
            'reply_characters': parsed.chinese.length,
          },
        );
        currentMood = parsed.mood;
        currentDisplayText = parsed.chinese;
        await conversationRepository.appendUserLine(userInput);
        await conversationRepository.appendRoleLine(parsed.chinese);
        history = await conversationRepository.loadHistory(selectedCharacter);
        _queueFinalVitsSegments(parsed.japanese);
      }
    } on LlmException catch (error) {
      AppLogger.warning(
        'chat.request.failed',
        fields: <String, Object?>{'message': error.message},
      );
      currentMood = 'default';
      currentDisplayText = '请求失败：${error.message}';
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat.request.failed',
        error: error,
        stackTrace: stackTrace,
      );
      currentMood = 'default';
      currentDisplayText = '请求失败：$error';
    }

    currentTachieFile = await characterRepository.resolveTachieFile(
      selectedCharacter,
      currentMood,
    );
    await vitsPlayback.waitUntilIdle();
    isSending = false;
    showContinueButton = true;
    if (resumeSpeechListening) {
      await _resumeAutomaticListening();
    }
    notifyListeners();
  }

  void continueConversation() {
    currentDisplayText = '';
    _rawReply = '';
    showContinueButton = false;
    notifyListeners();
  }

  Future<void> startRecording() async {
    if (isRecording ||
        _isStartingRecording ||
        _isStoppingRecording ||
        isSending ||
        isRecognizing ||
        _voiceSegmenter.isCapturing) {
      return;
    }

    _stopRequestedDuringStart = false;
    showContinueButton = false;
    currentDisplayText = '';
    pendingInputText = '';
    notifyListeners();

    try {
      _recordingBytes = BytesBuilder(copy: false);
      final bool started = await _ensureCaptureStream();
      if (!started) {
        _recordingBytes = null;
        return;
      }

      _automaticListening = false;
      isRecording = true;
      speechState = SpeechInteractionState.capturing;
      notifyListeners();
    } catch (error, stackTrace) {
      AppLogger.error(
        'speech.recording.start_failed',
        error: error,
        stackTrace: stackTrace,
      );
      _recordingBytes = null;
      currentDisplayText = '录音启动失败：$error';
      showContinueButton = true;
      notifyListeners();
    }

    if (_stopRequestedDuringStart && isRecording) {
      _stopRequestedDuringStart = false;
      await stopRecording();
    }
  }

  Future<void> stopRecording() async {
    if (_isStartingRecording && !isRecording) {
      _stopRequestedDuringStart = true;
      return;
    }
    if (!isRecording || _isStoppingRecording) {
      return;
    }

    _isStoppingRecording = true;
    _stopRequestedDuringStart = false;
    isRecording = false;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 80));
    final Uint8List pcmBytes = _recordingBytes?.takeBytes() ?? Uint8List(0);
    _recordingBytes = null;
    if (!appConfig.speechInput.wakeEnabled) {
      await _stopCaptureStream();
    }
    _isStoppingRecording = false;
    _stopRequestedDuringStart = false;

    if (pcmBytes.isEmpty) {
      currentDisplayText = '没有录到声音，请长按说话。';
      showContinueButton = true;
      await _resumeAutomaticListening();
      notifyListeners();
      return;
    }

    final SpeechInputConfig speechConfig = appConfig.speechInput;
    if (speechConfig.baiduApiKey.isEmpty ||
        speechConfig.baiduSecretKey.isEmpty) {
      currentDisplayText = '请先在设置页配置百度语音识别 API Key 和 Secret Key。';
      showContinueButton = true;
      await _resumeAutomaticListening();
      notifyListeners();
      return;
    }

    isRecognizing = true;
    notifyListeners();

    try {
      final String recognized = await _speechService.recognizeBytes(
        apiKey: speechConfig.baiduApiKey,
        secretKey: speechConfig.baiduSecretKey,
        audioBytes: pcmBytes,
      );
      AppLogger.info(
        'speech.recognition.completed',
        fields: <String, Object?>{
          'audio_bytes': pcmBytes.length,
          'result_characters': recognized.length,
          'automatic': false,
        },
      );

      if (recognized.isEmpty) {
        currentDisplayText = '语音识别结果为空。';
        showContinueButton = true;
      } else if (speechConfig.autoSend) {
        await sendMessage(recognized);
      } else {
        pendingInputText = recognized;
      }
    } on SpeechRecognitionException catch (error) {
      AppLogger.warning(
        'speech.recognition.failed',
        fields: <String, Object?>{'message': error.message, 'automatic': false},
      );
      currentDisplayText = '语音识别失败：${error.message}';
      showContinueButton = true;
    } catch (error, stackTrace) {
      AppLogger.error(
        'speech.recognition.failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'automatic': false},
      );
      currentDisplayText = '语音识别失败：$error';
      showContinueButton = true;
    }

    isRecognizing = false;
    await _resumeAutomaticListening();
    notifyListeners();
  }

  Future<bool> _ensureCaptureStream() async {
    if (_captureStreamActive) {
      return true;
    }
    if (_isStartingRecording) {
      return false;
    }

    _isStartingRecording = true;
    try {
      if (!await _recorder.hasPermission()) {
        currentDisplayText = '麦克风权限未授权，请在系统设置中开启。';
        showContinueButton = true;
        speechState = SpeechInteractionState.disabled;
        notifyListeners();
        return false;
      }

      final Stream<Uint8List> stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _speechSampleRate,
          numChannels: _speechChannels,
          streamBufferSize: 2048,
        ),
      );
      _recordingStreamSubscription = stream.listen(
        _handleAudioChunk,
        onError: _handleAudioStreamError,
      );
      _captureStreamActive = true;
      return true;
    } catch (error, stackTrace) {
      AppLogger.error(
        'speech.capture.start_failed',
        error: error,
        stackTrace: stackTrace,
      );
      currentDisplayText = '录音启动失败：$error';
      showContinueButton = true;
      speechState = SpeechInteractionState.disabled;
      notifyListeners();
      return false;
    } finally {
      _isStartingRecording = false;
    }
  }

  Future<void> _stopCaptureStream() async {
    final bool shouldStopRecorder =
        _captureStreamActive || _recordingStreamSubscription != null;
    _automaticListening = false;
    _captureStreamActive = false;
    await _recordingStreamSubscription?.cancel();
    _recordingStreamSubscription = null;
    if (shouldStopRecorder) {
      try {
        await _recorder.stop();
      } catch (_) {
        // 设备已停止时无需再次处理。
      }
    }
    _voiceSegmenter.reset();
  }

  Future<void> _resumeAutomaticListening() async {
    final SpeechInputConfig config = appConfig.speechInput;
    if (!config.enable || !config.wakeEnabled) {
      _automaticListening = false;
      speechState = SpeechInteractionState.disabled;
      return;
    }
    if (isSending || isRecognizing || isRecording || isLoading) {
      return;
    }

    final bool started = await _ensureCaptureStream();
    if (!started) {
      return;
    }
    _automaticListening = true;
    _setReadySpeechState();
  }

  void _handleAudioChunk(Uint8List pcm) {
    if (isRecording || _isStoppingRecording) {
      final BytesBuilder? bytes = _recordingBytes;
      if (bytes == null) {
        return;
      }
      final int remaining = _maximumSpeechBytes - bytes.length;
      if (remaining > 0) {
        bytes.add(pcm.length <= remaining ? pcm : pcm.sublist(0, remaining));
      }
      if (bytes.length >= _maximumSpeechBytes) {
        unawaited(stopRecording());
      }
      return;
    }

    if (!_automaticListening || isSending || isRecognizing) {
      return;
    }
    final PcmVoiceSegmentResult result = _voiceSegmenter.process(pcm);
    if (result.event == PcmVoiceSegmentEvent.started) {
      speechState = SpeechInteractionState.capturing;
      notifyListeners();
    } else if (result.event == PcmVoiceSegmentEvent.discarded) {
      _setReadySpeechState();
      notifyListeners();
    } else if (result.event == PcmVoiceSegmentEvent.completed &&
        result.pcm != null) {
      unawaited(_recognizeAutomaticSegment(result.pcm!));
    }
  }

  void _handleAudioStreamError(Object error, StackTrace stackTrace) {
    AppLogger.error(
      'speech.capture.stream_failed',
      error: error,
      stackTrace: stackTrace,
    );
    _captureStreamActive = false;
    _automaticListening = false;
    speechState = SpeechInteractionState.disabled;
    currentDisplayText = '麦克风采集失败：$error';
    showContinueButton = true;
    notifyListeners();
  }

  Future<void> _recognizeAutomaticSegment(Uint8List pcm) async {
    if (isRecognizing || isSending) {
      return;
    }
    _automaticListening = false;
    isRecognizing = true;
    speechState = SpeechInteractionState.recognizing;
    notifyListeners();

    final SpeechInputConfig config = appConfig.speechInput;
    try {
      if (config.baiduApiKey.isEmpty || config.baiduSecretKey.isEmpty) {
        throw const SpeechRecognitionException(
          '请先配置百度语音识别 API Key 和 Secret Key',
        );
      }
      final String recognized = await _speechService.recognizeBytes(
        apiKey: config.baiduApiKey,
        secretKey: config.baiduSecretKey,
        audioBytes: pcm,
      );
      AppLogger.info(
        'speech.recognition.completed',
        fields: <String, Object?>{
          'audio_bytes': pcm.length,
          'result_characters': recognized.length,
          'automatic': true,
        },
      );
      if (recognized.isEmpty) {
        return;
      }

      final SpeechRecognitionDecision decision = _speechSessionPolicy
          .consumeAutomaticRecognition(
            text: recognized,
            wakeWords: _wakeWords,
            endWords: _endWords,
          );
      if (decision == SpeechRecognitionDecision.ignore) {
        return;
      }

      isSpeechSessionActive = _speechSessionPolicy.isSessionActive;
      isRecognizing = false;
      speechState = decision == SpeechRecognitionDecision.submitAndEnd
          ? SpeechInteractionState.ending
          : SpeechInteractionState.waitingForReply;
      notifyListeners();

      await sendMessage(recognized, resumeSpeechListening: false);
      if (_speechSessionPolicy.completeOutput()) {
        isSpeechSessionActive = false;
      }
    } on SpeechRecognitionException catch (error) {
      AppLogger.warning(
        'speech.recognition.failed',
        fields: <String, Object?>{'message': error.message, 'automatic': true},
      );
      currentDisplayText = '语音识别失败：${error.message}';
      showContinueButton = true;
    } catch (error, stackTrace) {
      AppLogger.error(
        'speech.recognition.failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'automatic': true},
      );
      currentDisplayText = '语音识别失败：$error';
      showContinueButton = true;
    } finally {
      isRecognizing = false;
      await _resumeAutomaticListening();
      notifyListeners();
    }
  }

  List<String> get _wakeWords {
    final List<String> configured = characterAssetConfig.speechInput.wakeWords;
    return configured.isEmpty ? <String>[selectedCharacter] : configured;
  }

  List<String> get _endWords {
    final List<String> configured = characterAssetConfig.speechInput.endWords;
    return configured.isEmpty ? const <String>['结束对话'] : configured;
  }

  void _setReadySpeechState() {
    speechState = _speechSessionPolicy.isSessionActive
        ? SpeechInteractionState.continuousReady
        : SpeechInteractionState.waitingForWake;
  }

  Future<void> editHistoryEntry(int index, String newText) async {
    await conversationRepository.updateLine(index, newText);
    history = await conversationRepository.loadHistory(selectedCharacter);
    notifyListeners();
  }

  Future<void> deleteHistoryEntry(int index) async {
    await conversationRepository.deleteLine(index);
    history = await conversationRepository.loadHistory(selectedCharacter);
    notifyListeners();
  }

  /// 回退到指定位置：保留 index 之前的所有记录，删除 index 及之后的所有记录。
  Future<void> rollbackHistoryTo(int index) async {
    await conversationRepository.rollbackTo(index);
    history = await conversationRepository.loadHistory(selectedCharacter);
    notifyListeners();
  }

  /// 回溯到指定历史记录索引（匹配 Qt 行为）：截断历史并显示选中条目的内容。
  Future<void> rewindToHistoryIndex(int historyIndex) async {
    if (historyIndex < 0 || historyIndex >= history.entries.length) {
      return;
    }

    await vitsPlayback.stop();
    await conversationRepository.rollbackTo(historyIndex + 1);
    history = await conversationRepository.loadHistory(selectedCharacter);

    final HistoryEntry selected = history.entries[historyIndex];
    currentMood = 'default';
    currentDisplayText = selected.text;
    showContinueButton = selected.speaker != HistorySpeaker.user;
    currentTachieFile = await characterRepository.resolveTachieFile(
      selectedCharacter,
      currentMood,
    );
    notifyListeners();
  }

  /// 撤销最后一轮对话（移除最后一条用户消息和角色回复）。
  /// 如果最后一条是角色回复，则同时删除它和它前面的用户消息。
  Future<void> undoLastTurn() async {
    final List<HistoryEntry> entries = history.entries;
    if (entries.isEmpty) {
      return;
    }

    int removeCount = 0;
    // 从末尾往前找：如果最后一条是角色，则删除角色+用户（一轮）；否则只删最后一条
    for (int i = entries.length - 1; i >= 0; i -= 1) {
      if (entries[i].speaker == HistorySpeaker.role) {
        removeCount = entries.length - i + (i > 0 ? 1 : 1);
        break;
      }
      if (entries[i].speaker == HistorySpeaker.user) {
        removeCount = 1;
        break;
      }
      removeCount = 1;
    }

    final int keepIndex = (entries.length - removeCount).clamp(
      0,
      entries.length,
    );
    await conversationRepository.rollbackTo(keepIndex);
    history = await conversationRepository.loadHistory(selectedCharacter);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await conversationRepository.clearHistory();
    history = await conversationRepository.loadHistory(selectedCharacter);
    notifyListeners();
  }

  Future<void> saveTachieTransform({
    required double scale,
    required Offset offset,
  }) async {
    final int size = (scale * 100).round().clamp(50, 220).toInt();
    runtimeConfig = runtimeConfig.copyWith(
      tachieSize: size,
      tachieOffsetX: offset.dx,
      tachieOffsetY: offset.dy,
    );
    notifyListeners();
    await characterRepository.saveTachieTransform(
      selectedCharacter,
      size: size,
      offsetX: offset.dx,
      offsetY: offset.dy,
    );
  }

  Future<void> resetTachieTransform() async {
    runtimeConfig = runtimeConfig.copyWith(
      tachieSize: 100,
      tachieOffsetX: 0,
      tachieOffsetY: 0,
    );
    notifyListeners();
    await characterRepository.resetTachieTransform(selectedCharacter);
  }

  bool get _canUseVits {
    return runtimeConfig.vitsEnable &&
        runtimeConfig.vitsMasSelect.trim().isNotEmpty &&
        appConfig.vits.apiUrl.trim().isNotEmpty;
  }

  void _queueStreamVitsSegments() {
    final int firstSep = _rawReply.indexOf('|');
    if (firstSep < 0) {
      return;
    }

    final int secondSep = _rawReply.indexOf('|', firstSep + 1);
    if (secondSep < 0) {
      return;
    }

    final String japanesePartial = _rawReply.substring(secondSep + 1);
    final List<String> readySegments = <String>[];
    int sentenceEnd = _findNextSentenceEnd(japanesePartial, _streamSynthCursor);
    while (sentenceEnd >= 0) {
      final String sentence = japanesePartial
          .substring(_streamSynthCursor, sentenceEnd + 1)
          .trim();
      _streamSynthCursor = sentenceEnd + 1;
      if (sentence.isNotEmpty) {
        readySegments.add(sentence);
      }
      sentenceEnd = _findNextSentenceEnd(japanesePartial, _streamSynthCursor);
    }

    _queueVitsSegments(readySegments);
  }

  void _queueFinalVitsSegments(String japaneseReply) {
    if (!_canUseVits) {
      return;
    }

    if (appConfig.vits.sentenceSplit) {
      final int startIndex = _streamSynthCursor < 0
          ? 0
          : (_streamSynthCursor > japaneseReply.length
                ? japaneseReply.length
                : _streamSynthCursor);
      final String remaining = japaneseReply.substring(startIndex).trim();
      _queueVitsSegments(<String>[remaining]);
      return;
    }

    _queueVitsSegments(<String>[japaneseReply]);
  }

  void _queueVitsSegments(Iterable<String> segments) {
    if (!_canUseVits) {
      return;
    }

    final List<String> readySegments = segments
        .map((String segment) => segment.trim())
        .where((String segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (readySegments.isEmpty) {
      return;
    }

    unawaited(
      vitsPlayback.enqueueSegments(
        apiUrl: appConfig.vits.apiUrl,
        modelAndSpeaker: runtimeConfig.vitsMasSelect,
        texts: readySegments,
      ),
    );
  }

  int _findNextSentenceEnd(String text, int startIndex) {
    for (int index = startIndex; index < text.length; index += 1) {
      final String char = text[index];
      if (_sentenceEndMarks.contains(char)) {
        return index;
      }
    }
    return -1;
  }

  String _buildSystemPrompt(List<String> moods) {
    final StringBuffer buffer = StringBuffer();
    if (characterAssetConfig.prompt.trim().isNotEmpty) {
      buffer
        ..writeln('角色设定：${characterAssetConfig.prompt.trim()}')
        ..writeln('请始终保持该设定进行回复。')
        ..writeln();
    }

    final String moodList = (moods.isEmpty ? const <String>['default'] : moods)
        .join(', ');
    buffer
      ..writeln('你是一个 Galgame 风格的 AI 角色。')
      ..writeln('输出内容必须严格按照以下格式：')
      ..writeln('心情|中文|日语')
      ..writeln()
      ..writeln('要求：')
      ..writeln('1. 心情必须从以下列表中选择：$moodList')
      ..writeln('2. 中文是角色此刻想表达的内容')
      ..writeln('3. 日语是中文内容的对应翻译')
      ..writeln('4. 不要输出多余解释，严格使用 | 分隔')
      ..writeln('5. 中文回复自然、简洁，适合立绘对话框展示');

    return buffer.toString();
  }

  @override
  void dispose() {
    unawaited(vitsPlayback.stop());
    unawaited(_recordingStreamSubscription?.cancel() ?? Future<void>.value());
    final AudioRecorder? recorder = _audioRecorder;
    if (recorder != null) {
      unawaited(recorder.dispose());
    }
    super.dispose();
  }
}

const Set<String> _sentenceEndMarks = <String>{'。', '！', '？', '!', '?', '\n'};
const int _speechSampleRate = 16000;
const int _speechChannels = 1;
const int _maximumSpeechBytes = _speechSampleRate * 2 * 20;
