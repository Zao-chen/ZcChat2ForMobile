import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../controllers/chat_controller.dart';
import '../models/app_models.dart';
import '../models/anime_plugin_models.dart';

class ConversationPage extends StatefulWidget {
  const ConversationPage({
    required this.controller,
    required this.settingsPageBuilder,
    super.key,
  });

  final ConversationController controller;
  final WidgetBuilder settingsPageBuilder;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final TextEditingController _inputController = TextEditingController();
  Offset _tachieOffset = Offset.zero;
  double _tachieScale = 1;
  double _gestureStartScale = 1;
  bool _isManipulatingTachie = false;
  String _lastSyncedCharacter = '';
  String _lastAnimationBindingKey = '';
  AnimePluginAnimation? _activePluginAnimation;
  OverlayEntry? _historyOverlay;
  final GlobalKey<_HistoryPopupState> _historyPopupKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    if (widget.controller.isLoading) {
      unawaited(widget.controller.initialize());
    }
  }

  @override
  void dispose() {
    _historyOverlay?.remove();
    _historyOverlay = null;
    widget.controller.removeListener(_onControllerChanged);
    _inputController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _syncInputController();
    _syncTachieTransform();
    _syncPluginAnimation();
    if (mounted) {
      setState(() {});
    }
  }

  void _syncInputController() {
    final ConversationController controller = widget.controller;

    if (controller.pendingInputText.isNotEmpty) {
      final String pending = controller.pendingInputText;
      controller.pendingInputText = '';
      _inputController.value = TextEditingValue(
        text: pending,
        selection: TextSelection.collapsed(offset: pending.length),
      );
      return;
    }

    final bool locked = controller.isSending || controller.showContinueButton;
    final String nextText = locked ? controller.currentDisplayText : '';
    if (_inputController.text == nextText) {
      return;
    }
    _inputController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  Future<void> _submitInput() async {
    final ConversationController controller = widget.controller;
    if (controller.isSending || controller.showContinueButton) {
      return;
    }
    await controller.sendMessage(_inputController.text);
  }

  void _syncTachieTransform() {
    if (_isManipulatingTachie) {
      return;
    }

    final CharacterRuntimeConfig runtimeConfig =
        widget.controller.runtimeConfig;
    final Offset nextOffset = Offset(
      runtimeConfig.tachieOffsetX,
      runtimeConfig.tachieOffsetY,
    );
    final double nextScale = (runtimeConfig.tachieSize / 100).toDouble();
    if (_lastSyncedCharacter == widget.controller.selectedCharacter &&
        _tachieOffset == nextOffset &&
        _tachieScale == nextScale) {
      return;
    }

    _lastSyncedCharacter = widget.controller.selectedCharacter;
    _tachieOffset = nextOffset;
    _tachieScale = nextScale;
  }

  void _syncPluginAnimation() {
    final ConversationController controller = widget.controller;
    final String actionName = controller.currentMood.trim().isEmpty
        ? 'default'
        : controller.currentMood.trim();
    final String uniqueKey =
        controller.runtimeConfig.tachieAnimations[actionName] ?? '';
    final AnimePluginAnimation? animation = uniqueKey.isEmpty
        ? null
        : controller.animePluginRegistry
              .tryGetAnimationByUniqueKey(uniqueKey)
              ?.animation;
    final String nextBindingKey =
        '${controller.currentTachieFile?.path ?? ''}|$actionName|$uniqueKey';
    if (_lastAnimationBindingKey == nextBindingKey) {
      return;
    }

    _lastAnimationBindingKey = nextBindingKey;
    _activePluginAnimation = animation;
  }

  void _handleTachieScaleStart(ScaleStartDetails details) {
    _isManipulatingTachie = true;
    _gestureStartScale = _tachieScale;
  }

  void _handleTachieScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _tachieScale = (_gestureStartScale * details.scale).clamp(0.5, 2.2);
      _tachieOffset += details.focalPointDelta;
    });
  }

  Future<void> _handleTachieScaleEnd(ScaleEndDetails details) async {
    _isManipulatingTachie = false;
    await widget.controller.saveTachieTransform(
      scale: _tachieScale,
      offset: _tachieOffset,
    );
  }

  Future<void> _resetTachieTransform() async {
    _isManipulatingTachie = false;
    await widget.controller.resetTachieTransform();
    _syncTachieTransform();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: widget.settingsPageBuilder));
    await widget.controller.reload();
  }

  void _showHistorySheet() {
    if (_historyOverlay != null) {
      _closeHistoryPopup();
      return;
    }

    final ConversationController controller = widget.controller;
    final List<HistoryEntry> entries = controller.history.entries;

    _historyOverlay = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return _HistoryPopup(
          key: _historyPopupKey,
          entries: entries,
          onRollback: _rollbackTo,
          onClose: _removeHistoryOverlay,
        );
      },
    );

    Overlay.of(context).insert(_historyOverlay!);
  }

  void _closeHistoryPopup() {
    _historyPopupKey.currentState?.close();
  }

  void _removeHistoryOverlay() {
    _historyOverlay?.remove();
    _historyOverlay = null;
  }

  Future<void> _rollbackTo(int index) async {
    _closeHistoryPopup();
    await widget.controller.rewindToHistoryIndex(index);
  }

  void _stopRecordingFromPointerEvent() {
    unawaited(widget.controller.stopRecording());
  }

  @override
  Widget build(BuildContext context) {
    final ConversationController controller = widget.controller;
    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final double dialogBottom = math.max(16, keyboardInset + 16);
    const double dialogReservedHeight = 222;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerUp: (_) => _stopRecordingFromPointerEvent(),
          child: controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: Column(
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                            child: Row(
                              children: <Widget>[
                                const Spacer(),
                                IconButton(
                                  onPressed: _openSettings,
                                  icon: const Icon(Icons.settings_rounded),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 12,
                                bottom: dialogReservedHeight,
                              ),
                              child: Center(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onScaleStart: _handleTachieScaleStart,
                                  onScaleUpdate: _handleTachieScaleUpdate,
                                  onScaleEnd: _handleTachieScaleEnd,
                                  onDoubleTap: _resetTachieTransform,
                                  child: Transform.translate(
                                    offset: _tachieOffset,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      child: _TachieDisplay(
                                        key: ValueKey<String>(
                                          '${controller.currentTachieFile?.path ?? 'web'}|${controller.currentMood}',
                                        ),
                                        file: controller.currentTachieFile,
                                        mood: controller.currentMood,
                                        scale: _tachieScale,
                                        pluginAnimation: _activePluginAnimation,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      left: 16,
                      right: 16,
                      bottom: dialogBottom,
                      child: _DialogPanel(
                        inputController: _inputController,
                        isSending: controller.isSending,
                        showContinueButton: controller.showContinueButton,
                        isRecording: controller.isRecording,
                        isRecognizing: controller.isRecognizing,
                        speechState: controller.speechState,
                        speechEnabled: controller.appConfig.speechInput.enable,
                        wakeEnabled:
                            controller.appConfig.speechInput.wakeEnabled,
                        autoSend: controller.appConfig.speechInput.autoSend,
                        contextTokenLimit: controller.contextTokenLimit,
                        estimatedContextTokens:
                            controller.estimatedContextTokens,
                        contextProgressDescription:
                            controller.contextProgressDescription,
                        isCompactingContext: controller.isCompactingContext,
                        onInputChanged: (String value) {
                          controller.updateDraftContextEstimate(value);
                          setState(() {});
                        },
                        onSubmitted: _submitInput,
                        onContinue: controller.continueConversation,
                        onHistory: _showHistorySheet,
                        onAutoSendChanged: (bool? value) {
                          final SpeechInputConfig old =
                              controller.appConfig.speechInput;
                          controller.appConfig = controller.appConfig
                              .copyWithSpeechInput(
                                old.copyWith(autoSend: value ?? false),
                              );
                          controller.settingsRepository.saveSpeechInputConfig(
                            controller.appConfig.speechInput,
                          );
                          setState(() {});
                        },
                        onRecordStart: controller.startRecording,
                        onRecordStop: controller.stopRecording,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DialogPanel extends StatelessWidget {
  const _DialogPanel({
    required this.inputController,
    required this.isSending,
    required this.showContinueButton,
    required this.isRecording,
    required this.isRecognizing,
    required this.speechState,
    required this.speechEnabled,
    required this.wakeEnabled,
    required this.autoSend,
    required this.contextTokenLimit,
    required this.estimatedContextTokens,
    required this.contextProgressDescription,
    required this.isCompactingContext,
    required this.onInputChanged,
    required this.onSubmitted,
    required this.onContinue,
    required this.onHistory,
    required this.onAutoSendChanged,
    required this.onRecordStart,
    required this.onRecordStop,
  });

  final TextEditingController inputController;
  final bool isSending;
  final bool showContinueButton;
  final bool isRecording;
  final bool isRecognizing;
  final SpeechInteractionState speechState;
  final bool speechEnabled;
  final bool wakeEnabled;
  final bool autoSend;
  final int contextTokenLimit;
  final int estimatedContextTokens;
  final String contextProgressDescription;
  final bool isCompactingContext;
  final ValueChanged<String> onInputChanged;
  final Future<void> Function() onSubmitted;
  final VoidCallback onContinue;
  final VoidCallback onHistory;
  final ValueChanged<bool?> onAutoSendChanged;
  final AsyncCallback onRecordStart;
  final AsyncCallback onRecordStop;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool waitingForInput = !isSending && !showContinueButton;
    final String hintText = isSending
        ? '正在回复…'
        : showContinueButton
        ? '轻触这里继续对话'
        : '说点什么吧 (Shift+Enter换行 Enter发送)';
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '你',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: _ContextTokenProgress(
                          tokenLimit: contextTokenLimit,
                          estimatedTokens: estimatedContextTokens,
                          description: contextProgressDescription,
                          isCompacting: isCompactingContext,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: inputController,
                    readOnly: !waitingForInput,
                    showCursor: waitingForInput,
                    minLines: 4,
                    maxLines: 6,
                    textInputAction: TextInputAction.send,
                    onChanged: onInputChanged,
                    onTap: showContinueButton ? onContinue : null,
                    onSubmitted: (_) {
                      if (waitingForInput) {
                        onSubmitted();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: TextStyle(
                        fontSize: 16,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.78),
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.only(top: 2),
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.45,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      if (speechEnabled) ...<Widget>[
                        _MicRecordButton(
                          onRecordStart: onRecordStart,
                          onRecordStop: onRecordStop,
                          isRecording: isRecording,
                          speechState: speechState,
                          enabled:
                              isRecording ||
                              (speechState !=
                                      SpeechInteractionState.recognizing &&
                                  speechState !=
                                      SpeechInteractionState.waitingForReply &&
                                  speechState !=
                                      SpeechInteractionState.ending &&
                                  speechState !=
                                      SpeechInteractionState.capturing),
                          tooltip: wakeEnabled ? '长按录音；松开后恢复语音唤醒' : '长按录音',
                        ),
                        const SizedBox(width: 12),
                        _AutoSendChip(
                          selected: autoSend,
                          onChanged: onAutoSendChanged,
                        ),
                        if (isRecording ||
                            isRecognizing ||
                            speechState !=
                                SpeechInteractionState.disabled) ...<Widget>[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _speechStateLabel(
                                speechState,
                                isManualRecording: isRecording,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                      const Spacer(),
                      _QtStyleButton(
                        tooltip: '历史记录',
                        assetPath: 'assets/log-24.svg',
                        onTap: onHistory,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoSendChip extends StatelessWidget {
  const _AutoSendChip({required this.selected, required this.onChanged});

  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: '语音识别完成后直接发送',
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IgnorePointer(
                child: SizedBox.square(
                  dimension: 24,
                  child: Checkbox(
                    value: selected,
                    onChanged: onChanged,
                    activeColor: colors.primary,
                    side: BorderSide(color: colors.outline),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '识别后自动发送',
                style: TextStyle(fontSize: 14, color: colors.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextTokenProgress extends StatelessWidget {
  const _ContextTokenProgress({
    required this.tokenLimit,
    required this.estimatedTokens,
    required this.description,
    required this.isCompacting,
  });

  final int tokenLimit;
  final int estimatedTokens;
  final String description;
  final bool isCompacting;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int remaining = tokenLimit <= 0
        ? 0
        : (tokenLimit - estimatedTokens).clamp(0, tokenLimit);
    final double? progress = isCompacting
        ? null
        : tokenLimit <= 0
        ? 0
        : remaining / tokenLimit;
    final bool exhausted = tokenLimit > 0 && remaining <= 0;
    final bool nearlyExhausted =
        tokenLimit > 0 && remaining <= math.max(1, tokenLimit ~/ 10);
    final Color progressColor = exhausted
        ? colors.error
        : nearlyExhausted
        ? colors.tertiary
        : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      label: '查看上下文详情：$description',
      child: InkWell(
        onTap: () => _showDetails(context),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 32,
          child: Center(
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: progressColor,
              backgroundColor: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.memory_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '上下文详情',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TachieDisplay extends StatelessWidget {
  const _TachieDisplay({
    required this.file,
    required this.mood,
    required this.scale,
    required this.pluginAnimation,
    super.key,
  });

  final File? file;
  final String mood;
  final double scale;
  final AnimePluginAnimation? pluginAnimation;

  static const String _webTachieAssetBase =
      'assets/bootstrap/character/assets/亚托莉/Tachie';
  static const Set<String> _webTachieAssetNames = <String>{
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
  };

  @override
  Widget build(BuildContext context) {
    if (file == null || !file!.existsSync()) {
      if (kIsWeb) {
        final String assetPath = _resolveWebTachieAssetPath(mood);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _PluginAnimatedTachie(
            baseScale: scale,
            pluginAnimation: pluginAnimation,
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Image.asset(
                '$_webTachieAssetBase/default.png',
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const _TachiePlaceholder(),
              ),
            ),
          ),
        );
      }
      return const _TachiePlaceholder();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: _PluginAnimatedTachie(
        baseScale: scale,
        pluginAnimation: pluginAnimation,
        child: Image.file(
          file!,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const _TachiePlaceholder(),
        ),
      ),
    );
  }

  String _resolveWebTachieAssetPath(String mood) {
    final String assetName = _normalizeWebTachieMood(mood);
    return '$_webTachieAssetBase/$assetName.png';
  }

  String _normalizeWebTachieMood(String mood) {
    String value = mood.trim();
    if (value.toLowerCase().endsWith('.png')) {
      value = value.substring(0, value.length - 4).trim();
    }
    value = value
        .replaceAll(RegExp(r'[\\/]'), '')
        .replaceAll(RegExp(r'[。！？.!?]+$'), '')
        .trim();
    if (_webTachieAssetNames.contains(value)) {
      return value;
    }
    return 'default';
  }
}

class _PluginAnimatedTachie extends StatefulWidget {
  const _PluginAnimatedTachie({
    required this.baseScale,
    required this.pluginAnimation,
    required this.child,
  });

  final double baseScale;
  final AnimePluginAnimation? pluginAnimation;
  final Widget child;

  @override
  State<_PluginAnimatedTachie> createState() => _PluginAnimatedTachieState();
}

class _PluginAnimatedTachieState extends State<_PluginAnimatedTachie> {
  static const Duration _defaultDuration = Duration(milliseconds: 220);

  TachieAnimatedTransform _transform = const TachieAnimatedTransform();
  Duration _duration = _defaultDuration;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _startSequence();
  }

  @override
  void didUpdateWidget(covariant _PluginAnimatedTachie oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pluginAnimation != widget.pluginAnimation) {
      _startSequence();
    }
  }

  void _startSequence() {
    _token += 1;
    final int myToken = _token;
    setState(() {
      _transform = const TachieAnimatedTransform();
      _duration = _defaultDuration;
    });

    final AnimePluginAnimation? animation = widget.pluginAnimation;
    if (animation == null || animation.steps.isEmpty) {
      return;
    }

    Future<void>(() async {
      for (final AnimePluginStep step in animation.steps) {
        if (!mounted || myToken != _token) {
          return;
        }

        final int ms = (step.duration * 1000).round().clamp(1, 30000);
        final Duration stepDuration = Duration(milliseconds: ms);

        switch (step.type) {
          case AnimePluginStepType.move:
            setState(() {
              _duration = stepDuration;
              _transform = _transform.copyWith(
                //move按上一步累加位移
                offset: _transform.offset + Offset(step.x ?? 0, step.y ?? 0),
              );
            });
            break;
          case AnimePluginStepType.opacity:
            setState(() {
              _duration = Duration.zero;
              _transform = _transform.copyWith(
                opacity: step.from ?? _transform.opacity,
              );
            });
            await Future<void>.delayed(const Duration(milliseconds: 1));
            if (!mounted || myToken != _token) {
              return;
            }
            setState(() {
              _duration = stepDuration;
              _transform = _transform.copyWith(
                opacity: step.to ?? _transform.opacity,
              );
            });
            break;
          case AnimePluginStepType.scale:
            setState(() {
              _duration = Duration.zero;
              _transform = _transform.copyWith(
                scale: step.from ?? _transform.scale,
              );
            });
            await Future<void>.delayed(const Duration(milliseconds: 1));
            if (!mounted || myToken != _token) {
              return;
            }
            setState(() {
              _duration = stepDuration;
              _transform = _transform.copyWith(
                scale: step.to ?? _transform.scale,
              );
            });
            break;
        }

        await Future<void>.delayed(stepDuration);
      }

      if (!mounted || myToken != _token) {
        return;
      }
      setState(() {
        _duration = const Duration(milliseconds: 180);
        _transform = const TachieAnimatedTransform();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final Matrix4 translate = Matrix4.identity()
      ..translateByDouble(_transform.offset.dx, _transform.offset.dy, 0, 1);

    return AnimatedContainer(
      duration: _duration,
      curve: Curves.linear,
      transform: translate,
      child: AnimatedOpacity(
        duration: _duration,
        curve: Curves.linear,
        opacity: _transform.opacity.clamp(0, 1).toDouble(),
        child: AnimatedScale(
          duration: _duration,
          curve: Curves.linear,
          alignment: Alignment.center,
          scale: widget.baseScale * _transform.scale,
          child: widget.child,
        ),
      ),
    );
  }
}

class _TachiePlaceholder extends StatelessWidget {
  const _TachiePlaceholder();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: 250,
      height: 360,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 64,
        color: colors.onSurfaceVariant,
      ),
    );
  }
}

class _HistoryPopup extends StatefulWidget {
  const _HistoryPopup({
    required this.entries,
    required this.onRollback,
    required this.onClose,
    super.key,
  });

  final List<HistoryEntry> entries;
  final Future<void> Function(int index) onRollback;
  final VoidCallback onClose;

  @override
  State<_HistoryPopup> createState() => _HistoryPopupState();
}

class _HistoryPopupState extends State<_HistoryPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  final ScrollController _scrollController = ScrollController();
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _opacity = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  Future<void> close() async {
    if (_isClosing) return;
    _isClosing = true;
    await _animController.reverse();
    widget.onClose();
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double popupWidth = MediaQuery.of(context).size.width - 28;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Positioned(
      left: 14,
      right: 14,
      top: 15,
      bottom: 222 + MediaQuery.of(context).viewInsets.bottom + 12,
      child: SlideTransition(
        position: _offset,
        child: FadeTransition(
          opacity: _opacity,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: popupWidth,
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(15),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.25),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: widget.entries.isEmpty
                        ? Center(
                            child: Text(
                              '还没有历史记录',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          )
                        : ScrollConfiguration(
                            behavior: _ThinScrollbarBehavior(),
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(6, 12, 20, 12),
                              itemCount: widget.entries.length,
                              itemBuilder: (BuildContext context, int index) {
                                final HistoryEntry entry =
                                    widget.entries[index];
                                final String name = switch (entry.speaker) {
                                  HistorySpeaker.user => '你',
                                  HistorySpeaker.role => '她',
                                  HistorySpeaker.system => '记录',
                                };
                                return _HistoryEntryRow(
                                  name: name,
                                  message: entry.text,
                                  onRollback: () => widget.onRollback(index),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryEntryRow extends StatelessWidget {
  const _HistoryEntryRow({
    required this.name,
    required this.message,
    required this.onRollback,
  });

  final String name;
  final String message;
  final VoidCallback onRollback;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: _QtStyleButton(
              tooltip: '回溯到这条记录',
              assetPath: 'assets/turn-back.svg',
              onTap: onRollback,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(message, style: const TextStyle(fontSize: 11)),
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

class _MicRecordButton extends StatefulWidget {
  const _MicRecordButton({
    required this.onRecordStart,
    required this.onRecordStop,
    required this.isRecording,
    required this.speechState,
    required this.enabled,
    required this.tooltip,
  });

  final AsyncCallback onRecordStart;
  final AsyncCallback onRecordStop;
  final bool isRecording;
  final SpeechInteractionState speechState;
  final bool enabled;
  final String tooltip;

  @override
  State<_MicRecordButton> createState() => _MicRecordButtonState();
}

class _MicRecordButtonState extends State<_MicRecordButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isListening =
        widget.isRecording ||
        widget.speechState == SpeechInteractionState.capturing;
    final bool isReady =
        widget.speechState == SpeechInteractionState.waitingForWake ||
        widget.speechState == SpeechInteractionState.continuousReady;
    final Color borderColor = isListening
        ? colors.primary.withValues(alpha: 0.8)
        : _pressed
        ? colors.outline
        : _hovered
        ? colors.outlineVariant
        : isReady
        ? colors.tertiary.withValues(alpha: 0.55)
        : colors.outlineVariant;
    final Color backgroundColor = isListening
        ? colors.primaryContainer.withValues(alpha: 0.55)
        : isReady
        ? colors.tertiaryContainer.withValues(alpha: 0.45)
        : colors.surfaceContainerHighest.withValues(alpha: 0.45);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onEnter: (_) {
          if (widget.enabled) {
            setState(() => _hovered = true);
          }
        },
        onExit: (_) {
          if (_hovered || _pressed) {
            setState(() {
              _hovered = false;
              _pressed = false;
            });
          }
        },
        child: Listener(
          onPointerDown: (_) {
            if (!widget.enabled) {
              return;
            }
            setState(() => _pressed = true);
            unawaited(widget.onRecordStart());
          },
          onPointerUp: (_) {
            if (!_pressed) {
              return;
            }
            setState(() => _pressed = false);
            unawaited(widget.onRecordStop());
          },
          onPointerCancel: (_) {
            setState(() => _pressed = false);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(7),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SvgPicture.asset(
                  'assets/microphone-solid.svg',
                  width: 17,
                  height: 17,
                  colorFilter: widget.enabled
                      ? ColorFilter.mode(colors.onSurface, BlendMode.srcIn)
                      : ColorFilter.mode(
                          colors.onSurface.withValues(alpha: 0.35),
                          BlendMode.srcIn,
                        ),
                ),
                const SizedBox(width: 6),
                Text(
                  isListening ? '松开发送' : '按住说话',
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.enabled
                        ? colors.onSurface
                        : colors.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _speechStateLabel(
  SpeechInteractionState state, {
  required bool isManualRecording,
}) {
  if (isManualRecording) {
    return '录音中...';
  }
  return switch (state) {
    SpeechInteractionState.disabled => '',
    SpeechInteractionState.waitingForWake => '等待唤醒',
    SpeechInteractionState.capturing => '聆听中...',
    SpeechInteractionState.recognizing => '识别中...',
    SpeechInteractionState.waitingForReply => '回复中...',
    SpeechInteractionState.continuousReady => '连续对话中',
    SpeechInteractionState.ending => '结束对话中...',
  };
}

class _QtStyleButton extends StatefulWidget {
  const _QtStyleButton({
    required this.tooltip,
    required this.assetPath,
    required this.onTap,
  });

  final String tooltip;
  final String assetPath;
  final VoidCallback onTap;

  @override
  State<_QtStyleButton> createState() => _QtStyleButtonState();
}

class _QtStyleButtonState extends State<_QtStyleButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color borderColor = _pressed
        ? colors.outline
        : _hovered
        ? colors.outlineVariant
        : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 2),
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.all(6),
            child: SvgPicture.asset(
              widget.assetPath,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(
                colors.onSurfaceVariant,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinScrollbarBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return RawScrollbar(
      controller: details.controller,
      thickness: 8,
      radius: const Radius.circular(4),
      thumbColor: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      crossAxisMargin: 2,
      child: child,
    );
  }
}
