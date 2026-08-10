import 'package:flutter/material.dart';

import 'controllers/chat_controller.dart';
import 'models/app_models.dart';
import 'repositories/app_repositories.dart';
import 'repositories/app_storage_paths.dart';
import 'services/llm_service.dart';
import 'services/openai_compatible_llm_service.dart';
import 'services/vits_playback_service.dart';
import 'services/vits_service.dart';
import 'services/vits_simple_api_service.dart';
import 'ui/conversation_page.dart';
import 'ui/settings_page.dart';

class ZcChatApp extends StatefulWidget {
  const ZcChatApp({
    required this.storagePaths,
    this.characterRepository,
    this.settingsRepository,
    this.conversationRepository,
    this.vitsPlayback,
    super.key,
  });

  const ZcChatApp.webPreview({
    required CharacterRepository this.characterRepository,
    required SettingsRepository this.settingsRepository,
    required ConversationRepository this.conversationRepository,
    required VitsPlayback this.vitsPlayback,
    super.key,
  }) : storagePaths = null;

  final AppStoragePaths? storagePaths;
  final CharacterRepository? characterRepository;
  final SettingsRepository? settingsRepository;
  final ConversationRepository? conversationRepository;
  final VitsPlayback? vitsPlayback;

  @override
  State<ZcChatApp> createState() => _ZcChatAppState();
}

class _ZcChatAppState extends State<ZcChatApp> {
  late final CharacterRepository _characterRepository;
  late final SettingsRepository _settingsRepository;
  late final ConversationRepository _conversationRepository;
  late final Map<LlmProviderType, LlmService> _services;
  late final VitsService _vitsService;
  late final VitsPlayback _vitsPlayback;
  late final ConversationController _controller;

  @override
  void initState() {
    super.initState();
    _characterRepository =
        widget.characterRepository ?? CharacterRepository(widget.storagePaths!);
    _settingsRepository =
        widget.settingsRepository ?? SettingsRepository(widget.storagePaths!);
    _conversationRepository =
        widget.conversationRepository ??
        ConversationRepository(widget.storagePaths!, _characterRepository);
    _services = <LlmProviderType, LlmService>{
      LlmProviderType.openAI: OpenAiLlmService(),
      LlmProviderType.deepSeek: DeepSeekLlmService(),
      LlmProviderType.custom: CustomLlmService(),
    };
    _vitsService = VitsSimpleApiService();
    _vitsPlayback =
        widget.vitsPlayback ?? VitsPlaybackService(service: _vitsService);
    _controller = ConversationController(
      characterRepository: _characterRepository,
      settingsRepository: _settingsRepository,
      conversationRepository: _conversationRepository,
      services: _services,
      vitsPlayback: _vitsPlayback,
    );
  }

  @override
  void dispose() {
    for (final LlmService service in _services.values) {
      service.dispose();
    }
    _vitsPlayback.dispose();
    _vitsService.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZcChat2 for Android',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB75E3C),
          brightness: Brightness.light,
          primary: const Color(0xFF7C2D12),
          secondary: const Color(0xFFE8A17A),
          surface: const Color(0xFFFFF8F1),
        ),
        scaffoldBackgroundColor: const Color(0xFFF9F2E8),
      ),
      home: ConversationPage(
        controller: _controller,
        settingsPageBuilder: (BuildContext context) {
          return SettingsPage(
            characterRepository: _characterRepository,
            settingsRepository: _settingsRepository,
            services: _services,
            vitsService: _vitsService,
          );
        },
      ),
    );
  }
}

class NoopVitsPlayback implements VitsPlayback {
  const NoopVitsPlayback();

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
