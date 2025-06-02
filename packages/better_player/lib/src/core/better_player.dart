import 'dart:async';
import 'package:better_player/better_player.dart';
import 'package:better_player/src/configuration/better_player_controller_event.dart';
import 'package:better_player/src/core/better_player_utils.dart';
import 'package:better_player/src/core/better_player_with_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 使用指定控制器渲染视频播放器的组件
class BetterPlayer extends StatefulWidget {
  const BetterPlayer({Key? key, required this.controller}) : super(key: key);

  /// 从网络URL创建视频播放器实例
  factory BetterPlayer.network(
    String url, {
    BetterPlayerConfiguration? betterPlayerConfiguration,
  }) =>
      BetterPlayer(
        controller: BetterPlayerController(
          betterPlayerConfiguration ?? const BetterPlayerConfiguration(),
          betterPlayerDataSource:
              BetterPlayerDataSource(BetterPlayerDataSourceType.network, url),
        ),
      );

  /// 从本地文件创建视频播放器实例
  factory BetterPlayer.file(
    String url, {
    BetterPlayerConfiguration? betterPlayerConfiguration,
  }) =>
      BetterPlayer(
        controller: BetterPlayerController(
          betterPlayerConfiguration ?? const BetterPlayerConfiguration(),
          betterPlayerDataSource:
              BetterPlayerDataSource(BetterPlayerDataSourceType.file, url),
        ),
      );

  final BetterPlayerController controller; // 视频播放控制器

  @override
  _BetterPlayerState createState() => _BetterPlayerState();
}

class _BetterPlayerState extends State<BetterPlayer>
    with WidgetsBindingObserver {
  /// 获取播放器配置
  BetterPlayerConfiguration get _betterPlayerConfiguration =>
      widget.controller.betterPlayerConfiguration;

  bool _isFullScreen = false; // 全屏状态标志
  late NavigatorState _navigatorState; // 初始导航状态
  bool _initialized = false; // 组件初始化标志
  StreamSubscription? _controllerEventSubscription; // 控制器事件订阅

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
      BetterPlayerUtils.log(exception.toString());
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
          overlays: _betterPlayerConfiguration.systemOverlaysAfterFullScreen);
      SystemChrome.setPreferredOrientations(
          _betterPlayerConfiguration.deviceOrientationsAfterFullScreen);
    }

    WidgetsBinding.instance.removeObserver(this);
    _controllerEventSubscription?.cancel();
    widget.controller.dispose();
    VisibilityDetectorController.instance
        .forget(Key("${widget.controller.hashCode}_key"));
    super.dispose();
  }

  @override
  void didUpdateWidget(BetterPlayer oldWidget) {
    // 更新控制器事件监听
    if (oldWidget.controller != widget.controller) {
      _controllerEventSubscription?.cancel();
      _controllerEventSubscription =
          widget.controller.controllerEventStream.listen(onControllerEvent);
    }
    super.didUpdateWidget(oldWidget);
  }

  /// 处理控制器事件，更新UI或全屏状态
  void onControllerEvent(BetterPlayerControllerEvent event) {
    switch (event) {
      case BetterPlayerControllerEvent.openFullscreen:
        onFullScreenChanged();
        break;
      case BetterPlayerControllerEvent.hideFullscreen:
        onFullScreenChanged();
        break;
      case BetterPlayerControllerEvent.changeSubtitles:
      case BetterPlayerControllerEvent.setupDataSource:
        // 字幕或数据源变更时更新UI
        setState(() {});
        break;
      default:
        break;
    }
  }

  /// 处理全屏切换逻辑
  Future<void> onFullScreenChanged() async {
    final controller = widget.controller;
    if (controller.isFullScreen && !_isFullScreen) {
      _isFullScreen = true;
      controller
          .postEvent(BetterPlayerEvent(BetterPlayerEventType.openFullscreen));
      await _pushFullScreenWidget(context);
    } else if (_isFullScreen) {
      Navigator.of(context, rootNavigator: true).pop();
      _isFullScreen = false;
      controller
          .postEvent(BetterPlayerEvent(BetterPlayerEventType.hideFullscreen));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 构建视频播放器UI
    return BetterPlayerControllerProvider(
      controller: widget.controller,
      child: _buildPlayer(),
    );
  }

  /// 构建全屏视频播放页面
  Widget _buildFullScreenVideo(
      BuildContext context,
      Animation<double> animation,
      BetterPlayerControllerProvider controllerProvider) {
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
      BetterPlayerControllerProvider controllerProvider) {
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
    final controllerProvider = BetterPlayerControllerProvider(
        controller: widget.controller, child: _buildPlayer());

    final routePageBuilder = _betterPlayerConfiguration.routePageBuilder;
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

    if (_betterPlayerConfiguration.autoDetectFullscreenDeviceOrientation ==
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
        widget.controller.betterPlayerConfiguration
            .deviceOrientationsOnFullScreen,
      );
    }

    if (!_betterPlayerConfiguration.allowedScreenSleep) {
      WakelockPlus.enable();
    }

    await Navigator.of(context, rootNavigator: true).push(route);
    _isFullScreen = false;
    widget.controller.exitFullScreen();

    WakelockPlus.disable();

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: _betterPlayerConfiguration.systemOverlaysAfterFullScreen);
    await SystemChrome.setPreferredOrientations(
        _betterPlayerConfiguration.deviceOrientationsAfterFullScreen);
  }

  /// 构建带可见性检测的播放器组件
  Widget _buildPlayer() {
    return VisibilityDetector(
      key: Key("${widget.controller.hashCode}_key"),
      onVisibilityChanged: (VisibilityInfo info) =>
          widget.controller.onPlayerVisibilityChanged(info.visibleFraction),
      child: BetterPlayerWithControls(
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
typedef BetterPlayerRoutePageBuilder = Widget Function(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    BetterPlayerControllerProvider controllerProvider);
