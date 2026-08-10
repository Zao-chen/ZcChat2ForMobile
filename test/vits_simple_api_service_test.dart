import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zcchat2_for_mobile/src/services/vits_simple_api_service.dart';

void main() {
  test('uses the speaker id returned by vits-simple-api', () async {
    final List<Uri> requests = <Uri>[];
    final VitsSimpleApiService service = VitsSimpleApiService(
      client: MockClient((http.Request request) async {
        requests.add(request.url);
        if (request.url.path == '/voice/speakers') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'VITS': <Map<String, dynamic>>[
                  <String, dynamic>{'id': 164, 'name': '亚托莉'},
                ],
              }),
            ),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        return http.Response.bytes(<int>[1, 2, 3], 200);
      }),
    );
    addTearDown(service.dispose);

    final List<String> speakers = await service.fetchModelAndSpeakers(
      'http://127.0.0.1:23456',
    );
    expect(speakers, <String>['VITS - 164 - 亚托莉']);

    await service.synthesize(
      apiUrl: 'http://127.0.0.1:23456',
      modelAndSpeaker: speakers.single,
      text: '你好',
    );

    expect(requests.last.path, '/voice/vits');
    expect(requests.last.queryParameters['id'], '164');
    expect(requests.last.queryParameters['text'], '你好');
  });
}
