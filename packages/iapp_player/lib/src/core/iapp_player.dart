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
      // 记录语言环境设置异常
      IAppPlayerUtils.log(exception.toString());
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
    _updateDebounceTimer = Timer(const Duration(milliseconds: 16), () { // 约一帧的时间
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
    // 构建视频播放器UI
    return IAppPlayerControllerProvider(
      controller: widget.controller,
      child: _buildPlayer(),
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
