import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';

// Flutter imports:
import 'package:flutter/material.dart';

///Special version of Better Player used to play videos in playlist.
class IAppPlayerPlaylist extends StatefulWidget {
  final List<IAppPlayerDataSource> iappPlayerDataSourceList;
  final IAppPlayerConfiguration iappPlayerConfiguration;
  final IAppPlayerPlaylistConfiguration iappPlayerPlaylistConfiguration;

  const IAppPlayerPlaylist({
    Key? key,
    required this.iappPlayerDataSourceList,
    required this.iappPlayerConfiguration,
    required this.iappPlayerPlaylistConfiguration,
  }) : super(key: key);

  @override
  IAppPlayerPlaylistState createState() => IAppPlayerPlaylistState();
}

///State of IAppPlayerPlaylist, used to access IAppPlayerPlaylistController.
class IAppPlayerPlaylistState extends State<IAppPlayerPlaylist> {
  IAppPlayerPlaylistController? _iappPlayerPlaylistController;

  IAppPlayerController? get _iappPlayerController =>
      _iappPlayerPlaylistController!.iappPlayerController;

  ///Get IAppPlayerPlaylistController
  IAppPlayerPlaylistController? get iappPlayerPlaylistController =>
      _iappPlayerPlaylistController;

  @override
  void initState() {
    _iappPlayerPlaylistController = IAppPlayerPlaylistController(
        widget.iappPlayerDataSourceList,
        iappPlayerConfiguration: widget.iappPlayerConfiguration,
        iappPlayerPlaylistConfiguration:
            widget.iappPlayerPlaylistConfiguration);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _iappPlayerController!.getAspectRatio() ??
          IAppPlayerUtils.calculateAspectRatio(context),
      child: IAppPlayer(
        controller: _iappPlayerController!,
      ),
    );
  }

  @override
  void dispose() {
    _iappPlayerPlaylistController!.dispose();
    super.dispose();
  }
}
