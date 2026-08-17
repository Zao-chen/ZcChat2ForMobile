import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'app_logger.dart';
import 'vits_service.dart';

class VitsPlaybackService implements VitsPlayback {
  VitsPlaybackService({required this.service, AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      unawaited(_handlePlaybackCompleted());
    });
    unawaited(_player.setReleaseMode(ReleaseMode.stop));
  }

  final VitsService service;
  final AudioPlayer _player;

  final List<_QueuedVitsSegment> _pendingSegments = <_QueuedVitsSegment>[];
  final List<_QueuedVitsAudio> _readyAudios = <_QueuedVitsAudio>[];
  late final StreamSubscription<void> _completionSubscription;

  bool _requestInFlight = false;
  bool _isPlaying = false;
  int _sessionToken = 0;
  int _requestVersion = 0;
  Completer<void>? _idleCompleter;

  @override
  Future<void> enqueueSegments({
    required String apiUrl,
    required String modelAndSpeaker,
    required Iterable<String> texts,
  }) async {
    final List<String> segments = texts
        .map((String text) => text.trim())
        .where((String text) => text.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return;
    }

    _idleCompleter ??= Completer<void>();
    final int token = _sessionToken;
    for (final String segment in segments) {
      _pendingSegments.add(
        _QueuedVitsSegment(
          token: token,
          apiUrl: apiUrl,
          modelAndSpeaker: modelAndSpeaker,
          text: segment,
        ),
      );
    }

    unawaited(_startNextRequest());
    unawaited(_startNextPlayback());
  }

  @override
  Future<void> stop() async {
    _sessionToken += 1;
    _requestVersion += 1;
    _pendingSegments.clear();
    _readyAudios.clear();
    _requestInFlight = false;
    _isPlaying = false;
    await _player.stop();
    _completeIdleIfNeeded();
  }

  @override
  Future<void> waitUntilIdle() {
    _completeIdleIfNeeded();
    return _idleCompleter?.future ?? Future<void>.value();
  }

  Future<void> _startNextRequest() async {
    if (_requestInFlight || _pendingSegments.isEmpty) {
      return;
    }

    final _QueuedVitsSegment segment = _pendingSegments.removeAt(0);
    final int requestVersion = ++_requestVersion;
    _requestInFlight = true;
    try {
      final Uint8List audioBytes = await service.synthesize(
        apiUrl: segment.apiUrl,
        modelAndSpeaker: segment.modelAndSpeaker,
        text: segment.text,
      );
      if (segment.token == _sessionToken && audioBytes.isNotEmpty) {
        _readyAudios.add(
          _QueuedVitsAudio(token: segment.token, bytes: audioBytes),
        );
        await _startNextPlayback();
      }
    } catch (error) {
      AppLogger.warning(
        'vits.synthesis.failed',
        fields: <String, Object?>{'message': error},
      );
    } finally {
      if (requestVersion == _requestVersion) {
        _requestInFlight = false;
        unawaited(_startNextRequest());
        _completeIdleIfNeeded();
      }
    }
  }

  Future<void> _startNextPlayback() async {
    if (_isPlaying) {
      return;
    }

    while (_readyAudios.isNotEmpty) {
      final _QueuedVitsAudio audio = _readyAudios.removeAt(0);
      if (audio.token != _sessionToken) {
        continue;
      }

      _isPlaying = true;
      try {
        await _player.play(BytesSource(audio.bytes));
      } catch (error) {
        AppLogger.warning(
          'vits.playback.failed',
          fields: <String, Object?>{'message': error},
        );
        _isPlaying = false;
        continue;
      }
      return;
    }
    _completeIdleIfNeeded();
  }

  Future<void> _handlePlaybackCompleted() async {
    await _startNextPlayback();
    _completeIdleIfNeeded();
  }

  void _completeIdleIfNeeded() {
    if (_requestInFlight ||
        _isPlaying ||
        _pendingSegments.isNotEmpty ||
        _readyAudios.isNotEmpty) {
      return;
    }
    final Completer<void>? completer = _idleCompleter;
    _idleCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  void dispose() {
    unawaited(_completionSubscription.cancel());
    unawaited(_player.dispose());
  }
}

class _QueuedVitsSegment {
  const _QueuedVitsSegment({
    required this.token,
    required this.apiUrl,
    required this.modelAndSpeaker,
    required this.text,
  });

  final int token;
  final String apiUrl;
  final String modelAndSpeaker;
  final String text;
}

class _QueuedVitsAudio {
  const _QueuedVitsAudio({required this.token, required this.bytes});

  final int token;
  final Uint8List bytes;
}
