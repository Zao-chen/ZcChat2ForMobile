import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/chat_controller.dart';
import '../models/app_models.dart';

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

    final CharacterRuntimeConfig runtimeConfig = widget.controller.runtimeConfig;
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: widget.settingsPageBuilder,
      ),
    );
    await widget.controller.reload();
  }

  void _showHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final List<HistoryEntry> entries = widget.controller.history.entries;
        if (entries.isEmpty) {
          return const SizedBox(
            height: 240,
            child: Center(
              child: Text('还没有历史记录'),
            ),
          );
        }

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int index) {
              final HistoryEntry entry = entries[index];
              final bool isUser = entry.speaker == HistorySpeaker.user;
              final String speakerName = switch (entry.speaker) {
                HistorySpeaker.user => '用户',
                HistorySpeaker.role => widget.controller.selectedCharacter,
                HistorySpeaker.system => '记录',
              };
              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFFF4C7A1)
                          : const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            speakerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7C2D12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(entry.text),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
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
                    hintStyle: const TextStyle(
                      color: Color(0x8A2F241E),
                    ),
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
    super.key,
  });

  final File? file;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (file == null || !file!.existsSync()) {
      return const _TachiePlaceholder();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 220),
        child: Image.file(
          file!,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const _TachiePlaceholder(),
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

