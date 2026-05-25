import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'src/app.dart';
import 'src/bootstrap/app_bootstrap.dart';
import 'src/repositories/app_repositories.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    final characterRepository = WebPreviewCharacterRepository();
    runApp(
      ZcChatApp.webPreview(
        characterRepository: characterRepository,
        settingsRepository: WebPreviewSettingsRepository(),
        conversationRepository: WebPreviewConversationRepository(
          characterRepository,
        ),
        vitsPlayback: const NoopVitsPlayback(),
      ),
    );
    return;
  }

  final storagePaths = await AppBootstrap.ensureInitialized();
  runApp(ZcChatApp(storagePaths: storagePaths));
}
