import 'dart:async';

import 'package:better_player/better_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HlsToken {
  final String playlistToken;
  final int playlistExpiry;

  const HlsToken({
    required this.playlistToken,
    required this.playlistExpiry,
  });
}

typedef HlsTokenRefresh = Future<HlsToken> Function();

class HlsPlayer extends StatefulWidget {
  final String streamUrl;
  final HlsTokenRefresh? tokenRefreshMethod;
  final bool abrEnabled;
  final int playlistRefreshThreshold;
  final bool autoPlay;
  final bool muted;
  final bool isLive;

  const HlsPlayer({
    super.key,
    required this.streamUrl,
    this.tokenRefreshMethod,
    this.abrEnabled = true,
    this.playlistRefreshThreshold = 15,
    this.autoPlay = true,
    this.muted = false,
    this.isLive = false,
  });

  @override
  State<HlsPlayer> createState() => HlsPlayerState();
}

class HlsPlayerState extends State<HlsPlayer> {
  static const MethodChannel _platformChannel =
      MethodChannel('better_player_channel');
  late BetterPlayerController _controller;
  Timer? _refreshTimer;
  Timer? _scheduledRefreshTimer;
  Timer? _liveEdgeTimer;
  Timer? _retryTimer;
  HlsToken? _token;
  bool _refreshInProgress = false;
  bool _liveRecoveryInProgress = false;
  bool _pendingDataSourceUpdate = false;
  bool _errorRecoveryInProgress = false;
  bool _showLoader = false;
  int? _lastTokenRefreshEpoch;
  bool _retryKeepPosition = true;
  int _retryAttempt = 0;
  bool _suppressLoader = false;
  static const List<Duration> _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 12),
    Duration(seconds: 20),
  ];
  static const Duration _liveEdgeCheckInterval = Duration(seconds: 10);
  static const Duration _maxBehindLive = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: widget.autoPlay,
        fit: BoxFit.contain,
        aspectRatio: 16 / 9,
        errorBuilder: (_, __) => const SizedBox.shrink(),
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enableQualities: widget.abrEnabled,
          enableAudioTracks: true,
          enableSubtitles: true,
          enableSkips: false,
          loadingWidget: const SizedBox.shrink(),
          loadingColor: Colors.transparent,
        ),
      ),
    );
    _controller.addEventsListener(_onPlayerEvent);
    _initialize();
  }

  @override
  void didUpdateWidget(covariant HlsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldBaseUrl = _stripTokenParams(oldWidget.streamUrl);
    final newBaseUrl = _stripTokenParams(widget.streamUrl);
    final baseUrlChanged = oldBaseUrl != newBaseUrl;
    final tokenOnlyChanged =
        oldWidget.streamUrl != widget.streamUrl && !baseUrlChanged;
    if (baseUrlChanged ||
        oldWidget.tokenRefreshMethod != widget.tokenRefreshMethod ||
        oldWidget.abrEnabled != widget.abrEnabled ||
        oldWidget.isLive != widget.isLive) {
      _initialize();
    } else if (tokenOnlyChanged && widget.tokenRefreshMethod == null) {
      if (_isPlaying()) {
        _pendingDataSourceUpdate = true;
      } else {
        _applyDataSource(keepPosition: true);
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scheduledRefreshTimer?.cancel();
    _liveEdgeTimer?.cancel();
    _retryTimer?.cancel();
    _controller.removeEventsListener(_onPlayerEvent);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    _setLoader(true);
    _clearRetry();
    _refreshTimer?.cancel();
    _scheduledRefreshTimer?.cancel();
    _liveEdgeTimer?.cancel();
    _token = null;
    try {
      await _refreshTokenIfNeeded(force: true, applyAfterRefresh: false);
      await _applyDataSource(keepPosition: false);
      _startTokenRefreshLoop();
      _startLiveEdgeLoop();
    } catch (_) {
      _scheduleRetry(keepPosition: false);
    } finally {
      _setLoaderIfIdle();
    }
  }

  Future<void> _updatePlatformHlsToken(HlsToken token) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _platformChannel.invokeMethod('setHlsToken', {
        'token': token.playlistToken,
        'exp': token.playlistExpiry.toString(),
      });
    } catch (_) {
      // Ignore; token will be applied on next data source setup if needed.
    }
  }

  Future<void> _refreshTokenIfNeeded({
    required bool force,
    bool applyAfterRefresh = false,
  }) async {
    if (widget.tokenRefreshMethod == null) return;
    if (_refreshInProgress) return;

    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (force &&
        _lastTokenRefreshEpoch != null &&
        nowEpoch - _lastTokenRefreshEpoch! < 5) {
      return;
    }

    final token = _token;
    final needsRefresh =
        force || token == null || _needsRefresh(token.playlistExpiry);

    if (!needsRefresh) return;

    _refreshInProgress = true;
    final previousToken = _token?.playlistToken;
    try {
      final now = DateTime.now();
      debugPrint('Refreshing HLS token (force=$force, now=$now).');
      _token = await widget.tokenRefreshMethod!.call();
      _lastTokenRefreshEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      debugPrint('HLS token refreshed.');
      _scheduleTokenRefresh();
      final latestToken = _token;
      if (latestToken != null) {
        await _updatePlatformHlsToken(latestToken);
      }
      if (applyAfterRefresh && mounted) {
        final updatedToken = _token?.playlistToken;
        if (updatedToken != null && updatedToken != previousToken) {
          _pendingDataSourceUpdate = false;
          // Token update is applied via platform channel without reloading source.
        }
      }
    } catch (_) {
      _scheduleRetry(keepPosition: true);
    } finally {
      _refreshInProgress = false;
    }
  }

  void _startTokenRefreshLoop() {
    if (widget.tokenRefreshMethod == null) return;
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_pendingDataSourceUpdate) {
        _pendingDataSourceUpdate = false;
        await _applyDataSource(keepPosition: true, suppressLoader: true);
      }
      await _refreshTokenIfNeeded(force: false, applyAfterRefresh: false);
    });
  }

  void _scheduleTokenRefresh() {
    final token = _token;
    if (token == null) return;
    _scheduledRefreshTimer?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeRemaining = token.playlistExpiry - now;
    final secondsUntilRefresh = timeRemaining - widget.playlistRefreshThreshold;
    final delaySeconds = secondsUntilRefresh <= 0 ? 1 : secondsUntilRefresh;
    final refreshAt =
        DateTime.fromMillisecondsSinceEpoch((now + delaySeconds) * 1000);
    final expiryAt =
        DateTime.fromMillisecondsSinceEpoch(token.playlistExpiry * 1000);
    debugPrint(
        'Scheduled token refresh at $refreshAt (expires at $expiryAt).');
    _scheduledRefreshTimer =
        Timer(Duration(seconds: delaySeconds), () async {
      await _refreshTokenIfNeeded(force: true, applyAfterRefresh: true);
    });
  }

  bool _needsRefresh(int expiry) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeRemaining = expiry - now;
    if (timeRemaining <= 0) {
      debugPrint('HLS token expired ${-timeRemaining}s ago.');
    }
    return timeRemaining < widget.playlistRefreshThreshold;
  }

  void _startLiveEdgeLoop() {
    if (!widget.isLive) return;
    _liveEdgeTimer = Timer.periodic(_liveEdgeCheckInterval, (_) async {
      await _seekToLiveEdgeIfNeeded();
    });
  }

  Future<void> _seekToLiveEdgeIfNeeded() async {
    if (!widget.isLive) return;
    final controller = _controller.videoPlayerController;
    if (controller == null) return;
    final value = controller.value;
    if (!value.initialized) return;
    final duration = value.duration;
    if (duration == null) return;
    final position = value.position;
    if (duration == Duration.zero || position > duration) return;
    final behind = duration - position;
    if (behind <= _maxBehindLive) return;
    try {
      await _controller.seekTo(duration);
    } catch (_) {
      // Ignore; will retry on next tick.
    }
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    if (event.betterPlayerEventType == BetterPlayerEventType.bufferingStart) {
      if (!_suppressLoader) {
        _setLoader(true);
      }
      return;
    }
    if (event.betterPlayerEventType == BetterPlayerEventType.bufferingEnd) {
      if (!_suppressLoader) {
        _setLoader(false);
      }
      return;
    }
    if (event.betterPlayerEventType != BetterPlayerEventType.exception) return;
    final message = event.parameters?['exception']?.toString() ?? '';
    _setLoader(true);
    if (message.contains('BehindLiveWindowException') ||
        message.contains('Response code: 410')) {
      _recoverFromLiveWindow();
      return;
    }
    if (_pendingDataSourceUpdate ||
        message.contains('Response code: 401') ||
        message.contains('Response code: 403')) {
      _recoverFromTokenFailure();
      return;
    }
    _recoverFromPlaybackError();
  }

  Future<void> _recoverFromTokenFailure() async {
    if (_refreshInProgress) return;
    _pendingDataSourceUpdate = false;
    try {
      await _refreshTokenIfNeeded(force: true, applyAfterRefresh: false);
      await _applyDataSource(keepPosition: true);
      await _controller.retryDataSource();
      if (widget.autoPlay) {
        await _controller.play();
      }
    } catch (_) {
      _scheduleRetry(keepPosition: true);
    } finally {
      _setLoaderIfIdle();
    }
  }

  Future<void> _recoverFromPlaybackError() async {
    if (_errorRecoveryInProgress) return;
    _errorRecoveryInProgress = true;
    try {
      await _refreshTokenIfNeeded(force: true, applyAfterRefresh: false);
      await _applyDataSource(keepPosition: true);
      await _controller.retryDataSource();
      if (widget.autoPlay) {
        await _controller.play();
      }
    } catch (_) {
      _scheduleRetry(keepPosition: true);
    } finally {
      _errorRecoveryInProgress = false;
      _setLoaderIfIdle();
    }
  }

  Future<void> _recoverFromLiveWindow() async {
    if (_liveRecoveryInProgress) return;
    _liveRecoveryInProgress = true;
    try {
      debugPrint('Recovering from live window error.');
      await _refreshTokenIfNeeded(force: true, applyAfterRefresh: false);
      await _applyDataSource(keepPosition: false);
      await _controller.retryDataSource();
      if (widget.isLive) {
        await _seekToLiveEdgeIfNeeded();
      }
      await _controller.play();
    } finally {
      _liveRecoveryInProgress = false;
      _setLoaderIfIdle();
    }
  }

  Future<void> goLive() async {
    if (!widget.isLive) return;
    await _recoverFromLiveWindow();
  }

  Future<void> _applyDataSource({
    required bool keepPosition,
    bool suppressLoader = false,
  }) async {
    final url = _buildUrlWithToken(widget.streamUrl, _token);
    final headers = _buildTokenHeaders(_token);
    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      liveStream: widget.isLive,
      useAsmsSubtitles: false,
      headers: headers,
      cacheConfiguration: const BetterPlayerCacheConfiguration(useCache: false),
    );

    Duration? resumePosition;
    if (keepPosition) {
      resumePosition = await _controller.videoPlayerController?.position;
    }

    _suppressLoader = suppressLoader;
    if (suppressLoader) {
      _setLoader(false);
    }
    try {
      await _controller.setupDataSource(dataSource);
    } catch (_) {
      _scheduleRetry(keepPosition: keepPosition);
      return;
    } finally {
      _suppressLoader = false;
    }
    if (resumePosition != null && resumePosition > Duration.zero) {
      await _controller.seekTo(resumePosition);
    }

    if (widget.muted) {
      _controller.setVolume(0);
    } else {
      _controller.setVolume(1);
    }

    if (widget.autoPlay) {
      _controller.play();
    }

    _clearRetry();
  }

  bool _isPlaying() {
    return _controller.videoPlayerController?.value.isPlaying ?? false;
  }

  void _scheduleRetry({required bool keepPosition}) {
    if (!mounted) return;
    if (_retryTimer?.isActive ?? false) return;
    _retryKeepPosition = keepPosition;
    final index =
        _retryAttempt < _retryDelays.length ? _retryAttempt : _retryDelays.length - 1;
    final delay = _retryDelays[index];
    _retryAttempt++;
    _setLoader(true);
    _retryTimer = Timer(delay, () async {
      _retryTimer = null;
      if (!mounted) return;
      await _refreshTokenIfNeeded(force: false, applyAfterRefresh: false);
      await _applyDataSource(keepPosition: _retryKeepPosition);
    });
  }

  void _clearRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

  void _setLoaderIfIdle() {
    if (!(_retryTimer?.isActive ?? false)) {
      _setLoader(false);
    }
  }

  void _setLoader(bool value) {
    if (!mounted || _showLoader == value) return;
    setState(() {
      _showLoader = value;
    });
  }

  String _buildUrlWithToken(String url, HlsToken? token) {
    if (token == null) return url;
    try {
      final uri = Uri.parse(url);
      final updatedQuery = Map<String, String>.from(uri.queryParameters);
      updatedQuery['token'] = token.playlistToken;
      updatedQuery['exp'] = token.playlistExpiry.toString();
      final returnUri = uri.replace(queryParameters: updatedQuery).toString();
      debugPrint('returnUri>>>:\n$returnUri');
      return returnUri;
    } catch (_) {
      final separator = url.contains('?') ? '&' : '?';
      final returnUri =
          '$url${separator}token=${Uri.encodeComponent(token.playlistToken)}&exp=${token.playlistExpiry}';
      debugPrint('returnUri>>>:\n$returnUri');
      return returnUri;
    }
  }

  String _stripTokenParams(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.queryParameters.isEmpty) return url;
      final cleaned = Map<String, String>.from(uri.queryParameters);
      cleaned.remove('token');
      cleaned.remove('exp');
      return uri.replace(queryParameters: cleaned).toString();
    } catch (_) {
      return url;
    }
  }

  Map<String, String>? _buildTokenHeaders(HlsToken? token) {
    if (token == null) return null;
    return {
      'X-HLS-Token': token.playlistToken,
      'X-HLS-Exp': token.playlistExpiry.toString(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BetterPlayer(controller: _controller),
          if (_showLoader)
            const IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
