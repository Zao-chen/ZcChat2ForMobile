import 'dart:convert';
import 'dart:io';

import '../models/anime_plugin_models.dart';

class AnimePluginManager {
  const AnimePluginManager();

  Future<AnimePluginDefinition> parsePluginFile(String filePath) async {
    return _loadAnimePluginFromFile(filePath);
  }

  Future<AnimePluginRegistry> reload(Directory pluginDirectory) async {
    final List<AnimePluginDefinition> plugins = <AnimePluginDefinition>[];
    final List<String> animationUniqueKeys = <String>[];
    final List<String> errors = <String>[];
    final Map<String, AnimePluginAnimationRef> index =
        <String, AnimePluginAnimationRef>{};
    final Set<String> pluginNameSet = <String>{};

    if (!await pluginDirectory.exists()) {
      return const AnimePluginRegistry.empty();
    }

    final List<FileSystemEntity> entities = await pluginDirectory
        .list()
        .toList();
    final List<File> pluginFiles =
        entities
            .whereType<File>()
            .where((File file) => file.path.toLowerCase().endsWith('.json'))
            .toList(growable: false)
          ..sort((File a, File b) => a.path.compareTo(b.path));

    for (final File file in pluginFiles) {
      try {
        final AnimePluginDefinition plugin = await _loadAnimePluginFromFile(
          file.path,
        );
        if (pluginNameSet.contains(plugin.name)) {
          errors.add('插件名重复[${_fileName(file.path)}]: ${plugin.name}');
          continue;
        }

        pluginNameSet.add(plugin.name);
        plugins.add(plugin);
        for (final AnimePluginAnimation animation in plugin.animations) {
          final String uniqueKey = animation.buildUniqueKey(plugin.name);
          if (index.containsKey(uniqueKey)) {
            errors.add('动画唯一键重复[${_fileName(file.path)}]: $uniqueKey');
            continue;
          }
          animationUniqueKeys.add(uniqueKey);
          index[uniqueKey] = AnimePluginAnimationRef(
            plugin: plugin,
            animation: animation,
          );
        }
      } catch (error) {
        errors.add('插件加载失败[${_fileName(file.path)}]: $error');
      }
    }

    return AnimePluginRegistry(
      plugins: plugins,
      animationUniqueKeys: animationUniqueKeys,
      lastErrors: errors,
      animationIndexByUniqueKey: index,
    );
  }

  Future<AnimePluginDefinition> _loadAnimePluginFromFile(
    String filePath,
  ) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      throw const FormatException('文件不存在');
    }

    final String content = await file.readAsString();
    final Object? decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('JSON 根节点必须是对象');
    }

    final Map<String, dynamic> root = decoded.cast<String, dynamic>();
    final String name = (root['name'] as String? ?? '').trim();
    final String version = (root['version'] as String? ?? '').trim();
    final String author = (root['author'] as String? ?? '').trim();
    final String link = (root['link'] as String? ?? '').trim();
    if (name.isEmpty || version.isEmpty || author.isEmpty || link.isEmpty) {
      throw const FormatException('name/version/author/link 不能为空');
    }

    final Object? animationRaw = root['animations'];
    if (animationRaw is! List || animationRaw.isEmpty) {
      throw const FormatException('animations 不能为空');
    }

    final Set<String> animationNameSet = <String>{};
    final List<AnimePluginAnimation> animations = <AnimePluginAnimation>[];
    for (final Object item in animationRaw) {
      if (item is! Map) {
        throw const FormatException('animation 项必须是对象');
      }
      final Map<String, dynamic> animationObj = item.cast<String, dynamic>();
      final AnimePluginAnimation animation = _parseAnimation(animationObj);
      if (animationNameSet.contains(animation.name)) {
        throw FormatException('动画 name 重复: ${animation.name}');
      }
      animationNameSet.add(animation.name);
      animations.add(animation);
    }

    return AnimePluginDefinition(
      filePath: filePath,
      name: name,
      version: version,
      author: author,
      link: link,
      animations: animations,
    );
  }

  AnimePluginAnimation _parseAnimation(Map<String, dynamic> animationObj) {
    final String name = (animationObj['name'] as String? ?? '').trim();
    if (name.isEmpty) {
      throw const FormatException('动画 name 不能为空');
    }

    final Object? stepsRaw = animationObj['steps'];
    if (stepsRaw is! List || stepsRaw.isEmpty) {
      throw FormatException('动画 $name 的 steps 不能为空');
    }

    final List<AnimePluginStep> steps = <AnimePluginStep>[];
    for (final Object stepRaw in stepsRaw) {
      if (stepRaw is! Map) {
        throw FormatException('动画 $name 的 step 必须是对象');
      }
      steps.add(_parseStep(stepRaw.cast<String, dynamic>()));
    }

    return AnimePluginAnimation(name: name, steps: steps);
  }

  AnimePluginStep _parseStep(Map<String, dynamic> stepObj) {
    final String type = (stepObj['type'] as String? ?? '').trim().toLowerCase();
    final double duration = _readDouble(stepObj['duration']);
    if (duration <= 0) {
      throw const FormatException('duration 必须大于 0');
    }

    switch (type) {
      case 'move':
        return AnimePluginStep(
          type: AnimePluginStepType.move,
          duration: duration,
          x: _readDouble(stepObj['x']),
          y: _readDouble(stepObj['y']),
        );
      case 'opacity':
        return AnimePluginStep(
          type: AnimePluginStepType.opacity,
          duration: duration,
          from: _readDouble(stepObj['from']),
          to: _readDouble(stepObj['to']),
        );
      case 'scale':
        return AnimePluginStep(
          type: AnimePluginStepType.scale,
          duration: duration,
          from: _readDouble(stepObj['from']),
          to: _readDouble(stepObj['to']),
        );
      default:
        throw FormatException('不支持的 step type: $type');
    }
  }

  double _readDouble(Object? value) {
    return switch (value) {
      int v => v.toDouble(),
      double v => v,
      String v => double.tryParse(v) ?? 0,
      _ => 0,
    };
  }

  String _fileName(String filePath) {
    return filePath.replaceAll('\\', '/').split('/').last;
  }
}
