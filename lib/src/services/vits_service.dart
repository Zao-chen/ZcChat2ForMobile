import 'dart:typed_data';

abstract class VitsService {
  Future<List<String>> fetchModelAndSpeakers(String apiUrl);

  Future<Uint8List> synthesize({
    required String apiUrl,
    required String modelAndSpeaker,
    required String text,
  });

  void dispose() {}
}

class VitsException implements Exception {
  const VitsException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class VitsPlayback {
  Future<void> enqueueSegments({
    required String apiUrl,
    required String modelAndSpeaker,
    required Iterable<String> texts,
  });

  Future<void> stop();

  void dispose() {}
}
