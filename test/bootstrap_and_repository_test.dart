import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_mobile/src/bootstrap/app_bootstrap.dart';
import 'package:zcchat2_for_mobile/src/repositories/app_repositories.dart';
import 'package:zcchat2_for_mobile/src/repositories/app_storage_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bootstrap creates files and does not overwrite existing ini', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'zcchat2_bootstrap_test_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final AppStoragePaths paths = AppStoragePaths(tempDir);
    await AppBootstrap.ensureInitialized(storagePaths: paths);

    expect(paths.appConfigFile.existsSync(), isTrue);
    expect(paths.appIniFile.existsSync(), isTrue);
    expect(paths.characterAssetConfigFile('test').existsSync(), isTrue);
    expect(paths.characterRuntimeConfigFile('test').existsSync(), isTrue);
    expect(paths.characterContextFile('test').existsSync(), isTrue);
    expect(
      File(
        '${paths.characterTachieDirectory('test').path}${Platform.pathSeparator}default.png',
      ).existsSync(),
      isTrue,
    );

    await paths.appIniFile.writeAsString('[character]\nCharSelect=custom\n');
    await AppBootstrap.ensureInitialized(storagePaths: paths);
    expect(
      await paths.appIniFile.readAsString(),
      contains('CharSelect=custom'),
    );
  });

  test('bootstrap migrates legacy private storage into visible storage', () async {
    final Directory publicDir = await Directory.systemTemp.createTemp(
      'zcchat2_public_test_',
    );
    final Directory legacyDir = await Directory.systemTemp.createTemp(
      'zcchat2_legacy_test_',
    );
    addTearDown(() => publicDir.delete(recursive: true));
    addTearDown(() => legacyDir.delete(recursive: true));

    final AppStoragePaths publicPaths = AppStoragePaths(publicDir);
    final AppStoragePaths legacyPaths = AppStoragePaths(legacyDir);

    await legacyPaths.characterTachieDirectory('legacy').create(recursive: true);
    await legacyPaths.characterRuntimeConfigFile('legacy').parent.create(
      recursive: true,
    );
    await legacyPaths.appIniFile.parent.create(recursive: true);
    await legacyPaths.appIniFile.writeAsString('[character]\nCharSelect=legacy\n');
    await legacyPaths.characterAssetConfigFile('legacy').writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        <String, dynamic>{'prompt': '旧角色提示词'},
      ),
    );
    await legacyPaths.characterRuntimeConfigFile('legacy').writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        <String, dynamic>{
          'tachieSize': '100',
          'serverSelect': 'DeepSeek',
          'modelSelect': 'legacy-model',
        },
      ),
    );
    await legacyPaths.characterContextFile('legacy').writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        <String, dynamic>{'history': <String>['用户：你好']},
      ),
    );
    await File(
      '${legacyPaths.characterTachieDirectory('legacy').path}${Platform.pathSeparator}default.png',
    ).writeAsBytes(<int>[1, 2, 3]);

    await AppBootstrap.ensureInitialized(
      storagePaths: publicPaths,
      legacyStoragePaths: legacyPaths,
    );

    expect(publicPaths.appIniFile.existsSync(), isTrue);
    expect(
      await publicPaths.appIniFile.readAsString(),
      contains('CharSelect=legacy'),
    );
    expect(publicPaths.characterAssetConfigFile('legacy').existsSync(), isTrue);
    expect(publicPaths.characterRuntimeConfigFile('legacy').existsSync(), isTrue);
    expect(publicPaths.characterContextFile('legacy').existsSync(), isTrue);
    expect(
      File(
        '${publicPaths.characterTachieDirectory('legacy').path}${Platform.pathSeparator}default.png',
      ).existsSync(),
      isTrue,
    );
    expect(
      jsonDecode(await publicPaths.characterAssetConfigFile('legacy').readAsString())['prompt'],
      '旧角色提示词',
    );
  });

  test('conversation repository builds context message from saved history', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'zcchat2_context_test_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final AppStoragePaths paths = AppStoragePaths(tempDir);
    await AppBootstrap.ensureInitialized(storagePaths: paths);

    final CharacterRepository characterRepository = CharacterRepository(paths);
    final ConversationRepository conversationRepository =
        ConversationRepository(paths, characterRepository);

    await conversationRepository.appendUserLine('你好');
    await conversationRepository.appendRoleLine('欢迎回来');

    final String message =
        await conversationRepository.buildUserMessageWithContext('今天怎么样');
    expect(message, contains('用户：你好'));
    expect(message, contains('角色：欢迎回来'));
    expect(message, contains('用户当前输入：今天怎么样'));
  });

  test('character repository imports archive into assets and creates user config',
      () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'zcchat2_import_test_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final AppStoragePaths paths = AppStoragePaths(tempDir);
    await AppBootstrap.ensureInitialized(storagePaths: paths);

    final CharacterRepository characterRepository = CharacterRepository(paths);
    final Archive archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'sample/config.json',
          jsonEncode(<String, dynamic>{'prompt': '角色提示词'}),
        ),
      )
      ..addFile(
        ArchiveFile.bytes(
          'sample/Tachie/default.png',
          Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
      );

    final Uint8List zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    final String importedName = await characterRepository.importCharacterArchive(
      zipBytes,
      archiveName: 'sample.zip',
    );

    expect(importedName, 'sample');
    expect(paths.characterAssetConfigFile('sample').existsSync(), isTrue);
    expect(paths.characterRuntimeConfigFile('sample').existsSync(), isTrue);
    expect(paths.characterContextFile('sample').existsSync(), isTrue);
    expect(
      File(
        '${paths.characterTachieDirectory('sample').path}${Platform.pathSeparator}default.png',
      ).existsSync(),
      isTrue,
    );
    expect(
      jsonDecode(await paths.characterAssetConfigFile('sample').readAsString())['prompt'],
      '角色提示词',
    );
    expect(
      await paths.appIniFile.readAsString(),
      contains('CharSelect=sample'),
    );
  });
}
