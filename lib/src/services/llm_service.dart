import '../models/app_models.dart';

abstract class LlmService {
  LlmProviderType get provider;

  Future<List<String>> fetchModels(String apiKey);

  Stream<ChatStreamEvent> chatStream(ChatRequest request);

  void dispose() {}
}

class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}
