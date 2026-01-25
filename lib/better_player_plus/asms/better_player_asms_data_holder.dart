import 'package:convay_hls_player/better_player_plus/asms/better_player_asms_audio_track.dart';
import 'package:convay_hls_player/better_player_plus/asms/better_player_asms_subtitle.dart';
import 'package:convay_hls_player/better_player_plus/asms/better_player_asms_track.dart';

class BetterPlayerAsmsDataHolder {
  BetterPlayerAsmsDataHolder({this.tracks, this.subtitles, this.audios});
  List<BetterPlayerAsmsTrack>? tracks;
  List<BetterPlayerAsmsSubtitle>? subtitles;
  List<BetterPlayerAsmsAudioTrack>? audios;
}
