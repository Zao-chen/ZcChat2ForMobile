import 'context_token_estimator.dart';

class ContextCompactionPlan {
  const ContextCompactionPlan({
    this.compactedHistoryCount = 0,
    this.compactUntil = 0,
    this.source = '',
    this.contextToReplace = '',
  });

  final int compactedHistoryCount;
  final int compactUntil;
  final String source;
  final String contextToReplace;

  bool get isValid =>
      compactUntil > compactedHistoryCount &&
      source.trim().isNotEmpty &&
      contextToReplace.trim().isNotEmpty;
}

class ContextHistoryCompressor {
  const ContextHistoryCompressor._();

  static const int defaultTriggerPercent = 80;
  static const int minimumTriggerPercent = 50;
  static const int maximumTriggerPercent = 95;
  static const int retainedRecentLines = 4;
  static const String summaryPrefix = '较早对话摘要：';

  static int validatedTriggerPercent(int percent) {
    if (percent < minimumTriggerPercent || percent > maximumTriggerPercent) {
      return defaultTriggerPercent;
    }
    return percent;
  }

  static bool shouldCompress({
    required int estimatedTokens,
    required int contextTokenLimit,
    required int triggerPercent,
  }) {
    if (estimatedTokens <= 0 || contextTokenLimit <= 0) {
      return false;
    }
    final int threshold =
        contextTokenLimit * validatedTriggerPercent(triggerPercent) ~/ 100;
    return estimatedTokens >= threshold;
  }

  static List<String> activeHistory({
    required List<String> fullHistory,
    required String summary,
    required int compactedHistoryCount,
  }) {
    final int validCount = _validCompactedHistoryCount(
      fullHistory,
      summary,
      compactedHistoryCount,
    );
    if (validCount == 0) {
      return List<String>.from(fullHistory);
    }
    return <String>[
      '$summaryPrefix${summary.trim()}',
      ...fullHistory.skip(validCount),
    ];
  }

  static List<String> fastActiveHistory({
    required List<String> fullHistory,
    required String summary,
    required int compactedHistoryCount,
    required int compactUntil,
  }) {
    final int validCount = _validCompactedHistoryCount(
      fullHistory,
      summary,
      compactedHistoryCount,
    );
    if (compactUntil <= validCount || compactUntil > fullHistory.length) {
      return activeHistory(
        fullHistory: fullHistory,
        summary: summary,
        compactedHistoryCount: compactedHistoryCount,
      );
    }
    return <String>[
      if (validCount > 0) '$summaryPrefix${summary.trim()}',
      ...fullHistory.skip(compactUntil),
    ];
  }

  static ContextCompactionPlan createPlan({
    required List<String> fullHistory,
    required String summary,
    required int compactedHistoryCount,
    int retainedLines = retainedRecentLines,
  }) {
    final int validCount = _validCompactedHistoryCount(
      fullHistory,
      summary,
      compactedHistoryCount,
    );
    final int safeRetainedLines = retainedLines.clamp(2, 0x7fffffff);
    int compactUntil = fullHistory.length - safeRetainedLines;
    while (compactUntil > validCount &&
        !fullHistory[compactUntil].startsWith('用户：')) {
      compactUntil -= 1;
    }

    if (compactUntil - validCount < 2) {
      return ContextCompactionPlan(compactedHistoryCount: validCount);
    }

    final List<String> sourceSections = <String>[];
    final List<String> contextToReplace = <String>[];
    if (validCount > 0) {
      sourceSections.add('已有摘要：\n${summary.trim()}');
      contextToReplace.add('$summaryPrefix${summary.trim()}');
    }
    final List<String> historySlice = fullHistory.sublist(
      validCount,
      compactUntil,
    );
    sourceSections.add('需要合并进摘要的较早对话：\n${historySlice.join('\n')}');
    contextToReplace.addAll(historySlice);

    return ContextCompactionPlan(
      compactedHistoryCount: validCount,
      compactUntil: compactUntil,
      source: sourceSections.join('\n\n'),
      contextToReplace: contextToReplace.join('\n'),
    );
  }

  static bool isUsefulSummary({
    required String summary,
    required String contextToReplace,
  }) {
    final String normalizedSummary = summary.trim();
    if (normalizedSummary.isEmpty || contextToReplace.trim().isEmpty) {
      return false;
    }
    return ContextTokenEstimator.estimateTextTokens(
          '$summaryPrefix$normalizedSummary',
        ) <
        ContextTokenEstimator.estimateTextTokens(contextToReplace);
  }

  static int _validCompactedHistoryCount(
    List<String> history,
    String summary,
    int compactedHistoryCount,
  ) {
    if (summary.trim().isEmpty ||
        compactedHistoryCount <= 0 ||
        compactedHistoryCount > history.length) {
      return 0;
    }
    return compactedHistoryCount;
  }
}
