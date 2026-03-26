import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'vits_service.dart';

class VitsSimpleApiService implements VitsService {
  VitsSimpleApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<String>> fetchModelAndSpeakers(String apiUrl) async {
    final Uri uri = _buildBaseUri(apiUrl).resolve('voice/speakers');
    final http.Response response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VitsException(_extractError(response.body, fallback: '获取角色列表失败'));
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return const <String>[];
    }

    final List<String> items = <String>[];
    for (final MapEntry<dynamic, dynamic> entry in decoded.entries) {
      final String modelType = entry.key.toString().trim();
      if (modelType.isEmpty || entry.value is! List) {
        continue;
      }

      for (final Object? value in entry.value as List) {
        if (value is! Map) {
          continue;
        }
        final String name = value['name']?.toString().trim() ?? '';
        final String id = value['id']?.toString().trim() ?? '';
        if (name.isEmpty || id.isEmpty) {
          continue;
        }
        items.add('$modelType - $id - $name');
      }
    }

    return items;
  }

  @override
  Future<Uint8List> synthesize({
    required String apiUrl,
    required String modelAndSpeaker,
    required String text,
  }) async {
    final _ParsedModelAndSpeaker parsed = _parseModelAndSpeaker(modelAndSpeaker);
    final Uri uri = _buildBaseUri(apiUrl)
        .resolve('voice/${parsed.model}')
        .replace(queryParameters: <String, String>{
      'id': parsed.speaker,
      'text': text,
    });

    final http.Response response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VitsException(
        _extractError(
          utf8.decode(response.bodyBytes, allowMalformed: true),
          fallback: '语音合成失败',
        ),
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw const VitsException('语音合成返回为空');
    }

    return Uint8List.fromList(response.bodyBytes);
  }

  @override
  void dispose() {
    _client.close();
  }

  Uri _buildBaseUri(String apiUrl) {
    final String normalized = apiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw const VitsException('请先填写 VITS API 地址');
    }
    return Uri.parse('$normalized/');
  }

  _ParsedModelAndSpeaker _parseModelAndSpeaker(String value) {
    final List<String> parts = value
        .split(' - ')
        .map((String part) => part.trim())
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 3) {
      throw const VitsException('语音角色配置无效');
    }

    return _ParsedModelAndSpeaker(
      model: parts.first.toLowerCase(),
      speaker: parts.sublist(2).join(' - '),
    );
  }

  String _extractError(String body, {required String fallback}) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
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

class _ParsedModelAndSpeaker {
  const _ParsedModelAndSpeaker({
    required this.model,
    required this.speaker,
  });

  final String model;
  final String speaker;
}
