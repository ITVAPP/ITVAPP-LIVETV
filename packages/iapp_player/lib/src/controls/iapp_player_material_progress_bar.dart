import 'dart:async';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/video_player/video_player.dart';
import 'package:iapp_player/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/material.dart';

/// 视频进度条 - 修复版本
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
  
  /// 最新拖拽偏移量
  Offset? _latestDraggableOffset;
  
  /// 容器宽度缓存
  double? _containerWidth;

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

  /// 寻址到相对位置 - 修复：使用实际容器宽度
  void _seekToRelativePosition(Offset globalPosition, double containerWidth) {
    controller!.seekTo(_calcRelativePosition(
      controller!.value.duration!,
      globalPosition,
      containerWidth,
    ));
  }

  /// 计算相对位置 - 修复：使用容器宽度参数
  Duration _calcRelativePosition(
    Duration videoDuration,
    Offset globalPosition,
    double containerWidth,
  ) {
    final box = context.findRenderObject()! as RenderBox;
    final Offset tapPos = box.globalToLocal(globalPosition);
    // 使用实际容器宽度进行计算
    final double relative = (tapPos.dx / containerWidth).clamp(0, 1);
    final Duration position = videoDuration * relative;
    return position;
  }

  @override
  Widget build(BuildContext context) {
    final bool enableProgressBarDrag = iappPlayerController!
        .iappPlayerConfiguration.controlsConfiguration.enableProgressBarDrag;

    // 使用 LayoutBuilder 获取父容器提供的约束
    return LayoutBuilder(
      builder: (context, constraints) {
        // 缓存容器宽度
        _containerWidth = constraints.maxWidth;
        
        // 确定实际高度
        final containerHeight = constraints.maxHeight.isFinite 
            ? constraints.maxHeight 
            : 48.0; // 默认触摸区域高度
            
        final child = Container(
          height: containerHeight,
          width: constraints.maxWidth,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: CustomPaint(
            size: Size(constraints.maxWidth, containerHeight),
            painter: _ProgressBarPainter(
              value: controller!.value,
              colors: widget.colors,
              draggableValue: _latestDraggableOffset != null && _containerWidth != null
                  ? _calcRelativePosition(
                      controller!.value.duration!,
                      _latestDraggableOffset!,
                      _containerWidth!,
                    )
                  : null,
              containerHeight: containerHeight,
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
                  if (!controller!.value.initialized || _containerWidth == null) {
                    return;
                  }

                  // 更新拖拽偏移量并触发重绘
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

                  // 在拖拽结束时进行实际的 seek 操作
                  if (_latestDraggableOffset != null && _containerWidth != null) {
                    _seekToRelativePosition(_latestDraggableOffset!, _containerWidth!);
                    _latestDraggableOffset = null;
                  }

                  if (widget.onDragEnd != null) {
                    widget.onDragEnd!();
                  }
                },
                onTapDown: (TapDownDetails details) {
                  if (!controller!.value.initialized || _containerWidth == null) {
                    return;
                  }
                  _seekToRelativePosition(details.globalPosition, _containerWidth!);
                  if (widget.onTapDown != null) {
                    widget.onTapDown!();
                  }
                },
                child: child,
              )
            : child;
      },
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter({
    required this.value,
    required this.colors,
    this.draggableValue,
    required this.containerHeight,
  });

  /// 当前播放值
  final VideoPlayerValue value;
  /// 进度条颜色
  final IAppPlayerProgressColors colors;
  /// 拖拽值
  final Duration? draggableValue;
  /// 容器高度
  final double containerHeight;

  @override
  bool shouldRepaint(_ProgressBarPainter oldPainter) {
    return oldPainter.value != value ||
           oldPainter.draggableValue != draggableValue;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 动态计算进度条高度
    final height = containerHeight < 10 ? containerHeight : 2.0;
    final baseOffset = size.height / 2 - height / 2;

    // 绘制背景
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(0.0, baseOffset),
          Offset(size.width, baseOffset + height),
        ),
        const Radius.circular(4.0),
      ),
      colors.backgroundPaint,
    );
    
    if (!value.initialized || value.duration == null) {
      return;
    }
    
    // 使用拖拽值或当前播放位置
    final double playedPartPercent = (draggableValue != null
            ? draggableValue!.inMilliseconds
            : value.position.inMilliseconds) /
        value.duration!.inMilliseconds;
    final double playedPart =
        playedPartPercent > 1 ? size.width : playedPartPercent * size.width;
    
    // 绘制缓冲区域
    for (final DurationRange range in value.buffered) {
      final double start = range.startFraction(value.duration!) * size.width;
      final double end = range.endFraction(value.duration!) * size.width;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(
            Offset(start, baseOffset),
            Offset(end, baseOffset + height),
          ),
          const Radius.circular(4.0),
        ),
        colors.bufferedPaint,
      );
    }
    
    // 绘制已播放区域
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(0.0, baseOffset),
          Offset(playedPart, baseOffset + height),
        ),
        const Radius.circular(4.0),
      ),
      colors.playedPaint,
    );
    
    // 只在容器高度足够时绘制手柄
    if (containerHeight >= 10) {
      // 动态计算手柄大小
      final handleRadius = height * 3;
      
      canvas.drawCircle(
        Offset(playedPart, baseOffset + height / 2),
        handleRadius,
        colors.handlePaint,
      );
    }
  }
}
