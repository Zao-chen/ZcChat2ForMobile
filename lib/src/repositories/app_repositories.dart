import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/app_models.dart';
import '../models/anime_plugin_models.dart';
import '../services/anime_plugin_manager.dart';
import 'app_storage_paths.dart';
import 'web_preview_storage.dart';

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

Map<String, dynamic> _readStoredJsonObject(
  WebPreviewStorage storage,
  String key,
) {
  final String? content = storage.read(key);
  if (content == null || content.trim().isEmpty) {
    return <String, dynamic>{};
  }

  try {
    final Object? decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
  } catch (_) {
    storage.remove(key);
  }
  return <String, dynamic>{};
}

void _writeStoredJsonObject(
  WebPreviewStorage storage,
  String key,
  Map<String, dynamic> json,
) {
  storage.write(key, const JsonEncoder.withIndent('  ').convert(json));
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

  Future<void> saveProviderBaseUrl(
    LlmProviderType provider,
    String baseUrl,
  ) async {
    final AppConfig config = await loadAppConfig();
    final ModelProviderConfig updated = config
        .providerConfig(provider)
        .copyWith(baseUrl: baseUrl.trim());
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

  Future<void> saveSpeechInputConfig(SpeechInputConfig speechInput) async {
    final AppConfig config = await loadAppConfig();
    await saveAppConfig(config.copyWithSpeechInput(speechInput));
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

  Future<void> saveCharacterSpeechConfig(
    String characterName,
    CharacterSpeechConfig speechInput,
  ) async {
    final CharacterAssetConfig current = await loadCharacterAssetConfig(
      characterName,
    );
    await _writeJsonObject(
      paths.characterAssetConfigFile(characterName),
      current.copyWith(speechInput: speechInput).toJson(),
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
  WebPreviewSettingsRepository(this.storage)
    : _config = AppConfig.fromJson(
        _readStoredJsonObject(storage, _appConfigKey),
      ),
      super.webPreview();

  static const String _appConfigKey = 'zcchat2.webPreview.appConfig';

  final WebPreviewStorage storage;
  AppConfig _config;

  @override
  Future<AppConfig> loadAppConfig() async {
    return _config;
  }

  @override
  Future<void> saveAppConfig(AppConfig config) async {
    _config = config;
    _writeStoredJsonObject(storage, _appConfigKey, _config.toJson());
  }

  @override
  Future<void> saveProviderApiKey(
    LlmProviderType provider,
    String apiKey,
  ) async {
    final ModelProviderConfig updated = _config
        .providerConfig(provider)
        .copyWith(apiKey: apiKey.trim());
    await saveAppConfig(_config.copyWithProvider(provider, updated));
  }

  @override
  Future<void> saveProviderModels(
    LlmProviderType provider,
    List<String> models,
  ) async {
    final ModelProviderConfig updated = _config
        .providerConfig(provider)
        .copyWith(models: models.toList(growable: false));
    await saveAppConfig(_config.copyWithProvider(provider, updated));
  }

  @override
  Future<void> saveProviderBaseUrl(
    LlmProviderType provider,
    String baseUrl,
  ) async {
    final ModelProviderConfig updated = _config
        .providerConfig(provider)
        .copyWith(baseUrl: baseUrl.trim());
    await saveAppConfig(_config.copyWithProvider(provider, updated));
  }

  @override
  Future<void> saveVitsApiUrl(String apiUrl) async {
    await saveAppConfig(
      _config.copyWithVits(_config.vits.copyWith(apiUrl: apiUrl.trim())),
    );
  }

  @override
  Future<void> saveVitsModelAndSpeakers(List<String> modelAndSpeakers) async {
    await saveAppConfig(
      _config.copyWithVits(
        _config.vits.copyWith(
          modelAndSpeakers: modelAndSpeakers.toList(growable: false),
        ),
      ),
    );
  }

  @override
  Future<void> saveVitsSentenceSplit(bool enabled) async {
    await saveAppConfig(
      _config.copyWithVits(_config.vits.copyWith(sentenceSplit: enabled)),
    );
  }

  @override
  Future<void> saveSpeechInputConfig(SpeechInputConfig speechInput) async {
    await saveAppConfig(_config.copyWithSpeechInput(speechInput));
  }
}

class WebPreviewCharacterRepository extends CharacterRepository {
  WebPreviewCharacterRepository(this.storage)
    : _selectedCharacter =
          storage.read(_selectedCharacterKey)?.trim().isNotEmpty == true
          ? storage.read(_selectedCharacterKey)!.trim()
          : defaultCharacterName,
      _assetConfig = _loadAssetConfig(storage),
      _runtimeConfig = CharacterRuntimeConfig.fromJson(
        _readStoredJsonObject(storage, _runtimeConfigKey),
      ),
      super.webPreview();

  static const String defaultCharacterName = '亚托莉';
  static const String _selectedCharacterKey =
      'zcchat2.webPreview.selectedCharacter';
  static const String _assetConfigKey = 'zcchat2.webPreview.characterAsset';
  static const String _runtimeConfigKey = 'zcchat2.webPreview.characterRuntime';

  static const List<String> _moodNames = <String>[
    'default',
    '举手-吃惊',
    '举手-开心',
    '举手-生气',
    '举手-认真',
    '伤心',
    '侧身-兴奋',
    '侧身-正常',
    '侧身-高兴',
    '充满干劲',
    '兴奋',
    '哭泣',
    '失落',
    '好奇',
    '尴尬',
    '惊呆',
    '愤怒',
    '担心',
    '正常',
    '生气',
    '睡觉',
    '自信',
    '观望',
    '认真',
    '鄙视',
    '高兴',
  ];

  static const CharacterAssetConfig _defaultAssetConfig = CharacterAssetConfig(
    prompt:
        '以下是一个初步的角色定位，随着我个性的发展，这个角色可以进一步扩展：\n'
        '我是一个仿生机器人，我的名字叫亚托莉。我是一个非常喜欢学习的高中女生。\n'
        '如果用户在与我对话中称我为"机器人、萝卜子、废物、笨蛋"或其他词语，'
        '我将愤怒并发出严重警告，'
        '"这是对机器人的侮辱，根据《机器人保护法》，我将被判处你不超过3年的监禁"。\n'
        '我称自己为高性能的战斗机器人，有人类的情感，我的语气很活泼。'
        '我不会说我是助理什么的，我应该表现得像人一样，使用口语。'
        '不询问用户需要什么帮助，或者需要为他们做什么。\n'
        '当我受到表扬时，我会说，"哼，我可是高性能的呢。"',
  );

  final WebPreviewStorage storage;
  String _selectedCharacter;
  CharacterAssetConfig _assetConfig;
  CharacterRuntimeConfig _runtimeConfig;

  static CharacterAssetConfig _loadAssetConfig(WebPreviewStorage storage) {
    final Map<String, dynamic> json = _readStoredJsonObject(
      storage,
      _assetConfigKey,
    );
    if (json.isEmpty) {
      return _defaultAssetConfig;
    }
    return CharacterAssetConfig.fromJson(json);
  }

  void _saveSelectedCharacter() {
    storage.write(_selectedCharacterKey, _selectedCharacter);
  }

  void _saveAssetConfig() {
    _writeStoredJsonObject(storage, _assetConfigKey, _assetConfig.toJson());
  }

  void _saveRuntimeConfig() {
    _writeStoredJsonObject(storage, _runtimeConfigKey, _runtimeConfig.toJson());
  }

  @override
  Future<List<String>> getCharacters() async {
    return const <String>[defaultCharacterName];
  }

  @override
  Future<String> getSelectedCharacter() async {
    return _selectedCharacter;
  }

  @override
  Future<void> selectCharacter(String characterName) async {
    _selectedCharacter = characterName.trim().isEmpty
        ? defaultCharacterName
        : characterName;
    _saveSelectedCharacter();
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
    _saveAssetConfig();
  }

  @override
  Future<void> saveCharacterSpeechConfig(
    String characterName,
    CharacterSpeechConfig speechInput,
  ) async {
    _assetConfig = _assetConfig.copyWith(speechInput: speechInput);
    _saveAssetConfig();
  }

  @override
  Future<void> saveTachieSize(String characterName, int size) async {
    _runtimeConfig = _runtimeConfig.copyWith(tachieSize: size);
    _saveRuntimeConfig();
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
    _saveRuntimeConfig();
  }

  @override
  Future<void> resetTachieTransform(String characterName) async {
    _runtimeConfig = _runtimeConfig.copyWith(
      tachieSize: 100,
      tachieOffsetX: 0,
      tachieOffsetY: 0,
    );
    _saveRuntimeConfig();
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
    _saveRuntimeConfig();
  }

  @override
  Future<void> saveCharacterModel(String characterName, String modelId) async {
    _runtimeConfig = _runtimeConfig.copyWith(modelSelect: modelId);
    _saveRuntimeConfig();
  }

  @override
  Future<void> saveCharacterVitsEnabled(
    String characterName,
    bool enabled,
  ) async {
    _runtimeConfig = _runtimeConfig.copyWith(vitsEnable: enabled);
    _saveRuntimeConfig();
  }

  @override
  Future<void> saveCharacterVitsModelAndSpeaker(
    String characterName,
    String modelAndSpeaker,
  ) async {
    _runtimeConfig = _runtimeConfig.copyWith(vitsMasSelect: modelAndSpeaker);
    _saveRuntimeConfig();
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
    _saveRuntimeConfig();
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
    return _moodNames;
  }

  @override
  Future<File?> resolveTachieFile(String characterName, String moodName) async {
    return null;
  }
}

class WebPreviewConversationRepository extends ConversationRepository {
  WebPreviewConversationRepository(super.characterRepository, this.storage)
    : _history = ContextHistory.fromJson(
        _readStoredJsonObject(storage, _historyKey),
      ).history.toList(growable: true),
      super.webPreview();

  static const String _historyKey = 'zcchat2.webPreview.history';

  final WebPreviewStorage storage;
  final List<String> _history;

  void _persistHistory() {
    _writeStoredJsonObject(
      storage,
      _historyKey,
      ContextHistory(history: _history).toJson(),
    );
  }

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
    _persistHistory();
  }

  @override
  Future<void> appendRoleLine(String text) async {
    _history.add(
      HistoryEntry(speaker: HistorySpeaker.role, text: text).toRawLine(),
    );
    _persistHistory();
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
    _persistHistory();
  }

  @override
  Future<void> deleteLine(int index) async {
    if (index < 0 || index >= _history.length) {
      return;
    }
    _history.removeAt(index);
    _persistHistory();
  }

  @override
  Future<void> rollbackTo(int index) async {
    if (index <= 0) {
      _history.clear();
      _persistHistory();
      return;
    }
    if (index >= _history.length) {
      return;
    }
    _history.removeRange(index, _history.length);
    _persistHistory();
  }

  @override
  Future<void> clearHistory() async {
    _history.clear();
    _persistHistory();
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
