/*
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'hls_player.dart';

const String playlistAccessUrl =
    'https://streamrelay.convay.com/devcast/api/test/access';

HlsTokenRefresh createTokenRefreshFunction({
  String streamId = '65f5418b-4719-4231-9a99-d102304f6e9f',
}) {
  const int playlistRefreshThreshold = 20;
  HlsToken? cachedToken;

  int normalizeExpirySeconds(num expiration) {
    final value = expiration.toInt();
    // Treat large values as milliseconds since epoch.
    if (value > 9999999999) {
      return (value / 1000).floor();
    }
    return value;
  }

  bool needsRefresh(int expiry, int threshold) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeRemaining = expiry - now;
    return timeRemaining < threshold;
  }

  Future<HlsToken> getPlaylistAccess() async {
    final response = await http.post(
      Uri.parse(playlistAccessUrl),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'stream_id': streamId}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Playlist access failed: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw Exception('Invalid playlist access response');
    }

    final data = payload['data'];
    print('HLS DATA>>>>>: $data');
    if (data is! Map<String, dynamic>) {
      throw Exception('Missing playlist access data');
    }

    final token = data['token'];
    final expiration = data['expiration'];
    if (token is! String || expiration is! num) {
      throw Exception('Invalid playlist access payload');
    }

    final normalizedExpiry = normalizeExpirySeconds(expiration);
    final expiryTime =
        DateTime.fromMillisecondsSinceEpoch(normalizedExpiry * 1000);
    debugPrint('HLS token expires at: $expiryTime');
    return HlsToken(
      playlistToken: token,
      playlistExpiry: normalizedExpiry,
    );
  }

  return () async {
    if (cachedToken == null ||
        needsRefresh(cachedToken!.playlistExpiry, playlistRefreshThreshold)) {
      cachedToken = await getPlaylistAccess();
    }

    return cachedToken!;
  };
}
*/