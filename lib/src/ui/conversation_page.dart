import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
    widget.controller.initialize();
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
    final double dialogBottom = math.max(16, keyboardInset + 12);
    const double dialogReservedHeight = 176;

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
                      left: 14,
                      right: 14,
                      bottom: dialogBottom,
                      child: _DialogPanel(
                        characterName: controller.selectedCharacter,
                        inputController: _inputController,
                        isSending: controller.isSending,
                        isRecording: controller.isRecording,
                        isRecognizing: controller.isRecognizing,
                        speechEnabled: controller.appConfig.speechInput.enable,
                        autoSend: controller.appConfig.speechInput.autoSend,
                        onSubmitted: _submitInput,
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
    required this.characterName,
    required this.inputController,
    required this.isSending,
    required this.isRecording,
    required this.isRecognizing,
    required this.speechEnabled,
    required this.autoSend,
    required this.onSubmitted,
    required this.onHistory,
    required this.onAutoSendChanged,
    required this.onRecordStart,
    required this.onRecordStop,
  });

  final String characterName;
  final TextEditingController inputController;
  final bool isSending;
  final bool isRecording;
  final bool isRecognizing;
  final bool speechEnabled;
  final bool autoSend;
  final Future<void> Function() onSubmitted;
  final VoidCallback onHistory;
  final ValueChanged<bool?> onAutoSendChanged;
  final AsyncCallback onRecordStart;
  final AsyncCallback onRecordStop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x1A000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              characterName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: inputController,
              readOnly: isSending,
              showCursor: !isSending,
              minLines: 4,
              maxLines: 6,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmitted(),
              decoration: InputDecoration(
                hintText: isSending ? '' : '说点什么吧',
                hintStyle: const TextStyle(color: Color(0x80666666)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
              ),
              style: const TextStyle(
                fontSize: 15,
                height: 1.55,
                color: Color(0xFF333333),
              ),
            ),
            Row(
              children: <Widget>[
                if (speechEnabled) ...<Widget>[
                  _MicRecordButton(
                    onRecordStart: onRecordStart,
                    onRecordStop: onRecordStop,
                    isRecording: isRecording,
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    height: 32,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: autoSend,
                            onChanged: onAutoSendChanged,
                            activeColor: const Color(0xFF888888),
                            side: const BorderSide(color: Color(0xFF888888)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Text(
                          '直接发送',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isRecording || isRecognizing) ...<Widget>[
                    const SizedBox(width: 8),
                    Text(
                      isRecognizing ? '识别中...' : '录音中...',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
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
      ..translate(_transform.offset.dx, _transform.offset.dy);

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
    return Container(
      width: 250,
      height: 360,
      decoration: BoxDecoration(
        color: const Color(0x26FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 64,
        color: Color(0xFFBBBBBB),
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

    return Positioned(
      left: 14,
      right: 14,
      top: 15,
      bottom: 176 + MediaQuery.of(context).viewInsets.bottom + 20,
      child: SlideTransition(
        position: _offset,
        child: FadeTransition(
          opacity: _opacity,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: popupWidth,
              decoration: BoxDecoration(
                color: const Color(0xE6FFFFFF),
                borderRadius: BorderRadius.circular(15),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0x33000000),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: widget.entries.isEmpty
                        ? const Center(
                            child: Text(
                              '还没有历史记录',
                              style: TextStyle(color: Color(0xFF888888)),
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
  });

  final AsyncCallback onRecordStart;
  final AsyncCallback onRecordStop;
  final bool isRecording;

  @override
  State<_MicRecordButton> createState() => _MicRecordButtonState();
}

class _MicRecordButtonState extends State<_MicRecordButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = widget.isRecording
        ? const Color(0xFFAAAAAA)
        : _pressed
        ? const Color(0xFFAAAAAA)
        : _hovered
        ? const Color(0xFFCCCCCC)
        : Colors.transparent;

    return Tooltip(
      message: '长按录音',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
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
            setState(() => _pressed = true);
            unawaited(widget.onRecordStart());
          },
          onPointerUp: (_) {
            setState(() => _pressed = false);
            unawaited(widget.onRecordStop());
          },
          onPointerCancel: (_) {
            setState(() => _pressed = false);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 2),
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.all(6),
            child: SvgPicture.asset(
              'assets/microphone-solid.svg',
              width: 18,
              height: 18,
            ),
          ),
        ),
      ),
    );
  }
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
    final Color borderColor = _pressed
        ? const Color(0xFFAAAAAA)
        : _hovered
        ? const Color(0xFFCCCCCC)
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
            child: SvgPicture.asset(widget.assetPath, width: 18, height: 18),
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
      thumbColor: const Color(0x80888888),
      crossAxisMargin: 2,
      child: child,
    );
  }
}
