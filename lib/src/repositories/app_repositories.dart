import 'dart:convert';
import 'dart:io';

import '../models/app_models.dart';
import 'app_storage_paths.dart';

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  if (!await file.exists()) {
    return <String, dynamic>{};
  }

  final String content = await file.readAsString();
  if (content.trim().isEmpty) {
    return <String, dynamic>{};
  }

  final Object? decoded = jsonDecode(content);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.cast<String, dynamic>();
  }
  return <String, dynamic>{};
}

Future<void> _writeJsonObject(File file, Map<String, dynamic> json) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(json),
  );
}

class SettingsRepository {
  SettingsRepository(this.paths);

  final AppStoragePaths paths;

  Future<AppConfig> loadAppConfig() async {
    return AppConfig.fromJson(await _readJsonObject(paths.appConfigFile));
  }

  Future<void> saveAppConfig(AppConfig config) async {
    await _writeJsonObject(paths.appConfigFile, config.toJson());
  }

  Future<void> saveProviderApiKey(
    LlmProviderType provider,
    String apiKey,
  ) async {
    final AppConfig config = await loadAppConfig();
    final ModelProviderConfig updated =
        config.providerConfig(provider).copyWith(apiKey: apiKey.trim());
    await saveAppConfig(config.copyWithProvider(provider, updated));
  }

  Future<void> saveProviderModels(
    LlmProviderType provider,
    List<String> models,
  ) async {
    final AppConfig config = await loadAppConfig();
    final ModelProviderConfig updated = config
        .providerConfig(provider)
        .copyWith(models: models.toList(growable: false));
    await saveAppConfig(config.copyWithProvider(provider, updated));
  }
}

class CharacterRepository {
  CharacterRepository(this.paths);

  final AppStoragePaths paths;

  Future<List<String>> getCharacters() async {
    if (!await paths.characterAssetsDirectory.exists()) {
      return const <String>[];
    }

    final List<String> characters = await paths.characterAssetsDirectory
        .list()
        .where((FileSystemEntity entity) => entity is Directory)
        .map((FileSystemEntity entity) => entity.uri.pathSegments
            .where((String segment) => segment.isNotEmpty)
            .last)
        .toList();
    characters.sort();
    return characters;
  }

  Future<String> getSelectedCharacter() async {
    if (!await paths.appIniFile.exists()) {
      return 'test';
    }

    final String content = await paths.appIniFile.readAsString();
    final RegExpMatch? match =
        RegExp(r'^CharSelect=(.+)$', multiLine: true).firstMatch(content);
    if (match == null) {
      return 'test';
    }

    final String value = match.group(1)?.trim() ?? '';
    return value.isEmpty ? 'test' : value;
  }

  Future<void> selectCharacter(String characterName) async {
    await paths.appIniFile.parent.create(recursive: true);
    await paths.appIniFile.writeAsString('[character]\nCharSelect=$characterName\n');
  }

  Future<CharacterAssetConfig> loadCharacterAssetConfig(
    String characterName,
  ) async {
    return CharacterAssetConfig.fromJson(
      await _readJsonObject(paths.characterAssetConfigFile(characterName)),
    );
  }

  Future<CharacterRuntimeConfig> loadCharacterRuntimeConfig(
    String characterName,
  ) async {
    return CharacterRuntimeConfig.fromJson(
      await _readJsonObject(paths.characterRuntimeConfigFile(characterName)),
    );
  }

  Future<void> saveCharacterPrompt(String characterName, String prompt) async {
    final CharacterAssetConfig current =
        await loadCharacterAssetConfig(characterName);
    await _writeJsonObject(
      paths.characterAssetConfigFile(characterName),
      current.copyWith(prompt: prompt).toJson(),
    );
  }

  Future<void> saveTachieSize(String characterName, int size) async {
    final CharacterRuntimeConfig current =
        await loadCharacterRuntimeConfig(characterName);
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current.copyWith(tachieSize: size).toJson(),
    );
  }

  Future<void> saveTachieTransform(
    String characterName, {
    required int size,
    required double offsetX,
    required double offsetY,
  }) async {
    final CharacterRuntimeConfig current =
        await loadCharacterRuntimeConfig(characterName);
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current
          .copyWith(
            tachieSize: size,
            tachieOffsetX: offsetX,
            tachieOffsetY: offsetY,
          )
          .toJson(),
    );
  }

  Future<void> resetTachieTransform(String characterName) async {
    final CharacterRuntimeConfig current =
        await loadCharacterRuntimeConfig(characterName);
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current
          .copyWith(
            tachieSize: 100,
            tachieOffsetX: 0,
            tachieOffsetY: 0,
          )
          .toJson(),
    );
  }

  Future<void> saveCharacterProvider(
    String characterName,
    LlmProviderType provider,
  ) async {
    final CharacterRuntimeConfig current =
        await loadCharacterRuntimeConfig(characterName);
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current.copyWith(serverSelect: provider.configKey).toJson(),
    );
  }

  Future<void> saveCharacterModel(
    String characterName,
    String modelId,
  ) async {
    final CharacterRuntimeConfig current =
        await loadCharacterRuntimeConfig(characterName);
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current.copyWith(modelSelect: modelId).toJson(),
    );
  }

  Future<List<String>> getTachieMoodNames(String characterName) async {
    final Directory directory = paths.characterTachieDirectory(characterName);
    if (!await directory.exists()) {
      return const <String>['default'];
    }

    final List<String> names = <String>[];
    await for (final FileSystemEntity entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final String fileName = entity.uri.pathSegments.last;
      final String lowerName = fileName.toLowerCase();
      if (!lowerName.endsWith('.png') &&
          !lowerName.endsWith('.jpg') &&
          !lowerName.endsWith('.jpeg')) {
        continue;
      }

      final int dotIndex = fileName.lastIndexOf('.');
      names.add(dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName);
    }

    if (names.isEmpty) {
      return const <String>['default'];
    }

    names.sort();
    return names;
  }

  Future<File?> resolveTachieFile(
    String characterName,
    String moodName,
  ) async {
    final Directory directory = paths.characterTachieDirectory(characterName);
    if (!await directory.exists()) {
      return null;
    }

    final String trimmedMood = moodName.trim().isEmpty ? 'default' : moodName.trim();
    final List<FileSystemEntity> entries = await directory.list().toList();

    File? exactMatch;
    File? fallbackMatch;
    for (final FileSystemEntity entry in entries) {
      if (entry is! File) {
        continue;
      }

      final String fileName = entry.uri.pathSegments.last;
      final String lowerName = fileName.toLowerCase();
      if (!lowerName.endsWith('.png') &&
          !lowerName.endsWith('.jpg') &&
          !lowerName.endsWith('.jpeg')) {
        continue;
      }

      final int dotIndex = fileName.lastIndexOf('.');
      final String baseName =
          dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
      if (baseName == trimmedMood) {
        exactMatch = entry;
      }
      if (baseName.toLowerCase() == trimmedMood.toLowerCase()) {
        exactMatch ??= entry;
      }
      if (baseName.toLowerCase() == 'default') {
        fallbackMatch = entry;
      }
    }

    return exactMatch ?? fallbackMatch;
  }
}

class ConversationRepository {
  ConversationRepository(
    this.paths,
    this.characterRepository,
  );

  final AppStoragePaths paths;
  final CharacterRepository characterRepository;

  Future<ContextHistory> loadHistory(String characterName) async {
    return ContextHistory.fromJson(
      await _readJsonObject(paths.characterContextFile(characterName)),
    );
  }

  Future<String> buildUserMessageWithContext(String input) async {
    final String selectedCharacter = await characterRepository.getSelectedCharacter();
    final ContextHistory history = await loadHistory(selectedCharacter);
    if (history.history.isEmpty) {
      return input;
    }

    return '以下是你和用户最近的对话，请延续上下文并保持人设一致：\n'
        '${history.history.join('\n')}\n\n'
        '用户当前输入：$input';
  }

  Future<void> appendUserLine(String text) async {
    await _appendLine(
      HistoryEntry(speaker: HistorySpeaker.user, text: text).toRawLine(),
    );
  }

  Future<void> appendRoleLine(String text) async {
    await _appendLine(
      HistoryEntry(speaker: HistorySpeaker.role, text: text).toRawLine(),
    );
  }

  Future<void> _appendLine(String line) async {
    final String selectedCharacter = await characterRepository.getSelectedCharacter();
    final ContextHistory history = await loadHistory(selectedCharacter);
    final List<String> lines = List<String>.from(history.history)..add(line);
    await _writeJsonObject(
      paths.characterContextFile(selectedCharacter),
      ContextHistory(history: lines).toJson(),
    );
  }
}
