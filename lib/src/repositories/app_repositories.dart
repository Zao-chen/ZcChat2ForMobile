import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

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

class CharacterImportException implements Exception {
  const CharacterImportException(this.message);

  final String message;

  @override
  String toString() => 'CharacterImportException: $message';
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
    await paths.appIniFile.writeAsString(
      '[character]\nCharSelect=$characterName\n',
    );
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

  Future<String> importCharacterArchive(
    Uint8List bytes, {
    required String archiveName,
  }) async {
    final String characterName = _sanitizeCharacterName(
      p.basenameWithoutExtension(archiveName),
    );

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (error) {
      throw CharacterImportException('压缩包解析失败：$error');
    }

    final List<_ArchiveImportEntry> files = archive.files
        .where((ArchiveFile entry) => entry.isFile)
        .map(_ArchiveImportEntry.fromArchiveFile)
        .whereType<_ArchiveImportEntry>()
        .toList(growable: false);

    if (files.isEmpty) {
      throw const CharacterImportException('压缩包里没有可导入的角色文件');
    }

    final String? sharedRoot = _detectSharedRoot(files);
    final Directory targetDirectory = paths.characterAssetDirectory(characterName);
    if (await targetDirectory.exists()) {
      await targetDirectory.delete(recursive: true);
    }
    await targetDirectory.create(recursive: true);

    for (final _ArchiveImportEntry file in files) {
      final List<String> relativeSegments = sharedRoot == null
          ? file.pathSegments
          : file.pathSegments.sublist(1);
      if (relativeSegments.isEmpty) {
        continue;
      }

      final File destination = File(
        p.join(targetDirectory.path, p.joinAll(relativeSegments)),
      );
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(file.file.readBytes()!, flush: true);
    }

    await _ensureCharacterFiles(characterName);
    await selectCharacter(characterName);
    return characterName;
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

    final String trimmedMood =
        moodName.trim().isEmpty ? 'default' : moodName.trim();
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

  Future<void> _ensureCharacterFiles(String characterName) async {
    final File assetConfigFile = paths.characterAssetConfigFile(characterName);
    if (!await assetConfigFile.exists()) {
      await _writeJsonObject(
        assetConfigFile,
        const CharacterAssetConfig().toJson(),
      );
    }

    final File runtimeConfigFile = paths.characterRuntimeConfigFile(characterName);
    if (!await runtimeConfigFile.exists()) {
      await _writeJsonObject(
        runtimeConfigFile,
        const CharacterRuntimeConfig().toJson(),
      );
    }

    final File contextFile = paths.characterContextFile(characterName);
    if (!await contextFile.exists()) {
      await _writeJsonObject(
        contextFile,
        const ContextHistory(history: <String>[]).toJson(),
      );
    }
  }

  static String _sanitizeCharacterName(String value) {
    final String sanitized = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (sanitized.isEmpty) {
      return 'imported_character';
    }
    return sanitized;
  }

  static String? _detectSharedRoot(List<_ArchiveImportEntry> files) {
    if (files.any((_ArchiveImportEntry file) => file.pathSegments.length < 2)) {
      return null;
    }

    final String firstSegment = files.first.pathSegments.first;
    if (!files.every(
      (_ArchiveImportEntry file) => file.pathSegments.first == firstSegment,
    )) {
      return null;
    }
    return firstSegment;
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
    final String selectedCharacter =
        await characterRepository.getSelectedCharacter();
    final ContextHistory history = await loadHistory(selectedCharacter);
    if (history.history.isEmpty) {
      return input;
    }

    return '以下是你和用户最近的对话，请继续上下文并保持人设一致：\n'
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
    final String selectedCharacter =
        await characterRepository.getSelectedCharacter();
    final ContextHistory history = await loadHistory(selectedCharacter);
    final List<String> lines = List<String>.from(history.history)..add(line);
    await _writeJsonObject(
      paths.characterContextFile(selectedCharacter),
      ContextHistory(history: lines).toJson(),
    );
  }
}

class _ArchiveImportEntry {
  const _ArchiveImportEntry({
    required this.file,
    required this.pathSegments,
  });

  final ArchiveFile file;
  final List<String> pathSegments;

  static _ArchiveImportEntry? fromArchiveFile(ArchiveFile file) {
    final String normalizedPath = file.name.replaceAll('\\', '/').trim();
    if (normalizedPath.isEmpty || normalizedPath.startsWith('/')) {
      return null;
    }

    final List<String> segments = normalizedPath
        .split('/')
        .where((String segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }
    if (segments.any((String segment) => segment == '..')) {
      throw const CharacterImportException('压缩包包含非法路径');
    }

    return _ArchiveImportEntry(file: file, pathSegments: segments);
  }
}


