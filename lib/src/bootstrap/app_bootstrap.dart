import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_models.dart';
import '../repositories/app_storage_paths.dart';

class AppBootstrap {
  static const String _defaultTachieAssetPath =
      'assets/bootstrap/character/assets/test/Tachie/default.png';

  static Future<AppStoragePaths> ensureInitialized({
    AppStoragePaths? storagePaths,
    AssetBundle? assetBundle,
  }) async {
    final AssetBundle resolvedAssetBundle = assetBundle ?? rootBundle;
    final AppStoragePaths paths = storagePaths ??
        AppStoragePaths(await getApplicationDocumentsDirectory());

    await paths.rootDirectory.create(recursive: true);
    await paths.characterAssetsDirectory.create(recursive: true);
    await paths.characterUserConfigDirectory.create(recursive: true);
    await paths.characterTachieDirectory('test').create(recursive: true);
    await paths.characterRuntimeConfigFile('test').parent.create(recursive: true);

    if (!await paths.appConfigFile.exists()) {
      await paths.appConfigFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(AppConfig.initial().toJson()),
      );
    }

    if (!await paths.appIniFile.exists()) {
      await paths.appIniFile.writeAsString('[character]\nCharSelect=test\n');
    }

    if (!await paths.characterAssetConfigFile('test').exists()) {
      await paths.characterAssetConfigFile('test').writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          const CharacterAssetConfig(
            prompt: '你是一名温柔、自然的二次元角色，请用轻松的语气与用户对话。',
          ).toJson(),
        ),
      );
    }

    if (!await paths.characterRuntimeConfigFile('test').exists()) {
      await paths.characterRuntimeConfigFile('test').writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          const CharacterRuntimeConfig().toJson(),
        ),
      );
    }

    if (!await paths.characterContextFile('test').exists()) {
      await paths.characterContextFile('test').writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          const ContextHistory(history: <String>[]).toJson(),
        ),
      );
    }

    final File tachieFile = File(
      '${paths.characterTachieDirectory('test').path}${Platform.pathSeparator}default.png',
    );
    await _copyDefaultTachie(
      destinationFile: tachieFile,
      assetBundle: resolvedAssetBundle,
    );

    return paths;
  }

  static Future<void> _copyDefaultTachie({
    required File destinationFile,
    required AssetBundle assetBundle,
  }) async {
    if (await destinationFile.exists()) {
      return;
    }

    await destinationFile.parent.create(recursive: true);

    Uint8List bytes;
    try {
      final ByteData data = await assetBundle.load(_defaultTachieAssetPath);
      bytes = data.buffer.asUint8List();
    } catch (_) {
      bytes = base64Decode(_fallbackTransparentPngBase64);
    }

    await destinationFile.writeAsBytes(bytes, flush: true);
  }

  static String get _fallbackTransparentPngBase64 =>
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg==';
}
