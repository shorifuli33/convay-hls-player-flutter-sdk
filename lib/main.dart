import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'hls_player.dart';

void main() {
  runApp(const HlsPlayerApp());
}

class HlsPlayerApp extends StatelessWidget {
  const HlsPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Convay Player',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const HlsPlayerScreen(),
    );
  }
}

class HlsPlayerScreen extends StatefulWidget {
  const HlsPlayerScreen({
    super.key,
    this.tokenRefreshMethod,
  });

  final HlsTokenRefresh? tokenRefreshMethod;

  @override
  State<HlsPlayerScreen> createState() => _HlsPlayerScreenState();
}

class _HlsPlayerScreenState extends State<HlsPlayerScreen> {
  static const String defaultStreamUrl =
      'https://cast.convay.com/hls/stream.m3u8';
  static const String _playlistAccessUrl =
      'https://streamrelay.convay.com/devcast/api/test/access';
  static const String _streamId = '37a3209e-3b9b-4013-9c66-4ba1cb864165';

  late String _streamUrl;

  @override
  void initState() {
    super.initState();
    final queryStreamUrl = Uri.base.queryParameters['streamUrl'];
    _streamUrl = queryStreamUrl ?? defaultStreamUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convay Player')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: HlsPlayer(
                  streamUrl: _streamUrl.trim(),
                  abrEnabled: true,
                  isLive: true,
                  autoPlay: true,
                  muted: false,
                  playlistRefreshThreshold: 20,
                  tokenRefreshMethod: () async {
                    int normalizeExpirySeconds(num expiration) {
                      final value = expiration.toInt();
                      if (value > 9999999999) {
                        return (value / 1000).floor();
                      }
                      return value;
                    }

                    final response = await http.post(
                      Uri.parse(_playlistAccessUrl),
                      headers: const {'Content-Type': 'application/json'},
                      body: jsonEncode({'stream_id': _streamId}),
                    );

                    if (response.statusCode < 200 ||
                        response.statusCode >= 300) {
                      throw Exception(
                          'Playlist access failed: ${response.statusCode}');
                    }

                    final payload = jsonDecode(response.body);
                    if (payload is! Map<String, dynamic>) {
                      throw Exception('Invalid playlist access response');
                    }

                    final data = payload['data'];
                    if (data is! Map<String, dynamic>) {
                      throw Exception('Missing playlist access data');
                    }

                    final token = data['token'];
                    final expiration = data['expiration'];
                    if (token is! String || expiration is! num) {
                      throw Exception('Invalid playlist access payload');
                    }

                    final normalizedExpiry = normalizeExpirySeconds(expiration);
                    // final expiryTime = DateTime.fromMillisecondsSinceEpoch(
                    //     normalizedExpiry * 1000);
                    // debugPrint('HLS token expires at: $expiryTime');
                    return HlsToken(
                      playlistToken: token,
                      playlistExpiry: normalizedExpiry,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
