import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    widget.controller.initialize();
  }

  @override
  void dispose() {
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
    final bool locked =
        widget.controller.isSending || widget.controller.showContinueButton;
    final String nextText = locked ? widget.controller.currentDisplayText : '';
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        final ConversationController controller = widget.controller;
        final List<HistoryEntry> entries = controller.history.entries;
        if (entries.isEmpty) {
          return const SizedBox(
            height: 240,
            child: Center(child: Text('还没有历史记录')),
          );
        }

        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.7,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                child: Row(
                  children: <Widget>[
                    Text(
                      '历史记录（${entries.length} 条）',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7C2D12),
                      ),
                    ),
                    const Spacer(),
                    _SheetIconButton(
                      icon: Icons.undo_rounded,
                      tooltip: '撤销最后一轮',
                      onTap: () => _confirmUndoLastTurn(sheetContext),
                    ),
                    const SizedBox(width: 4),
                    _SheetIconButton(
                      icon: Icons.delete_sweep_rounded,
                      tooltip: '清空全部',
                      onTap: () => _confirmClearHistory(sheetContext),
                    ),
                  ],
                ),
              ),
              const Divider(indent: 20, endIndent: 20),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final HistoryEntry entry = entries[index];
                    final bool isUser = entry.speaker == HistorySpeaker.user;
                    final String speakerName = switch (entry.speaker) {
                      HistorySpeaker.user => '用户',
                      HistorySpeaker.role => controller.selectedCharacter,
                      HistorySpeaker.system => '记录',
                    };
                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFFF4C7A1)
                                : const Color(0xFFFFFFFF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        speakerName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Color(0xFF7C2D12),
                                        ),
                                      ),
                                    ),
                                    _SheetIconButton(
                                      icon: Icons.edit_outlined,
                                      tooltip: '修改',
                                      size: 18,
                                      onTap: () =>
                                          _showEditDialog(sheetContext, index),
                                    ),
                                    _SheetIconButton(
                                      icon: Icons.delete_outline_rounded,
                                      tooltip: '删除',
                                      size: 18,
                                      onTap: () => _confirmDeleteEntry(
                                        sheetContext,
                                        index,
                                      ),
                                    ),
                                    _SheetIconButton(
                                      icon: Icons.reply_rounded,
                                      tooltip: '回退到此',
                                      size: 18,
                                      onTap: () => _confirmRollbackTo(
                                        sheetContext,
                                        index,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(entry.text),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditDialog(BuildContext sheetContext, int index) async {
    final ConversationController controller = widget.controller;
    final HistoryEntry entry = controller.history.entries[index];
    final TextEditingController editController = TextEditingController(
      text: entry.text,
    );

    final bool? confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('修改记录'),
          content: TextField(
            controller: editController,
            maxLines: 5,
            minLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '输入修改后的内容',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final String newText = editController.text.trim();
      if (newText.isNotEmpty && newText != entry.text) {
        await controller.editHistoryEntry(index, newText);
        if (sheetContext.mounted) {
          Navigator.of(sheetContext).pop();
          _showHistorySheet();
        }
      }
    }
    editController.dispose();
  }

  Future<void> _confirmDeleteEntry(BuildContext sheetContext, int index) async {
    final bool? confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除记录'),
          content: const Text('确定要删除这条历史记录吗？此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await widget.controller.deleteHistoryEntry(index);
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
        _showHistorySheet();
      }
    }
  }

  /// 回退到此位置：保留此条及之前的所有记录，删除之后的所有记录。
  Future<void> _confirmRollbackTo(BuildContext sheetContext, int index) async {
    final ConversationController controller = widget.controller;
    final int totalEntries = controller.history.entries.length;
    final int willRemove = totalEntries - index - 1;

    if (willRemove <= 0) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(
          sheetContext,
        ).showSnackBar(const SnackBar(content: Text('已经是最后一条，无需回退')));
      }
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('回退到此'),
          content: Text('将删除此条之后的 $willRemove 条记录，此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF6C00),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认回退'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await controller.rollbackHistoryTo(index + 1);
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
        _showHistorySheet();
      }
    }
  }

  Future<void> _confirmUndoLastTurn(BuildContext sheetContext) async {
    final ConversationController controller = widget.controller;
    if (controller.history.entries.isEmpty) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('撤销最后一轮'),
          content: const Text('将撤销最后一轮对话（用户消息和角色回复）。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('撤销'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await controller.undoLastTurn();
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
        _showHistorySheet();
      }
    }
  }

  Future<void> _confirmClearHistory(BuildContext sheetContext) async {
    final bool? confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('清空历史记录'),
          content: const Text('确定要清空全部历史记录吗？此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await widget.controller.clearHistory();
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
        _showHistorySheet();
      }
    }
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
                                onPressed: _showHistorySheet,
                                icon: const Icon(Icons.history_rounded),
                              ),
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
                                    duration: const Duration(milliseconds: 250),
                                    child: _TachieDisplay(
                                      key: ValueKey<String?>(
                                        controller.currentTachieFile?.path,
                                      ),
                                      file: controller.currentTachieFile,
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
                      showContinueButton: controller.showContinueButton,
                      onSubmitted: _submitInput,
                      onTapBox: () {
                        if (controller.showContinueButton) {
                          FocusScope.of(context).unfocus();
                          controller.continueConversation();
                        }
                      },
                    ),
                  ),
                ],
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
    required this.showContinueButton,
    required this.onSubmitted,
    required this.onTapBox,
  });

  final String characterName;
  final TextEditingController inputController;
  final bool isSending;
  final bool showContinueButton;
  final Future<void> Function() onSubmitted;
  final VoidCallback onTapBox;

  @override
  Widget build(BuildContext context) {
    final bool readOnly = isSending || showContinueButton;
    final String hintText = showContinueButton
        ? '点击继续'
        : isSending
        ? ''
        : '说点什么吧';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD9FFF8F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x22000000)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              characterName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2F241E),
              ),
            ),
            const SizedBox(height: 6),
            Stack(
              children: <Widget>[
                TextField(
                  controller: inputController,
                  readOnly: readOnly,
                  showCursor: !readOnly,
                  minLines: 4,
                  maxLines: 6,
                  textInputAction: TextInputAction.send,
                  onTap: onTapBox,
                  onSubmitted: (_) => onSubmitted(),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(color: Color(0x8A2F241E)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.fromLTRB(0, 4, 28, 18),
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: Color(0xFF2F241E),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: isSending
                        ? const SizedBox(
                            key: ValueKey<String>('loading'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Icon(
                            showContinueButton
                                ? Icons.touch_app_rounded
                                : Icons.keyboard_return_rounded,
                            key: ValueKey<bool>(showContinueButton),
                            size: 18,
                            color: const Color(0xFF7C6A5C),
                          ),
                  ),
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
    required this.scale,
    required this.pluginAnimation,
    super.key,
  });

  final File? file;
  final double scale;
  final AnimePluginAnimation? pluginAnimation;

  @override
  Widget build(BuildContext context) {
    if (file == null || !file!.existsSync()) {
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
        color: Color(0xFFBFA38A),
      ),
    );
  }
}

class _SheetIconButton extends StatelessWidget {
  const _SheetIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 20,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: size, color: const Color(0xFF8D6E63)),
        ),
      ),
    );
  }
}
