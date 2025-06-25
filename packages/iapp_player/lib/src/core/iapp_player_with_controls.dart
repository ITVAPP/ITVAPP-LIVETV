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

// 视频播放组件，渲染视频、控件和字幕
class IAppPlayerWithControls extends StatefulWidget {
  final IAppPlayerController? controller;

  const IAppPlayerWithControls({Key? key, this.controller}) : super(key: key);

  @override
  _IAppPlayerWithControlsState createState() =>
      _IAppPlayerWithControlsState();
}

class _IAppPlayerWithControlsState extends State<IAppPlayerWithControls> {
  // 字幕配置
  IAppPlayerSubtitlesConfiguration get subtitlesConfiguration =>
      widget.controller!.iappPlayerConfiguration.subtitlesConfiguration;

  // 控件配置
  IAppPlayerControlsConfiguration get controlsConfiguration =>
      widget.controller!.iappPlayerControlsConfiguration;

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

  // 处理控制器事件更新 - 关键修改：添加 mounted 检查
  void _onControllerChanged(IAppPlayerControllerEvent event) {
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
    final IAppPlayerController iappPlayerController =
        IAppPlayerController.of(context);
    final configuration = iappPlayerController.iappPlayerConfiguration;
    final controlsConfig = configuration.controlsConfiguration;
    
    // 音频模式判断：
    // 1. 不在全屏模式
    // 2. showControls 为 true
    // 3. audioHeight 大于 0
    final bool shouldUseAudioMode = 
        !iappPlayerController.isFullScreen &&
        controlsConfig.showControls &&
        controlsConfig.audioHeight != null &&
        controlsConfig.audioHeight! > 0;
    
    // 音频模式处理：直接返回控制条，不使用 AspectRatio
    if (shouldUseAudioMode) {
      return Container(
        width: double.infinity,
        height: controlsConfig.effectiveAudioHeight,
        color: controlsConfig.backgroundColor,
        child: Stack(
          children: [
            // 使用 Offstage 隐藏视频部分
            Offstage(
              offstage: true,
              child: _IAppPlayerVideoFitWidget(
                iappPlayerController,
                iappPlayerController.getFit(),
              ),
            ),
            // 显示控制条
            _buildControls(context, iappPlayerController),
          ],
        ),
      );
    }

    // 以下是原有的视频模式代码，保持不变
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

  // 构建视频播放器，包含控件和字幕
  Container _buildPlayerWithControls(
      IAppPlayerController iappPlayerController, BuildContext context) {
    final configuration = iappPlayerController.iappPlayerConfiguration;
    var rotation = configuration.rotation;

    if (!(rotation <= 360 && rotation % 90 == 0)) {
      IAppPlayerUtils.log("旋转角度无效，使用默认旋转 0");
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

  // 构建占位符组件
  Widget _buildPlaceholder(IAppPlayerController iappPlayerController) {
    return iappPlayerController.iappPlayerDataSource!.placeholder ??
        iappPlayerController.iappPlayerConfiguration.placeholder ??
        Container();
  }

  // 构建控件，支持 Material 或 Cupertino 风格
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

  // 构建 Material 风格控件
  Widget _buildMaterialControl() {
    return IAppPlayerMaterialControls(
      onControlsVisibilityChanged: onControlsVisibilityChanged,
      controlsConfiguration: controlsConfiguration,
    );
  }

  // 构建 Cupertino 风格控件
  Widget _buildCupertinoControl() {
    return IAppPlayerCupertinoControls(
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
  // 视频播放器控制器
  VideoPlayerController? get controller =>
      widget.iappPlayerController.videoPlayerController;

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
        widget.iappPlayerController.controllerEventStream.listen((event) {
      // 新增：在处理事件前检查组件是否仍然挂载
      if (!mounted) {
        return;
      }
      
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
