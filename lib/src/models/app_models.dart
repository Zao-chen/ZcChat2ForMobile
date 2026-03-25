class ModelProviderConfig {
  const ModelProviderConfig({
    this.apiKey = '',
    this.models = const <String>[],
  });

  final String apiKey;
  final List<String> models;

  ModelProviderConfig copyWith({
    String? apiKey,
    List<String>? models,
  }) {
    return ModelProviderConfig(
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
    );
  }

  factory ModelProviderConfig.fromJson(Map<String, dynamic> json) {
    final Object? rawModels = json['ModelList'];
    final List<String> modelList = rawModels is List
        ? rawModels.whereType<String>().toList(growable: false)
        : const <String>[];

    return ModelProviderConfig(
      apiKey: (json['ApiKey'] as String?)?.trim() ?? '',
      models: modelList,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'ApiKey': apiKey,
      'ModelList': models,
    };
  }
}

enum LlmProviderType {
  openAI,
  deepSeek;

  String get configKey {
    switch (this) {
      case LlmProviderType.openAI:
        return 'OpenAI';
      case LlmProviderType.deepSeek:
        return 'DeepSeek';
    }
  }

  String get label {
    switch (this) {
      case LlmProviderType.openAI:
        return 'OpenAI';
      case LlmProviderType.deepSeek:
        return 'DeepSeek';
    }
  }

  String get baseUrl {
    switch (this) {
      case LlmProviderType.openAI:
        return 'https://api.openai.com/v1/';
      case LlmProviderType.deepSeek:
        return 'https://api.deepseek.com/v1/';
    }
  }

  static LlmProviderType fromConfigKey(String? value) {
    switch (value) {
      case 'OpenAI':
        return LlmProviderType.openAI;
      case 'DeepSeek':
      default:
        return LlmProviderType.deepSeek;
    }
  }
}

class AppConfig {
  const AppConfig({
    required this.providers,
  });

  final Map<LlmProviderType, ModelProviderConfig> providers;

  factory AppConfig.initial() {
    return AppConfig(
      providers: <LlmProviderType, ModelProviderConfig>{
        LlmProviderType.openAI: const ModelProviderConfig(),
        LlmProviderType.deepSeek: const ModelProviderConfig(),
      },
    );
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> llmMap =
        (json['llm'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};

    final Map<LlmProviderType, ModelProviderConfig> providers =
        <LlmProviderType, ModelProviderConfig>{};

    for (final LlmProviderType provider in LlmProviderType.values) {
      final Map<String, dynamic> providerMap =
          (llmMap[provider.configKey] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      providers[provider] = ModelProviderConfig.fromJson(providerMap);
    }

    return AppConfig(providers: providers);
  }

  ModelProviderConfig providerConfig(LlmProviderType provider) {
    return providers[provider] ?? const ModelProviderConfig();
  }

  AppConfig copyWithProvider(
    LlmProviderType provider,
    ModelProviderConfig config,
  ) {
    return AppConfig(
      providers: <LlmProviderType, ModelProviderConfig>{
        ...providers,
        provider: config,
      },
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> llmMap = <String, dynamic>{};
    for (final LlmProviderType provider in LlmProviderType.values) {
      llmMap[provider.configKey] = providerConfig(provider).toJson();
    }

    return <String, dynamic>{'llm': llmMap};
  }
}

class CharacterAssetConfig {
  const CharacterAssetConfig({
    this.prompt = '',
  });

  final String prompt;

  CharacterAssetConfig copyWith({
    String? prompt,
  }) {
    return CharacterAssetConfig(prompt: prompt ?? this.prompt);
  }

  factory CharacterAssetConfig.fromJson(Map<String, dynamic> json) {
    return CharacterAssetConfig(
      prompt: (json['prompt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'prompt': prompt};
  }
}

class CharacterRuntimeConfig {
  const CharacterRuntimeConfig({
    this.tachieSize = 100,
    this.tachieOffsetX = 0,
    this.tachieOffsetY = 0,
    this.serverSelect = 'DeepSeek',
    this.modelSelect = '',
  });

  final int tachieSize;
  final double tachieOffsetX;
  final double tachieOffsetY;
  final String serverSelect;
  final String modelSelect;

  LlmProviderType get provider => LlmProviderType.fromConfigKey(serverSelect);

  CharacterRuntimeConfig copyWith({
    int? tachieSize,
    double? tachieOffsetX,
    double? tachieOffsetY,
    String? serverSelect,
    String? modelSelect,
  }) {
    return CharacterRuntimeConfig(
      tachieSize: tachieSize ?? this.tachieSize,
      tachieOffsetX: tachieOffsetX ?? this.tachieOffsetX,
      tachieOffsetY: tachieOffsetY ?? this.tachieOffsetY,
      serverSelect: serverSelect ?? this.serverSelect,
      modelSelect: modelSelect ?? this.modelSelect,
    );
  }

  factory CharacterRuntimeConfig.fromJson(Map<String, dynamic> json) {
    final Object? rawTachieSize = json['tachieSize'];
    final int tachieSize = switch (rawTachieSize) {
      int value => value,
      String value => int.tryParse(value) ?? 100,
      _ => 100,
    };
    final Object? rawOffsetX = json['tachieOffsetX'];
    final Object? rawOffsetY = json['tachieOffsetY'];

    return CharacterRuntimeConfig(
      tachieSize: tachieSize,
      tachieOffsetX: switch (rawOffsetX) {
        num value => value.toDouble(),
        String value => double.tryParse(value) ?? 0,
        _ => 0,
      },
      tachieOffsetY: switch (rawOffsetY) {
        num value => value.toDouble(),
        String value => double.tryParse(value) ?? 0,
        _ => 0,
      },
      serverSelect: (json['serverSelect'] as String?)?.trim().isNotEmpty == true
          ? (json['serverSelect'] as String)
          : 'DeepSeek',
      modelSelect: (json['modelSelect'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tachieSize': tachieSize.toString(),
      'tachieOffsetX': tachieOffsetX,
      'tachieOffsetY': tachieOffsetY,
      'serverSelect': serverSelect,
      'modelSelect': modelSelect,
    };
  }
}

enum HistorySpeaker {
  user,
  role,
  system,
}

class HistoryEntry {
  const HistoryEntry({
    required this.speaker,
    required this.text,
  });

  static const String userPrefix = '用户：';
  static const String rolePrefix = '角色：';

  final HistorySpeaker speaker;
  final String text;

  factory HistoryEntry.fromRawLine(String rawLine) {
    if (rawLine.startsWith(userPrefix)) {
      return HistoryEntry(
        speaker: HistorySpeaker.user,
        text: rawLine.substring(userPrefix.length),
      );
    }
    if (rawLine.startsWith(rolePrefix)) {
      return HistoryEntry(
        speaker: HistorySpeaker.role,
        text: rawLine.substring(rolePrefix.length),
      );
    }
    return HistoryEntry(
      speaker: HistorySpeaker.system,
      text: rawLine,
    );
  }

  String toRawLine() {
    switch (speaker) {
      case HistorySpeaker.user:
        return '$userPrefix$text';
      case HistorySpeaker.role:
        return '$rolePrefix$text';
      case HistorySpeaker.system:
        return text;
    }
  }
}

class ContextHistory {
  const ContextHistory({
    required this.history,
  });

  final List<String> history;

  List<HistoryEntry> get entries =>
      history.map(HistoryEntry.fromRawLine).toList(growable: false);

  factory ContextHistory.fromJson(Map<String, dynamic> json) {
    final Object? rawHistory = json['history'];
    final List<String> lines = rawHistory is List
        ? rawHistory.whereType<String>().toList(growable: false)
        : const <String>[];
    return ContextHistory(history: lines);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'history': history};
  }
}

class ChatRequest {
  const ChatRequest({
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    required this.userMessage,
  });

  final String apiKey;
  final String model;
  final String systemPrompt;
  final String userMessage;
}

class ChatStreamEvent {
  const ChatStreamEvent({
    required this.rawText,
    required this.displayedChinese,
    required this.isCompleted,
  });

  final String rawText;
  final String displayedChinese;
  final bool isCompleted;
}

class ParsedCharacterReply {
  const ParsedCharacterReply({
    required this.mood,
    required this.chinese,
    required this.japanese,
  });

  final String mood;
  final String chinese;
  final String japanese;

  static ParsedCharacterReply? tryParse(String rawReply) {
    final int firstSep = rawReply.indexOf('|');
    if (firstSep < 0) {
      return null;
    }

    final int secondSep = rawReply.indexOf('|', firstSep + 1);
    if (secondSep < 0) {
      return null;
    }

    final String mood = rawReply.substring(0, firstSep).trim();
    final String chinese = rawReply.substring(firstSep + 1, secondSep).trim();
    final String japanese = rawReply.substring(secondSep + 1).trim();
    if (chinese.isEmpty) {
      return null;
    }

    return ParsedCharacterReply(
      mood: mood.isEmpty ? 'default' : mood,
      chinese: chinese,
      japanese: japanese,
    );
  }

  static String extractDisplayedChinese(String rawReply) {
    final int firstSep = rawReply.indexOf('|');
    if (firstSep < 0) {
      return '';
    }

    final int secondSep = rawReply.indexOf('|', firstSep + 1);
    if (secondSep < 0) {
      return rawReply.substring(firstSep + 1).trimLeft();
    }

    return rawReply.substring(firstSep + 1, secondSep).trimLeft();
  }
}
