class ContextTokenEstimator {
  const ContextTokenEstimator._();

  static const int defaultContextTokenLimit = 65536;
  static const int minimumContextTokenLimit = 1024;
  static const int contextTokenLimitStep = minimumContextTokenLimit;
  static const int maximumContextTokenLimit = 10000000;

  static int estimateTextTokens(String text) {
    if (text.isEmpty) {
      return 0;
    }

    int quarterTokenUnits = 0;
    for (final int codePoint in text.runes) {
      if (codePoint <= 0x7f) {
        quarterTokenUnits += 1;
      } else if (_isEmojiCodePoint(codePoint)) {
        quarterTokenUnits += 8;
      } else {
        quarterTokenUnits += 4;
      }
    }
    return ((quarterTokenUnits + 3) ~/ 4).clamp(1, 0x7fffffff);
  }

  static int estimateChatRequestTokens({
    required String systemPrompt,
    required String userMessage,
  }) {
    int tokens = 2;
    if (systemPrompt.isNotEmpty) {
      tokens += 4 + estimateTextTokens(systemPrompt);
    }
    if (userMessage.isNotEmpty) {
      tokens += 4 + estimateTextTokens(userMessage);
    }
    return tokens;
  }

  static int validatedTokenLimit(int tokenLimit) {
    if (tokenLimit < minimumContextTokenLimit ||
        tokenLimit > maximumContextTokenLimit) {
      return defaultContextTokenLimit;
    }
    return tokenLimit;
  }

  static int tokenLimitForSelection(
    int storedTokenLimit, {
    required bool selectionMatches,
  }) {
    return selectionMatches
        ? validatedTokenLimit(storedTokenLimit)
        : defaultContextTokenLimit;
  }

  static int remainingTokens(int tokenLimit, int estimatedUsedTokens) {
    return (tokenLimit - estimatedUsedTokens.clamp(0, 0x7fffffff)).clamp(
      0,
      0x7fffffff,
    );
  }

  static String formatContextProgress({
    required int tokenLimit,
    required int estimatedUsedTokens,
    required String source,
  }) {
    final int safeUsed = estimatedUsedTokens.clamp(0, 0x7fffffff);
    final int remaining = remainingTokens(tokenLimit, safeUsed);
    final int overflow = (safeUsed - tokenLimit).clamp(0, 0x7fffffff);
    final StringBuffer text = StringBuffer()
      ..writeln('本地估算剩余：${_formatNumber(remaining)} Token')
      ..writeln('本地估算已用：${_formatNumber(safeUsed)} Token')
      ..write('上下文上限：${_formatNumber(tokenLimit)} Token（$source）');
    if (overflow > 0) {
      text.write('\n已超出：${_formatNumber(overflow)} Token');
    }
    text.write('\n不同模型的分词方式不同，实际值以模型服务商为准');
    return text.toString();
  }

  static bool _isEmojiCodePoint(int codePoint) {
    return (codePoint >= 0x1f000 && codePoint <= 0x1faff) ||
        (codePoint >= 0x2600 && codePoint <= 0x27bf);
  }

  static String _formatNumber(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
}
