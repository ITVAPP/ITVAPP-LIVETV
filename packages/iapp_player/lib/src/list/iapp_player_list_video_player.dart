import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:flutter/material.dart';

///Special version of Better Player which is used to play video in list view.
class IAppPlayerListVideoPlayer extends StatefulWidget {
  ///Video to show
  final IAppPlayerDataSource dataSource;

  ///Video player configuration
  final IAppPlayerConfiguration configuration;

  ///Fraction of the screen height that will trigger play/pause. For example
  ///if playFraction is 0.6 video will be played if 60% of player height is
  ///visible.
  final double playFraction;

  ///Flag to determine if video should be auto played
  final bool autoPlay;

  ///Flag to determine if video should be auto paused
  final bool autoPause;

  final IAppPlayerListVideoPlayerController?
      iappPlayerListVideoPlayerController;

  const IAppPlayerListVideoPlayer(
    this.dataSource, {
    this.configuration = const IAppPlayerConfiguration(),
    this.playFraction = 0.6,
    this.autoPlay = true,
    this.autoPause = true,
    this.iappPlayerListVideoPlayerController,
    Key? key,
  })  : assert(playFraction >= 0.0 && playFraction <= 1.0,
            "Play fraction can't be null and must be between 0.0 and 1.0"),
        super(key: key);

  @override
  _IAppPlayerListVideoPlayerState createState() =>
      _IAppPlayerListVideoPlayerState();
}

class _IAppPlayerListVideoPlayerState
    extends State<IAppPlayerListVideoPlayer>
    with AutomaticKeepAliveClientMixin<IAppPlayerListVideoPlayer> {
  IAppPlayerController? _iappPlayerController;
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    _iappPlayerController = IAppPlayerController(
      widget.configuration.copyWith(
        playerVisibilityChangedBehavior: onVisibilityChanged,
      ),
      iappPlayerDataSource: widget.dataSource,
      iappPlayerPlaylistConfiguration:
          const IAppPlayerPlaylistConfiguration(),
    );

    if (widget.iappPlayerListVideoPlayerController != null) {
      widget.iappPlayerListVideoPlayerController!
          .setIAppPlayerController(_iappPlayerController);
    }
  }

  @override
  void dispose() {
    _iappPlayerController!.dispose();
    _isDisposing = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AspectRatio(
      aspectRatio: _iappPlayerController!.getAspectRatio() ??
          IAppPlayerUtils.calculateAspectRatio(context),
      child: IAppPlayer(
        key: Key("${_getUniqueKey()}_player"),
        controller: _iappPlayerController!,
      ),
    );
  }

  void onVisibilityChanged(double visibleFraction) async {
    final bool? isPlaying = _iappPlayerController!.isPlaying();
    final bool? initialized = _iappPlayerController!.isVideoInitialized();
    if (visibleFraction >= widget.playFraction) {
      if (widget.autoPlay && initialized! && !isPlaying! && !_isDisposing) {
        _iappPlayerController!.play();
      }
    } else {
      if (widget.autoPause && initialized! && isPlaying! && !_isDisposing) {
        _iappPlayerController!.pause();
      }
    }
  }

  String _getUniqueKey() => widget.dataSource.hashCode.toString();

  @override
  bool get wantKeepAlive => true;
}
