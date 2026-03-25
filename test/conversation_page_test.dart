import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_android/src/bootstrap/app_bootstrap.dart';
import 'package:zcchat2_for_android/src/controllers/chat_controller.dart';
import 'package:zcchat2_for_android/src/models/app_models.dart';
import 'package:zcchat2_for_android/src/repositories/app_repositories.dart';
import 'package:zcchat2_for_android/src/repositories/app_storage_paths.dart';
import 'package:zcchat2_for_android/src/services/llm_service.dart';
import 'package:zcchat2_for_android/src/ui/conversation_page.dart';

class FakeLlmService implements LlmService {
  FakeLlmService(this.provider);

  @override
  final LlmProviderType provider;

  @override
  Future<List<String>> fetchModels(String apiKey) async {
    return const <String>['fake-model'];
  }

  @override
  Stream<ChatStreamEvent> chatStream(ChatRequest request) async* {
    yield const ChatStreamEvent(
      rawText: 'happy|今天天气很好',
      displayedChinese: '今天天气很好',
      isCompleted: false,
    );
    yield const ChatStreamEvent(
      rawText: 'happy|今天天气很好|今日はいい天気です',
      displayedChinese: '今天天气很好',
      isCompleted: true,
    );
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('conversation page sends text and continues by tapping input box',
      (WidgetTester tester) async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('zcchat2_page_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final AppStoragePaths paths = AppStoragePaths(tempDir);
    await AppBootstrap.ensureInitialized(storagePaths: paths);

    final CharacterRepository characterRepository = CharacterRepository(paths);
    final SettingsRepository settingsRepository = SettingsRepository(paths);
    final ConversationRepository conversationRepository =
        ConversationRepository(paths, characterRepository);

    await settingsRepository.saveProviderApiKey(
      LlmProviderType.deepSeek,
      'fake-key',
    );
    await settingsRepository.saveProviderModels(
      LlmProviderType.deepSeek,
      const <String>['fake-model'],
    );
    await characterRepository.saveCharacterProvider(
      'test',
      LlmProviderType.deepSeek,
    );
    await characterRepository.saveCharacterModel('test', 'fake-model');

    final ConversationController controller = ConversationController(
      characterRepository: characterRepository,
      settingsRepository: settingsRepository,
      conversationRepository: conversationRepository,
      services: <LlmProviderType, LlmService>{
        LlmProviderType.openAI: FakeLlmService(LlmProviderType.openAI),
        LlmProviderType.deepSeek: FakeLlmService(LlmProviderType.deepSeek),
      },
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationPage(
          controller: controller,
          settingsPageBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '你好');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('今天天气很好'), findsOneWidget);
    expect(find.byIcon(Icons.touch_app_rounded), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_return_rounded), findsOneWidget);
  });
}
