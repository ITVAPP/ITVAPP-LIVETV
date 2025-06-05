import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:better_player/better_player.dart';
import 'package:better_player/src/configuration/better_player_controller_event.dart';
import 'package:better_player/src/controls/better_player_cupertino_controls.dart';
import 'package:better_player/src/controls/better_player_material_controls.dart';
import 'package:better_player/src/core/better_player_utils.dart';
import 'package:better_player/src/subtitles/better_player_subtitles_drawer.dart';
import 'package:better_player/src/video_player/video_player.dart';
import 'package:flutter/material.dart';

// 视频播放组件，渲染视频、控件和字幕
class BetterPlayerWithControls extends StatefulWidget {
  final BetterPlayerController? controller;

  const BetterPlayerWithControls({Key? key, this.controller}) : super(key: key);

  @override
  _BetterPlayerWithControlsState createState() =>
      _BetterPlayerWithControlsState();
}

class _BetterPlayerWithControlsState extends State<BetterPlayerWithControls> {
  // 字幕配置
  BetterPlayerSubtitlesConfiguration get subtitlesConfiguration =>
      widget.controller!.betterPlayerConfiguration.subtitlesConfiguration;

  // 控件配置
  BetterPlayerControlsConfiguration get controlsConfiguration =>
      widget.controller!.betterPlayerControlsConfiguration;

  // 播放器可见性状态流控制器
  final StreamController<bool> playerVisibilityStreamController =
      StreamController();

  // 初始化状态
  bool _initialized = false;

  // 控制器事件订阅
  StreamSubscription? _controllerEventSubscription;

  @override
  void initState() {
    playerVisibilityStreamController.add(true);
    _controllerEventSubscription =
        widget.controller!.controllerEventStream.listen(_onControllerChanged);
    super.initState();
  }

  @override
  void didUpdateWidget(BetterPlayerWithControls oldWidget) {
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

  // 处理控制器事件更新 - 关键修改：添加 mounted 检查
  void _onControllerChanged(BetterPlayerControllerEvent event) {
    // 新增：检查组件是否仍然挂载
    if (!mounted) {
      return;
    }
    
    setState(() {
      if (!_initialized) {
        _initialized = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final BetterPlayerController betterPlayerController =
        BetterPlayerController.of(context);

    double? aspectRatio;
    if (betterPlayerController.isFullScreen) {
      if (betterPlayerController.betterPlayerConfiguration
              .autoDetectFullscreenDeviceOrientation ||
          betterPlayerController
              .betterPlayerConfiguration.autoDetectFullscreenAspectRatio) {
        aspectRatio =
            betterPlayerController.videoPlayerController?.value.aspectRatio ??
                1.0;
      } else {
        aspectRatio = betterPlayerController
                .betterPlayerConfiguration.fullScreenAspectRatio ??
            BetterPlayerUtils.calculateAspectRatio(context);
      }
    } else {
      aspectRatio = betterPlayerController.getAspectRatio();
    }

    aspectRatio ??= 16 / 9;
    final innerContainer = Container(
      width: double.infinity,
      color: betterPlayerController
          .betterPlayerConfiguration.controlsConfiguration.backgroundColor,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: _buildPlayerWithControls(betterPlayerController, context),
      ),
    );

    if (betterPlayerController.betterPlayerConfiguration.expandToFill) {
      return Center(child: innerContainer);
    } else {
      return innerContainer;
    }
  }

  // 构建视频播放器，包含控件和字幕
  Container _buildPlayerWithControls(
      BetterPlayerController betterPlayerController, BuildContext context) {
    final configuration = betterPlayerController.betterPlayerConfiguration;
    var rotation = configuration.rotation;

    if (!(rotation <= 360 && rotation % 90 == 0)) {
      BetterPlayerUtils.log("旋转角度无效，使用默认旋转 0");
      rotation = 0;
    }
    if (betterPlayerController.betterPlayerDataSource == null) {
      return Container();
    }
    _initialized = true;

    final bool placeholderOnTop =
        betterPlayerController.betterPlayerConfiguration.placeholderOnTop;
    // ignore: avoid_unnecessary_containers
    return Container(
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          if (placeholderOnTop) _buildPlaceholder(betterPlayerController),
          Transform.rotate(
            angle: rotation * pi / 180,
            child: _BetterPlayerVideoFitWidget(
              betterPlayerController,
              betterPlayerController.getFit(),
            ),
          ),
          betterPlayerController.betterPlayerConfiguration.overlay ??
              Container(),
          BetterPlayerSubtitlesDrawer(
            betterPlayerController: betterPlayerController,
            betterPlayerSubtitlesConfiguration: subtitlesConfiguration,
            subtitles: betterPlayerController.subtitlesLines,
            playerVisibilityStream: playerVisibilityStreamController.stream,
          ),
          if (!placeholderOnTop) _buildPlaceholder(betterPlayerController),
          _buildControls(context, betterPlayerController),
        ],
      ),
    );
  }

  // 构建占位符组件
  Widget _buildPlaceholder(BetterPlayerController betterPlayerController) {
    return betterPlayerController.betterPlayerDataSource!.placeholder ??
        betterPlayerController.betterPlayerConfiguration.placeholder ??
        Container();
  }

  // 构建控件，支持 Material 或 Cupertino 风格
  Widget _buildControls(
    BuildContext context,
    BetterPlayerController betterPlayerController,
  ) {
    if (controlsConfiguration.showControls) {
      BetterPlayerTheme? playerTheme = controlsConfiguration.playerTheme;
      if (playerTheme == null) {
        if (Platform.isAndroid) {
          playerTheme = BetterPlayerTheme.material;
        } else {
          playerTheme = BetterPlayerTheme.cupertino;
        }
      }

      if (controlsConfiguration.customControlsBuilder != null &&
          playerTheme == BetterPlayerTheme.custom) {
        return controlsConfiguration.customControlsBuilder!(
            betterPlayerController, onControlsVisibilityChanged);
      } else if (playerTheme == BetterPlayerTheme.material) {
        return _buildMaterialControl();
      } else if (playerTheme == BetterPlayerTheme.cupertino) {
        return _buildCupertinoControl();
      }
    }

    return const SizedBox();
  }

  // 构建 Material 风格控件
  Widget _buildMaterialControl() {
    return BetterPlayerMaterialControls(
      onControlsVisibilityChanged: onControlsVisibilityChanged,
      controlsConfiguration: controlsConfiguration,
    );
  }

  // 构建 Cupertino 风格控件
  Widget _buildCupertinoControl() {
    return BetterPlayerCupertinoControls(
      onControlsVisibilityChanged: onControlsVisibilityChanged,
      controlsConfiguration: controlsConfiguration,
    );
  }

  // 处理控件可见性变化
  void onControlsVisibilityChanged(bool state) {
    playerVisibilityStreamController.add(state);
  }
}

// 设置视频适配模式的组件，默认适配为填充
class _BetterPlayerVideoFitWidget extends StatefulWidget {
  const _BetterPlayerVideoFitWidget(
    this.betterPlayerController,
    this.boxFit, {
    Key? key,
  }) : super(key: key);

  final BetterPlayerController betterPlayerController;
  final BoxFit boxFit;

  @override
  _BetterPlayerVideoFitWidgetState createState() =>
      _BetterPlayerVideoFitWidgetState();
}

class _BetterPlayerVideoFitWidgetState
    extends State<_BetterPlayerVideoFitWidget> {
  // 视频播放器控制器
  VideoPlayerController? get controller =>
      widget.betterPlayerController.videoPlayerController;

  // 初始化状态
  bool _initialized = false;

  // 初始化监听器
  VoidCallback? _initializedListener;

  // 播放开始状态
  bool _started = false;

  // 控制器事件订阅
  StreamSubscription? _controllerEventSubscription;

  @override
  void initState() {
    super.initState();
    if (!widget.betterPlayerController.betterPlayerConfiguration
        .showPlaceholderUntilPlay) {
      _started = true;
    } else {
      _started = widget.betterPlayerController.hasCurrentDataSourceStarted;
    }

    _initialize();
  }

  @override
  void didUpdateWidget(_BetterPlayerVideoFitWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.betterPlayerController.videoPlayerController != controller) {
      if (_initializedListener != null) {
        oldWidget.betterPlayerController.videoPlayerController!
            .removeListener(_initializedListener!);
      }
      _initialized = false;
      _initialize();
    }
  }

  // 初始化视频适配组件 - 关键修改：添加 mounted 检查
  void _initialize() {
    if (controller?.value.initialized == false) {
      _initializedListener = () {
        // 新增：检查组件是否仍然挂载
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
        widget.betterPlayerController.controllerEventStream.listen((event) {
      // 新增：在处理事件前检查组件是否仍然挂载
      if (!mounted) {
        return;
      }
      
      if (event == BetterPlayerControllerEvent.play) {
        if (!_started) {
          setState(() {
            _started =
                widget.betterPlayerController.hasCurrentDataSourceStarted;
          });
        }
      }
      if (event == BetterPlayerControllerEvent.setupDataSource) {
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
      widget.betterPlayerController.videoPlayerController!
          .removeListener(_initializedListener!);
    }
    _controllerEventSubscription?.cancel();
    super.dispose();
  }
}
