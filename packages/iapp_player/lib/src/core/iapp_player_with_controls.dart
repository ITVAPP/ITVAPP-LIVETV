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

/// 视频播放组件 - 重构版本
/// 负责协调视频渲染、控件层和字幕层的布局
class IAppPlayerWithControls extends StatefulWidget {
  final IAppPlayerController? controller;

  const IAppPlayerWithControls({Key? key, this.controller}) : super(key: key);

  @override
  _IAppPlayerWithControlsState createState() =>
      _IAppPlayerWithControlsState();
}

class _IAppPlayerWithControlsState extends State<IAppPlayerWithControls> {
  // 控制器相关
  late IAppPlayerController _controller;
  StreamSubscription? _controllerEventSubscription;
  
  // 状态管理
  bool _initialized = false;
  
  // 控件可见性流
  final StreamController<bool> _playerVisibilityStreamController =
      StreamController<bool>.broadcast();

  @override
  void initState() {
    super.initState();
    _playerVisibilityStreamController.add(true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 获取控制器
    final newController = widget.controller ?? IAppPlayerController.of(context);
    if (_controller != newController) {
      // 取消旧的订阅
      _controllerEventSubscription?.cancel();
      
      // 更新控制器引用
      _controller = newController;
      
      // 订阅新的事件
      _controllerEventSubscription = 
          _controller.controllerEventStream.listen(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _playerVisibilityStreamController.close();
    _controllerEventSubscription?.cancel();
    super.dispose();
  }

  /// 处理控制器事件
  void _onControllerChanged(IAppPlayerControllerEvent event) {
    if (!mounted) return;
    
    setState(() {
      _initialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 计算宽高比
    final aspectRatio = _calculateAspectRatio();
    
    // 构建播放器容器
    final playerContainer = Container(
      width: double.infinity,
      color: _controller.iappPlayerConfiguration.controlsConfiguration.backgroundColor,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: _buildPlayerStack(),
      ),
    );

    // 根据配置决定是否居中
    if (_controller.iappPlayerConfiguration.expandToFill) {
      return Center(child: playerContainer);
    } else {
      return playerContainer;
    }
  }

  /// 计算视频宽高比
  double _calculateAspectRatio() {
    double? aspectRatio;
    
    if (_controller.isFullScreen) {
      // 全屏模式下的宽高比计算
      if (_controller.iappPlayerConfiguration.autoDetectFullscreenDeviceOrientation ||
          _controller.iappPlayerConfiguration.autoDetectFullscreenAspectRatio) {
        aspectRatio = _controller.videoPlayerController?.value.aspectRatio ?? 1.0;
      } else {
        aspectRatio = _controller.iappPlayerConfiguration.fullScreenAspectRatio ??
            IAppPlayerUtils.calculateAspectRatio(context);
      }
    } else {
      // 非全屏模式
      aspectRatio = _controller.getAspectRatio();
    }

    // 处理无效值
    if (aspectRatio == null || aspectRatio.isNaN || aspectRatio.isInfinite) {
      return 16 / 9; // 默认宽高比
    }
    
    return aspectRatio;
  }

  /// 构建播放器层叠布局
  Widget _buildPlayerStack() {
    // 检查数据源
    if (_controller.iappPlayerDataSource == null) {
      return Container();
    }

    // 获取配置
    final configuration = _controller.iappPlayerConfiguration;
    final placeholderOnTop = configuration.placeholderOnTop;
    
    // 处理旋转角度
    var rotation = configuration.rotation;
    if (!(rotation <= 360 && rotation % 90 == 0)) {
      IAppPlayerUtils.log("旋转角度无效，使用默认旋转 0");
      rotation = 0;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 底层占位符（如果配置）
        if (placeholderOnTop) _buildPlaceholder(),
        
        // 视频层
        Transform.rotate(
          angle: rotation * pi / 180,
          child: _IAppPlayerVideoFitWidget(
            iappPlayerController: _controller,
            boxFit: _controller.getFit(),
          ),
        ),
        
        // 自定义覆盖层
        configuration.overlay ?? const SizedBox.shrink(),
        
        // 字幕层
        IAppPlayerSubtitlesDrawer(
          iappPlayerController: _controller,
          iappPlayerSubtitlesConfiguration: 
              configuration.subtitlesConfiguration,
          subtitles: _controller.subtitlesLines,
          playerVisibilityStream: _playerVisibilityStreamController.stream,
        ),
        
        // 顶层占位符（如果配置）
        if (!placeholderOnTop) _buildPlaceholder(),
        
        // 控件层 - 使用 Positioned.fill 确保控件填充整个区域
        Positioned.fill(
          child: _buildControls(),
        ),
      ],
    );
  }

  /// 构建占位符
  Widget _buildPlaceholder() {
    return _controller.iappPlayerDataSource!.placeholder ??
        _controller.iappPlayerConfiguration.placeholder ??
        const SizedBox.shrink();
  }

  /// 构建控件层
  Widget _buildControls() {
    final controlsConfig = _controller.iappPlayerControlsConfiguration;
    
    // 如果不显示控件，返回空
    if (!controlsConfig.showControls) {
      return const SizedBox.shrink();
    }

    // 确定主题
    IAppPlayerTheme? playerTheme = controlsConfig.playerTheme;
    if (playerTheme == null) {
      playerTheme = Platform.isAndroid 
          ? IAppPlayerTheme.material 
          : IAppPlayerTheme.cupertino;
    }

    // 根据主题构建对应控件
    switch (playerTheme) {
      case IAppPlayerTheme.custom:
        if (controlsConfig.customControlsBuilder != null) {
          return controlsConfig.customControlsBuilder!(
            _controller, 
            _onControlsVisibilityChanged,
          );
        }
        return const SizedBox.shrink();
        
      case IAppPlayerTheme.material:
        return IAppPlayerMaterialControls(
          onControlsVisibilityChanged: _onControlsVisibilityChanged,
          controlsConfiguration: controlsConfig,
        );
        
      case IAppPlayerTheme.cupertino:
        return IAppPlayerCupertinoControls(
          onControlsVisibilityChanged: _onControlsVisibilityChanged,
          controlsConfiguration: controlsConfig,
        );
        
      default:
        return const SizedBox.shrink();
    }
  }

  /// 控件可见性变化回调
  void _onControlsVisibilityChanged(bool visible) {
    _playerVisibilityStreamController.add(visible);
  }
}

/// 视频适配组件 - 保持原有逻辑，仅优化 mounted 检查
class _IAppPlayerVideoFitWidget extends StatefulWidget {
  final IAppPlayerController iappPlayerController;
  final BoxFit boxFit;

  const _IAppPlayerVideoFitWidget({
    Key? key,
    required this.iappPlayerController,
    required this.boxFit,
  }) : super(key: key);

  @override
  _IAppPlayerVideoFitWidgetState createState() =>
      _IAppPlayerVideoFitWidgetState();
}

class _IAppPlayerVideoFitWidgetState extends State<_IAppPlayerVideoFitWidget> {
  VideoPlayerController? get controller =>
      widget.iappPlayerController.videoPlayerController;

  bool _initialized = false;
  VoidCallback? _initializedListener;
  bool _started = false;
  StreamSubscription? _controllerEventSubscription;

  @override
  void initState() {
    super.initState();
    
    // 确定初始播放状态
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
      // 清理旧监听器
      if (_initializedListener != null) {
        oldWidget.iappPlayerController.videoPlayerController!
            .removeListener(_initializedListener!);
      }
      
      // 重新初始化
      _initialized = false;
      _initialize();
    }
  }

  void _initialize() {
    // 监听视频初始化状态
    if (controller?.value.initialized == false) {
      _initializedListener = () {
        if (!mounted) return;

        if (_initialized != controller!.value.initialized) {
          setState(() {
            _initialized = controller!.value.initialized;
          });
        }
      };
      controller!.addListener(_initializedListener!);
    } else {
      _initialized = true;
    }

    // 监听控制器事件
    _controllerEventSubscription = widget.iappPlayerController
        .controllerEventStream.listen((event) {
      if (!mounted) return;
      
      if (event == IAppPlayerControllerEvent.play) {
        if (!_started) {
          setState(() {
            _started = widget.iappPlayerController.hasCurrentDataSourceStarted;
          });
        }
      } else if (event == IAppPlayerControllerEvent.setupDataSource) {
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
          child: FittedBox(
            fit: widget.boxFit,
            child: SizedBox(
              width: controller!.value.size?.width ?? 0,
              height: controller!.value.size?.height ?? 0,
              child: VideoPlayer(controller!),
            ),
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    // 清理监听器
    if (_initializedListener != null) {
      controller?.removeListener(_initializedListener!);
    }
    _controllerEventSubscription?.cancel();
    super.dispose();
  }
}
