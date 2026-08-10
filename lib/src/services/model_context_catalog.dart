import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_models.dart';
import 'app_logger.dart';

class ModelContextMatch {
  const ModelContextMatch({
    this.canonicalModelId = '',
    this.contextTokenLimit = 0,
  });

  final String canonicalModelId;
  final int contextTokenLimit;

  bool get isValid => canonicalModelId.isNotEmpty && contextTokenLimit > 0;
}

class ModelContextCatalog {
  const ModelContextCatalog._();

  static bool selectionMatches({
    required String storedProvider,
    required String storedModel,
    required String currentProvider,
    required String currentModel,
  }) {
    final String normalizedModel = currentModel.trim();
    if (normalizedModel.isEmpty ||
        storedModel.trim().toLowerCase() != normalizedModel.toLowerCase()) {
      return false;
    }
    final String normalizedStoredProvider = storedProvider.trim();
    return normalizedStoredProvider.isEmpty ||
        normalizedStoredProvider.toLowerCase() ==
            currentProvider.trim().toLowerCase();
  }

  static ModelContextMatch findContextWindow({
    required Map<String, dynamic> catalog,
    required LlmProviderType provider,
    required String modelId,
  }) {
    final String trimmedModelId = modelId.trim();
    if (catalog.isEmpty || trimmedModelId.isEmpty) {
      return const ModelContextMatch();
    }

    final String prefix = switch (provider) {
      LlmProviderType.openAI => 'openai',
      LlmProviderType.deepSeek => 'deepseek',
      LlmProviderType.custom => '',
    };
    final int firstSlash = trimmedModelId.indexOf('/');
    final int lastSlash = trimmedModelId.lastIndexOf('/');
    if (prefix.isNotEmpty &&
        firstSlash >= 0 &&
        trimmedModelId.substring(0, firstSlash).toLowerCase() != prefix) {
      return const ModelContextMatch();
    }

    final List<String> exactCandidates = <String>[
      if (prefix.isNotEmpty && lastSlash < 0)
        '$prefix/$trimmedModelId'
      else
        trimmedModelId,
    ];
    final int variantSeparator = trimmedModelId.lastIndexOf(':');
    if (variantSeparator > lastSlash) {
      final String withoutVariant = trimmedModelId.substring(
        0,
        variantSeparator,
      );
      exactCandidates.add(
        prefix.isNotEmpty && !withoutVariant.contains('/')
            ? '$prefix/$withoutVariant'
            : withoutVariant,
      );
    }

    for (final String candidate in exactCandidates.toSet()) {
      final ModelContextMatch match = _matchEntry(catalog, candidate);
      if (match.isValid) {
        return match;
      }
    }
    if (prefix.isNotEmpty) {
      return const ModelContextMatch();
    }

    String suffixModelId = trimmedModelId;
    if (variantSeparator > lastSlash) {
      suffixModelId = trimmedModelId.substring(0, variantSeparator);
    }
    if (suffixModelId.contains('/')) {
      return const ModelContextMatch();
    }

    ModelContextMatch suffixMatch = const ModelContextMatch();
    final String suffix = '/${suffixModelId.toLowerCase()}';
    for (final MapEntry<String, dynamic> entry in catalog.entries) {
      if (!entry.key.toLowerCase().endsWith(suffix)) {
        continue;
      }
      final int limit = _contextTokenLimit(entry.value);
      if (limit <= 0) {
        continue;
      }
      if (suffixMatch.isValid) {
        return const ModelContextMatch();
      }
      suffixMatch = ModelContextMatch(
        canonicalModelId: entry.key,
        contextTokenLimit: limit,
      );
    }
    return suffixMatch;
  }

  static ModelContextMatch _matchEntry(
    Map<String, dynamic> catalog,
    String requestedId,
  ) {
    for (final MapEntry<String, dynamic> entry in catalog.entries) {
      if (entry.key.toLowerCase() != requestedId.toLowerCase()) {
        continue;
      }
      final int limit = _contextTokenLimit(entry.value);
      return limit > 0
          ? ModelContextMatch(
              canonicalModelId: entry.key,
              contextTokenLimit: limit,
            )
          : const ModelContextMatch();
    }
    return const ModelContextMatch();
  }

  static int _contextTokenLimit(Object? value) {
    if (value is! Map) {
      return 0;
    }
    final Object? limit = value['limit'];
    if (limit is! Map) {
      return 0;
    }
    final Object? context = limit['context'];
    return context is num ? context.toInt() : 0;
  }
}

class ModelContextCatalogService {
  ModelContextCatalogService({http.Client? client})
    : _client = client ?? http.Client();

  static final Uri catalogUri = Uri.parse('https://models.dev/models.json');

  final http.Client _client;
  Map<String, dynamic>? _cachedCatalog;

  Future<ModelContextMatch> resolve({
    required LlmProviderType provider,
    required String modelId,
    bool forceRefresh = false,
  }) async {
    final Map<String, dynamic> catalog = await _fetchCatalog(
      forceRefresh: forceRefresh,
    );
    return ModelContextCatalog.findContextWindow(
      catalog: catalog,
      provider: provider,
      modelId: modelId,
    );
  }

  Future<Map<String, dynamic>> _fetchCatalog({
    required bool forceRefresh,
  }) async {
    if (!forceRefresh && _cachedCatalog != null) {
      return _cachedCatalog!;
    }
    AppLogger.info('model_context.fetch.started');
    final http.Response response = await _client
        .get(
          catalogUri,
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Models.dev 请求失败（${response.statusCode}）');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded.isEmpty) {
      throw const FormatException('Models.dev 返回无效数据');
    }
    final Map<String, dynamic> catalog = decoded.cast<String, dynamic>();
    _cachedCatalog = catalog;
    AppLogger.info(
      'model_context.fetch.completed',
      fields: <String, Object?>{'model_count': catalog.length},
    );
    return catalog;
  }

  void dispose() {
    _client.close();
  }
}
