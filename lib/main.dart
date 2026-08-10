import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'src/app.dart';
import 'src/bootstrap/app_bootstrap.dart';
import 'src/repositories/app_repositories.dart';
import 'src/repositories/web_preview_storage.dart';
import 'src/services/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    final WebPreviewStorage storage = createWebPreviewStorage();
    final characterRepository = WebPreviewCharacterRepository(storage);
    runApp(
      ZcChatApp.webPreview(
        characterRepository: characterRepository,
        settingsRepository: WebPreviewSettingsRepository(storage),
        conversationRepository: WebPreviewConversationRepository(
          characterRepository,
          storage,
        ),
        vitsPlayback: const NoopVitsPlayback(),
      ),
    );
    return;
  }

  final storagePaths = await AppBootstrap.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.error(
      'flutter.framework.error',
      error: details.exception,
      stackTrace: details.stack,
      fields: <String, Object?>{'library': details.library ?? 'unknown'},
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    AppLogger.error(
      'flutter.platform.error',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  };
  AppLogger.info(
    'application.start',
    fields: <String, Object?>{'platform': defaultTargetPlatform.name},
  );
  runApp(ZcChatApp(storagePaths: storagePaths));
}
