import 'dart:async';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/video_player/video_player.dart';
import 'package:iapp_player/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/material.dart';

/// 视频进度条
class IAppPlayerMaterialVideoProgressBar extends StatefulWidget {
  IAppPlayerMaterialVideoProgressBar(
    this.controller,
    this.iappPlayerController, {
    IAppPlayerProgressColors? colors,
    this.onDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onTapDown,
    Key? key,
  })  : colors = colors ?? IAppPlayerProgressColors(),
        super(key: key);

  /// 视频播放控制器
  final VideoPlayerController? controller;
  /// 播放器控制器
  final IAppPlayerController? iappPlayerController;
  /// 进度条颜色配置
  final IAppPlayerProgressColors colors;
  /// 拖拽开始回调
  final Function()? onDragStart;
  /// 拖拽结束回调
  final Function()? onDragEnd;
  /// 拖拽更新回调
  final Function()? onDragUpdate;
  /// 点击回调
  final Function()? onTapDown;

  @override
  _VideoProgressBarState createState() {
    return _VideoProgressBarState();
  }
}

class _VideoProgressBarState
    extends State<IAppPlayerMaterialVideoProgressBar> {
  /// 控制器监听器
  late VoidCallback listener;
  /// 拖拽前是否在播放
  bool _controllerWasPlaying = false;

  /// 获取视频播放控制器
  VideoPlayerController? get controller => widget.controller;

  /// 获取播放器控制器
  IAppPlayerController? get iappPlayerController =>
      widget.iappPlayerController;

  /// 拖拽结束是否应播放
  bool shouldPlayAfterDragEnd = false;
  /// 最后寻址位置
  Duration? lastSeek;
  /// 更新阻止定时器
  Timer? _updateBlockTimer;
  
  /// 最后更新时间
  DateTime? _lastUpdateTime;
  /// 更新间隔（60fps）
  static const _updateInterval = Duration(milliseconds: 16);

  @override
  void initState() {
    super.initState();
    listener = () {
      /// 限制更新频率，避免过度重绘
      final now = DateTime.now();
      if (_lastUpdateTime == null || 
          now.difference(_lastUpdateTime!) > _updateInterval) {
        _lastUpdateTime = now;
        if (mounted) setState(() {});
      }
    };
    controller!.addListener(listener);
  }

  @override
  void deactivate() {
    controller!.removeListener(listener);
    _cancelUpdateBlockTimer();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final bool enableProgressBarDrag = iappPlayerController!
        .iappPlayerConfiguration.controlsConfiguration.enableProgressBarDrag;

    return GestureDetector(
      onHorizontalDragStart: (DragStartDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }

        _controllerWasPlaying = controller!.value.isPlaying;
        if (_controllerWasPlaying) {
          controller!.pause();
        }

        if (widget.onDragStart != null) {
          widget.onDragStart!();
        }
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }

        seekToRelativePosition(details.globalPosition);

        if (widget.onDragUpdate != null) {
          widget.onDragUpdate!();
        }
      },
      onHorizontalDragEnd: (DragEndDetails details) {
        if (!enableProgressBarDrag) {
          return;
        }

        if (_controllerWasPlaying) {
          iappPlayerController?.play();
          shouldPlayAfterDragEnd = true;
        }
        _setupUpdateBlockTimer();

        if (widget.onDragEnd != null) {
          widget.onDragEnd!();
        }
      },
      onTapDown: (TapDownDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }
        seekToRelativePosition(details.globalPosition);
        _setupUpdateBlockTimer();
        if (widget.onTapDown != null) {
          widget.onTapDown!();
        }
      },
      child: Center(
        child: Container(
          /// 优化触摸区域高度
          height: 48.0,
          width: MediaQuery.of(context).size.width,
          color: Colors.transparent,
          child: CustomPaint(
            painter: _ProgressBarPainter(
              _getValue(),
              widget.colors,
            ),
          ),
        ),
      ),
    );
  }

  /// 设置更新阻止定时器
  void _setupUpdateBlockTimer() {
    _updateBlockTimer = Timer(const Duration(milliseconds: 1000), () {
      lastSeek = null;
      _cancelUpdateBlockTimer();
    });
  }

  /// 取消更新阻止
  void _cancelUpdateBlockTimer() {
    _updateBlockTimer?.cancel();
    _updateBlockTimer = null;
  }

  /// 获取当前播放值
  VideoPlayerValue _getValue() {
    if (lastSeek != null) {
      return controller!.value.copyWith(position: lastSeek);
    } else {
      return controller!.value;
    }
  }

  /// 寻址到目标位置
  void seekToRelativePosition(Offset globalPosition) async {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject != null) {
      final box = renderObject as RenderBox;
      final Offset tapPos = box.globalToLocal(globalPosition);
      final double relative = tapPos.dx / box.size.width;
      if (relative > 0) {
        final Duration position = controller!.value.duration! * relative.clamp(0.0, 1.0);
        lastSeek = position;
        await iappPlayerController!.seekTo(position);
        onFinishedLastSeek();
      }
    }
  }

  /// 完成最后寻址
  void onFinishedLastSeek() {
    if (shouldPlayAfterDragEnd) {
      shouldPlayAfterDragEnd = false;
      iappPlayerController?.play();
    }
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter(this.value, this.colors);

  /// 当前播放值
  VideoPlayerValue value;
  /// 进度条颜色
  IAppPlayerProgressColors colors;

  @override
  bool shouldRepaint(CustomPainter painter) {
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const height = 2.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(0.0, size.height / 2),
          Offset(size.width, size.height / 2 + height),
        ),
        const Radius.circular(4.0),
      ),
      colors.backgroundPaint,
    );
    if (!value.initialized) {
      return;
    }
    
    /// 安全检查防止除零
    final duration = value.duration?.inMilliseconds ?? 0;
    if (duration == 0) return;
    
    double playedPartPercent = value.position.inMilliseconds / duration;
    playedPartPercent = playedPartPercent.clamp(0.0, 1.0);
    
    final double playedPart = playedPartPercent * size.width;
    
    for (final DurationRange range in value.buffered) {
      final start = (range.startFraction(value.duration!) * size.width).clamp(0.0, size.width);
      final end = (range.endFraction(value.duration!) * size.width).clamp(0.0, size.width);
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(
            Offset(start, size.height / 2),
            Offset(end, size.height / 2 + height),
          ),
          const Radius.circular(4.0),
        ),
        colors.bufferedPaint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(0.0, size.height / 2),
          Offset(playedPart, size.height / 2 + height),
        ),
        const Radius.circular(4.0),
      ),
      colors.playedPaint,
    );
    canvas.drawCircle(
      Offset(playedPart, size.height / 2 + height / 2),
      height * 3,
      colors.handlePaint,
    );
  }
}
