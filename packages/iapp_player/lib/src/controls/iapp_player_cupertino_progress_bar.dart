import 'dart:async';
import 'package:iapp_player/src/controls/iapp_player_progress_colors.dart';
import 'package:iapp_player/src/core/iapp_player_controller.dart';
import 'package:iapp_player/src/video_player/video_player.dart';
import 'package:iapp_player/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/material.dart';

/// Cupertino风格视频进度条
class IAppPlayerCupertinoVideoProgressBar extends StatefulWidget {
  IAppPlayerCupertinoVideoProgressBar(
    this.controller,
    this.iappPlayerController, {
    IAppPlayerProgressColors? colors,
    this.onDragStart,
    this.onDragEnd,
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
    extends State<IAppPlayerCupertinoVideoProgressBar> {
  _VideoProgressBarState() {
    listener = () {
      if (!mounted) return;
      
      /// 仅当播放值变化时更新状态
      final currentValue = controller?.value;
      if (currentValue != null && 
          (_lastValue == null || 
           _lastValue!.position != currentValue.position ||
           _lastValue!.duration != currentValue.duration ||
           _lastValue!.buffered != currentValue.buffered)) {
        setState(() {
          _lastValue = currentValue;
        });
      }
    };
  }

  /// 控制器监听器
  late VoidCallback listener;
  /// 拖拽前是否在播放
  bool _controllerWasPlaying = false;
  /// 最后播放值
  VideoPlayerValue? _lastValue;

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

  @override
  void initState() {
    super.initState();
    controller!.addListener(listener);
    _lastValue = controller!.value;
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
        .iappPlayerControlsConfiguration.enableProgressBarDrag;
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
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          color: Colors.transparent,
          child: CustomPaint(
            painter: _ProgressBarPainter(
              _getValue(),
              widget.colors,
              _lastValue,
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

  /// 取消更新阻止定时器
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

  /// 寻址到相对位置
  void seekToRelativePosition(Offset globalPosition) async {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject != null) {
      final box = renderObject as RenderBox;
      final Offset tapPos = box.globalToLocal(globalPosition);
      final double relative = tapPos.dx / box.size.width;
      
      /// 安全检查防止无效寻址
      if (relative > 0 && controller!.value.duration != null) {
        final Duration position = controller!.value.duration! * relative;
        lastSeek = position;
        await iappPlayerController!.seekTo(position);
        onFinishedLastSeek();
        if (relative >= 1) {
          lastSeek = controller!.value.duration;
          await iappPlayerController!.seekTo(controller!.value.duration!);
          onFinishedLastSeek();
        }
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
  _ProgressBarPainter(this.value, this.colors, this.oldValue);

  /// 当前播放值
  VideoPlayerValue value;
  /// 之前播放值
  VideoPlayerValue? oldValue;
  /// 进度条颜色
  IAppPlayerProgressColors colors;

  @override
  bool shouldRepaint(CustomPainter painter) {
    if (painter is _ProgressBarPainter) {
      /// 仅当播放值变化时重绘
      return oldValue == null ||
          value.position != oldValue!.position ||
          value.duration != oldValue!.duration ||
          value.buffered != oldValue!.buffered;
    }
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 5.0;
    const handleHeight = 6.0;
    final baseOffset = size.height / 2 - barHeight / 2.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(0.0, baseOffset),
          Offset(size.width, baseOffset + barHeight),
        ),
        const Radius.circular(4.0),
      ),
      colors.backgroundPaint,
    );
    if (!value.initialized || value.duration == null) {
      return;
    }
    
    /// 安全检查防止除零
    if (value.duration!.inMilliseconds == 0) {
      return;
    }
    
    final double playedPartPercent =
        value.position.inMilliseconds / value.duration!.inMilliseconds;
    final double playedPart =
        playedPartPercent > 1 ? size.width : playedPartPercent * size.width;
    for (final DurationRange range in value.buffered) {
      final double start = range.startFraction(value.duration!) * size.width;
      final double end = range.endFraction(value.duration!) * size.width;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(
            Offset(start, baseOffset),
            Offset(end, baseOffset + barHeight),
          ),
          const Radius.circular(4.0),
        ),
        colors.bufferedPaint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(0.0, baseOffset),
          Offset(playedPart, baseOffset + barHeight),
        ),
        const Radius.circular(4.0),
      ),
      colors.playedPaint,
    );

    final shadowPath = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(playedPart, baseOffset + barHeight / 2),
          radius: handleHeight));

    canvas.drawShadow(shadowPath, Colors.black, 0.2, false);
    canvas.drawCircle(
      Offset(playedPart, baseOffset + barHeight / 2),
      handleHeight,
      colors.handlePaint,
    );
  }
}
