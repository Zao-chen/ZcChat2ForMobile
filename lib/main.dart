import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'src/app.dart';
import 'src/bootstrap/app_bootstrap.dart';
import 'src/repositories/app_repositories.dart';
import 'src/repositories/web_preview_storage.dart';

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
  runApp(ZcChatApp(storagePaths: storagePaths));
}
