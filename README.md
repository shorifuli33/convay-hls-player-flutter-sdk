# Flutter HLS Player

Minimal Flutter HLS player built on top of `better_player`, with token refresh
support for time-limited HLS URLs.

## Setup

1. Install dependencies:

```
flutter pub get
```

2. Run the sample app:

```
flutter run
```

## Usage

Use the `HlsPlayer` widget:

```
HlsPlayer(
  streamUrl: 'https://example.com/stream.m3u8',
  abrEnabled: true,
  isLive: false,
  autoPlay: true,
)
```

## Token refresh (optional)

If your HLS URLs require time-limited tokens, provide a refresh function:

```
HlsPlayer(
  streamUrl: 'https://example.com/stream.m3u8',
  tokenRefreshMethod: () async {
    return const HlsToken(
      playlistToken: 'your-token',
      playlistExpiry: 1700000000,
    );
  },
)
```

## Notes

- `lib/hls_player.dart` contains the HLS player widget and refresh logic.
- The Android player updates HLS tokens without interrupting playback.
