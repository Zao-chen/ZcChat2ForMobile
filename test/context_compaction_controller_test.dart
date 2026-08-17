import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_mobile/src/bootstrap/app_bootstrap.dart';
import 'package:zcchat2_for_mobile/src/controllers/chat_controller.dart';
import 'package:zcchat2_for_mobile/src/models/app_models.dart';
import 'package:zcchat2_for_mobile/src/repositories/app_repositories.dart';
import 'package:zcchat2_for_mobile/src/repositories/app_storage_paths.dart';
import 'package:zcchat2_for_mobile/src/services/llm_service.dart';
import 'package:zcchat2_for_mobile/src/services/vits_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller compacts old context but preserves full history', () async {
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'zcchat2_compaction_controller_test_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final AppStoragePaths paths = AppStoragePaths(tempDirectory);
    await AppBootstrap.ensureInitialized(storagePaths: paths);
    final CharacterRepository characterRepository = CharacterRepository(paths);
    final SettingsRepository settingsRepository = SettingsRepository(paths);
    final ConversationRepository conversationRepository =
        ConversationRepository(paths, characterRepository);
    final _CompactionAwareLlmService llmService = _CompactionAwareLlmService();
    final ConversationController controller = ConversationController(
      characterRepository: characterRepository,
      settingsRepository: settingsRepository,
      conversationRepository: conversationRepository,
      services: <LlmProviderType, LlmService>{
        LlmProviderType.deepSeek: llmService,
      },
      vitsPlayback: const _NoopVitsPlayback(),
    );
    addTearDown(controller.dispose);

    await settingsRepository.saveProviderApiKey(
      LlmProviderType.deepSeek,
      'fake-key',
    );
    await characterRepository.saveCharacterModel('test', 'fake-model');
    await characterRepository.saveCharacterContextTokenLimit(
      'test',
      tokenLimit: 1024,
      source: 'manual',
      model: 'fake-model',
      provider: 'DeepSeek',
    );
    await characterRepository.saveCharacterContextAutoCompactThreshold(
      'test',
      50,
    );

    final String oldUserLine = '很久以前${List<String>.filled(300, '早').join()}';
    final String oldRoleLine = '旧回复${List<String>.filled(300, '答').join()}';
    await conversationRepository.appendUserLine(oldUserLine);
    await conversationRepository.appendRoleLine(oldRoleLine);
    await conversationRepository.appendUserLine(
      '第二轮${List<String>.filled(160, '问').join()}',
    );
    await conversationRepository.appendRoleLine(
      '第二答${List<String>.filled(160, '应').join()}',
    );
    await conversationRepository.appendUserLine('最近的问题');
    await conversationRepository.appendRoleLine('最近的回答');

    await controller.initialize();
    await controller.sendMessage('继续聊');

    final ContextHistory saved = await conversationRepository.loadHistory(
      'test',
    );
    expect(llmService.requests, hasLength(2));
    expect(llmService.requests.first.systemPrompt, contains('上下文压缩组件'));
    expect(llmService.requests.last.userMessage, contains('较早对话摘要：用户喜欢公园'));
    expect(llmService.requests.last.userMessage, isNot(contains(oldUserLine)));
    expect(saved.summary, '用户喜欢公园');
    expect(saved.compactedHistoryCount, 2);
    expect(saved.history, hasLength(8));
    expect(saved.history.first, contains(oldUserLine));
    expect(controller.contextCompactionStatus, contains('完整历史仍然保留'));
  });
}

class _CompactionAwareLlmService implements LlmService {
  final List<ChatRequest> requests = <ChatRequest>[];

  @override
  LlmProviderType get provider => LlmProviderType.deepSeek;

  @override
  Future<List<String>> fetchModels(String apiKey) async => const <String>[
    'fake-model',
  ];

  @override
  Stream<ChatStreamEvent> chatStream(ChatRequest request) async* {
    requests.add(request);
    if (request.systemPrompt.contains('上下文压缩组件')) {
      yield const ChatStreamEvent(
        rawText: '用户喜欢公园',
        displayedChinese: '',
        isCompleted: true,
      );
      return;
    }
    yield const ChatStreamEvent(
      rawText: 'happy|继续聊吧|続きを話しましょう',
      displayedChinese: '继续聊吧',
      isCompleted: true,
    );
  }

  @override
  void dispose() {}
}

class _NoopVitsPlayback implements VitsPlayback {
  const _NoopVitsPlayback();

  @override
  Future<void> enqueueSegments({
    required String apiUrl,
    required String modelAndSpeaker,
    required Iterable<String> texts,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> waitUntilIdle() async {}

  @override
  void dispose() {}
}
