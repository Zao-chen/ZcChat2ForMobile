import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_mobile/src/services/app_version.dart';

void main() {
  test('only reports a strictly newer semantic version', () {
    expect(isVersionNewer('v1.7.1', '1.7.0'), isTrue);
    expect(isVersionNewer('1.10.0', '1.9.9'), isTrue);
    expect(isVersionNewer('1.7', '1.7.0'), isFalse);
    expect(isVersionNewer('1.6.9', '1.7.0'), isFalse);
  });

  test('handles pre-release and build metadata precedence', () {
    expect(isVersionNewer('1.7.0', '1.7.0-rc.1'), isTrue);
    expect(isVersionNewer('1.7.0-rc.2', '1.7.0-rc.1'), isTrue);
    expect(isVersionNewer('1.7.0-rc.1', '1.7.0'), isFalse);
    expect(isVersionNewer('1.7.0+2', '1.7.0+1'), isFalse);
  });

  test('does not offer an update for an unknown version format', () {
    expect(isVersionNewer('latest', '1.7.0'), isFalse);
    expect(isVersionNewer('1.8.0', 'dev'), isFalse);
  });
}
