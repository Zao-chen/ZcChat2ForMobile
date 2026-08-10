enum SpeechRecognitionDecision { ignore, submit, submitAndEnd }

/// 管理唤醒词、连续对话和结束词之间的会话策略。
class SpeechSessionPolicy {
  bool _sessionActive = false;
  bool _endAfterReply = false;

  bool get isSessionActive => _sessionActive;
  bool get shouldEndAfterReply => _endAfterReply;

  SpeechRecognitionDecision consumeAutomaticRecognition({
    required String text,
    required List<String> wakeWords,
    required List<String> endWords,
  }) {
    if (!_sessionActive) {
      if (!matchesKeyword(text, wakeWords)) {
        return SpeechRecognitionDecision.ignore;
      }
      _sessionActive = true;
    }

    if (matchesKeyword(text, endWords)) {
      _endAfterReply = true;
      return SpeechRecognitionDecision.submitAndEnd;
    }
    return SpeechRecognitionDecision.submit;
  }

  bool completeOutput() {
    if (!_endAfterReply) {
      return false;
    }
    _endAfterReply = false;
    _sessionActive = false;
    return true;
  }

  void reset() {
    _sessionActive = false;
    _endAfterReply = false;
  }

  static bool matchesKeyword(String text, Iterable<String> keywords) {
    final String normalizedText = normalizeForKeywordMatch(text);
    if (normalizedText.isEmpty) {
      return false;
    }
    return keywords.any((String keyword) {
      final String normalizedKeyword = normalizeForKeywordMatch(keyword);
      return normalizedKeyword.isNotEmpty &&
          normalizedText.contains(normalizedKeyword);
    });
  }

  static String normalizeForKeywordMatch(String text) {
    return text.toLowerCase().replaceAll(_ignoredCharacters, '');
  }
}

final RegExp _ignoredCharacters = RegExp(
  r'''[\s\.,，。!！?？、;；:：…—\-_"'“”‘’（）()【】\[\]{}<>《》]+''',
  unicode: true,
);
