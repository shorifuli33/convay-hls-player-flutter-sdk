typedef ProxyUrlSigner = Future<Uri> Function(Uri targetUrl);

class LocalHlsProxy {
  bool get isRunning => false;

  Future<void> start({required ProxyUrlSigner urlSigner}) async {}

  Uri buildProxyUrl(Uri targetUrl) => targetUrl;

  Future<void> dispose() async {}
}
