import 'package:iapp_player/iapp_player.dart';

///Controller of Better Player List Video Player.
class IAppPlayerListVideoPlayerController {
  IAppPlayerController? _iappPlayerController;

  void setVolume(double volume) {
    _iappPlayerController?.setVolume(volume);
  }

  void pause() {
    _iappPlayerController?.pause();
  }

  void play() {
    _iappPlayerController?.play();
  }

  void seekTo(Duration duration) {
    _iappPlayerController?.seekTo(duration);
  }

  // ignore: use_setters_to_change_properties
  void setIAppPlayerController(
      IAppPlayerController? iappPlayerController) {
    _iappPlayerController = iappPlayerController;
  }

  void setMixWithOthers(bool mixWithOthers) {
    _iappPlayerController?.setMixWithOthers(mixWithOthers);
  }
}
