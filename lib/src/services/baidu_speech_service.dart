import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class BaiduSpeechService {
  const BaiduSpeechService();

  Future<String> recognize({
    required String apiKey,
    required String secretKey,
    required File audioFile,
    String format = 'm4a',
    int rate = 16000,
    int channel = 1,
  }) async {
    final String accessToken = await _requestAccessToken(apiKey, secretKey);
    if (accessToken.isEmpty) {
      throw const SpeechRecognitionException('获取百度 Token 失败，请检查 API Key 和 Secret Key');
    }

    final List<int> audioBytes = await audioFile.readAsBytes();
    if (audioBytes.isEmpty) {
      throw const SpeechRecognitionException('录音文件为空');
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

  Future<String> _requestAccessToken(String apiKey, String secretKey) async {
    if (apiKey.isEmpty || secretKey.isEmpty) {
      return '';
    }

    final Uri url = Uri.parse(
      'https://aip.baidubce.com/oauth/2.0/token'
      '?grant_type=client_credentials'
      '&client_id=$apiKey'
      '&client_secret=$secretKey',
    );

    final http.Response response = await http.post(
      url,
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      return '';
    }

    final Map<String, dynamic> result =
        jsonDecode(response.body) as Map<String, dynamic>;
    return (result['access_token'] as String?)?.trim() ?? '';
  }
}

class SpeechRecognitionException implements Exception {
  const SpeechRecognitionException(this.message);

  final String message;

  @override
  String toString() => 'SpeechRecognitionException: $message';
}
