class ModelProviderConfig {
  const ModelProviderConfig({
    this.apiKey = '',
    this.baseUrl = '',
    this.models = const <String>[],
  });

  final String apiKey;
  final String baseUrl;
  final List<String> models;

  ModelProviderConfig copyWith({
    String? apiKey,
    String? baseUrl,
    List<String>? models,
  }) {
    return ModelProviderConfig(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
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
      baseUrl: (json['BaseUrl'] as String?)?.trim() ?? '',
      models: modelList,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'ApiKey': apiKey,
      'BaseUrl': baseUrl,
      'ModelList': models,
    };
  }
}

class VitsConfig {
  const VitsConfig({
    this.apiUrl = '',
    this.modelAndSpeakers = const <String>[],
    this.sentenceSplit = true,
  });

  final String apiUrl;
  final List<String> modelAndSpeakers;
  final bool sentenceSplit;

  VitsConfig copyWith({
    String? apiUrl,
    List<String>? modelAndSpeakers,
    bool? sentenceSplit,
  }) {
    return VitsConfig(
      apiUrl: apiUrl ?? this.apiUrl,
      modelAndSpeakers: modelAndSpeakers ?? this.modelAndSpeakers,
      sentenceSplit: sentenceSplit ?? this.sentenceSplit,
    );
  }

  factory VitsConfig.fromJson(Map<String, dynamic> json) {
    final Object? rawModels = json['ModelAndSpeakerList'];
    final List<String> modelAndSpeakers = rawModels is List
        ? rawModels.whereType<String>().toList(growable: false)
        : const <String>[];

    final Object? rawSentenceSplit = json['SentenceSplit'];
    final bool sentenceSplit = switch (rawSentenceSplit) {
      bool value => value,
      String value => value.toLowerCase() == 'true',
      int value => value != 0,
      _ => true,
    };

    return VitsConfig(
      apiUrl: (json['ApiUrl'] as String?)?.trim() ?? '',
      modelAndSpeakers: modelAndSpeakers,
      sentenceSplit: sentenceSplit,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'ApiUrl': apiUrl,
      'ModelAndSpeakerList': modelAndSpeakers,
      'SentenceSplit': sentenceSplit,
    };
  }
}

class SpeechInputConfig {
  const SpeechInputConfig({
    this.enable = false,
    this.wakeEnabled = false,
    this.autoSend = false,
    this.baiduApiKey = '',
    this.baiduSecretKey = '',
  });

  final bool enable;
  final bool wakeEnabled;
  final bool autoSend;
  final String baiduApiKey;
  final String baiduSecretKey;

  SpeechInputConfig copyWith({
    bool? enable,
    bool? wakeEnabled,
    bool? autoSend,
    String? baiduApiKey,
    String? baiduSecretKey,
  }) {
    return SpeechInputConfig(
      enable: enable ?? this.enable,
      wakeEnabled: wakeEnabled ?? this.wakeEnabled,
      autoSend: autoSend ?? this.autoSend,
      baiduApiKey: baiduApiKey ?? this.baiduApiKey,
      baiduSecretKey: baiduSecretKey ?? this.baiduSecretKey,
    );
  }

  factory SpeechInputConfig.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> baiduMap =
        (json['Baidu'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final Map<String, dynamic> wakeMap =
        (json['Wake'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return SpeechInputConfig(
      enable: _parseBool(json['Enable']),
      wakeEnabled: _parseBool(wakeMap['Enable']),
      autoSend: _parseBool(json['AutoSend']),
      baiduApiKey: (baiduMap['ApiKey'] as String?)?.trim() ?? '',
      baiduSecretKey: (baiduMap['SecretKey'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Enable': enable,
      'Wake': <String, dynamic>{'Enable': wakeEnabled},
      'AutoSend': autoSend,
      'Baidu': <String, dynamic>{
        'ApiKey': baiduApiKey,
        'SecretKey': baiduSecretKey,
      },
    };
  }
}

bool _parseBool(Object? value) {
  return switch (value) {
    bool v => v,
    String v => v.toLowerCase() == 'true',
    int v => v != 0,
    _ => false,
  };
}

enum LlmProviderType {
  openAI,
  deepSeek,
  custom;

  String get configKey {
    switch (this) {
      case LlmProviderType.openAI:
        return 'OpenAI';
      case LlmProviderType.deepSeek:
        return 'DeepSeek';
      case LlmProviderType.custom:
        return 'Custom';
    }
  }

  String get label {
    switch (this) {
      case LlmProviderType.openAI:
        return 'OpenAI';
      case LlmProviderType.deepSeek:
        return 'DeepSeek';
      case LlmProviderType.custom:
        return '自定义';
    }
  }

  String get baseUrl {
    switch (this) {
      case LlmProviderType.openAI:
        return 'https://api.openai.com/v1/';
      case LlmProviderType.deepSeek:
        return 'https://api.deepseek.com/v1/';
      case LlmProviderType.custom:
        return '';
    }
  }

  static LlmProviderType fromConfigKey(String? value) {
    switch (value) {
      case 'OpenAI':
        return LlmProviderType.openAI;
      case 'Custom':
        return LlmProviderType.custom;
      case 'DeepSeek':
      default:
        return LlmProviderType.deepSeek;
    }
  }
}

class AppConfig {
  const AppConfig({
    required this.providers,
    required this.vits,
    this.speechInput = const SpeechInputConfig(),
  });

  final Map<LlmProviderType, ModelProviderConfig> providers;
  final VitsConfig vits;
  final SpeechInputConfig speechInput;

  factory AppConfig.initial() {
    return AppConfig(
      providers: <LlmProviderType, ModelProviderConfig>{
        LlmProviderType.openAI: const ModelProviderConfig(),
        LlmProviderType.deepSeek: const ModelProviderConfig(),
        LlmProviderType.custom: const ModelProviderConfig(),
      },
      vits: const VitsConfig(),
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

    final Map<String, dynamic> vitsMap =
        (json['vits'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final Map<String, dynamic> speechMap =
        (json['speechInput'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return AppConfig(
      providers: providers,
      vits: VitsConfig.fromJson(vitsMap),
      speechInput: SpeechInputConfig.fromJson(speechMap),
    );
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
      vits: vits,
      speechInput: speechInput,
    );
  }

  AppConfig copyWithVits(VitsConfig config) {
    return AppConfig(
      providers: providers,
      vits: config,
      speechInput: speechInput,
    );
  }

  AppConfig copyWithSpeechInput(SpeechInputConfig config) {
    return AppConfig(providers: providers, vits: vits, speechInput: config);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> llmMap = <String, dynamic>{};
    for (final LlmProviderType provider in LlmProviderType.values) {
      llmMap[provider.configKey] = providerConfig(provider).toJson();
    }

    return <String, dynamic>{
      'llm': llmMap,
      'vits': vits.toJson(),
      'speechInput': speechInput.toJson(),
    };
  }
}

class CharacterSpeechConfig {
  const CharacterSpeechConfig({
    this.wakeWords = const <String>[],
    this.endWords = const <String>[],
  });

  final List<String> wakeWords;
  final List<String> endWords;

  CharacterSpeechConfig copyWith({
    List<String>? wakeWords,
    List<String>? endWords,
  }) {
    return CharacterSpeechConfig(
      wakeWords: wakeWords ?? List<String>.from(this.wakeWords),
      endWords: endWords ?? List<String>.from(this.endWords),
    );
  }

  factory CharacterSpeechConfig.fromJson(Map<String, dynamic> json) {
    List<String> readWords(String key) {
      final Object? value = json[key];
      return value is List
          ? value
                .whereType<String>()
                .map((String word) => word.trim())
                .where((String word) => word.isNotEmpty)
                .toList(growable: false)
          : const <String>[];
    }

    return CharacterSpeechConfig(
      wakeWords: readWords('wakeWords'),
      endWords: readWords('endWords'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'wakeWords': wakeWords, 'endWords': endWords};
  }
}

class CharacterAssetConfig {
  const CharacterAssetConfig({
    this.prompt = '',
    this.speechInput = const CharacterSpeechConfig(),
  });

  final String prompt;
  final CharacterSpeechConfig speechInput;

  CharacterAssetConfig copyWith({
    String? prompt,
    CharacterSpeechConfig? speechInput,
  }) {
    return CharacterAssetConfig(
      prompt: prompt ?? this.prompt,
      speechInput: speechInput ?? this.speechInput,
    );
  }

  factory CharacterAssetConfig.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> speechMap =
        (json['speechInput'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return CharacterAssetConfig(
      prompt: (json['prompt'] as String?) ?? '',
      speechInput: CharacterSpeechConfig.fromJson(speechMap),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'prompt': prompt,
      'speechInput': speechInput.toJson(),
    };
  }
}

class CharacterRuntimeConfig {
  const CharacterRuntimeConfig({
    this.tachieSize = 100,
    this.tachieOffsetX = 0,
    this.tachieOffsetY = 0,
    this.serverSelect = 'DeepSeek',
    this.modelSelect = '',
    this.vitsEnable = false,
    this.vitsMasSelect = '',
    this.tachieAnimations = const <String, String>{},
    this.contextTokenLimit = 65536,
    this.contextTokenLimitSource = '',
    this.contextTokenModel = '',
    this.contextTokenProvider = '',
    this.contextAutoCompactThresholdPercent = 80,
  });

  final int tachieSize;
  final double tachieOffsetX;
  final double tachieOffsetY;
  final String serverSelect;
  final String modelSelect;
  final bool vitsEnable;
  final String vitsMasSelect;
  final Map<String, String> tachieAnimations;
  final int contextTokenLimit;
  final String contextTokenLimitSource;
  final String contextTokenModel;
  final String contextTokenProvider;
  final int contextAutoCompactThresholdPercent;

  LlmProviderType get provider => LlmProviderType.fromConfigKey(serverSelect);

  CharacterRuntimeConfig copyWith({
    int? tachieSize,
    double? tachieOffsetX,
    double? tachieOffsetY,
    String? serverSelect,
    String? modelSelect,
    bool? vitsEnable,
    String? vitsMasSelect,
    Map<String, String>? tachieAnimations,
    int? contextTokenLimit,
    String? contextTokenLimitSource,
    String? contextTokenModel,
    String? contextTokenProvider,
    int? contextAutoCompactThresholdPercent,
  }) {
    return CharacterRuntimeConfig(
      tachieSize: tachieSize ?? this.tachieSize,
      tachieOffsetX: tachieOffsetX ?? this.tachieOffsetX,
      tachieOffsetY: tachieOffsetY ?? this.tachieOffsetY,
      serverSelect: serverSelect ?? this.serverSelect,
      modelSelect: modelSelect ?? this.modelSelect,
      vitsEnable: vitsEnable ?? this.vitsEnable,
      vitsMasSelect: vitsMasSelect ?? this.vitsMasSelect,
      tachieAnimations:
          tachieAnimations ?? Map<String, String>.from(this.tachieAnimations),
      contextTokenLimit: contextTokenLimit ?? this.contextTokenLimit,
      contextTokenLimitSource:
          contextTokenLimitSource ?? this.contextTokenLimitSource,
      contextTokenModel: contextTokenModel ?? this.contextTokenModel,
      contextTokenProvider: contextTokenProvider ?? this.contextTokenProvider,
      contextAutoCompactThresholdPercent:
          contextAutoCompactThresholdPercent ??
          this.contextAutoCompactThresholdPercent,
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
    final Object? rawVitsEnable = json['vitsEnable'];
    final Object? rawTachieAnimations = json['tachieAnimations'];
    final int contextTokenLimit = _parseInt(
      json['contextTokenLimit'],
      fallback: 65536,
    );
    final int contextAutoCompactThresholdPercent = _parseInt(
      json['contextAutoCompactThresholdPercent'],
      fallback: 80,
    );

    final Map<String, String> tachieAnimations = <String, String>{};
    if (rawTachieAnimations is Map) {
      for (final MapEntry<dynamic, dynamic> entry
          in rawTachieAnimations.entries) {
        final String key = entry.key.toString().trim();
        final String value = entry.value.toString().trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          tachieAnimations[key] = value;
        }
      }
    }

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
      vitsEnable: switch (rawVitsEnable) {
        bool value => value,
        String value => value.toLowerCase() == 'true',
        int value => value != 0,
        _ => false,
      },
      vitsMasSelect: (json['vitsMasSelect'] as String?) ?? '',
      tachieAnimations: tachieAnimations,
      contextTokenLimit:
          contextTokenLimit >= 1024 && contextTokenLimit <= 10000000
          ? contextTokenLimit
          : 65536,
      contextTokenLimitSource:
          (json['contextTokenLimitSource'] as String?)?.trim() ?? '',
      contextTokenModel: (json['contextTokenModel'] as String?)?.trim() ?? '',
      contextTokenProvider:
          (json['contextTokenProvider'] as String?)?.trim() ?? '',
      contextAutoCompactThresholdPercent:
          contextAutoCompactThresholdPercent >= 50 &&
              contextAutoCompactThresholdPercent <= 95
          ? contextAutoCompactThresholdPercent
          : 80,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tachieSize': tachieSize.toString(),
      'tachieOffsetX': tachieOffsetX,
      'tachieOffsetY': tachieOffsetY,
      'serverSelect': serverSelect,
      'modelSelect': modelSelect,
      'vitsEnable': vitsEnable,
      'vitsMasSelect': vitsMasSelect,
      'tachieAnimations': tachieAnimations,
      'contextTokenLimit': contextTokenLimit,
      'contextTokenLimitSource': contextTokenLimitSource,
      'contextTokenModel': contextTokenModel,
      'contextTokenProvider': contextTokenProvider,
      'contextAutoCompactThresholdPercent': contextAutoCompactThresholdPercent,
    };
  }
}

int _parseInt(Object? value, {required int fallback}) {
  return switch (value) {
    int parsed => parsed,
    num parsed => parsed.toInt(),
    String parsed => int.tryParse(parsed) ?? fallback,
    _ => fallback,
  };
}

enum HistorySpeaker { user, role, system }

class HistoryEntry {
  const HistoryEntry({required this.speaker, required this.text});

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
    return HistoryEntry(speaker: HistorySpeaker.system, text: rawLine);
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
    this.summary = '',
    this.compactedHistoryCount = 0,
  });

  final List<String> history;
  final String summary;
  final int compactedHistoryCount;

  List<HistoryEntry> get entries =>
      history.map(HistoryEntry.fromRawLine).toList(growable: false);

  factory ContextHistory.fromJson(Map<String, dynamic> json) {
    final Object? rawHistory = json['history'];
    final List<String> lines = rawHistory is List
        ? rawHistory.whereType<String>().toList(growable: false)
        : const <String>[];
    final Map<String, dynamic> compaction =
        (json['compaction'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final String summary = (compaction['summary'] as String?)?.trim() ?? '';
    final int compactedHistoryCount = _parseInt(
      compaction['historyCount'],
      fallback: 0,
    );
    final bool validCompaction =
        summary.isNotEmpty &&
        compactedHistoryCount > 0 &&
        compactedHistoryCount <= lines.length;
    return ContextHistory(
      history: lines,
      summary: validCompaction ? summary : '',
      compactedHistoryCount: validCompaction ? compactedHistoryCount : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'history': history,
      'compaction': <String, dynamic>{
        'summary': summary,
        'historyCount': compactedHistoryCount,
      },
    };
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
