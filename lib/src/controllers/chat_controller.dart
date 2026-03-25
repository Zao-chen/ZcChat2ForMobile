import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/llm_service.dart';

class ConversationController extends ChangeNotifier {
  ConversationController({
    required this.characterRepository,
    required this.settingsRepository,
    required this.conversationRepository,
    required this.services,
  });

  final CharacterRepository characterRepository;
  final SettingsRepository settingsRepository;
  final ConversationRepository conversationRepository;
  final Map<LlmProviderType, LlmService> services;

  bool isLoading = true;
  bool isSending = false;
  bool showContinueButton = false;
  String selectedCharacter = 'test';
  CharacterAssetConfig characterAssetConfig = const CharacterAssetConfig();
  CharacterRuntimeConfig runtimeConfig = const CharacterRuntimeConfig();
  AppConfig appConfig = AppConfig.initial();
  ContextHistory history = const ContextHistory(history: <String>[]);
  String currentMood = 'default';
  String currentDisplayText = '';
  File? currentTachieFile;
  String _rawReply = '';

  Future<void> initialize() async {
    await reload();
  }

  Future<void> reload() async {
    isLoading = true;
    notifyListeners();

    selectedCharacter = await characterRepository.getSelectedCharacter();
    characterAssetConfig =
        await characterRepository.loadCharacterAssetConfig(selectedCharacter);
    runtimeConfig =
        await characterRepository.loadCharacterRuntimeConfig(selectedCharacter);
    appConfig = await settingsRepository.loadAppConfig();
    history = await conversationRepository.loadHistory(selectedCharacter);
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

    final ModelProviderConfig providerConfig =
        appConfig.providerConfig(runtimeConfig.provider);
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

    final LlmService service = services[runtimeConfig.provider]!;
    final List<String> moods =
        await characterRepository.getTachieMoodNames(selectedCharacter);

    isSending = true;
    showContinueButton = false;
    currentMood = 'default';
    currentDisplayText = '...';
    _rawReply = '';
    notifyListeners();

    try {
      await for (final ChatStreamEvent event in service.chatStream(
        ChatRequest(
          apiKey: providerConfig.apiKey,
          model: runtimeConfig.modelSelect,
          systemPrompt: _buildSystemPrompt(moods),
          userMessage:
              await conversationRepository.buildUserMessageWithContext(userInput),
        ),
      )) {
        _rawReply = event.rawText;
        if (event.displayedChinese.isNotEmpty) {
          currentDisplayText = event.displayedChinese;
        }
        if (!event.isCompleted) {
          notifyListeners();
        }
      }

      final ParsedCharacterReply? parsed =
          ParsedCharacterReply.tryParse(_rawReply);
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
    final int size = (scale * 100).round().clamp(50, 220);
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

  String _buildSystemPrompt(List<String> moods) {
    final StringBuffer buffer = StringBuffer();
    if (characterAssetConfig.prompt.trim().isNotEmpty) {
      buffer
        ..writeln('角色设定：${characterAssetConfig.prompt.trim()}')
        ..writeln('请始终保持该设定进行回复。')
        ..writeln();
    }

    final String moodList =
        (moods.isEmpty ? const <String>['default'] : moods).join(', ');
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
}
