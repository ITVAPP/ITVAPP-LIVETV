import 'dart:async';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/configuration/iapp_player_controller_event.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:iapp_player/src/core/iapp_player_with_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 使用指定控制器渲染视频播放器的组件
class IAppPlayer extends StatefulWidget {
  const IAppPlayer({Key? key, required this.controller}) : super(key: key);

  /// 从网络URL创建视频播放器实例
  factory IAppPlayer.network(
    String url, {
    IAppPlayerConfiguration? iappPlayerConfiguration,
  }) =>
      IAppPlayer(
        controller: IAppPlayerController(
          iappPlayerConfiguration ?? const IAppPlayerConfiguration(),
          iappPlayerDataSource:
              IAppPlayerDataSource(IAppPlayerDataSourceType.network, url),
        ),
      );

  /// 从本地文件创建视频播放器实例
  factory IAppPlayer.file(
    String url, {
    IAppPlayerConfiguration? iappPlayerConfiguration,
  }) =>
      IAppPlayer(
        controller: IAppPlayerController(
          iappPlayerConfiguration ?? const IAppPlayerConfiguration(),
          iappPlayerDataSource:
              IAppPlayerDataSource(IAppPlayerDataSourceType.file, url),
        ),
      );

  final IAppPlayerController controller; // 视频播放控制器

  @override
  _IAppPlayerState createState() => _IAppPlayerState();
}

class _IAppPlayerState extends State<IAppPlayer>
    with WidgetsBindingObserver {
  // 性能优化：提取常量
  static const double _defaultAspectRatio = 16.0 / 9.0;
  static const double _minReasonableSize = 50.0;
  static const double _aspectRatioDifferenceThreshold = 5.0;
  static const double _minValidAspectRatio = 0.1;
  static const double _maxValidAspectRatio = 10.0;
  static const Duration _updateDebounceDelay = Duration(milliseconds: 16);

  /// 获取播放器配置
  IAppPlayerConfiguration get _iappPlayerConfiguration =>
      widget.controller.iappPlayerConfiguration;

  bool _isFullScreen = false; // 全屏状态标志
  late NavigatorState _navigatorState; // 初始导航状态
  bool _initialized = false; // 组件初始化标志
  StreamSubscription? _controllerEventSubscription; // 控制器事件订阅
  
  // 性能优化：批量更新标志
  bool _needsUpdate = false;
  Timer? _updateDebounceTimer;

  @override
  void initState() {
    super.initState();
    // 初始化状态，注册生命周期观察者
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    if (!_initialized) {
      final navigator = Navigator.of(context);
      // 保存导航状态并执行初始化设置
      _navigatorState = navigator;
      _setup();
      _initialized = true;
    }
    super.didChangeDependencies();
  }

  /// 设置控制器事件监听和语言环境
  Future<void> _setup() async {
    _controllerEventSubscription =
        widget.controller.controllerEventStream.listen(onControllerEvent);

    // 设置默认语言环境
    var locale = const Locale("en", "US");
    try {
      if (mounted) {
        final contextLocale = Localizations.localeOf(context);
        locale = contextLocale;
      }
    } catch (exception) {
      // 性能优化：仅在调试模式下记录日志
      assert(() {
        IAppPlayerUtils.log(exception.toString());
        return true;
      }());
    }
    widget.controller.setupTranslations(locale);
  }

  @override
  void dispose() {
    // 清理资源，退出全屏并恢复系统设置
    if (_isFullScreen) {
      WakelockPlus.disable();
      _navigatorState.maybePop();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: _iappPlayerConfiguration.systemOverlaysAfterFullScreen);
      SystemChrome.setPreferredOrientations(
          _iappPlayerConfiguration.deviceOrientationsAfterFullScreen);
    }

    WidgetsBinding.instance.removeObserver(this);
    _controllerEventSubscription?.cancel();
    _updateDebounceTimer?.cancel(); // 性能优化：清理定时器
    widget.controller.dispose();
    VisibilityDetectorController.instance
        .forget(Key("${widget.controller.hashCode}_key"));
    super.dispose();
  }

  @override
  void didUpdateWidget(IAppPlayer oldWidget) {
    // 更新控制器事件监听
    if (oldWidget.controller != widget.controller) {
      _controllerEventSubscription?.cancel();
      _controllerEventSubscription =
          widget.controller.controllerEventStream.listen(onControllerEvent);
    }
    super.didUpdateWidget(oldWidget);
  }

  /// 处理控制器事件，更新UI或全屏状态 - 性能优化：批量处理更新
  void onControllerEvent(IAppPlayerControllerEvent event) {
    switch (event) {
      case IAppPlayerControllerEvent.openFullscreen:
        onFullScreenChanged();
        break;
      case IAppPlayerControllerEvent.hideFullscreen:
        onFullScreenChanged();
        break;
      case IAppPlayerControllerEvent.changeSubtitles:
      case IAppPlayerControllerEvent.setupDataSource:
        // 性能优化：批量处理UI更新，避免频繁setState
        _scheduleUpdate();
        break;
      default:
        break;
    }
  }
  
  /// 性能优化：批量处理UI更新
  void _scheduleUpdate() {
    if (_needsUpdate) {
      return; // 已经有待处理的更新
    }
    
    _needsUpdate = true;
    
    // 取消之前的定时器
    _updateDebounceTimer?.cancel();
    
    // 延迟批量更新，减少重绘次数
    _updateDebounceTimer = Timer(_updateDebounceDelay, () {
      if (mounted && _needsUpdate) {
        setState(() {
          _needsUpdate = false;
        });
      }
    });
  }

  /// 处理全屏切换逻辑
  Future<void> onFullScreenChanged() async {
    final controller = widget.controller;
    if (controller.isFullScreen && !_isFullScreen) {
      _isFullScreen = true;
      controller
          .postEvent(IAppPlayerEvent(IAppPlayerEventType.openFullscreen));
      await _pushFullScreenWidget(context);
    } else if (_isFullScreen) {
      Navigator.of(context, rootNavigator: true).pop();
      _isFullScreen = false;
      controller
          .postEvent(IAppPlayerEvent(IAppPlayerEventType.hideFullscreen));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔧 完全修正的解决方案：智能约束检测和处理
    return IAppPlayerControllerProvider(
      controller: widget.controller,
      child: LayoutBuilder(
        builder: (context, constraints) {
          try {
            // 1. 验证 Controller 状态
            if (widget.controller.isDisposed) {
              assert(() {
                IAppPlayerUtils.log('Controller已释放，显示错误占位');
                return true;
              }());
              return _buildErrorPlaceholder('播放器已释放');
            }

            // 2. 获取安全的宽高比
            final aspectRatio = _getSafeAspectRatio();
            
            // 3. 智能约束检测：检查是否需要提供默认约束
            if (_shouldProvideDefaultConstraints(constraints)) {
              assert(() {
                IAppPlayerUtils.log('提供默认约束，宽高比: $aspectRatio');
                return true;
              }());
              return AspectRatio(
                aspectRatio: aspectRatio,
                child: _buildPlayer(),
              );
            }
            
            // 4. 使用外部约束
            return _buildPlayer();
          } catch (e, stackTrace) {
            // 5. 异常捕获和降级处理
            assert(() {
              IAppPlayerUtils.log('IAppPlayer构建异常: $e');
              return true;
            }());
            return _buildErrorPlaceholder('播放器构建失败');
          }
        },
      ),
    );
  }

  /// 智能检测是否应该提供默认约束
  bool _shouldProvideDefaultConstraints(BoxConstraints constraints) {
    // 情况1：高度无限大或无效
    if (constraints.maxHeight == double.infinity || 
        constraints.maxHeight.isNaN || 
        constraints.maxHeight <= 0) {
      return true;
    }
    
    // 情况2：宽度无限大或无效  
    if (constraints.maxWidth == double.infinity || 
        constraints.maxWidth.isNaN || 
        constraints.maxWidth <= 0) {
      return true;
    }
    
    // 情况3：约束过小（可能是占位约束，如 TableVideoWidget 中的 16x9）
    // 这是关键修正：检测到占位尺寸时仍提供默认约束
    if (constraints.maxWidth < _minReasonableSize || 
        constraints.maxHeight < _minReasonableSize) {
      assert(() {
        IAppPlayerUtils.log(
          '检测到占位约束: ${constraints.maxWidth}x${constraints.maxHeight}，应用默认约束'
        );
        return true;
      }());
      return true;
    }
    
    // 情况4：宽高比严重失真（可能是布局错误）
    final constraintAspectRatio = constraints.maxWidth / constraints.maxHeight;
    final expectedAspectRatio = _getSafeAspectRatio();
    final aspectRatioDifference = (constraintAspectRatio - expectedAspectRatio).abs();
    
    // 如果约束的宽高比与期望相差过大，可能是布局错误
    if (aspectRatioDifference > _aspectRatioDifferenceThreshold) {
      assert(() {
        IAppPlayerUtils.log(
          '检测到异常宽高比: 约束=${constraintAspectRatio.toStringAsFixed(2)}, '
          '期望=${expectedAspectRatio.toStringAsFixed(2)}，应用默正约束'
        );
        return true;
      }());
      return true;
    }
    
    // 其他情况使用外部约束
    return false;
  }

  /// 获取安全的宽高比值，带完整错误处理
  double _getSafeAspectRatio() {
    try {
      // 优先级1：控制器配置的宽高比
      final controllerAspectRatio = widget.controller.getAspectRatio();
      if (controllerAspectRatio != null && _isValidAspectRatio(controllerAspectRatio)) {
        return controllerAspectRatio;
      }
      
      // 优先级2：视频播放器的实际宽高比
      final videoAspectRatio = widget.controller.videoPlayerController?.value.aspectRatio;
      if (videoAspectRatio != null && _isValidAspectRatio(videoAspectRatio)) {
        return videoAspectRatio;
      }
      
      // 优先级3：配置中的默认宽高比
      final configAspectRatio = widget.controller.iappPlayerConfiguration.aspectRatio;
      if (configAspectRatio != null && _isValidAspectRatio(configAspectRatio)) {
        return configAspectRatio;
      }
      
      // 最终回退：16:9 标准宽高比
      return _defaultAspectRatio;
    } catch (e) {
      assert(() {
        IAppPlayerUtils.log('获取宽高比失败: $e，使用默认值 16:9');
        return true;
      }());
      return _defaultAspectRatio;
    }
  }

  /// 验证宽高比是否在合理范围内
  bool _isValidAspectRatio(double aspectRatio) {
    return !aspectRatio.isNaN && 
           !aspectRatio.isInfinite && 
           aspectRatio > _minValidAspectRatio && 
           aspectRatio < _maxValidAspectRatio;
  }

  /// 构建错误状态的占位组件
  Widget _buildErrorPlaceholder(String message) {
    return Container(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: _defaultAspectRatio,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              Text(
                '播放器错误',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建全屏视频播放页面
  Widget _buildFullScreenVideo(
      BuildContext context,
      Animation<double> animation,
      IAppPlayerControllerProvider controllerProvider) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        alignment: Alignment.center,
        color: Colors.black,
        child: controllerProvider,
      ),
    );
  }

  /// 默认全屏页面构建器
  AnimatedWidget _defaultRoutePageBuilder(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      IAppPlayerControllerProvider controllerProvider) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return _buildFullScreenVideo(context, animation, controllerProvider);
      },
    );
  }

  /// 自定义全屏页面构建器
  Widget _fullScreenRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final controllerProvider = IAppPlayerControllerProvider(
        controller: widget.controller, child: _buildPlayer());

    final routePageBuilder = _iappPlayerConfiguration.routePageBuilder;
    if (routePageBuilder == null) {
      return _defaultRoutePageBuilder(
          context, animation, secondaryAnimation, controllerProvider);
    }

    return routePageBuilder(
        context, animation, secondaryAnimation, controllerProvider);
  }

  /// 推送全屏页面并设置屏幕方向
  Future<dynamic> _pushFullScreenWidget(BuildContext context) async {
    final TransitionRoute<void> route = PageRouteBuilder<void>(
      settings: const RouteSettings(),
      pageBuilder: _fullScreenRoutePageBuilder,
    );

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (_iappPlayerConfiguration.autoDetectFullscreenDeviceOrientation ==
        true) {
      final aspectRatio =
          widget.controller.videoPlayerController?.value.aspectRatio ?? 1.0;
      List<DeviceOrientation> deviceOrientations;
      if (aspectRatio < 1.0) {
        deviceOrientations = [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown
        ];
      } else {
        deviceOrientations = [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight
        ];
      }
      await SystemChrome.setPreferredOrientations(deviceOrientations);
    } else {
      await SystemChrome.setPreferredOrientations(
        widget.controller.iappPlayerConfiguration
            .deviceOrientationsOnFullScreen,
      );
    }

    if (!_iappPlayerConfiguration.allowedScreenSleep) {
      WakelockPlus.enable();
    }

    await Navigator.of(context, rootNavigator: true).push(route);
    _isFullScreen = false;
    widget.controller.exitFullScreen();

    WakelockPlus.disable();

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: _iappPlayerConfiguration.systemOverlaysAfterFullScreen);
    await SystemChrome.setPreferredOrientations(
        _iappPlayerConfiguration.deviceOrientationsAfterFullScreen);
  }

  /// 构建带可见性检测的播放器组件
  Widget _buildPlayer() {
    return VisibilityDetector(
      key: Key("${widget.controller.hashCode}_key"),
      onVisibilityChanged: (VisibilityInfo info) =>
          widget.controller.onPlayerVisibilityChanged(info.visibleFraction),
      child: IAppPlayerWithControls(
        controller: widget.controller,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 更新应用生命周期状态
    super.didChangeAppLifecycleState(state);
    widget.controller.setAppLifecycleState(state);
  }
}

/// 全屏模式下使用的页面构建器类型
typedef IAppPlayerRoutePageBuilder = Widget Function(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    IAppPlayerControllerProvider controllerProvider);
