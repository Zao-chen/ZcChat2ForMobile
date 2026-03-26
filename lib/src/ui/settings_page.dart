import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/app_models.dart';
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
      appBar: AppBar(
        title: const Text('设置'),
      ),
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
        ],
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
      appBar: AppBar(
        title: const Text('对话模型'),
      ),
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
      await widget.settingsRepository.saveProviderApiKey(widget.provider, apiKey);
      await widget.settingsRepository.saveProviderModels(widget.provider, models);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<String> models = _appConfig.providerConfig(widget.provider).models;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.provider.label),
      ),
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

class VitsSettingsHomePage extends StatelessWidget {
  const VitsSettingsHomePage({
    required this.settingsRepository,
    required this.vitsService,
    super.key,
  });

  final SettingsRepository settingsRepository;
  final VitsService vitsService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('语言合成'),
      ),
      body: ListView(
        children: <Widget>[
          _SettingsEntry(
            title: 'vits-simple-api',
            subtitle: 'API 地址、角色列表、句切分',
            icon: Icons.graphic_eq_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VitsSimpleApiSettingsPage(
                    settingsRepository: settingsRepository,
                    vitsService: vitsService,
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

  Future<void> _toggleSentenceSplit(bool enabled) async {
    setState(() {
      _appConfig = _appConfig.copyWithVits(
        _appConfig.vits.copyWith(sentenceSplit: enabled),
      );
    });
    await widget.settingsRepository.saveVitsSentenceSplit(enabled);
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
      final List<String> modelAndSpeakers =
          await widget.vitsService.fetchModelAndSpeakers(apiUrl);
      await widget.settingsRepository.saveVitsApiUrl(apiUrl);
      await widget.settingsRepository
          .saveVitsModelAndSpeakers(modelAndSpeakers);
      _appConfig = await widget.settingsRepository.loadAppConfig();
      _showSnackBar(
        modelAndSpeakers.isEmpty ? '未获取到角色列表' : '角色列表已刷新',
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<String> modelAndSpeakers = _appConfig.vits.modelAndSpeakers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('vits-simple-api'),
      ),
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
            title: '句切分',
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _appConfig.vits.sentenceSplit,
              title: const Text('切分生成语音'),
              subtitle: const Text('对话时按日语句子分段请求并播放'),
              onChanged: _toggleSentenceSplit,
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '模型和说话人',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _isFetchingSpeakers ? null : _fetchModelAndSpeakers,
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
    final List<String> characters = await widget.characterRepository.getCharacters();
    final String selectedCharacter =
        await widget.characterRepository.getSelectedCharacter();
    final CharacterAssetConfig assetConfig =
        await widget.characterRepository.loadCharacterAssetConfig(selectedCharacter);
    final CharacterRuntimeConfig runtimeConfig =
        await widget.characterRepository.loadCharacterRuntimeConfig(selectedCharacter);
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
          .importCharacterArchive(
        bytes,
        archiveName: pickedFile.name,
      );
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
    await widget.characterRepository.saveCharacterPrompt(_selectedCharacter, value);
  }

  Future<void> _saveTachieSize(double value) async {
    final int size = value.round();
    setState(() {
      _runtimeConfig = _runtimeConfig.copyWith(tachieSize: size);
    });
    await widget.characterRepository.saveTachieSize(_selectedCharacter, size);
  }

  Future<void> _resetTachieTransform() async {
    await widget.characterRepository.resetTachieTransform(_selectedCharacter);
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
    await widget.characterRepository.saveCharacterModel(_selectedCharacter, model);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<String> modelList =
        _appConfig.providerConfig(_runtimeConfig.provider).models;
    final List<String> vitsList = _appConfig.vits.modelAndSpeakers;
    final String? selectedVitsItem =
        vitsList.contains(_runtimeConfig.vitsMasSelect) &&
                _runtimeConfig.vitsMasSelect.isNotEmpty
            ? _runtimeConfig.vitsMasSelect
            : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('角色设置'),
      ),
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
                  decoration: const InputDecoration(
                    labelText: '当前角色',
                  ),
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
                  value: _runtimeConfig.tachieSize.toDouble().clamp(50.0, 160.0),
                  label: '${_runtimeConfig.tachieSize}%',
                  onChanged: (double value) {
                    setState(() {
                      _runtimeConfig =
                          _runtimeConfig.copyWith(tachieSize: value.round());
                    });
                  },
                  onChangeEnd: _saveTachieSize,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _resetTachieTransform,
                    icon: const Icon(Icons.center_focus_strong_rounded),
                    label: const Text('重置立绘'),
                  ),
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
                  key: ValueKey<String>('provider_${_runtimeConfig.serverSelect}'),
                  initialValue: _runtimeConfig.provider,
                  decoration: const InputDecoration(
                    labelText: '对话模型服务商',
                  ),
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
                  initialValue: modelList.contains(_runtimeConfig.modelSelect) &&
                          _runtimeConfig.modelSelect.isNotEmpty
                      ? _runtimeConfig.modelSelect
                      : null,
                  decoration: const InputDecoration(
                    labelText: '当前模型',
                  ),
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
                  decoration: const InputDecoration(
                    labelText: '角色语音',
                  ),
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
  const _SettingsSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
