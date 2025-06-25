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
    this.barHeight = 2.0,
    this.handleHeight = 6.0,
    this.drawShadow = true,
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
  /// 进度条高度
  final double barHeight;
  /// 控制柄高度
  final double handleHeight;
  /// 是否绘制阴影
  final bool drawShadow;

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
  
  /// 最新拖拽偏移量 - 与Chewie保持一致
  Offset? _latestDraggableOffset;

  /// 获取视频播放控制器
  VideoPlayerController? get controller => widget.controller;

  /// 获取播放器控制器
  IAppPlayerController? get iappPlayerController =>
      widget.iappPlayerController;

  @override
  void initState() {
    super.initState();
    listener = () {
      if (!mounted) return;
      setState(() {});
    };
    controller!.addListener(listener);
  }

  @override
  void deactivate() {
    controller!.removeListener(listener);
    super.deactivate();
  }

  /// 寻址到相对位置 - 与Chewie保持一致的实现
  void _seekToRelativePosition(Offset globalPosition) {
    controller!.seekTo(_calcRelativePosition(
      controller!.value.duration!,
      globalPosition,
    ));
  }

  /// 计算相对位置 - 与Chewie扩展方法保持一致
  Duration _calcRelativePosition(
    Duration videoDuration,
    Offset globalPosition,
  ) {
    final box = context.findRenderObject()! as RenderBox;
    final Offset tapPos = box.globalToLocal(globalPosition);
    final double relative = (tapPos.dx / box.size.width).clamp(0, 1);
    final Duration position = videoDuration * relative;
    return position;
  }

  @override
  Widget build(BuildContext context) {
    final bool enableProgressBarDrag = iappPlayerController!
        .iappPlayerConfiguration.controlsConfiguration.enableProgressBarDrag;

    final child = Center(
      child: Container(
        /// 与Chewie保持一致的容器高度
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        color: Colors.transparent,
        child: CustomPaint(
          painter: _ProgressBarPainter(
            value: controller!.value,
            colors: widget.colors,
            barHeight: widget.barHeight,
            handleHeight: widget.handleHeight,
            drawShadow: widget.drawShadow,
            // 与Chewie保持一致：如果正在拖拽，使用拖拽位置计算的时长
            draggableValue: _latestDraggableOffset != null
                ? _calcRelativePosition(
                    controller!.value.duration!,
                    _latestDraggableOffset!,
                  )
                : null,
          ),
        ),
      ),
    );

    return enableProgressBarDrag
        ? GestureDetector(
            onHorizontalDragStart: (DragStartDetails details) {
              if (!controller!.value.initialized) {
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
              if (!controller!.value.initialized) {
                return;
              }

              // 与Chewie保持一致：更新拖拽偏移量并触发重绘
              _latestDraggableOffset = details.globalPosition;
              listener();

              if (widget.onDragUpdate != null) {
                widget.onDragUpdate!();
              }
            },
            onHorizontalDragEnd: (DragEndDetails details) {
              if (_controllerWasPlaying) {
                controller!.play();
              }

              // 与Chewie保持一致：在拖拽结束时进行实际的seek操作
              if (_latestDraggableOffset != null) {
                _seekToRelativePosition(_latestDraggableOffset!);
                _latestDraggableOffset = null;
              }

              if (widget.onDragEnd != null) {
                widget.onDragEnd!();
              }
            },
            onTapDown: (TapDownDetails details) {
              if (!controller!.value.initialized) {
                return;
              }
              _seekToRelativePosition(details.globalPosition);
              if (widget.onTapDown != null) {
                widget.onTapDown!();
              }
            },
            child: child,
          )
        : child;
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter({
    required this.value,
    required this.colors,
    required this.barHeight,
    required this.handleHeight,
    required this.drawShadow,
    this.draggableValue,
  });

  /// 当前播放值
  final VideoPlayerValue value;
  /// 进度条颜色
  final IAppPlayerProgressColors colors;
  /// 进度条高度
  final double barHeight;
  /// 控制柄高度
  final double handleHeight;
  /// 是否绘制阴影
  final bool drawShadow;
  /// 拖拽值 - 与Chewie保持一致
  final Duration? draggableValue;

  @override
  bool shouldRepaint(CustomPainter painter) {
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final baseOffset = size.height / 2 - barHeight / 2;

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
    
    if (!value.initialized) {
      return;
    }
    
    // 与Chewie保持一致：优先使用拖拽值，否则使用当前播放位置
    final double playedPartPercent = (draggableValue != null
            ? draggableValue!.inMilliseconds
            : value.position.inMilliseconds) /
        value.duration!.inMilliseconds;
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
    
    // 与Chewie保持一致：添加阴影支持
    if (drawShadow) {
      final Path shadowPath = Path()
        ..addOval(
          Rect.fromCircle(
            center: Offset(playedPart, baseOffset + barHeight / 2),
            radius: handleHeight,
          ),
        );

      canvas.drawShadow(shadowPath, Colors.black, 0.2, false);
    }
    
    canvas.drawCircle(
      Offset(playedPart, baseOffset + barHeight / 2),
      handleHeight,
      colors.handlePaint,
    );
  }
}
