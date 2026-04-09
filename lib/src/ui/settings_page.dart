import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_models.dart';
import '../models/anime_plugin_models.dart';
import '../repositories/app_repositories.dart';
import '../services/llm_service.dart';
import '../services/vits_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.characterRepository,
    required this.settingsRepository,
    required this.services,
    required this.vitsService,
    super.key,
  });

  final CharacterRepository characterRepository;
  final SettingsRepository settingsRepository;
  final Map<LlmProviderType, LlmService> services;
  final VitsService vitsService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: <Widget>[
          _SettingsEntry(
            title: '对话模型',
            subtitle: 'OpenAI / DeepSeek',
            icon: Icons.chat_bubble_outline_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LlmSettingsHomePage(
                    settingsRepository: settingsRepository,
                    services: services,
                  ),
                ),
              );
            },
          ),
          _SettingsEntry(
            title: '语言合成',
            subtitle: 'vits-simple-api',
            icon: Icons.record_voice_over_outlined,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VitsSettingsHomePage(
                    settingsRepository: settingsRepository,
                    vitsService: vitsService,
                  ),
                ),
              );
            },
          ),
          _SettingsEntry(
            title: '插件配置',
            subtitle: '动画插件管理与详情',
            icon: Icons.extension_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PluginSettingsPage(
                    characterRepository: characterRepository,
                  ),
                ),
              );
            },
          ),
          _SettingsEntry(
            title: '角色设置',
            subtitle: '当前角色、提示词、立绘大小、运行配置',
            icon: Icons.face_retouching_natural_outlined,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CharacterSettingsPage(
                    characterRepository: characterRepository,
                    settingsRepository: settingsRepository,
                  ),
                ),
              );
            },
          ),
          _SettingsEntry(
            title: '关于',
            subtitle: '版本信息、更新检查、项目链接',
            icon: Icons.info_outline_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AboutPage(characterRepository: characterRepository),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class PluginSettingsPage extends StatefulWidget {
  const PluginSettingsPage({required this.characterRepository, super.key});

  final CharacterRepository characterRepository;

  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class AboutPage extends StatefulWidget {
  const AboutPage({required this.characterRepository, super.key});

  final CharacterRepository characterRepository;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static final Uri _repoUri = Uri.parse(
    'https://github.com/Zao-chen/ZcChat2ForMobile',
  );
  static final Uri _issueUri = Uri.parse(
    'https://github.com/Zao-chen/ZcChat2ForMobile/issues/new/choose',
  );
  static final Uri _releaseApiUri = Uri.parse(
    'https://api.github.com/repos/Zao-chen/ZcChat2ForMobile/releases',
  );

  bool _isLoading = true;
  bool _isCheckingUpdate = false;
  bool _isDownloadingApk = false;
  bool _downloadProgressKnown = false;
  double _downloadProgress = 0;
  String _appVersion = '0.0.0';
  String? _latestTagName;
  Uri? _latestReleaseUrl;
  Uri? _latestApkUrl;
  String? _statusText;
  String? _errorText;
  List<_ReleaseInfo> _releases = const <_ReleaseInfo>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _loadVersion();
    await _checkUpdate();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadVersion() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    _appVersion = _normalizeVersion(info.version);
  }

  Future<void> _checkUpdate() async {
    if (mounted) {
      setState(() {
        _isCheckingUpdate = true;
        _errorText = null;
      });
    }

    try {
      final http.Response response = await http.get(_releaseApiUri);
      if (response.statusCode != 200) {
        throw Exception('请求失败(${response.statusCode})');
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('更新数据格式错误');
      }

      final List<_ReleaseInfo> releaseList = <_ReleaseInfo>[];
      bool matchedCurrentVersion = false;
      for (final Object item in decoded) {
        if (item is! Map) {
          continue;
        }
        final Map<dynamic, dynamic> rawMap = item;
        final String tagName = _normalizeVersion(
          rawMap['tag_name']?.toString() ?? '',
        );
        final String name = (rawMap['name']?.toString() ?? '').trim();
        final String publishedAtRaw = rawMap['published_at']?.toString() ?? '';
        final String publishedDate = publishedAtRaw.length >= 10
            ? publishedAtRaw.substring(0, 10)
            : '';
        final String htmlUrl = rawMap['html_url']?.toString() ?? '';
        final List<String> nameTokens = name.split(' ');
        final String firstToken = nameTokens.isEmpty ? '' : nameTokens.first;
        final String versionText = tagName.isNotEmpty
            ? tagName
            : _normalizeVersion(firstToken);
        final bool isCurrentVersion =
            !matchedCurrentVersion && versionText == _appVersion;
        if (isCurrentVersion) {
          matchedCurrentVersion = true;
        }
        releaseList.add(
          _ReleaseInfo(
            version: versionText,
            title: name.isEmpty ? versionText : name,
            date: publishedDate,
            isCurrent: isCurrentVersion,
            htmlUrl: htmlUrl,
          ),
        );
      }

      Uri? latestUrl;
      Uri? latestApkUrl;
      String? latestTag;
      if (releaseList.isNotEmpty && decoded.first is Map) {
        latestTag = releaseList.first.version;
        if (releaseList.first.htmlUrl.isNotEmpty) {
          latestUrl = Uri.tryParse(releaseList.first.htmlUrl);
        }
        final Map<dynamic, dynamic> firstRelease =
            decoded.first as Map<dynamic, dynamic>;
        final Object? assetsObj = firstRelease['assets'];
        if (assetsObj is List) {
          for (final Object assetObj in assetsObj) {
            if (assetObj is! Map) {
              continue;
            }
            final String assetName = (assetObj['name']?.toString() ?? '')
                .toLowerCase();
            if (!assetName.endsWith('.apk')) {
              continue;
            }
            final String url =
                assetObj['browser_download_url']?.toString() ?? '';
            if (url.isEmpty) {
              continue;
            }
            latestApkUrl = Uri.tryParse(url);
            break;
          }
        }
      }

      final String statusText;
      if (latestTag == null || latestTag.isEmpty) {
        statusText = '获取新版本失败';
      } else if (latestTag != _appVersion) {
        statusText = '发现新版本 v$latestTag';
      } else {
        statusText = '当前为最新正式版';
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _releases = releaseList;
        _latestTagName = latestTag;
        _latestReleaseUrl = latestUrl;
        _latestApkUrl = latestApkUrl;
        _statusText = statusText;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '更新检查失败: $error';
        _statusText = '获取新版本失败';
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCheckingUpdate = false;
      });
    }
  }

  String _normalizeVersion(String version) {
    final String trimmed = version.trim();
    if (trimmed.toLowerCase().startsWith('v')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }

  Future<void> _openUrl(Uri uri) async {
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开链接: $uri')));
    }
  }

  Future<void> _openLogPath() async {
    final File logFile = File(
      '${widget.characterRepository.paths.rootDirectory.path}${Platform.pathSeparator}log.txt',
    );
    if (await logFile.exists()) {
      await _openUrl(Uri.file(logFile.path));
      return;
    }

    await Clipboard.setData(ClipboardData(text: logFile.path));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('日志文件不存在，路径已复制: ${logFile.path}')));
  }

  Future<void> _onUpdateButtonPressed() async {
    final bool hasNewVersion =
        _latestTagName != null &&
        _latestTagName!.isNotEmpty &&
        _latestTagName != _appVersion;
    if (hasNewVersion && _latestApkUrl != null) {
      await _downloadAndInstallLatestApk();
      return;
    }
    if (hasNewVersion && _latestReleaseUrl != null) {
      await _openUrl(_latestReleaseUrl!);
      return;
    }
    await _checkUpdate();
  }

  Future<void> _downloadAndInstallLatestApk() async {
    if (_latestApkUrl == null || _isDownloadingApk) {
      return;
    }

    setState(() {
      _isDownloadingApk = true;
      _downloadProgressKnown = false;
      _downloadProgress = 0;
      _errorText = null;
    });

    final http.Client client = http.Client();
    IOSink? sink;
    try {
      final http.Request request = http.Request('GET', _latestApkUrl!);
      final http.StreamedResponse response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('下载失败(${response.statusCode})');
      }

      final int total = response.contentLength ?? 0;
      final String apkName = _latestApkUrl!.pathSegments.isEmpty
          ? 'zcchat2_update.apk'
          : _latestApkUrl!.pathSegments.last;

      final Directory saveDirectory;
      if (Platform.isAndroid) {
        saveDirectory =
            await getExternalStorageDirectory() ??
            await getTemporaryDirectory();
      } else {
        saveDirectory = await getTemporaryDirectory();
      }
      await saveDirectory.create(recursive: true);
      final File apkFile = File(
        '${saveDirectory.path}${Platform.pathSeparator}$apkName',
      );
      sink = apkFile.openWrite();

      int received = 0;
      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (!mounted) {
          continue;
        }
        if (total > 0) {
          setState(() {
            _downloadProgressKnown = true;
            _downloadProgress = (received / total).clamp(0, 1);
          });
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final OpenResult result = await OpenFilex.open(apkFile.path);
      if (!mounted) {
        return;
      }
      if (result.type != ResultType.done) {
        setState(() {
          _errorText = '安装器启动失败: ${result.message}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = '下载失败: $error';
        });
      }
    } finally {
      if (sink != null) {
        await sink.close();
      }
      client.close();
      if (mounted) {
        setState(() {
          _isDownloadingApk = false;
          _downloadProgressKnown = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bool hasNewVersion =
        _latestTagName != null &&
        _latestTagName!.isNotEmpty &&
        _latestTagName != _appVersion;
    final String updateButtonText = _isDownloadingApk
        ? (_downloadProgressKnown
              ? '下载中 ${(100 * _downloadProgress).toStringAsFixed(0)}%'
              : '下载中...')
        : hasNewVersion
        ? (_latestApkUrl != null
              ? '发现新版本 v$_latestTagName（下载APK）'
              : '发现新版本 v$_latestTagName')
        : (_statusText ?? '检查更新');

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('ZcChat2', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: 8),
              Text(
                'v$_appVersion',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('一个模仿 Galgame 演出效果的 AI 桌宠'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: () => _openUrl(_repoUri),
                icon: const Icon(Icons.code_rounded),
                label: const Text('GitHub'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openUrl(_issueUri),
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('Issue'),
              ),
              FilledButton.tonalIcon(
                onPressed: _openLogPath,
                icon: const Icon(Icons.description_outlined),
                label: const Text('软件日志'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (_isCheckingUpdate || _isDownloadingApk)
                ? null
                : _onUpdateButtonPressed,
            icon: (_isCheckingUpdate || _isDownloadingApk)
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt_rounded),
            label: Text(updateButtonText),
          ),
          if (_isCheckingUpdate) ...<Widget>[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_isDownloadingApk) ...<Widget>[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _downloadProgressKnown ? _downloadProgress : null,
            ),
          ],
          if (_errorText != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_errorText!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 18),
          Text('更新日志', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_releases.isEmpty)
            const Text('暂无可展示的发布记录')
          else
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FixedColumnWidth(44),
                1: FixedColumnWidth(76),
                2: FixedColumnWidth(96),
                3: FlexColumnWidth(),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: Color(0x1A000000),
                  width: 1,
                ),
              ),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: <TableRow>[
                const TableRow(
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('状态'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('版本'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('日期'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('标题'),
                    ),
                  ],
                ),
                ..._releases.map(
                  (_ReleaseInfo item) => TableRow(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(item.isCurrent ? '■' : '□'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(item.version),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(item.date),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          item.title,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReleaseInfo {
  const _ReleaseInfo({
    required this.version,
    required this.title,
    required this.date,
    required this.isCurrent,
    required this.htmlUrl,
  });

  final String version;
  final String title;
  final String date;
  final bool isCurrent;
  final String htmlUrl;
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  bool _isLoading = true;
  AnimePluginRegistry _registry = const AnimePluginRegistry.empty();

  @override
  void initState() {
    super.initState();
    _reloadPlugins();
  }

  Future<void> _reloadPlugins() async {
    final AnimePluginRegistry registry = await widget.characterRepository
        .loadAnimePluginRegistry();
    if (!mounted) {
      return;
    }

    setState(() {
      _registry = registry;
      _isLoading = false;
    });
  }

  Future<void> _importAnimePlugin() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final PlatformFile picked = result.files.single;
    if (picked.path == null || picked.path!.trim().isEmpty) {
      _showSnackBar('无法读取插件文件路径');
      return;
    }

    try {
      final String pluginName = await widget.characterRepository
          .installAnimePluginFromFile(picked.path!);
      await _reloadPlugins();
      _showSnackBar('已导入插件: $pluginName');
    } on CharacterImportException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('导入失败: $error');
    }
  }

  Future<void> _deletePlugin(String pluginName) async {
    try {
      await widget.characterRepository.deleteAnimePluginByName(pluginName);
      await _reloadPlugins();
      _showSnackBar('已删除插件: $pluginName');
    } on CharacterImportException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('删除失败: $error');
    }
  }

  void _openPluginDetail(String pluginName) {
    for (final AnimePluginDefinition plugin in _registry.plugins) {
      if (plugin.name == pluginName) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AnimePluginDetailPage(plugin: plugin),
          ),
        );
        return;
      }
    }
    _showSnackBar('未找到插件，可能已被删除');
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('插件配置')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('已安装动画插件', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _reloadPlugins,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _importAnimePlugin,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('导入插件'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_registry.plugins.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('暂无动画插件，请先导入 json 插件文件。'),
              ),
            if (_registry.lastErrors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _registry.lastErrors
                      .map(
                        (String error) => Text(
                          '[错误] $error',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: _registry.plugins.length,
                itemBuilder: (BuildContext context, int index) {
                  final AnimePluginDefinition plugin = _registry.plugins[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  plugin.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '版本: ${plugin.version}  作者: ${plugin.author}',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          TextButton(
                            onPressed: () => _deletePlugin(plugin.name),
                            child: const Text('删除插件'),
                          ),
                          const SizedBox(width: 6),
                          FilledButton.tonal(
                            onPressed: () => _openPluginDetail(plugin.name),
                            child: const Text('查看动画'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimePluginDetailPage extends StatelessWidget {
  const AnimePluginDetailPage({required this.plugin, super.key});

  final AnimePluginDefinition plugin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('动画 - ${plugin.name}')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: plugin.animations.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          final AnimePluginAnimation animation = plugin.animations[index];
          final String uniqueKey = animation.buildUniqueKey(plugin.name);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(uniqueKey),
            subtitle: Text('步骤数: ${animation.steps.length}'),
          );
        },
      ),
    );
  }
}

class LlmSettingsHomePage extends StatelessWidget {
  const LlmSettingsHomePage({
    required this.settingsRepository,
    required this.services,
    super.key,
  });

  final SettingsRepository settingsRepository;
  final Map<LlmProviderType, LlmService> services;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('对话模型')),
      body: ListView(
        children: <Widget>[
          for (final LlmProviderType provider in LlmProviderType.values)
            _SettingsEntry(
              title: provider.label,
              subtitle: '配置 API Key 并获取模型列表',
              icon: provider == LlmProviderType.openAI
                  ? Icons.auto_awesome_outlined
                  : Icons.memory_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProviderSettingsPage(
                      provider: provider,
                      settingsRepository: settingsRepository,
                      service: services[provider]!,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class ProviderSettingsPage extends StatefulWidget {
  const ProviderSettingsPage({
    required this.provider,
    required this.settingsRepository,
    required this.service,
    super.key,
  });

  final LlmProviderType provider;
  final SettingsRepository settingsRepository;
  final LlmService service;

  @override
  State<ProviderSettingsPage> createState() => _ProviderSettingsPageState();
}

class _ProviderSettingsPageState extends State<ProviderSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();

  bool _isLoading = true;
  bool _isFetchingModels = false;
  AppConfig _appConfig = AppConfig.initial();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AppConfig config = await widget.settingsRepository.loadAppConfig();
    _appConfig = config;
    _apiKeyController.text = config.providerConfig(widget.provider).apiKey;
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveApiKey(String value) async {
    await widget.settingsRepository.saveProviderApiKey(widget.provider, value);
    _appConfig = await widget.settingsRepository.loadAppConfig();
  }

  Future<void> _fetchModels() async {
    final String apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnackBar('请先填写 API Key');
      return;
    }

    setState(() {
      _isFetchingModels = true;
    });

    try {
      final List<String> models = await widget.service.fetchModels(apiKey);
      await widget.settingsRepository.saveProviderApiKey(
        widget.provider,
        apiKey,
      );
      await widget.settingsRepository.saveProviderModels(
        widget.provider,
        models,
      );
      _appConfig = await widget.settingsRepository.loadAppConfig();
      _showSnackBar(models.isEmpty ? '未获取到模型列表' : '模型列表已刷新');
    } on LlmException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('获取模型失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<String> models = _appConfig
        .providerConfig(widget.provider)
        .models;

    return Scaffold(
      appBar: AppBar(title: Text(widget.provider.label)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _SettingsSection(
            title: 'API Key',
            child: TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                filled: true,
              ),
              onChanged: _saveApiKey,
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '模型列表',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _isFetchingModels ? null : _fetchModels,
                  icon: _isFetchingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_download_rounded),
                  label: const Text('获取'),
                ),
                const SizedBox(height: 12),
                if (models.isEmpty)
                  const Text('暂无模型')
                else
                  ...models.map(
                    (String model) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(model),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VitsSettingsHomePage extends StatefulWidget {
  const VitsSettingsHomePage({
    required this.settingsRepository,
    required this.vitsService,
    super.key,
  });

  final SettingsRepository settingsRepository;
  final VitsService vitsService;

  @override
  State<VitsSettingsHomePage> createState() => _VitsSettingsHomePageState();
}

class _VitsSettingsHomePageState extends State<VitsSettingsHomePage> {
  bool _isLoading = true;
  AppConfig _appConfig = AppConfig.initial();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final AppConfig config = await widget.settingsRepository.loadAppConfig();
    _appConfig = config;
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSentenceSplit(bool enabled) async {
    setState(() {
      _appConfig = _appConfig.copyWithVits(
        _appConfig.vits.copyWith(sentenceSplit: enabled),
      );
    });
    await widget.settingsRepository.saveVitsSentenceSplit(enabled);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('\u8bed\u8a00\u5408\u6210')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _SettingsSection(
            title: '\u63a5\u53e3',
            child: _SettingsEntry(
              title: 'vits-simple-api',
              subtitle: 'API \u5730\u5740\u3001\u89d2\u8272\u5217\u8868',
              icon: Icons.graphic_eq_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VitsSimpleApiSettingsPage(
                      settingsRepository: widget.settingsRepository,
                      vitsService: widget.vitsService,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '\u8bbe\u7f6e',
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _appConfig.vits.sentenceSplit,
              title: const Text('\u5207\u5206\u751f\u6210\u8bed\u97f3'),
              subtitle: const Text(
                '\u5bf9\u8bdd\u65f6\u6309\u65e5\u8bed\u53e5\u5b50\u5206\u6bb5\u8bf7\u6c42\u5e76\u64ad\u653e',
              ),
              onChanged: _toggleSentenceSplit,
            ),
          ),
        ],
      ),
    );
  }
}

class VitsSimpleApiSettingsPage extends StatefulWidget {
  const VitsSimpleApiSettingsPage({
    required this.settingsRepository,
    required this.vitsService,
    super.key,
  });

  final SettingsRepository settingsRepository;
  final VitsService vitsService;

  @override
  State<VitsSimpleApiSettingsPage> createState() =>
      _VitsSimpleApiSettingsPageState();
}

class _VitsSimpleApiSettingsPageState extends State<VitsSimpleApiSettingsPage> {
  final TextEditingController _apiUrlController = TextEditingController();

  bool _isLoading = true;
  bool _isFetchingSpeakers = false;
  AppConfig _appConfig = AppConfig.initial();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AppConfig config = await widget.settingsRepository.loadAppConfig();
    _appConfig = config;
    _apiUrlController.text = config.vits.apiUrl;
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveApiUrl(String value) async {
    await widget.settingsRepository.saveVitsApiUrl(value);
    _appConfig = await widget.settingsRepository.loadAppConfig();
  }

  Future<void> _fetchModelAndSpeakers() async {
    final String apiUrl = _apiUrlController.text.trim();
    if (apiUrl.isEmpty) {
      _showSnackBar('请先填写 API 地址');
      return;
    }

    setState(() {
      _isFetchingSpeakers = true;
    });

    try {
      final List<String> modelAndSpeakers = await widget.vitsService
          .fetchModelAndSpeakers(apiUrl);
      await widget.settingsRepository.saveVitsApiUrl(apiUrl);
      await widget.settingsRepository.saveVitsModelAndSpeakers(
        modelAndSpeakers,
      );
      _appConfig = await widget.settingsRepository.loadAppConfig();
      _showSnackBar(modelAndSpeakers.isEmpty ? '未获取到角色列表' : '角色列表已刷新');
    } on VitsException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('获取角色列表失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingSpeakers = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<String> modelAndSpeakers = _appConfig.vits.modelAndSpeakers;

    return Scaffold(
      appBar: AppBar(title: const Text('vits-simple-api')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _SettingsSection(
            title: 'API 地址',
            child: TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API Url',
                filled: true,
              ),
              onChanged: _saveApiUrl,
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '模型和说话人',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _isFetchingSpeakers
                      ? null
                      : _fetchModelAndSpeakers,
                  icon: _isFetchingSpeakers
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_download_rounded),
                  label: const Text('获取'),
                ),
                const SizedBox(height: 12),
                if (modelAndSpeakers.isEmpty)
                  const Text('暂无角色列表')
                else
                  ...modelAndSpeakers.map(
                    (String item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CharacterSettingsPage extends StatefulWidget {
  const CharacterSettingsPage({
    required this.characterRepository,
    required this.settingsRepository,
    super.key,
  });

  final CharacterRepository characterRepository;
  final SettingsRepository settingsRepository;

  @override
  State<CharacterSettingsPage> createState() => _CharacterSettingsPageState();
}

class _CharacterSettingsPageState extends State<CharacterSettingsPage> {
  final TextEditingController _promptController = TextEditingController();

  bool _isLoading = true;
  bool _isImporting = false;
  List<String> _characters = const <String>[];
  String _selectedCharacter = 'test';
  CharacterAssetConfig _assetConfig = const CharacterAssetConfig();
  CharacterRuntimeConfig _runtimeConfig = const CharacterRuntimeConfig();
  AppConfig _appConfig = AppConfig.initial();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<String> characters = await widget.characterRepository
        .getCharacters();
    final String selectedCharacter = await widget.characterRepository
        .getSelectedCharacter();
    final CharacterAssetConfig assetConfig = await widget.characterRepository
        .loadCharacterAssetConfig(selectedCharacter);
    final CharacterRuntimeConfig runtimeConfig = await widget
        .characterRepository
        .loadCharacterRuntimeConfig(selectedCharacter);
    final AppConfig appConfig = await widget.settingsRepository.loadAppConfig();

    _characters = characters;
    _selectedCharacter = selectedCharacter;
    _assetConfig = assetConfig;
    _runtimeConfig = runtimeConfig;
    _appConfig = appConfig;
    _promptController.text = assetConfig.prompt;

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _switchCharacter(String? value) async {
    if (value == null || value == _selectedCharacter) {
      return;
    }
    await widget.characterRepository.selectCharacter(value);
    await _load();
  }

  Future<void> _importCharacter() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final PlatformFile pickedFile = result.files.single;
    Uint8List? bytes = pickedFile.bytes;
    if (bytes == null && pickedFile.path != null) {
      bytes = await File(pickedFile.path!).readAsBytes();
    }
    if (bytes == null) {
      _showSnackBar('无法读取压缩包内容');
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final String characterName = await widget.characterRepository
          .importCharacterArchive(bytes, archiveName: pickedFile.name);
      await _load();
      _showSnackBar('角色 $characterName 已导入');
    } on CharacterImportException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('导入失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _savePrompt(String value) async {
    _assetConfig = _assetConfig.copyWith(prompt: value);
    await widget.characterRepository.saveCharacterPrompt(
      _selectedCharacter,
      value,
    );
  }

  Future<void> _saveTachieSize(double value) async {
    final int size = value.round();
    setState(() {
      _runtimeConfig = _runtimeConfig.copyWith(tachieSize: size);
    });
    await widget.characterRepository.saveTachieSize(_selectedCharacter, size);
  }

  Future<void> _openTachieSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TachieSettingsPage(
          characterRepository: widget.characterRepository,
          characterName: _selectedCharacter,
        ),
      ),
    );
    await _load();
  }

  Future<void> _changeProvider(LlmProviderType? provider) async {
    if (provider == null) {
      return;
    }
    setState(() {
      _runtimeConfig = _runtimeConfig.copyWith(
        serverSelect: provider.configKey,
        modelSelect: '',
      );
    });
    await widget.characterRepository.saveCharacterProvider(
      _selectedCharacter,
      provider,
    );
    await widget.characterRepository.saveCharacterModel(_selectedCharacter, '');
    _appConfig = await widget.settingsRepository.loadAppConfig();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _changeModel(String? model) async {
    if (model == null) {
      return;
    }
    setState(() {
      _runtimeConfig = _runtimeConfig.copyWith(modelSelect: model);
    });
    await widget.characterRepository.saveCharacterModel(
      _selectedCharacter,
      model,
    );
  }

  Future<void> _changeVitsEnabled(bool enabled) async {
    setState(() {
      _runtimeConfig = _runtimeConfig.copyWith(vitsEnable: enabled);
    });
    await widget.characterRepository.saveCharacterVitsEnabled(
      _selectedCharacter,
      enabled,
    );
  }

  Future<void> _changeVitsModelAndSpeaker(String? value) async {
    if (value == null) {
      return;
    }
    setState(() {
      _runtimeConfig = _runtimeConfig.copyWith(vitsMasSelect: value);
    });
    await widget.characterRepository.saveCharacterVitsModelAndSpeaker(
      _selectedCharacter,
      value,
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<String> modelList = _appConfig
        .providerConfig(_runtimeConfig.provider)
        .models;
    final List<String> vitsList = _appConfig.vits.modelAndSpeakers;
    final String? selectedVitsItem =
        vitsList.contains(_runtimeConfig.vitsMasSelect) &&
            _runtimeConfig.vitsMasSelect.isNotEmpty
        ? _runtimeConfig.vitsMasSelect
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('角色设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _SettingsSection(
            title: '选中角色',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('character_$_selectedCharacter'),
                  initialValue: _selectedCharacter,
                  decoration: const InputDecoration(labelText: '当前角色'),
                  items: _characters
                      .map(
                        (String character) => DropdownMenuItem<String>(
                          value: character,
                          child: Text(character),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _switchCharacter,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isImporting ? null : _importCharacter,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_isImporting ? '导入中' : '导入'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '角色提示词',
            child: TextField(
              controller: _promptController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '提示词',
                alignLabelWithHint: true,
                filled: true,
              ),
              onChanged: _savePrompt,
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '立绘设置',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('立绘大小：${_runtimeConfig.tachieSize}%'),
                Slider(
                  min: 50,
                  max: 160,
                  divisions: 22,
                  value: _runtimeConfig.tachieSize.toDouble().clamp(
                    50.0,
                    160.0,
                  ),
                  label: '${_runtimeConfig.tachieSize}%',
                  onChanged: (double value) {
                    setState(() {
                      _runtimeConfig = _runtimeConfig.copyWith(
                        tachieSize: value.round(),
                      );
                    });
                  },
                  onChangeEnd: _saveTachieSize,
                ),
                _SettingsEntry(
                  title: '立绘位置与动画绑定',
                  subtitle: '位置重置、动作动画绑定',
                  icon: Icons.wallpaper_rounded,
                  onTap: _openTachieSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '对话模型',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<LlmProviderType>(
                  key: ValueKey<String>(
                    'provider_${_runtimeConfig.serverSelect}',
                  ),
                  initialValue: _runtimeConfig.provider,
                  decoration: const InputDecoration(labelText: '对话模型服务商'),
                  items: LlmProviderType.values
                      .map(
                        (LlmProviderType provider) =>
                            DropdownMenuItem<LlmProviderType>(
                              value: provider,
                              child: Text(provider.label),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: _changeProvider,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'model_${_runtimeConfig.serverSelect}_${_runtimeConfig.modelSelect}',
                  ),
                  initialValue:
                      modelList.contains(_runtimeConfig.modelSelect) &&
                          _runtimeConfig.modelSelect.isNotEmpty
                      ? _runtimeConfig.modelSelect
                      : null,
                  decoration: const InputDecoration(labelText: '当前模型'),
                  items: modelList
                      .map(
                        (String model) => DropdownMenuItem<String>(
                          value: model,
                          child: Text(model),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: modelList.isEmpty ? null : _changeModel,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '语音合成',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _runtimeConfig.vitsEnable,
                  title: const Text('启用 VITS'),
                  subtitle: const Text('播放角色回复中的日语语音'),
                  onChanged: _changeVitsEnabled,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'vits_${_runtimeConfig.vitsEnable}_${_runtimeConfig.vitsMasSelect}',
                  ),
                  initialValue: selectedVitsItem,
                  decoration: const InputDecoration(labelText: '角色语音'),
                  items: vitsList
                      .map(
                        (String item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: !_runtimeConfig.vitsEnable || vitsList.isEmpty
                      ? null
                      : _changeVitsModelAndSpeaker,
                ),
                if (vitsList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('先到“语言合成 > vits-simple-api”获取角色列表'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TachieSettingsPage extends StatefulWidget {
  const TachieSettingsPage({
    required this.characterRepository,
    required this.characterName,
    super.key,
  });

  final CharacterRepository characterRepository;
  final String characterName;

  @override
  State<TachieSettingsPage> createState() => _TachieSettingsPageState();
}

class _TachieSettingsPageState extends State<TachieSettingsPage> {
  bool _isLoading = true;
  CharacterRuntimeConfig _runtimeConfig = const CharacterRuntimeConfig();
  AnimePluginRegistry _animePluginRegistry = const AnimePluginRegistry.empty();
  List<String> _tachieActionNames = const <String>['default'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final CharacterRuntimeConfig runtimeConfig = await widget
        .characterRepository
        .loadCharacterRuntimeConfig(widget.characterName);
    final AnimePluginRegistry animePluginRegistry = await widget
        .characterRepository
        .loadAnimePluginRegistry();
    final List<String> actionNames = await widget.characterRepository
        .getTachieMoodNames(widget.characterName);

    if (!mounted) {
      return;
    }
    setState(() {
      _runtimeConfig = runtimeConfig;
      _animePluginRegistry = animePluginRegistry;
      _tachieActionNames = actionNames.isEmpty
          ? const <String>['default']
          : actionNames;
      _isLoading = false;
    });
  }

  Future<void> _resetTachieTransform() async {
    await widget.characterRepository.resetTachieTransform(widget.characterName);
    await _load();
  }

  Future<void> _changeTachieAnimationBinding(
    String actionName,
    String? animationUniqueKey,
  ) async {
    final String? normalizedValue =
        (animationUniqueKey == null || animationUniqueKey.isEmpty)
        ? null
        : animationUniqueKey;
    final Map<String, String> nextMap = Map<String, String>.from(
      _runtimeConfig.tachieAnimations,
    );
    if (normalizedValue == null) {
      nextMap.remove(actionName);
    } else {
      nextMap[actionName] = normalizedValue;
    }

    setState(() {
      _runtimeConfig = _runtimeConfig.copyWith(tachieAnimations: nextMap);
    });
    await widget.characterRepository.saveTachieAnimationBinding(
      widget.characterName,
      actionName,
      normalizedValue,
    );
  }

  String _animationLabel(String uniqueKey) {
    final AnimePluginAnimationRef? ref = _animePluginRegistry
        .tryGetAnimationByUniqueKey(uniqueKey);
    if (ref == null) {
      return uniqueKey;
    }
    return '${ref.plugin.name} / ${ref.animation.name}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text('立绘设置 - ${widget.characterName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _SettingsSection(
            title: '立绘位置',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _resetTachieTransform,
                    icon: const Icon(Icons.center_focus_strong_rounded),
                    label: const Text('重置立绘位置与缩放'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '动作动画绑定',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _animePluginRegistry.hasPlugins
                      ? '已加载插件：${_animePluginRegistry.plugins.length}，可绑定动作：${_tachieActionNames.length}'
                      : '未检测到动画插件（目录：ZcChat2/Plugin/Anime）',
                ),
                if (_animePluginRegistry.lastErrors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _animePluginRegistry.lastErrors
                          .map(
                            (String error) => Text(
                              error,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                const SizedBox(height: 12),
                for (final String actionName in _tachieActionNames) ...<Widget>[
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('tachie_bind_$actionName'),
                    initialValue:
                        _animePluginRegistry.animationUniqueKeys.contains(
                          _runtimeConfig.tachieAnimations[actionName],
                        )
                        ? _runtimeConfig.tachieAnimations[actionName]
                        : null,
                    decoration: InputDecoration(labelText: '动作: $actionName'),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('无动画'),
                      ),
                      ..._animePluginRegistry.animationUniqueKeys.map(
                        (String key) => DropdownMenuItem<String>(
                          value: key,
                          child: Text(_animationLabel(key)),
                        ),
                      ),
                    ],
                    onChanged: (String? value) {
                      _changeTachieAnimationBinding(actionName, value);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsEntry extends StatelessWidget {
  const _SettingsEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
