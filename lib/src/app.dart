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
    _controller.dispose();
    for (final LlmService service in _services.values) {
      service.dispose();
    }
    _vitsPlayback.dispose();
    _vitsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZcChat2 for Mobile',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
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

ThemeData _buildTheme(Brightness brightness) {
  final ColorScheme generated = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB75E3C),
    brightness: brightness,
  );
  final ColorScheme colorScheme = brightness == Brightness.light
      ? generated.copyWith(
          primary: const Color(0xFF7C2D12),
          secondary: const Color(0xFFE8A17A),
          surface: const Color(0xFFFFF8F1),
        )
      : generated.copyWith(
          primary: const Color(0xFFFFB596),
          secondary: const Color(0xFFF0A07A),
          surface: const Color(0xFF211A17),
        );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF9F2E8)
        : const Color(0xFF171210),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
    ),
  );
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
