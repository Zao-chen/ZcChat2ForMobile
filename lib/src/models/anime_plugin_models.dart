import 'dart:ui';

enum AnimePluginStepType { move, opacity, scale }

class AnimePluginStep {
  const AnimePluginStep({
    required this.type,
    required this.duration,
    this.x,
    this.y,
    this.from,
    this.to,
  });

  final AnimePluginStepType type;
  final double duration;
  final double? x;
  final double? y;
  final double? from;
  final double? to;
}

class AnimePluginAnimation {
  const AnimePluginAnimation({required this.name, required this.steps});

  final String name;
  final List<AnimePluginStep> steps;

  String buildUniqueKey(String pluginName) {
    return '${pluginName}_$name';
  }
}

class AnimePluginDefinition {
  const AnimePluginDefinition({
    required this.filePath,
    required this.name,
    required this.version,
    required this.author,
    required this.link,
    required this.animations,
  });

  final String filePath;
  final String name;
  final String version;
  final String author;
  final String link;
  final List<AnimePluginAnimation> animations;
}

class AnimePluginRegistry {
  const AnimePluginRegistry({
    required this.plugins,
    required this.animationUniqueKeys,
    required this.lastErrors,
    required this.animationIndexByUniqueKey,
  });

  const AnimePluginRegistry.empty()
    : plugins = const <AnimePluginDefinition>[],
      animationUniqueKeys = const <String>[],
      lastErrors = const <String>[],
      animationIndexByUniqueKey = const <String, AnimePluginAnimationRef>{};

  final List<AnimePluginDefinition> plugins;
  final List<String> animationUniqueKeys;
  final List<String> lastErrors;
  final Map<String, AnimePluginAnimationRef> animationIndexByUniqueKey;

  bool get hasPlugins => plugins.isNotEmpty;

  AnimePluginAnimationRef? tryGetAnimationByUniqueKey(String uniqueKey) {
    return animationIndexByUniqueKey[uniqueKey];
  }

  AnimePluginRegistry copyWithIndex(
    Map<String, AnimePluginAnimationRef> index,
  ) {
    return AnimePluginRegistry(
      plugins: plugins,
      animationUniqueKeys: animationUniqueKeys,
      lastErrors: lastErrors,
      animationIndexByUniqueKey: index,
    );
  }
}

class AnimePluginAnimationRef {
  const AnimePluginAnimationRef({
    required this.plugin,
    required this.animation,
  });

  final AnimePluginDefinition plugin;
  final AnimePluginAnimation animation;
}

class TachieAnimatedTransform {
  const TachieAnimatedTransform({
    this.offset = Offset.zero,
    this.scale = 1,
    this.opacity = 1,
  });

  final Offset offset;
  final double scale;
  final double opacity;

  TachieAnimatedTransform copyWith({
    Offset? offset,
    double? scale,
    double? opacity,
  }) {
    return TachieAnimatedTransform(
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
    );
  }
}
