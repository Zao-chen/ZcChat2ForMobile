import 'dart:io';

import 'package:path/path.dart' as p;

class AppStoragePaths {
  AppStoragePaths(this.baseDirectory);

  final Directory baseDirectory;

  Directory get rootDirectory => Directory(p.join(baseDirectory.path, 'ZcChat2'));

  File get appConfigFile => File(p.join(rootDirectory.path, 'config.json'));

  File get appIniFile => File(p.join(rootDirectory.path, 'config.ini'));

  Directory get characterAssetsDirectory =>
      Directory(p.join(rootDirectory.path, 'Character', 'Assets'));

  Directory get characterUserConfigDirectory =>
      Directory(p.join(rootDirectory.path, 'Character', 'UserConfig'));

  Directory characterAssetDirectory(String characterName) =>
      Directory(p.join(characterAssetsDirectory.path, characterName));

  Directory characterTachieDirectory(String characterName) =>
      Directory(p.join(characterAssetDirectory(characterName).path, 'Tachie'));

  File characterAssetConfigFile(String characterName) =>
      File(p.join(characterAssetDirectory(characterName).path, 'config.json'));

  File characterRuntimeConfigFile(String characterName) => File(
        p.join(characterUserConfigDirectory.path, characterName, 'config.json'),
      );

  File characterContextFile(String characterName) => File(
        p.join(characterUserConfigDirectory.path, characterName, 'context.json'),
      );
}
