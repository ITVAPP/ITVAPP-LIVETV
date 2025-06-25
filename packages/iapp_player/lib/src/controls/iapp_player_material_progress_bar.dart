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
    extends State<IAppPlayerMaterialVideoProgressBar> 
    with SingleTickerProviderStateMixin {
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
  
  /// 动画控制器
  late AnimationController _animationController;
  /// 拖拽时的进度位置
  double? _dragValue;
  /// 是否正在拖拽
  bool _isDragging = false;
  
  /// 悬停动画
  late Animation<double> _hoverAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _hoverAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    listener = () {
      /// 限制更新频率，避免过度重绘
      final now = DateTime.now();
      if (_lastUpdateTime == null || 
          now.difference(_lastUpdateTime!) > _updateInterval) {
        _lastUpdateTime = now;
        if (mounted && !_isDragging) setState(() {});
      }
    };
    controller!.addListener(listener);
  }

  @override
  void dispose() {
    controller!.removeListener(listener);
    _animationController.dispose();
    _cancelUpdateBlockTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool enableProgressBarDrag = iappPlayerController!
        .iappPlayerConfiguration.controlsConfiguration.enableProgressBarDrag;

    return MouseRegion(
      onEnter: (_) => _animationController.forward(),
      onExit: (_) => _animationController.reverse(),
      child: GestureDetector(
        onHorizontalDragStart: (DragStartDetails details) {
          if (!controller!.value.initialized || !enableProgressBarDrag) {
            return;
          }

          _controllerWasPlaying = controller!.value.isPlaying;
          if (_controllerWasPlaying) {
            controller!.pause();
          }

          setState(() {
            _isDragging = true;
          });

          if (widget.onDragStart != null) {
            widget.onDragStart!();
          }
        },
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          if (!controller!.value.initialized || !enableProgressBarDrag) {
            return;
          }

          seekToRelativePosition(details.globalPosition, updateDragValue: true);

          if (widget.onDragUpdate != null) {
            widget.onDragUpdate!();
          }
        },
        onHorizontalDragEnd: (DragEndDetails details) {
          if (!enableProgressBarDrag) {
            return;
          }

          setState(() {
            _isDragging = false;
            _dragValue = null;
          });

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
        child: Container(
          height: 48.0,
          color: Colors.transparent,
          child: AnimatedBuilder(
            animation: _hoverAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: _ProgressBarPainter(
                  value: _getValue(),
                  colors: widget.colors,
                  dragValue: _dragValue,
                  isDragging: _isDragging,
                  hoverValue: _hoverAnimation.value,
                ),
              );
            },
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
  void seekToRelativePosition(Offset globalPosition, {bool updateDragValue = false}) async {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject != null) {
      final box = renderObject as RenderBox;
      final Offset tapPos = box.globalToLocal(globalPosition);
      final double relative = (tapPos.dx / box.size.width).clamp(0.0, 1.0);
      
      if (updateDragValue) {
        setState(() {
          _dragValue = relative;
        });
      }
      
      if (controller!.value.duration != null) {
        final Duration position = controller!.value.duration! * relative;
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
  _ProgressBarPainter({
    required this.value,
    required this.colors,
    this.dragValue,
    this.isDragging = false,
    this.hoverValue = 0.0,
  });

  /// 当前播放值
  final VideoPlayerValue value;
  /// 进度条颜色
  final IAppPlayerProgressColors colors;
  /// 拖拽位置值
  final double? dragValue;
  /// 是否正在拖拽
  final bool isDragging;
  /// 悬停动画值
  final double hoverValue;

  @override
  bool shouldRepaint(CustomPainter painter) {
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 进度条高度 - 根据状态变化
    final baseHeight = 4.0;
    final expandedHeight = 8.0;
    final height = baseHeight + (expandedHeight - baseHeight) * hoverValue;
    
    final centerY = size.height / 2;
    final barTop = centerY - height / 2;
    
    // 绘制背景
    final backgroundRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, barTop, size.width, height),
      Radius.circular(height / 2),
    );
    canvas.drawRRect(backgroundRect, colors.backgroundPaint);

    if (!value.initialized || value.duration == null) {
      return;
    }
    
    final duration = value.duration?.inMilliseconds ?? 0;
    if (duration == 0) return;
    
    // 计算播放进度
    double playedPercent;
    if (isDragging && dragValue != null) {
      playedPercent = dragValue!;
    } else {
      playedPercent = (value.position.inMilliseconds / duration).clamp(0.0, 1.0);
    }
    
    final playedWidth = playedPercent * size.width;
    
    // 绘制缓冲进度
    for (final DurationRange range in value.buffered) {
      final start = (range.startFraction(value.duration!) * size.width).clamp(0.0, size.width);
      final end = (range.endFraction(value.duration!) * size.width).clamp(0.0, size.width);
      
      final bufferedRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(start, barTop, end - start, height),
        Radius.circular(height / 2),
      );
      canvas.drawRRect(bufferedRect, colors.bufferedPaint);
    }
    
    // 绘制已播放进度
    if (playedWidth > 0) {
      final playedRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, barTop, playedWidth, height),
        Radius.circular(height / 2),
      );
      
      // 添加发光效果
      if (hoverValue > 0) {
        final glowPaint = Paint()
          ..color = colors.playedPaint.color.withOpacity(0.3 * hoverValue)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawRRect(playedRect, glowPaint);
      }
      
      canvas.drawRRect(playedRect, colors.playedPaint);
    }
    
    // 绘制拖动手柄
    final handleRadius = 6.0 + 4.0 * hoverValue;
    final handleOpacity = 0.6 + 0.4 * hoverValue;
    
    if (isDragging || hoverValue > 0) {
      // 手柄阴影
      final shadowPath = Path()
        ..addOval(Rect.fromCircle(
          center: Offset(playedWidth, centerY),
          radius: handleRadius + 2,
        ));
      canvas.drawShadow(shadowPath, Colors.black.withOpacity(0.3), 4, false);
      
      // 手柄本体
      final handlePaint = Paint()
        ..color = colors.handlePaint.color.withOpacity(handleOpacity);
      canvas.drawCircle(
        Offset(playedWidth, centerY),
        handleRadius,
        handlePaint,
      );
      
      // 内圆点
      canvas.drawCircle(
        Offset(playedWidth, centerY),
        handleRadius * 0.4,
        Paint()..color = Colors.white.withOpacity(handleOpacity),
      );
    }
    
    // 绘制时间提示（拖拽时）
    if (isDragging && dragValue != null) {
      final dragPosition = Duration(
        milliseconds: (dragValue! * duration).round(),
      );
      final timeText = _formatDuration(dragPosition);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: timeText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      
      // 计算提示框位置
      final tooltipX = (playedWidth - textPainter.width / 2).clamp(
        4.0,
        size.width - textPainter.width - 4.0,
      );
      final tooltipY = barTop - 28;
      
      // 绘制提示框背景
      final tooltipRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          tooltipX - 8,
          tooltipY - 4,
          textPainter.width + 16,
          20,
        ),
        Radius.circular(4),
      );
      canvas.drawRRect(
        tooltipRect,
        Paint()..color = Colors.black.withOpacity(0.8),
      );
      
      // 绘制时间文本
      textPainter.paint(canvas, Offset(tooltipX, tooltipY));
    }
  }
  
  /// 格式化时长
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return "${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}";
    } else {
      return "${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
  }
}
