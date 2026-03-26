import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_mobile/src/models/app_models.dart';

void main() {
  test('extractDisplayedChinese reads partial chinese content', () {
    expect(
      ParsedCharacterReply.extractDisplayedChinese('happy|今天天气不错'),
      '今天天气不错',
    );
    expect(
      ParsedCharacterReply.extractDisplayedChinese('happy|今天天气不错|'),
      '今天天气不错',
    );
    expect(ParsedCharacterReply.extractDisplayedChinese('happy'), '');
  });

  test('tryParse returns structured reply for valid protocol', () {
    final ParsedCharacterReply? parsed = ParsedCharacterReply.tryParse(
      'happy|今天天气不错|今日はいい天気です',
    );

    expect(parsed, isNotNull);
    expect(parsed!.mood, 'happy');
    expect(parsed.chinese, '今天天气不错');
    expect(parsed.japanese, '今日はいい天気です');
  });
}
