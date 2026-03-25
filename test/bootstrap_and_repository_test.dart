import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcchat2_for_android/src/bootstrap/app_bootstrap.dart';
import 'package:zcchat2_for_android/src/repositories/app_repositories.dart';
import 'package:zcchat2_for_android/src/repositories/app_storage_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bootstrap creates files and does not overwrite existing ini', () async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('zcchat2_bootstrap_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final AppStoragePaths paths = AppStoragePaths(tempDir);
    await AppBootstrap.ensureInitialized(storagePaths: paths);

    expect(paths.appConfigFile.existsSync(), isTrue);
    expect(paths.appIniFile.existsSync(), isTrue);
    expect(paths.characterAssetConfigFile('test').existsSync(), isTrue);
    expect(paths.characterRuntimeConfigFile('test').existsSync(), isTrue);
    expect(paths.characterContextFile('test').existsSync(), isTrue);
    expect(
      File('${paths.characterTachieDirectory('test').path}${Platform.pathSeparator}default.png')
          .existsSync(),
      isTrue,
    );

    await paths.appIniFile.writeAsString('[character]\nCharSelect=custom\n');
    await AppBootstrap.ensureInitialized(storagePaths: paths);
    expect(await paths.appIniFile.readAsString(), contains('CharSelect=custom'));
  });

  test('conversation repository builds context message from saved history', () async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('zcchat2_context_test_');
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
}
