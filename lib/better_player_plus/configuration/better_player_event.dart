import 'package:convay_hls_player/better_player_plus/configuration/better_player_event_type.dart';

///Event that happens in player. It can be used to determine current player state
///on higher layer.
class BetterPlayerEvent {
  BetterPlayerEvent(this.betterPlayerEventType, {this.parameters});
  final BetterPlayerEventType betterPlayerEventType;
  final Map<String, dynamic>? parameters;
}
