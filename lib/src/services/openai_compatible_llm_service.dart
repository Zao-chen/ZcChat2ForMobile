import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_models.dart';
import 'app_logger.dart';
import 'llm_service.dart';

class OpenAiCompatibleLlmService implements LlmService {
  OpenAiCompatibleLlmService({required this.provider, http.Client? client})
    : _client = client ?? http.Client();

  @override
  final LlmProviderType provider;

  final http.Client _client;

  Uri getBaseUri() => Uri.parse(provider.baseUrl);

  @override
  Future<List<String>> fetchModels(String apiKey) async {
    final Uri baseUri = getBaseUri();
    final Uri requestUri = baseUri.resolve('models');
    AppLogger.info(
      'model_list.fetch.started',
      fields: <String, Object?>{
        'provider': provider.name,
        'endpoint': requestUri,
      },
    );
    final http.Request request = http.Request('GET', requestUri)
      ..headers.addAll(_headers(apiKey))
      ..headers['Accept'] = 'application/json';

    final http.StreamedResponse response = await _client.send(request);
    final String body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AppLogger.warning(
        'model_list.fetch.failed',
        fields: <String, Object?>{
          'provider': provider.name,
          'status': response.statusCode,
        },
      );
      throw LlmException(_extractError(body, fallback: '获取模型列表失败'));
    }

    final Object? decoded = jsonDecode(body);
    final Map<String, dynamic> json = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    final Object? data = json['data'];
    if (data is! List) {
      return const <String>[];
    }

    final List<String> models = data
        .whereType<Map>()
        .map((Map model) => model['id'])
        .whereType<String>()
        .toList(growable: false);
    AppLogger.info(
      'model_list.fetch.completed',
      fields: <String, Object?>{
        'provider': provider.name,
        'model_count': models.length,
      },
    );
    return models;
  }

  @override
  Stream<ChatStreamEvent> chatStream(ChatRequest request) async* {
    AppLogger.info(
      'chat.http.started',
      fields: <String, Object?>{
        'provider': provider.name,
        'model': request.model,
      },
    );
    final http.Request httpRequest =
        http.Request('POST', getBaseUri().resolve('chat/completions'))
          ..headers.addAll(_headers(request.apiKey))
          ..body = jsonEncode(<String, dynamic>{
            'model': request.model,
            'stream': true,
            'messages': <Map<String, String>>[
              <String, String>{
                'role': 'system',
                'content': request.systemPrompt,
              },
              <String, String>{'role': 'user', 'content': request.userMessage},
            ],
          });

    final http.StreamedResponse response = await _client.send(httpRequest);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String body = await response.stream.bytesToString();
      AppLogger.warning(
        'chat.http.failed',
        fields: <String, Object?>{
          'provider': provider.name,
          'model': request.model,
          'status': response.statusCode,
        },
      );
      throw LlmException(_extractError(body, fallback: '对话请求失败'));
    }

    String rawReply = '';
    await for (final String line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final String trimmedLine = line.trim();
      if (trimmedLine.isEmpty || !trimmedLine.startsWith('data:')) {
        continue;
      }

      final String payload = trimmedLine.substring(5).trim();
      if (payload == '[DONE]') {
        break;
      }

      Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } catch (_) {
        continue;
      }
      final Map<String, dynamic> json = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      final Object? choices = json['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        continue;
      }

      final Map<dynamic, dynamic> choice =
          choices.first as Map<dynamic, dynamic>;
      final Object? delta = choice['delta'];
      final String content = delta is Map
          ? (delta['content'] as String? ?? '')
          : '';
      if (content.isEmpty) {
        continue;
      }

      rawReply += content;
      yield ChatStreamEvent(
        rawText: rawReply,
        displayedChinese: ParsedCharacterReply.extractDisplayedChinese(
          rawReply,
        ),
        isCompleted: false,
      );
    }

    yield ChatStreamEvent(
      rawText: rawReply,
      displayedChinese: ParsedCharacterReply.extractDisplayedChinese(rawReply),
      isCompleted: true,
    );
  }

  @override
  void dispose() {
    _client.close();
  }

  Map<String, String> _headers(String apiKey) {
    return <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
  }

  String _extractError(String body, {required String fallback}) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final Object? error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final String message = (error['message'] as String?)?.trim() ?? '';
          if (message.isNotEmpty) {
            return message;
          }
        }
        final String message = (decoded['message'] as String?)?.trim() ?? '';
        if (message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      // Ignore malformed error bodies and fall back to a generic message.
    }
    return fallback;
  }
}

class OpenAiLlmService extends OpenAiCompatibleLlmService {
  OpenAiLlmService({super.client}) : super(provider: LlmProviderType.openAI);
}

class DeepSeekLlmService extends OpenAiCompatibleLlmService {
  DeepSeekLlmService({super.client})
    : super(provider: LlmProviderType.deepSeek);
}

class CustomLlmService extends OpenAiCompatibleLlmService {
  CustomLlmService({String baseUrl = '', super.client})
    : _customBaseUrl = baseUrl,
      super(provider: LlmProviderType.custom);

  String _customBaseUrl;

  void updateBaseUrl(String baseUrl) {
    _customBaseUrl = baseUrl;
  }

  @override
  Uri getBaseUri() {
    final String url = _customBaseUrl.endsWith('/')
        ? _customBaseUrl
        : '$_customBaseUrl/';
    return Uri.parse(url);
  }
}
