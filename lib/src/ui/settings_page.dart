import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/llm_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.characterRepository,
    required this.settingsRepository,
    required this.services,
    super.key,
  });

  final CharacterRepository characterRepository;
  final SettingsRepository settingsRepository;
  final Map<LlmProviderType, LlmService> services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  bool _isLoading = true;
  bool _isFetchingModels = false;
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
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _characters = await widget.characterRepository.getCharacters();
    _selectedCharacter = await widget.characterRepository.getSelectedCharacter();
    _assetConfig = await widget.characterRepository.loadCharacterAssetConfig(
      _selectedCharacter,
    );
    _runtimeConfig = await widget.characterRepository.loadCharacterRuntimeConfig(
      _selectedCharacter,
    );
    _appConfig = await widget.settingsRepository.loadAppConfig();
    _promptController.text = _assetConfig.prompt;
    _apiKeyController.text =
        _appConfig.providerConfig(_runtimeConfig.provider).apiKey;
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _switchCharacter(String? value) async {
    if (value == null || value == _selectedCharacter) {
      return;
    }
    await widget.characterRepository.selectCharacter(value);
    await _load();
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

  Future<void> _changeProvider(LlmProviderType provider) async {
    setState(() {
      _runtimeConfig = _runtimeConfig.copyWith(
        serverSelect: provider.configKey,
        modelSelect: '',
      );
      _apiKeyController.text = _appConfig.providerConfig(provider).apiKey;
    });
    await widget.characterRepository.saveCharacterProvider(
      _selectedCharacter,
      provider,
    );
    await widget.characterRepository.saveCharacterModel(_selectedCharacter, '');
  }

  Future<void> _saveApiKey(String value) async {
    await widget.settingsRepository.saveProviderApiKey(
      _runtimeConfig.provider,
      value,
    );
    _appConfig = await widget.settingsRepository.loadAppConfig();
  }

  Future<void> _fetchModels() async {
    final String apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnackBar('请先填写 API Key');
      return;
    }

    setState(() => _isFetchingModels = true);
    try {
      final List<String> models = await widget.services[_runtimeConfig.provider]!
          .fetchModels(apiKey);
      await widget.settingsRepository.saveProviderApiKey(
        _runtimeConfig.provider,
        apiKey,
      );
      await widget.settingsRepository.saveProviderModels(
        _runtimeConfig.provider,
        models,
      );
      _appConfig = await widget.settingsRepository.loadAppConfig();

      if (models.isNotEmpty) {
        final String selectedModel =
            models.contains(_runtimeConfig.modelSelect)
                ? _runtimeConfig.modelSelect
                : models.first;
        _runtimeConfig = _runtimeConfig.copyWith(modelSelect: selectedModel);
        await widget.characterRepository.saveCharacterModel(
          _selectedCharacter,
          selectedModel,
        );
      }
      _showSnackBar(models.isEmpty ? '未获取到模型列表' : '模型列表已刷新');
      setState(() {});
    } on LlmException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('获取模型失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isFetchingModels = false);
      }
    }
  }

  Future<void> _changeModel(String? value) async {
    if (value == null) {
      return;
    }
    setState(() {
      _runtimeConfig = _runtimeConfig.copyWith(modelSelect: value);
    });
    await widget.characterRepository.saveCharacterModel(_selectedCharacter, value);
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

    final LlmProviderType provider = _runtimeConfig.provider;
    final List<String> models = _appConfig.providerConfig(provider).models;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _SettingsCard(
            title: '角色设置',
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
                const SizedBox(height: 16),
                TextField(
                  controller: _promptController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '角色提示词',
                    alignLabelWithHint: true,
                    filled: true,
                  ),
                  onChanged: _savePrompt,
                ),
                const SizedBox(height: 18),
                Text(
                  '立绘大小：${_runtimeConfig.tachieSize}%',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Slider(
                  min: 50,
                  max: 160,
                  divisions: 22,
                  value: _runtimeConfig.tachieSize
                      .toDouble()
                      .clamp(50.0, 160.0),
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
          _SettingsCard(
            title: '模型设置',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  children: LlmProviderType.values
                      .map(
                        (LlmProviderType item) => ChoiceChip(
                          label: Text(item.label),
                          selected: provider == item,
                          onSelected: (_) => _changeProvider(item),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKeyController,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    filled: true,
                  ),
                  onChanged: _saveApiKey,
                ),
                const SizedBox(height: 16),
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
                  label: const Text('获取模型列表'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                    'model_${provider.configKey}_${_runtimeConfig.modelSelect}',
                  ),
                  initialValue: models.contains(_runtimeConfig.modelSelect) &&
                          _runtimeConfig.modelSelect.isNotEmpty
                      ? _runtimeConfig.modelSelect
                      : null,
                  decoration: const InputDecoration(
                    labelText: '当前模型',
                  ),
                  items: models
                      .map(
                        (String model) => DropdownMenuItem<String>(
                          value: model,
                          child: Text(model),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: models.isEmpty ? null : _changeModel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF7),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7C2D12),
                  ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
