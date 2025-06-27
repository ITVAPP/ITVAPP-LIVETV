import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/configuration/iapp_player_controller_event.dart';
import 'package:iapp_player/src/controls/iapp_player_cupertino_controls.dart';
import 'package:iapp_player/src/controls/iapp_player_material_controls.dart';
import 'package:iapp_player/src/controls/iapp_player_controls_state.dart';
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
  // 状态管理
  late final ValueNotifier<IAppPlayerUIState> _uiStateNotifier;
  
  // 配置缓存
  IAppPlayerSubtitlesConfiguration get subtitlesConfiguration =>
      widget.controller!.iappPlayerConfiguration.subtitlesConfiguration;
  IAppPlayerControlsConfiguration get controlsConfiguration =>
      widget.controller!.iappPlayerControlsConfiguration;

  // 流控制器
  final StreamController<bool> playerVisibilityStreamController =
      StreamController();

  // 状态标记
  bool _initialized = false;
  StreamSubscription? _controllerEventSubscription;

  @override
  void initState() {
    super.initState();
    _uiStateNotifier = ValueNotifier(const IAppPlayerUIState());
    playerVisibilityStreamController.add(true);
    _controllerEventSubscription =
        widget.controller!.controllerEventStream.listen(_onControllerChanged);
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
    _uiStateNotifier.dispose();
    super.dispose();
  }

  void _onControllerChanged(IAppPlayerControllerEvent event) {
    if (!mounted) return;
    
    setState(() {
      if (!_initialized) {
        _initialized = true;
      }
    });
  }

  // 更新 UI 状态
  void _updateUIState({
    bool? controlsVisible,
    bool? isLoading,
    bool? hasError,
  }) {
    final current = _uiStateNotifier.value;
    _uiStateNotifier.value = current.copyWith(
      controlsVisible: controlsVisible,
      isLoading: isLoading,
      hasError: hasError,
    );
  }

  @override
  Widget build(BuildContext context) {
    final IAppPlayerController iappPlayerController =
        IAppPlayerController.of(context);

    return Container(
      color: iappPlayerController
          .iappPlayerConfiguration.controlsConfiguration.backgroundColor,
      child: _buildPlayerStack(iappPlayerController),
    );
  }

  Widget _buildPlayerStack(IAppPlayerController iappPlayerController) {
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

    // 按照 TableVideoWidget 的模式构建 Stack
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        // 底层占位符
        if (placeholderOnTop) 
          _buildPlaceholder(iappPlayerController),
        
        // 视频层 - 居中显示，使用 AspectRatio
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
        
        // 覆盖层 - 使用 Positioned.fill 确保填满
        if (configuration.overlay != null)
          Positioned.fill(
            child: configuration.overlay!,
          ),
        
        // 字幕层 - 使用 Positioned.fill
        Positioned.fill(
          child: IAppPlayerSubtitlesDrawer(
            iappPlayerController: iappPlayerController,
            iappPlayerSubtitlesConfiguration: subtitlesConfiguration,
            subtitles: iappPlayerController.subtitlesLines,
            playerVisibilityStream: playerVisibilityStreamController.stream,
          ),
        ),
        
        // 顶层占位符
        if (!placeholderOnTop)
          _buildPlaceholder(iappPlayerController),
        
        // 控件层 - 关键：使用 Positioned.fill 提供明确约束
        Positioned.fill(
          child: ValueListenableBuilder<IAppPlayerUIState>(
            valueListenable: _uiStateNotifier,
            builder: (context, uiState, child) {
              return _buildControls(
                context, 
                iappPlayerController,
                uiState,
              );
            },
          ),
        ),
      ],
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
    IAppPlayerUIState uiState,
  ) {
    if (!controlsConfiguration.showControls) {
      return const SizedBox();
    }

    IAppPlayerTheme? playerTheme = controlsConfiguration.playerTheme;
    if (playerTheme == null) {
      if (Platform.isAndroid) {
        playerTheme = IAppPlayerTheme.material;
      } else {
        playerTheme = IAppPlayerTheme.cupertino;
      }
    }

    // 传递通用参数
    final commonParams = {
      'onControlsVisibilityChanged': onControlsVisibilityChanged,
      'controlsConfiguration': controlsConfiguration,
      'uiState': uiState,
      'onUIStateChanged': _updateUIState,
    };

    if (controlsConfiguration.customControlsBuilder != null &&
        playerTheme == IAppPlayerTheme.custom) {
      return controlsConfiguration.customControlsBuilder!(
          iappPlayerController, onControlsVisibilityChanged);
    } else if (playerTheme == IAppPlayerTheme.material) {
      return IAppPlayerMaterialControls(
        onControlsVisibilityChanged: commonParams['onControlsVisibilityChanged'] as Function(bool),
        controlsConfiguration: commonParams['controlsConfiguration'] as IAppPlayerControlsConfiguration,
        uiState: commonParams['uiState'] as IAppPlayerUIState,
        onUIStateChanged: commonParams['onUIStateChanged'] as Function({bool? controlsVisible, bool? isLoading, bool? hasError}),
      );
    } else if (playerTheme == IAppPlayerTheme.cupertino) {
      return IAppPlayerCupertinoControls(
        onControlsVisibilityChanged: commonParams['onControlsVisibilityChanged'] as Function(bool),
        controlsConfiguration: commonParams['controlsConfiguration'] as IAppPlayerControlsConfiguration,
        uiState: commonParams['uiState'] as IAppPlayerUIState,
        onUIStateChanged: commonParams['onUIStateChanged'] as Function({bool? controlsVisible, bool? isLoading, bool? hasError}),
      );
    }

    return const SizedBox();
  }

  void onControlsVisibilityChanged(bool state) {
    playerVisibilityStreamController.add(state);
    if (!state != _uiStateNotifier.value.controlsVisible) {
      _updateUIState(controlsVisible: !state);
    }
  }
}

// 视频适配组件
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
        if (!mounted) return;

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
      if (!mounted) return;
      
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
