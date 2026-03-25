import 'dart:io';

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
      backgroundColor: const Color(0xFFFFFBF6),
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
                HistorySpeaker.user => '你',
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
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
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

    return Scaffold(
      body: SafeArea(
        child: controller.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
        ? '点击文本框继续'
        : isSending
            ? ''
            : '说点什么吧';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF7FFFDF9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1F7C2D12)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              characterName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF7C2D12),
              ),
            ),
            const SizedBox(height: 10),
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
                    filled: true,
                    fillColor: const Color(0xFFF9F1E7),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  ),
                  style: const TextStyle(
                    height: 1.5,
                    color: Color(0xFF3A1F13),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 12,
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
                            size: 20,
                            color: const Color(0xFF8E7A6A),
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
        borderRadius: BorderRadius.circular(36),
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
