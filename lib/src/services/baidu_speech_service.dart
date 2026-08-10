import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class BaiduSpeechService {
  String _accessToken = '';
  String _credentialKey = '';
  DateTime? _accessTokenExpiry;

  Future<String> recognize({
    required String apiKey,
    required String secretKey,
    required File audioFile,
    String format = 'm4a',
    int rate = 16000,
    int channel = 1,
  }) async {
    final Uint8List audioBytes = await audioFile.readAsBytes();
    if (audioBytes.isEmpty) {
      throw const SpeechRecognitionException('录音文件为空');
    }

    return recognizeBytes(
      apiKey: apiKey,
      secretKey: secretKey,
      audioBytes: audioBytes,
      format: format,
      rate: rate,
      channel: channel,
    );
  }

  Future<String> recognizeBytes({
    required String apiKey,
    required String secretKey,
    required Uint8List audioBytes,
    String format = 'pcm',
    int rate = 16000,
    int channel = 1,
  }) async {
    if (audioBytes.isEmpty) {
      throw const SpeechRecognitionException('录音数据为空');
    }

    final String accessToken = await _getAccessToken(apiKey, secretKey);
    if (accessToken.isEmpty) {
      throw const SpeechRecognitionException(
        '获取百度 Token 失败，请检查 API Key 和 Secret Key',
      );
    }

    final String base64Speech = base64Encode(audioBytes);
    final String cuid = const Uuid().v4();

    final Uri url = Uri.parse('https://vop.baidu.com/server_api');
    final http.Response response = await http.post(
      url,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'format': format,
        'rate': rate,
        'channel': channel,
        'token': accessToken,
        'cuid': cuid,
        'speech': base64Speech,
        'len': audioBytes.length,
      }),
    );

    if (response.statusCode != 200) {
      throw SpeechRecognitionException('语音识别请求失败: ${response.statusCode}');
    }

    final Map<String, dynamic> result =
        jsonDecode(response.body) as Map<String, dynamic>;
    final int? errNo = result['err_no'] as int?;
    if (errNo != null && errNo != 0) {
      throw SpeechRecognitionException('语音识别错误: ${result['err_msg'] ?? errNo}');
    }

    final List<dynamic>? resultList = result['result'] as List<dynamic>?;
    if (resultList == null || resultList.isEmpty) {
      return '';
    }

    return resultList.first.toString().trim();
  }

  Future<String> _getAccessToken(String apiKey, String secretKey) async {
    if (apiKey.isEmpty || secretKey.isEmpty) {
      return '';
    }

    final String credentialKey = '$apiKey\u0000$secretKey';
    final DateTime now = DateTime.now().toUtc();
    if (_credentialKey == credentialKey &&
        _accessToken.isNotEmpty &&
        _accessTokenExpiry?.isAfter(now) == true) {
      return _accessToken;
    }

    final Uri url =
        Uri.https('aip.baidubce.com', '/oauth/2.0/token', <String, String>{
          'grant_type': 'client_credentials',
          'client_id': apiKey,
          'client_secret': secretKey,
        });

    final http.Response response = await http.post(
      url,
      headers: <String, String>{'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      return '';
    }

    final Map<String, dynamic> result =
        jsonDecode(response.body) as Map<String, dynamic>;
    final String token = (result['access_token'] as String?)?.trim() ?? '';
    if (token.isEmpty) {
      return '';
    }

    final Object? rawExpiresIn = result['expires_in'];
    final int expiresIn = rawExpiresIn is int ? rawExpiresIn : 2592000;
    _credentialKey = credentialKey;
    _accessToken = token;
    _accessTokenExpiry = now.add(
      Duration(seconds: expiresIn > 120 ? expiresIn - 60 : 60),
    );
    return token;
  }
}

class SpeechRecognitionException implements Exception {
  const SpeechRecognitionException(this.message);

  final String message;

  @override
  String toString() => 'SpeechRecognitionException: $message';
}
