import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_mobile/src/services/app_logger.dart';

void main() {
  test('AppLogger writes structured events without multiline fields', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'zcchat2_app_logger_test_',
    );
    addTearDown(() async {
      await AppLogger.flush();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final File logFile = File('${directory.path}/log.txt');
    await AppLogger.initialize(logFile.path);
    AppLogger.info(
      'test.started',
      fields: <String, Object?>{'provider': 'custom', 'note': 'line1\nline2'},
    );
    AppLogger.warning('test.warning', fields: <String, Object?>{'status': 503});
    AppLogger.error('test.failed', error: StateError('expected'));
    await AppLogger.flush();

    final String contents = await logFile.readAsString();
    expect(contents, contains('[Info] logging.initialized'));
    expect(contents, contains('[Info] test.started provider=custom'));
    expect(contents, contains(r'note=line1\nline2'));
    expect(contents, contains('[Warning] test.warning status=503'));
    expect(contents, contains('[Error] test.failed'));
    expect(contents, contains('Bad state: expected'));
  });
}
