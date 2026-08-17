import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static File? _logFile;
  static Future<void> _pendingWrite = Future<void>.value();

  static String? get logFilePath => _logFile?.path;

  static Future<void> initialize(String filePath) async {
    await _pendingWrite;
    final File nextFile = File(filePath);
    if (_logFile?.path == nextFile.path) {
      return;
    }

    await nextFile.parent.create(recursive: true);
    await nextFile.writeAsString('', flush: true);
    _logFile = nextFile;
    info('logging.initialized', fields: <String, Object?>{'path': filePath});
    await flush();
  }

  static void info(String event, {Map<String, Object?> fields = const {}}) {
    _log('Info', event, fields);
  }

  static void warning(String event, {Map<String, Object?> fields = const {}}) {
    _log('Warning', event, fields);
  }

  static void error(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    _log('Error', event, <String, Object?>{
      ...fields,
      'error': ?error,
      'stack': ?stackTrace,
    });
  }

  static Future<void> flush() => _pendingWrite;

  static void _log(String level, String event, Map<String, Object?> fields) {
    final StringBuffer line = StringBuffer(
      '${DateTime.now().toIso8601String()} [$level] $event',
    );
    for (final MapEntry<String, Object?> field in fields.entries) {
      line
        ..write(' ')
        ..write(field.key)
        ..write('=')
        ..write(_sanitize(field.value));
    }

    final String text = line.toString();
    debugPrint(text);
    final File? file = _logFile;
    if (file == null) {
      return;
    }
    _pendingWrite = _pendingWrite
        .then(
          (_) =>
              file.writeAsString('$text\n', mode: FileMode.append, flush: true),
        )
        .then<void>((_) {})
        .catchError((Object error) {
          debugPrint('AppLogger write failed: $error');
        });
  }

  static String _sanitize(Object? value) {
    final String text = value
        .toString()
        .replaceAll(RegExp(r'[\r\n]+'), r'\n')
        .trim();
    return text.length <= 2000 ? text : '${text.substring(0, 2000)}…';
  }
}
