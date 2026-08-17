import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_mobile/src/bootstrap/app_bootstrap.dart';
import 'package:zcchat2_for_mobile/src/controllers/chat_controller.dart';
import 'package:zcchat2_for_mobile/src/models/app_models.dart';
import 'package:zcchat2_for_mobile/src/repositories/app_repositories.dart';
import 'package:zcchat2_for_mobile/src/repositories/app_storage_paths.dart';
import 'package:zcchat2_for_mobile/src/services/llm_service.dart';
import 'package:zcchat2_for_mobile/src/services/vits_service.dart';
import 'package:zcchat2_for_mobile/src/ui/conversation_page.dart';

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

class FakeVitsPlayback implements VitsPlayback {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'conversation page sends text and continues by tapping input box',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final Directory tempDir = Directory.systemTemp.createTempSync(
        'zcchat2_page_test_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final AppStoragePaths paths = AppStoragePaths(tempDir);

      final CharacterRepository characterRepository = CharacterRepository(
        paths,
      );
      final SettingsRepository settingsRepository = SettingsRepository(paths);
      final ConversationRepository conversationRepository =
          ConversationRepository(paths, characterRepository);

      final ConversationController controller = ConversationController(
        characterRepository: characterRepository,
        settingsRepository: settingsRepository,
        conversationRepository: conversationRepository,
        services: <LlmProviderType, LlmService>{
          LlmProviderType.openAI: FakeLlmService(LlmProviderType.openAI),
          LlmProviderType.deepSeek: FakeLlmService(LlmProviderType.deepSeek),
        },
        vitsPlayback: FakeVitsPlayback(),
      );
      await tester.runAsync(() async {
        await AppBootstrap.ensureInitialized(storagePaths: paths);
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
        await controller.initialize();
      });
      controller.appConfig = controller.appConfig.copyWithSpeechInput(
        controller.appConfig.speechInput.copyWith(enable: true),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationPage(
            controller: controller,
            settingsPageBuilder: (_) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('你'), findsOneWidget);
      expect(find.text('按住说话'), findsOneWidget);
      expect(find.text('识别后自动发送'), findsOneWidget);
      expect(find.textContaining('剩余'), findsNothing);
      expect(find.text('说点什么吧'), findsOneWidget);
      final TextField input = tester.widget<TextField>(find.byType(TextField));
      expect(input.keyboardType, TextInputType.multiline);
      expect(input.textInputAction, TextInputAction.newline);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('send-message-button')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byType(LinearProgressIndicator));
      await tester.pumpAndSettle();
      expect(find.text('上下文详情'), findsOneWidget);
      await tester.tap(find.byType(ModalBarrier).last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '你好');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('send-message-button')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey<String>('send-message-button')),
        );
        await _waitUntil(() => controller.history.entries.isNotEmpty);
      });
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('今天天气很好'), findsOneWidget);
      expect(find.text('轻触这里继续对话'), findsOneWidget);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text('说点什么吧'), findsOneWidget);
      controller.dispose();
    },
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('等待页面异步状态超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
