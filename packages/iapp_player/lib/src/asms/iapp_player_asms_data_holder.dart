import 'package:iapp_player/src/asms/iapp_player_asms_audio_track.dart';
import 'package:iapp_player/src/asms/iapp_player_asms_subtitle.dart';
import 'package:iapp_player/src/asms/iapp_player_asms_track.dart';

class IAppPlayerAsmsDataHolder {
  List<IAppPlayerAsmsTrack>? tracks;
  List<IAppPlayerAsmsSubtitle>? subtitles;
  List<IAppPlayerAsmsAudioTrack>? audios;

  IAppPlayerAsmsDataHolder({this.tracks, this.subtitles, this.audios});
}
