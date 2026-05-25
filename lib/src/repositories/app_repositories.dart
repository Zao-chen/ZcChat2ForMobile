import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/app_models.dart';
import '../models/anime_plugin_models.dart';
import '../services/anime_plugin_manager.dart';
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
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
}

class CharacterImportException implements Exception {
  const CharacterImportException(this.message);

  final String message;

  @override
  String toString() => 'CharacterImportException: $message';
}

class SettingsRepository {
  SettingsRepository(AppStoragePaths paths) : _paths = paths;

  SettingsRepository.webPreview() : _paths = null;

  final AppStoragePaths? _paths;

  AppStoragePaths get paths {
    final AppStoragePaths? paths = _paths;
    if (paths == null) {
      throw UnsupportedError('Web 预览模式不支持本机文件路径');
    }
    return paths;
  }

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
    final ModelProviderConfig updated = config
        .providerConfig(provider)
        .copyWith(apiKey: apiKey.trim());
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

  Future<void> saveVitsApiUrl(String apiUrl) async {
    final AppConfig config = await loadAppConfig();
    await saveAppConfig(
      config.copyWithVits(config.vits.copyWith(apiUrl: apiUrl.trim())),
    );
  }

  Future<void> saveVitsModelAndSpeakers(List<String> modelAndSpeakers) async {
    final AppConfig config = await loadAppConfig();
    await saveAppConfig(
      config.copyWithVits(
        config.vits.copyWith(
          modelAndSpeakers: modelAndSpeakers.toList(growable: false),
        ),
      ),
    );
  }

  Future<void> saveVitsSentenceSplit(bool enabled) async {
    final AppConfig config = await loadAppConfig();
    await saveAppConfig(
      config.copyWithVits(config.vits.copyWith(sentenceSplit: enabled)),
    );
  }
}

class CharacterRepository {
  CharacterRepository(AppStoragePaths paths)
    : _paths = paths,
      _animePluginManager = const AnimePluginManager();

  CharacterRepository.webPreview()
    : _paths = null,
      _animePluginManager = const AnimePluginManager();

  final AppStoragePaths? _paths;
  final AnimePluginManager _animePluginManager;

  AppStoragePaths get paths {
    final AppStoragePaths? paths = _paths;
    if (paths == null) {
      throw UnsupportedError('Web 预览模式不支持本机文件路径');
    }
    return paths;
  }

  Future<List<String>> getCharacters() async {
    if (!await paths.characterAssetsDirectory.exists()) {
      return const <String>[];
    }

    final List<String> characters = await paths.characterAssetsDirectory
        .list()
        .where((FileSystemEntity entity) => entity is Directory)
        .map(
          (FileSystemEntity entity) => entity.uri.pathSegments
              .where((String segment) => segment.isNotEmpty)
              .last,
        )
        .toList();
    characters.sort();
    return characters;
  }

  Future<String> getSelectedCharacter() async {
    if (!await paths.appIniFile.exists()) {
      return 'test';
    }

    final String content = await paths.appIniFile.readAsString();
    final RegExpMatch? match = RegExp(
      r'^CharSelect=(.+)$',
      multiLine: true,
    ).firstMatch(content);
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
    final CharacterAssetConfig current = await loadCharacterAssetConfig(
      characterName,
    );
    await _writeJsonObject(
      paths.characterAssetConfigFile(characterName),
      current.copyWith(prompt: prompt).toJson(),
    );
  }

  Future<void> saveTachieSize(String characterName, int size) async {
    final CharacterRuntimeConfig current = await loadCharacterRuntimeConfig(
      characterName,
    );
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
    final CharacterRuntimeConfig current = await loadCharacterRuntimeConfig(
      characterName,
    );
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
    final CharacterRuntimeConfig current = await loadCharacterRuntimeConfig(
      characterName,
    );
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current
          .copyWith(tachieSize: 100, tachieOffsetX: 0, tachieOffsetY: 0)
          .toJson(),
    );
  }

  Future<void> saveCharacterProvider(
    String characterName,
    LlmProviderType provider,
  ) async {
    final CharacterRuntimeConfig current = await loadCharacterRuntimeConfig(
      characterName,
    );
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current.copyWith(serverSelect: provider.configKey).toJson(),
    );
  }

  Future<void> saveCharacterModel(String characterName, String modelId) async {
    final CharacterRuntimeConfig current = await loadCharacterRuntimeConfig(
      characterName,
    );
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current.copyWith(modelSelect: modelId).toJson(),
    );
  }

  Future<void> saveCharacterVitsEnabled(
    String characterName,
    bool enabled,
  ) async {
    final CharacterRuntimeConfig current = await loadCharacterRuntimeConfig(
      characterName,
    );
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current.copyWith(vitsEnable: enabled).toJson(),
    );
  }

  Future<void> saveCharacterVitsModelAndSpeaker(
    String characterName,
    String modelAndSpeaker,
  ) async {
    final CharacterRuntimeConfig current = await loadCharacterRuntimeConfig(
      characterName,
    );
    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current.copyWith(vitsMasSelect: modelAndSpeaker).toJson(),
    );
  }

  Future<void> saveTachieAnimationBinding(
    String characterName,
    String actionName,
    String? animationUniqueKey,
  ) async {
    final CharacterRuntimeConfig current = await loadCharacterRuntimeConfig(
      characterName,
    );
    final Map<String, String> map = Map<String, String>.from(
      current.tachieAnimations,
    );
    final String trimmedAction = actionName.trim();
    final String trimmedKey = (animationUniqueKey ?? '').trim();
    if (trimmedAction.isEmpty) {
      return;
    }

    if (trimmedKey.isEmpty) {
      map.remove(trimmedAction);
    } else {
      map[trimmedAction] = trimmedKey;
    }

    await _writeJsonObject(
      paths.characterRuntimeConfigFile(characterName),
      current.copyWith(tachieAnimations: map).toJson(),
    );
  }

  Future<AnimePluginRegistry> loadAnimePluginRegistry() async {
    return _animePluginManager.reload(paths.animePluginDirectory);
  }

  Future<String> installAnimePluginFromFile(String sourceFilePath) async {
    final AnimePluginDefinition plugin = await _animePluginManager
        .parsePluginFile(sourceFilePath);
    final AnimePluginRegistry registry = await loadAnimePluginRegistry();
    for (final AnimePluginDefinition existPlugin in registry.plugins) {
      if (existPlugin.name == plugin.name) {
        throw CharacterImportException('插件名称重复: ${plugin.name}');
      }
    }

    final String fileSafePluginName = plugin.name
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .trim();
    if (fileSafePluginName.isEmpty) {
      throw const CharacterImportException('插件名称无效');
    }

    final File targetFile = File(
      p.join(paths.animePluginDirectory.path, '$fileSafePluginName.json'),
    );
    if (await targetFile.exists()) {
      throw CharacterImportException('目标文件已存在: ${targetFile.path}');
    }

    await targetFile.parent.create(recursive: true);
    await File(sourceFilePath).copy(targetFile.path);
    return plugin.name;
  }

  Future<void> deleteAnimePluginByName(String pluginName) async {
    final AnimePluginRegistry registry = await loadAnimePluginRegistry();
    for (final AnimePluginDefinition plugin in registry.plugins) {
      if (plugin.name == pluginName) {
        final File pluginFile = File(plugin.filePath);
        if (!await pluginFile.exists()) {
          throw CharacterImportException('插件文件不存在: ${plugin.filePath}');
        }
        await pluginFile.delete();
        return;
      }
    }
    throw CharacterImportException('未找到插件: $pluginName');
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
    final Directory targetDirectory = paths.characterAssetDirectory(
      characterName,
    );
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

  Future<File?> resolveTachieFile(String characterName, String moodName) async {
    final Directory directory = paths.characterTachieDirectory(characterName);
    if (!await directory.exists()) {
      return null;
    }

    final String trimmedMood = moodName.trim().isEmpty
        ? 'default'
        : moodName.trim();
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
      final String baseName = dotIndex > 0
          ? fileName.substring(0, dotIndex)
          : fileName;
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

    final File runtimeConfigFile = paths.characterRuntimeConfigFile(
      characterName,
    );
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
  ConversationRepository(AppStoragePaths paths, this.characterRepository)
    : _paths = paths;

  ConversationRepository.webPreview(this.characterRepository) : _paths = null;

  final AppStoragePaths? _paths;
  final CharacterRepository characterRepository;

  AppStoragePaths get paths {
    final AppStoragePaths? paths = _paths;
    if (paths == null) {
      throw UnsupportedError('Web 预览模式不支持本机文件路径');
    }
    return paths;
  }

  Future<ContextHistory> loadHistory(String characterName) async {
    return ContextHistory.fromJson(
      await _readJsonObject(paths.characterContextFile(characterName)),
    );
  }

  Future<String> buildUserMessageWithContext(String input) async {
    final String selectedCharacter = await characterRepository
        .getSelectedCharacter();
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

  Future<void> updateLine(int index, String newText) async {
    final String selectedCharacter = await characterRepository
        .getSelectedCharacter();
    final ContextHistory history = await loadHistory(selectedCharacter);
    final List<String> lines = List<String>.from(history.history);
    if (index < 0 || index >= lines.length) {
      return;
    }

    final HistoryEntry originalEntry = HistoryEntry.fromRawLine(lines[index]);
    final HistoryEntry updatedEntry = HistoryEntry(
      speaker: originalEntry.speaker,
      text: newText,
    );
    lines[index] = updatedEntry.toRawLine();
    await _saveHistory(selectedCharacter, lines);
  }

  Future<void> deleteLine(int index) async {
    final String selectedCharacter = await characterRepository
        .getSelectedCharacter();
    final ContextHistory history = await loadHistory(selectedCharacter);
    final List<String> lines = List<String>.from(history.history);
    if (index < 0 || index >= lines.length) {
      return;
    }
    lines.removeAt(index);
    await _saveHistory(selectedCharacter, lines);
  }

  /// 回退到指定位置：保留 [0, index) 的记录，删除 index 及之后的所有记录。
  Future<void> rollbackTo(int index) async {
    final String selectedCharacter = await characterRepository
        .getSelectedCharacter();
    final ContextHistory history = await loadHistory(selectedCharacter);
    final List<String> lines = List<String>.from(history.history);
    if (index <= 0) {
      await _saveHistory(selectedCharacter, <String>[]);
      return;
    }
    if (index >= lines.length) {
      return;
    }
    final List<String> kept = lines.sublist(0, index);
    await _saveHistory(selectedCharacter, kept);
  }

  Future<void> clearHistory() async {
    final String selectedCharacter = await characterRepository
        .getSelectedCharacter();
    await _saveHistory(selectedCharacter, <String>[]);
  }

  Future<void> _appendLine(String line) async {
    final String selectedCharacter = await characterRepository
        .getSelectedCharacter();
    final ContextHistory history = await loadHistory(selectedCharacter);
    final List<String> lines = List<String>.from(history.history)..add(line);
    await _saveHistory(selectedCharacter, lines);
  }

  Future<void> _saveHistory(String characterName, List<String> lines) async {
    await _writeJsonObject(
      paths.characterContextFile(characterName),
      ContextHistory(history: lines).toJson(),
    );
  }
}

class WebPreviewSettingsRepository extends SettingsRepository {
  WebPreviewSettingsRepository() : super.webPreview();

  AppConfig _config = AppConfig.initial();

  @override
  Future<AppConfig> loadAppConfig() async {
    return _config;
  }

  @override
  Future<void> saveAppConfig(AppConfig config) async {
    _config = config;
  }

  @override
  Future<void> saveProviderApiKey(
    LlmProviderType provider,
    String apiKey,
  ) async {
    final ModelProviderConfig updated = _config
        .providerConfig(provider)
        .copyWith(apiKey: apiKey.trim());
    _config = _config.copyWithProvider(provider, updated);
  }

  @override
  Future<void> saveProviderModels(
    LlmProviderType provider,
    List<String> models,
  ) async {
    final ModelProviderConfig updated = _config
        .providerConfig(provider)
        .copyWith(models: models.toList(growable: false));
    _config = _config.copyWithProvider(provider, updated);
  }

  @override
  Future<void> saveVitsApiUrl(String apiUrl) async {
    _config = _config.copyWithVits(_config.vits.copyWith(apiUrl: apiUrl));
  }

  @override
  Future<void> saveVitsModelAndSpeakers(List<String> modelAndSpeakers) async {
    _config = _config.copyWithVits(
      _config.vits.copyWith(
        modelAndSpeakers: modelAndSpeakers.toList(growable: false),
      ),
    );
  }

  @override
  Future<void> saveVitsSentenceSplit(bool enabled) async {
    _config = _config.copyWithVits(
      _config.vits.copyWith(sentenceSplit: enabled),
    );
  }
}

class WebPreviewCharacterRepository extends CharacterRepository {
  WebPreviewCharacterRepository() : super.webPreview();

  String _selectedCharacter = 'test';
  CharacterAssetConfig _assetConfig = const CharacterAssetConfig(
    prompt: '你是一名温柔、自然的二次元角色，请用轻松的语气与用户对话。',
  );
  CharacterRuntimeConfig _runtimeConfig = const CharacterRuntimeConfig();

  @override
  Future<List<String>> getCharacters() async {
    return const <String>['test'];
  }

  @override
  Future<String> getSelectedCharacter() async {
    return _selectedCharacter;
  }

  @override
  Future<void> selectCharacter(String characterName) async {
    _selectedCharacter = characterName.trim().isEmpty ? 'test' : characterName;
  }

  @override
  Future<CharacterAssetConfig> loadCharacterAssetConfig(
    String characterName,
  ) async {
    return _assetConfig;
  }

  @override
  Future<CharacterRuntimeConfig> loadCharacterRuntimeConfig(
    String characterName,
  ) async {
    return _runtimeConfig;
  }

  @override
  Future<void> saveCharacterPrompt(String characterName, String prompt) async {
    _assetConfig = _assetConfig.copyWith(prompt: prompt);
  }

  @override
  Future<void> saveTachieSize(String characterName, int size) async {
    _runtimeConfig = _runtimeConfig.copyWith(tachieSize: size);
  }

  @override
  Future<void> saveTachieTransform(
    String characterName, {
    required int size,
    required double offsetX,
    required double offsetY,
  }) async {
    _runtimeConfig = _runtimeConfig.copyWith(
      tachieSize: size,
      tachieOffsetX: offsetX,
      tachieOffsetY: offsetY,
    );
  }

  @override
  Future<void> resetTachieTransform(String characterName) async {
    _runtimeConfig = _runtimeConfig.copyWith(
      tachieSize: 100,
      tachieOffsetX: 0,
      tachieOffsetY: 0,
    );
  }

  @override
  Future<void> saveCharacterProvider(
    String characterName,
    LlmProviderType provider,
  ) async {
    _runtimeConfig = _runtimeConfig.copyWith(
      serverSelect: provider.configKey,
      modelSelect: '',
    );
  }

  @override
  Future<void> saveCharacterModel(String characterName, String modelId) async {
    _runtimeConfig = _runtimeConfig.copyWith(modelSelect: modelId);
  }

  @override
  Future<void> saveCharacterVitsEnabled(
    String characterName,
    bool enabled,
  ) async {
    _runtimeConfig = _runtimeConfig.copyWith(vitsEnable: enabled);
  }

  @override
  Future<void> saveCharacterVitsModelAndSpeaker(
    String characterName,
    String modelAndSpeaker,
  ) async {
    _runtimeConfig = _runtimeConfig.copyWith(vitsMasSelect: modelAndSpeaker);
  }

  @override
  Future<void> saveTachieAnimationBinding(
    String characterName,
    String actionName,
    String? animationUniqueKey,
  ) async {
    final Map<String, String> map = Map<String, String>.from(
      _runtimeConfig.tachieAnimations,
    );
    final String trimmedKey = (animationUniqueKey ?? '').trim();
    if (trimmedKey.isEmpty) {
      map.remove(actionName);
    } else {
      map[actionName] = trimmedKey;
    }
    _runtimeConfig = _runtimeConfig.copyWith(tachieAnimations: map);
  }

  @override
  Future<AnimePluginRegistry> loadAnimePluginRegistry() async {
    return const AnimePluginRegistry.empty();
  }

  @override
  Future<String> installAnimePluginFromFile(String sourceFilePath) async {
    throw const CharacterImportException('Web 预览模式暂不支持导入动画插件');
  }

  @override
  Future<void> deleteAnimePluginByName(String pluginName) async {
    throw const CharacterImportException('Web 预览模式暂不支持删除动画插件');
  }

  @override
  Future<String> importCharacterArchive(
    Uint8List bytes, {
    required String archiveName,
  }) async {
    throw const CharacterImportException('Web 预览模式暂不支持导入角色包');
  }

  @override
  Future<List<String>> getTachieMoodNames(String characterName) async {
    return const <String>['default'];
  }

  @override
  Future<File?> resolveTachieFile(String characterName, String moodName) async {
    return null;
  }
}

class WebPreviewConversationRepository extends ConversationRepository {
  WebPreviewConversationRepository(super.characterRepository)
    : super.webPreview();

  final List<String> _history = <String>[];

  @override
  Future<ContextHistory> loadHistory(String characterName) async {
    return ContextHistory(history: List<String>.from(_history));
  }

  @override
  Future<String> buildUserMessageWithContext(String input) async {
    if (_history.isEmpty) {
      return input;
    }
    return '以下是你和用户最近的对话，请继续上下文并保持人设一致：\n'
        '${_history.join('\n')}\n\n'
        '用户当前输入：$input';
  }

  @override
  Future<void> appendUserLine(String text) async {
    _history.add(
      HistoryEntry(speaker: HistorySpeaker.user, text: text).toRawLine(),
    );
  }

  @override
  Future<void> appendRoleLine(String text) async {
    _history.add(
      HistoryEntry(speaker: HistorySpeaker.role, text: text).toRawLine(),
    );
  }

  @override
  Future<void> updateLine(int index, String newText) async {
    if (index < 0 || index >= _history.length) {
      return;
    }
    final HistoryEntry originalEntry = HistoryEntry.fromRawLine(
      _history[index],
    );
    _history[index] = HistoryEntry(
      speaker: originalEntry.speaker,
      text: newText,
    ).toRawLine();
  }

  @override
  Future<void> deleteLine(int index) async {
    if (index < 0 || index >= _history.length) {
      return;
    }
    _history.removeAt(index);
  }

  @override
  Future<void> rollbackTo(int index) async {
    if (index <= 0) {
      _history.clear();
      return;
    }
    if (index >= _history.length) {
      return;
    }
    _history.removeRange(index, _history.length);
  }

  @override
  Future<void> clearHistory() async {
    _history.clear();
  }
}

class _ArchiveImportEntry {
  const _ArchiveImportEntry({required this.file, required this.pathSegments});

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
