import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/app_models.dart';
import '../models/anime_plugin_models.dart';
import '../repositories/app_repositories.dart';
import '../services/baidu_speech_service.dart';
import '../services/llm_service.dart';
import '../services/vits_service.dart';

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

  final AudioRecorder _audioRecorder = AudioRecorder();
  final BaiduSpeechService _speechService = const BaiduSpeechService();
  bool _isStartingRecording = false;
  bool _isStoppingRecording = false;
  bool _stopRequestedDuringStart = false;
  String? _recordingFilePath;
  BytesBuilder? _recordingBytes;
  StreamSubscription<Uint8List>? _recordingStreamSubscription;

  Future<void> initialize() async {
    await reload();
  }

  Future<void> reload() async {
    isLoading = true;
    notifyListeners();

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

    isLoading = false;
    notifyListeners();
  }

  Future<void> sendMessage(String input) async {
    final String userInput = input.trim();
    if (userInput.isEmpty || isSending) {
      return;
    }

    final ModelProviderConfig providerConfig = appConfig.providerConfig(
      runtimeConfig.provider,
    );
    if (providerConfig.apiKey.isEmpty || runtimeConfig.modelSelect.isEmpty) {
      currentMood = 'default';
      currentDisplayText = '请先在设置页配置服务商、API Key 和模型。';
      showContinueButton = true;
      isSending = false;
      currentTachieFile = await characterRepository.resolveTachieFile(
        selectedCharacter,
        currentMood,
      );
      notifyListeners();
      return;
    }

    await vitsPlayback.stop();
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
      await for (final ChatStreamEvent event in service.chatStream(
        ChatRequest(
          apiKey: providerConfig.apiKey,
          model: runtimeConfig.modelSelect,
          systemPrompt: _buildSystemPrompt(moods),
          userMessage: await conversationRepository.buildUserMessageWithContext(
            userInput,
          ),
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
        currentMood = 'default';
        currentDisplayText = _rawReply.trim().isEmpty
            ? '模型返回格式无效，请检查角色提示词或切换模型。'
            : '模型返回格式无效：${_rawReply.trim()}';
      } else {
        currentMood = parsed.mood;
        currentDisplayText = parsed.chinese;
        await conversationRepository.appendUserLine(userInput);
        await conversationRepository.appendRoleLine(parsed.chinese);
        history = await conversationRepository.loadHistory(selectedCharacter);
        _queueFinalVitsSegments(parsed.japanese);
      }
    } on LlmException catch (error) {
      currentMood = 'default';
      currentDisplayText = '请求失败：${error.message}';
    } catch (error) {
      currentMood = 'default';
      currentDisplayText = '请求失败：$error';
    }

    currentTachieFile = await characterRepository.resolveTachieFile(
      selectedCharacter,
      currentMood,
    );
    isSending = false;
    showContinueButton = true;
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
        isRecognizing) {
      return;
    }

    _isStartingRecording = true;
    _stopRequestedDuringStart = false;
    showContinueButton = false;
    currentDisplayText = '';
    pendingInputText = '';
    notifyListeners();

    bool shouldStopAfterStart = false;

    try {
      if (!await _audioRecorder.hasPermission()) {
        currentDisplayText = '麦克风权限未授权，请在系统设置中开启。';
        showContinueButton = true;
        notifyListeners();
        return;
      }

      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = p.join(
        tempDir.path,
        'speech_input_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      _recordingFilePath = filePath;

      final Stream<Uint8List> stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _speechSampleRate,
          numChannels: _speechChannels,
          streamBufferSize: 2048,
        ),
      );
      final BytesBuilder recordingBytes = BytesBuilder(copy: false);
      _recordingBytes = recordingBytes;
      _recordingStreamSubscription = stream.listen(recordingBytes.add);

      isRecording = true;
      shouldStopAfterStart = _stopRequestedDuringStart;
      notifyListeners();
    } catch (error) {
      await _clearRecordingSession();
      currentDisplayText = '录音启动失败：$error';
      showContinueButton = true;
      notifyListeners();
    } finally {
      _isStartingRecording = false;
      if (!isRecording) {
        _stopRequestedDuringStart = false;
      }
    }

    if (shouldStopAfterStart && isRecording) {
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

    String? filePath;
    try {
      filePath = await _finishStreamRecording();
    } catch (_) {
      // 录音停止失败，仍然重置状态
    } finally {
      _isStoppingRecording = false;
      _stopRequestedDuringStart = false;
    }

    filePath = await _resolveRecordedFilePath(filePath);
    await _clearRecordingSession();

    if (filePath == null || filePath.isEmpty) {
      currentDisplayText = '没有录到声音，请长按说话。';
      showContinueButton = true;
      notifyListeners();
      return;
    }

    final SpeechInputConfig speechConfig = appConfig.speechInput;
    if (speechConfig.baiduApiKey.isEmpty ||
        speechConfig.baiduSecretKey.isEmpty) {
      currentDisplayText = '请先在设置页配置百度语音识别 API Key 和 Secret Key。';
      showContinueButton = true;
      notifyListeners();
      return;
    }

    isRecognizing = true;
    notifyListeners();

    try {
      final String recognized = await _speechService.recognize(
        apiKey: speechConfig.baiduApiKey,
        secretKey: speechConfig.baiduSecretKey,
        audioFile: File(filePath),
        format: _speechFormatForPath(filePath),
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
      currentDisplayText = '语音识别失败：${error.message}';
      showContinueButton = true;
    } catch (error) {
      currentDisplayText = '语音识别失败：$error';
      showContinueButton = true;
    }

    isRecognizing = false;
    notifyListeners();
  }

  Future<String?> _finishStreamRecording() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _audioRecorder.stop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await _recordingStreamSubscription?.cancel();
    _recordingStreamSubscription = null;

    final String? filePath = _recordingFilePath;
    final Uint8List pcmBytes = _recordingBytes?.takeBytes() ?? Uint8List(0);
    _recordingBytes = null;

    if (filePath == null || filePath.isEmpty || pcmBytes.isEmpty) {
      return null;
    }

    final File outputFile = File(filePath);
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsBytes(_buildWavBytes(pcmBytes), flush: true);
    return filePath;
  }

  Future<String?> _resolveRecordedFilePath(String? stoppedPath) async {
    final String? candidate = stoppedPath != null && stoppedPath.isNotEmpty
        ? stoppedPath
        : _recordingFilePath;
    if (candidate == null || candidate.isEmpty) {
      return null;
    }

    try {
      final File file = File(candidate);
      if (!await file.exists() || await file.length() == 0) {
        return null;
      }
      return candidate;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearRecordingSession() async {
    await _recordingStreamSubscription?.cancel();
    _recordingStreamSubscription = null;
    _recordingBytes = null;
    _recordingFilePath = null;
  }

  String _speechFormatForPath(String filePath) {
    return p.extension(filePath).toLowerCase() == '.wav' ? 'wav' : 'm4a';
  }

  Uint8List _buildWavBytes(Uint8List pcmBytes) {
    final Uint8List wavBytes = Uint8List(44 + pcmBytes.length);
    final ByteData header = ByteData.sublistView(wavBytes);

    void writeAscii(int offset, String value) {
      for (int i = 0; i < value.length; i += 1) {
        wavBytes[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + pcmBytes.length, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, _speechChannels, Endian.little);
    header.setUint32(24, _speechSampleRate, Endian.little);
    header.setUint32(
      28,
      _speechSampleRate * _speechChannels * _speechBytesPerSample,
      Endian.little,
    );
    header.setUint16(
      32,
      _speechChannels * _speechBytesPerSample,
      Endian.little,
    );
    header.setUint16(34, _speechBitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, pcmBytes.length, Endian.little);
    wavBytes.setRange(44, wavBytes.length, pcmBytes);
    return wavBytes;
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
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }
}

const Set<String> _sentenceEndMarks = <String>{'。', '！', '？', '!', '?', '\n'};
const int _speechSampleRate = 16000;
const int _speechChannels = 1;
const int _speechBitsPerSample = 16;
const int _speechBytesPerSample = _speechBitsPerSample ~/ 8;
