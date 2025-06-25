import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/configuration/iapp_player_controller_event.dart';
import 'package:iapp_player/src/controls/iapp_player_cupertino_controls.dart';
import 'package:iapp_player/src/controls/iapp_player_material_controls.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:iapp_player/src/subtitles/iapp_player_subtitles_drawer.dart';
import 'package:iapp_player/src/video_player/video_player.dart';
import 'package:flutter/material.dart';

class IAppPlayerWithControls extends StatefulWidget {
  final IAppPlayerController? controller;

  const IAppPlayerWithControls({Key? key, this.controller}) : super(key: key);

  @override
  _IAppPlayerWithControlsState createState() =>
      _IAppPlayerWithControlsState();
}

class _IAppPlayerWithControlsState extends State<IAppPlayerWithControls> {
  IAppPlayerSubtitlesConfiguration get subtitlesConfiguration =>
      widget.controller!.iappPlayerConfiguration.subtitlesConfiguration;

  IAppPlayerControlsConfiguration get controlsConfiguration =>
      widget.controller!.iappPlayerControlsConfiguration;

  final StreamController<bool> playerVisibilityStreamController =
      StreamController();

  bool _initialized = false;

  StreamSubscription? _controllerEventSubscription;

  @override
  void initState() {
    playerVisibilityStreamController.add(true);
    _controllerEventSubscription =
        widget.controller!.controllerEventStream.listen(_onControllerChanged);
    super.initState();
  }

  @override
  void didUpdateWidget(IAppPlayerWithControls oldWidget) {
    if (oldWidget.controller != widget.controller) {
      _controllerEventSubscription?.cancel();
      _controllerEventSubscription =
          widget.controller!.controllerEventStream.listen(_onControllerChanged);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    playerVisibilityStreamController.close();
    _controllerEventSubscription?.cancel();
    super.dispose();
  }

  void _onControllerChanged(IAppPlayerControllerEvent event) {
    setState(() {
      if (!_initialized) {
        _initialized = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final IAppPlayerController iappPlayerController =
        IAppPlayerController.of(context);

    double? aspectRatio;
    if (iappPlayerController.isFullScreen) {
      if (iappPlayerController.iappPlayerConfiguration
              .autoDetectFullscreenDeviceOrientation ||
          iappPlayerController
              .iappPlayerConfiguration.autoDetectFullscreenAspectRatio) {
        aspectRatio =
            iappPlayerController.videoPlayerController?.value.aspectRatio ??
                1.0;
      } else {
        aspectRatio = iappPlayerController
                .iappPlayerConfiguration.fullScreenAspectRatio ??
            IAppPlayerUtils.calculateAspectRatio(context);
      }
    } else {
      aspectRatio = iappPlayerController.getAspectRatio();
    }

    aspectRatio ??= 16 / 9;
    final innerContainer = Container(
      width: double.infinity,
      color: iappPlayerController
          .iappPlayerConfiguration.controlsConfiguration.backgroundColor,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: _buildPlayerWithControls(iappPlayerController, context),
      ),
    );

    if (iappPlayerController.iappPlayerConfiguration.expandToFill) {
      return Center(child: innerContainer);
    } else {
      return innerContainer;
    }
  }

  Container _buildPlayerWithControls(
      IAppPlayerController iappPlayerController, BuildContext context) {
    final configuration = iappPlayerController.iappPlayerConfiguration;
    var rotation = configuration.rotation;

    if (!(rotation <= 360 && rotation % 90 == 0)) {
      IAppPlayerUtils.log("Invalid rotation provided. Using rotation = 0");
      rotation = 0;
    }
    if (iappPlayerController.iappPlayerDataSource == null) {
      return Container();
    }
    _initialized = true;

    final bool placeholderOnTop =
        iappPlayerController.iappPlayerConfiguration.placeholderOnTop;
    // ignore: avoid_unnecessary_containers
    return Container(
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          if (placeholderOnTop) _buildPlaceholder(iappPlayerController),
          Transform.rotate(
            angle: rotation * pi / 180,
            child: _IAppPlayerVideoFitWidget(
              iappPlayerController,
              iappPlayerController.getFit(),
            ),
          ),
          iappPlayerController.iappPlayerConfiguration.overlay ??
              Container(),
          IAppPlayerSubtitlesDrawer(
            iappPlayerController: iappPlayerController,
            iappPlayerSubtitlesConfiguration: subtitlesConfiguration,
            subtitles: iappPlayerController.subtitlesLines,
            playerVisibilityStream: playerVisibilityStreamController.stream,
          ),
          if (!placeholderOnTop) _buildPlaceholder(iappPlayerController),
          _buildControls(context, iappPlayerController),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(IAppPlayerController iappPlayerController) {
    return iappPlayerController.iappPlayerDataSource!.placeholder ??
        iappPlayerController.iappPlayerConfiguration.placeholder ??
        Container();
  }

  Widget _buildControls(
    BuildContext context,
    IAppPlayerController iappPlayerController,
  ) {
    if (controlsConfiguration.showControls) {
      IAppPlayerTheme? playerTheme = controlsConfiguration.playerTheme;
      if (playerTheme == null) {
        if (Platform.isAndroid) {
          playerTheme = IAppPlayerTheme.material;
        } else {
          playerTheme = IAppPlayerTheme.cupertino;
        }
      }

      if (controlsConfiguration.customControlsBuilder != null &&
          playerTheme == IAppPlayerTheme.custom) {
        return controlsConfiguration.customControlsBuilder!(
            iappPlayerController, onControlsVisibilityChanged);
      } else if (playerTheme == IAppPlayerTheme.material) {
        return _buildMaterialControl();
      } else if (playerTheme == IAppPlayerTheme.cupertino) {
        return _buildCupertinoControl();
      }
    }

    return const SizedBox();
  }

  Widget _buildMaterialControl() {
    return IAppPlayerMaterialControls(
      onControlsVisibilityChanged: onControlsVisibilityChanged,
      controlsConfiguration: controlsConfiguration,
    );
  }

  Widget _buildCupertinoControl() {
    return IAppPlayerCupertinoControls(
      onControlsVisibilityChanged: onControlsVisibilityChanged,
      controlsConfiguration: controlsConfiguration,
    );
  }

  void onControlsVisibilityChanged(bool state) {
    playerVisibilityStreamController.add(state);
  }
}

///Widget used to set the proper box fit of the video. Default fit is 'fill'.
class _IAppPlayerVideoFitWidget extends StatefulWidget {
  const _IAppPlayerVideoFitWidget(
    this.iappPlayerController,
    this.boxFit, {
    Key? key,
  }) : super(key: key);

  final IAppPlayerController iappPlayerController;
  final BoxFit boxFit;

  @override
  _IAppPlayerVideoFitWidgetState createState() =>
      _IAppPlayerVideoFitWidgetState();
}

class _IAppPlayerVideoFitWidgetState
    extends State<_IAppPlayerVideoFitWidget> {
  VideoPlayerController? get controller =>
      widget.iappPlayerController.videoPlayerController;

  bool _initialized = false;

  VoidCallback? _initializedListener;

  bool _started = false;

  StreamSubscription? _controllerEventSubscription;

  @override
  void initState() {
    super.initState();
    if (!widget.iappPlayerController.iappPlayerConfiguration
        .showPlaceholderUntilPlay) {
      _started = true;
    } else {
      _started = widget.iappPlayerController.hasCurrentDataSourceStarted;
    }

    _initialize();
  }

  @override
  void didUpdateWidget(_IAppPlayerVideoFitWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iappPlayerController.videoPlayerController != controller) {
      if (_initializedListener != null) {
        oldWidget.iappPlayerController.videoPlayerController!
            .removeListener(_initializedListener!);
      }
      _initialized = false;
      _initialize();
    }
  }

  void _initialize() {
    if (controller?.value.initialized == false) {
      _initializedListener = () {
        if (!mounted) {
          return;
        }

        if (_initialized != controller!.value.initialized) {
          _initialized = controller!.value.initialized;
          setState(() {});
        }
      };
      controller!.addListener(_initializedListener!);
    } else {
      _initialized = true;
    }

    _controllerEventSubscription =
        widget.iappPlayerController.controllerEventStream.listen((event) {
      if (event == IAppPlayerControllerEvent.play) {
        if (!_started) {
          setState(() {
            _started =
                widget.iappPlayerController.hasCurrentDataSourceStarted;
          });
        }
      }
      if (event == IAppPlayerControllerEvent.setupDataSource) {
        setState(() {
          _started = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized && _started) {
      return Center(
        child: ClipRect(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            child: FittedBox(
              fit: widget.boxFit,
              child: SizedBox(
                width: controller!.value.size?.width ?? 0,
                height: controller!.value.size?.height ?? 0,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ),
      );
    } else {
      return const SizedBox();
    }
  }

  @override
  void dispose() {
    if (_initializedListener != null) {
      widget.iappPlayerController.videoPlayerController!
          .removeListener(_initializedListener!);
    }
    _controllerEventSubscription?.cancel();
    super.dispose();
  }
}
