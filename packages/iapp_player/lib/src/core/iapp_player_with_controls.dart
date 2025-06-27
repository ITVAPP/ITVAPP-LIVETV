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

  // 处理控制器事件更新 - 添加 mounted 检查
  void _onControllerChanged(IAppPlayerControllerEvent event) {
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

    // 关键修改：分离视频层和控件层的布局
    return Container(
      color: iappPlayerController
          .iappPlayerConfiguration.controlsConfiguration.backgroundColor,
      child: _buildPlayerStack(iappPlayerController, context),
    );
  }

  // 构建播放器层叠结构 - 新方法
  // 简化后的 _buildPlayerStack 方法
Widget _buildPlayerStack(
    IAppPlayerController iappPlayerController, BuildContext context) {
  if (iappPlayerController.iappPlayerDataSource == null) {
    return Container();
  }
  
  final configuration = iappPlayerController.iappPlayerConfiguration;
  var rotation = configuration.rotation;

  if (!(rotation <= 360 && rotation % 90 == 0)) {
    IAppPlayerUtils.log("旋转角度无效，使用默认旋转 0");
    rotation = 0;
  }

  _initialized = true;

  final bool placeholderOnTop = configuration.placeholderOnTop;
  
  // 计算视频宽高比
  double? aspectRatio;
  if (iappPlayerController.isFullScreen) {
    if (configuration.autoDetectFullscreenDeviceOrientation ||
        configuration.autoDetectFullscreenAspectRatio) {
      aspectRatio =
          iappPlayerController.videoPlayerController?.value.aspectRatio ?? 1.0;
    } else {
      aspectRatio = configuration.fullScreenAspectRatio ??
          IAppPlayerUtils.calculateAspectRatio(context);
    }
  } else {
    aspectRatio = iappPlayerController.getAspectRatio();
  }
  aspectRatio ??= 16 / 9;

  // 简化：移除 LayoutBuilder，直接使用 Stack
  return Stack(
    children: <Widget>[
      // 占位符（底层）
      if (placeholderOnTop) 
        _buildPlaceholder(iappPlayerController),
      
      // 视频层 - 只有这一层需要 AspectRatio
      Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Transform.rotate(
            angle: rotation * pi / 180,
            child: _IAppPlayerVideoFitWidget(
              iappPlayerController,
              iappPlayerController.getFit(),
            ),
          ),
        ),
      ),
      
      // 覆盖层 - 填满容器
      if (configuration.overlay != null)
        configuration.overlay!,
      
      // 字幕层 - 填满容器，让字幕组件自己处理位置
      IAppPlayerSubtitlesDrawer(
        iappPlayerController: iappPlayerController,
        iappPlayerSubtitlesConfiguration: subtitlesConfiguration,
        subtitles: iappPlayerController.subtitlesLines,
        playerVisibilityStream: playerVisibilityStreamController.stream,
      ),
      
      // 占位符（顶层）
      if (!placeholderOnTop)
        _buildPlaceholder(iappPlayerController),
      
      // 控件层 - 填满容器，用于检测点击和显示控件
      _buildControls(context, iappPlayerController),
    ],
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

  // 初始化视频适配组件 - 添加 mounted 检查
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
      // 视频内容填满 AspectRatio 分配的空间
      return Container(
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
