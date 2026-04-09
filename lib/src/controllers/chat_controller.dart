import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/app_models.dart';
import '../models/anime_plugin_models.dart';
import '../repositories/app_repositories.dart';
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
    super.dispose();
  }
}

const Set<String> _sentenceEndMarks = <String>{'。', '！', '？', '!', '?', '\n'};
