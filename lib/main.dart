import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/bootstrap/app_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storagePaths = await AppBootstrap.ensureInitialized();
  runApp(ZcChatApp(storagePaths: storagePaths));
}
