import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef ProxyUrlSigner = Future<Uri> Function(Uri targetUrl);

class LocalHlsProxy {
  static const String _proxyPath = '/proxy';
  HttpServer? _server;
  Uri? _baseUri;
  ProxyUrlSigner? _urlSigner;
  String? _secret;
  final http.Client _client = http.Client();

  bool get isRunning => _server != null;

  Future<void> start({required ProxyUrlSigner urlSigner}) async {
    if (_server != null) return;
    _urlSigner = urlSigner;
    _secret = _generateSecret();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _baseUri = Uri.parse('http://127.0.0.1:${_server!.port}');
    unawaited(_serveRequests());
    debugPrint('Local HLS proxy started at $_baseUri');
  }

  String _generateSecret() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  Uri buildProxyUrl(Uri targetUrl) {
    final baseUri = _baseUri;
    if (baseUri == null) {
      return targetUrl;
    }
    return baseUri.replace(
      path: _proxyPath,
      queryParameters: {
        'url': targetUrl.toString(),
        'key': _secret,
      },
    );
  }

  Future<void> dispose() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
    _client.close();
  }

  Future<void> _serveRequests() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    if (request.uri.path != _proxyPath) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final key = request.uri.queryParameters['key'];
    if (key == null || key != _secret) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final target = request.uri.queryParameters['url'];
    if (target == null || target.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final targetUrl = Uri.tryParse(target);
    if (targetUrl == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final signedUrl = await _signUrl(targetUrl);
    await _proxyRequest(request, signedUrl, targetUrl);
  }

  Future<Uri> _signUrl(Uri targetUrl) async {
    final signer = _urlSigner;
    if (signer == null) return targetUrl;
    try {
      return await signer(targetUrl);
    } catch (error) {
      debugPrint('Local HLS proxy signer failed: $error');
      return targetUrl;
    }
  }

  Future<void> _proxyRequest(
    HttpRequest request,
    Uri signedUrl,
    Uri originalUrl,
  ) async {
    http.StreamedResponse upstreamResponse;
    try {
      final upstreamRequest = http.Request(request.method, signedUrl);
      upstreamRequest.headers['accept-encoding'] = 'identity';
      request.headers.forEach((name, values) {
        if (_isHopByHopHeader(name)) return;
        if (name.toLowerCase() == 'host') return;
        upstreamRequest.headers[name] = values.join(',');
      });
      upstreamResponse = await _client.send(upstreamRequest);
    } catch (error) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    final contentType =
        upstreamResponse.headers['content-type']?.toLowerCase() ?? '';
    final isPlaylist =
        contentType.contains('application/vnd.apple.mpegurl') ||
            contentType.contains('application/x-mpegurl') ||
            signedUrl.path.toLowerCase().endsWith('.m3u8');

    request.response.statusCode = upstreamResponse.statusCode;
    upstreamResponse.headers.forEach((name, value) {
      final lower = name.toLowerCase();
      if (lower == 'content-length') return;
      if (lower == 'content-encoding') return;
      request.response.headers.set(name, value);
    });

    if (!isPlaylist) {
      await request.response.addStream(upstreamResponse.stream);
      await request.response.close();
      return;
    }

    final body = await upstreamResponse.stream.bytesToString();
    final rewritten = _rewritePlaylist(body, originalUrl);
    final bytes = utf8.encode(rewritten);
    request.response.headers.set(
      'content-type',
      'application/vnd.apple.mpegurl; charset=utf-8',
    );
    request.response.headers.set('content-length', bytes.length);
    request.response.add(bytes);
    await request.response.close();
  }

  String _rewritePlaylist(String body, Uri baseUrl) {
    final lines = const LineSplitter().convert(body);
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        buffer.writeln(line);
        continue;
      }
      if (line.startsWith('#')) {
        buffer.writeln(_rewriteUriAttributes(line, baseUrl));
        continue;
      }
      final leading = line.substring(0, line.length - line.trimLeft().length);
      final resolved = baseUrl.resolve(line.trim());
      buffer.writeln('$leading${buildProxyUrl(resolved)}');
    }
    return buffer.toString();
  }

  String _rewriteUriAttributes(String line, Uri baseUrl) {
    final uriAttribute = RegExp(r'URI="([^"]+)"');
    return line.replaceAllMapped(uriAttribute, (match) {
      final raw = match.group(1);
      if (raw == null || raw.isEmpty) {
        return match.group(0) ?? '';
      }
      final resolved = baseUrl.resolve(raw);
      return 'URI="${buildProxyUrl(resolved)}"';
    });
  }

  bool _isHopByHopHeader(String name) {
    switch (name.toLowerCase()) {
      case 'connection':
      case 'keep-alive':
      case 'proxy-authenticate':
      case 'proxy-authorization':
      case 'te':
      case 'trailers':
      case 'transfer-encoding':
      case 'upgrade':
        return true;
      default:
        return false;
    }
  }
}
