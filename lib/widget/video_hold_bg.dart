import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'music_bars.dart';
import '../generated/l10n.dart';
import '../gradient_progress_bar.dart';

/// 背景图片状态管理类
class BingBackgroundState {
  final List<String> imageUrls;
  final int currentIndex;
  final int nextIndex;
  final bool isAnimating;
  final bool isTransitionLocked;
  final int currentAnimationType;
  final bool isBingLoaded;

  const BingBackgroundState({
    required this.imageUrls,
    required this.currentIndex,
    required this.nextIndex,
    required this.isAnimating,
    required this.isTransitionLocked,
    required this.currentAnimationType,
    required this.isBingLoaded,
  });

  BingBackgroundState copyWith({
    List<String>? imageUrls,
    int? currentIndex,
    int? nextIndex,
    bool? isAnimating,
    bool? isTransitionLocked,
    int? currentAnimationType,
    bool? isBingLoaded,
  }) {
    return BingBackgroundState(
      imageUrls: imageUrls ?? this.imageUrls,
      currentIndex: currentIndex ?? this.currentIndex,
      nextIndex: nextIndex ?? this.nextIndex,
      isAnimating: isAnimating ?? this.isAnimating,
      isTransitionLocked: isTransitionLocked ?? this.isTransitionLocked,
      currentAnimationType: currentAnimationType ?? this.currentAnimationType,
      isBingLoaded: isBingLoaded ?? this.isBingLoaded,
    );
  }
}

/// 视频占位背景组件
class VideoHoldBg extends StatefulWidget {
  /// Toast提示文本
  final String? toastString;
  /// 当前频道logo
  final String? currentChannelLogo;
  /// 当前频道标题
  final String? currentChannelTitle;
  /// 是否显示必应背景
  final bool showBingBackground;

  const VideoHoldBg({
    Key? key, 
    required this.toastString, 
    required this.currentChannelLogo, 
    required this.currentChannelTitle, 
    this.showBingBackground = false,
  }) : super(key: key);

  @override
  _VideoHoldBgState createState() => _VideoHoldBgState();
}

/// 频道Logo组件
class ChannelLogo extends StatelessWidget {
  final String? logoUrl;
  final bool isPortrait;

  const ChannelLogo({
    Key? key,
    required this.logoUrl,
    required this.isPortrait,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (logoUrl == null || logoUrl!.isEmpty) {
      return const SizedBox.shrink();
    }

    final double logoSize = isPortrait ? 28.0 : 38.0;
    final double margin = isPortrait ? 16.0 : 24.0;

    return Positioned(
      left: margin,
      top: margin,
      child: RepaintBoundary(
        child: Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black26,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: Image.network(
              logoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                LogUtil.logError('加载频道 logo 失败', error, stackTrace);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Toast显示组件
class ToastDisplay extends StatefulWidget {
  final String message;
  final bool isPortrait;
  final bool showProgress;

  const ToastDisplay({
    Key? key,
    required this.message,
    required this.isPortrait,
    this.showProgress = true,
  }) : super(key: key);

  @override
  State<ToastDisplay> createState() => _ToastDisplayState();
}

class _ToastDisplayState extends State<ToastDisplay> with SingleTickerProviderStateMixin {
  late AnimationController _textAnimationController;
  late Animation<Offset> _textAnimation;
  double _textWidth = 0;
  double _containerWidth = 0;

  @override
  void initState() {
    super.initState();
    _setupTextAnimation();
  }

  void _setupTextAnimation() {
    _textAnimationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );

    _textAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: const Offset(-1.0, 0.0),
    ).animate(_textAnimationController);

    _textAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _textAnimationController.reset();
        _textAnimationController.forward();
      }
    });

    _textAnimationController.forward();
  }

  @override
  void dispose() {
    _textAnimationController.dispose();
    super.dispose();
  }

  Widget _buildToast(TextStyle textStyle) {
    final textSpan = TextSpan(text: widget.message, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: double.infinity);
    _textWidth = textPainter.width;

    if (_textWidth > _containerWidth) {
      return RepaintBoundary(
        child: SlideTransition(
          position: _textAnimation,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              widget.message,
              style: textStyle,
            ),
          ),
        ),
      );
    }

    return Text(
      widget.message,
      style: textStyle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = EdgeInsets.only(
      bottom: widget.isPortrait ? 8.0 : 12.0
    );
    
    final TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: widget.isPortrait ? 15 : 17,
    );

    final mediaQuery = MediaQuery.of(context);
    final progressBarWidth = widget.isPortrait ? 
      mediaQuery.size.width * 0.5 : 
      mediaQuery.size.width * 0.3;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: padding,
        child: RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showProgress) ...[
                GradientProgressBar(
                  width: progressBarWidth,
                  height: 5,
                ),
                const SizedBox(height: 5),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  _containerWidth = constraints.maxWidth;
                  return _buildToast(textStyle);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 音频可视化组件
class AudioBarsWrapper extends StatelessWidget {
  final GlobalKey<DynamicAudioBarsState> audioBarKey;
  final bool isActive;
  
  const AudioBarsWrapper({
    Key? key,
    required this.audioBarKey,
    this.isActive = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();
    
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: MediaQuery.of(context).size.height * 0.3,
      child: RepaintBoundary(
        child: DynamicAudioBars(
          key: audioBarKey,
        ),
      ),
    );
  }
}

/// 圆形显示裁剪器
class CircleRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Alignment centerAlignment;
 
  const CircleRevealClipper({
    required this.fraction,
    required this.centerAlignment,
  });

  @override
  Path getClip(Size size) {
    if (size.isEmpty || fraction.isNaN) {
      return Path();
    }
    
    try {
      final center = centerAlignment.alongSize(size);
      final maxRadius = sqrt(size.width * size.width + size.height * size.height) / 2;
      final radius = (maxRadius * fraction.clamp(0.0, 3.2)).clamp(0.0, maxRadius * 2.2);
      
      return Path()
        ..addOval(Rect.fromCircle(
          center: center,
          radius: radius,
        ));
    } catch (e) {
      LogUtil.logError('创建径向裁剪路径时发生错误', e);
      return Path();
    }
  }

  @override
  bool shouldReclip(CircleRevealClipper oldClipper) =>
    oldClipper.fraction != fraction || 
    oldClipper.centerAlignment != centerAlignment;
}

/// 背景动画组件
class BackgroundTransition extends StatelessWidget {
  final Animation<double> animation;
  final String imageUrl;
  final int animationType;
  final List<Animation<double>> blindAnimations;
  
  const BackgroundTransition({
    Key? key,
    required this.animation,
    required this.imageUrl,
    required this.animationType,
    required this.blindAnimations,
  }) : super(key: key);

  Widget _buildAnimatedImage() {
    final nextImage = Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          image: NetworkImage(imageUrl),
        ),
      ),
    );

    switch (animationType) {
      case 0: // 淡入淡出效果
        return FadeTransition(
          opacity: animation,
          child: nextImage,
        );
        
      case 1: // 3D旋转效果
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            if (animation.value.isNaN) return const SizedBox.shrink();
            
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.003)
                ..rotateY(animation.value * pi)
                ..scale(animation.value < 0.5 ? 
                      1.0 + (animation.value * 0.4) :
                      1.4 - (animation.value * 0.4)),
              child: FadeTransition(
                opacity: animation,
                child: nextImage,
              ),
            );
          },
        );
        
      case 2: // 缩放效果
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final progress = animation.value;
            if (progress.isNaN) return const SizedBox.shrink();
            
            final scale = Tween<double>(begin: 1.4, end: 1.0)
                .transform(progress)
                .clamp(0.8, 1.6);
            final opacity = Tween<double>(begin: 0.0, end: 1.0)
                .transform(progress)
                .clamp(0.0, 1.0);
            
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scale(scale)
                ..translate(
                  0.0,
                  30.0 * (1.0 - progress).clamp(0.0, 1.0),
                ),
              child: Opacity(
                opacity: opacity,
                child: nextImage,
              ),
            );
          },
        );
        
      case 3: // 径向扩散效果
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            if (animation.value.isNaN) return const SizedBox.shrink();
            
            return Stack(
              children: [
                ClipPath(
                  clipper: CircleRevealClipper(
                    fraction: animation.value.clamp(0.0, 3.2),
                    centerAlignment: Alignment.center,
                  ),
                  child: FadeTransition(
                    opacity: animation,
                    child: nextImage,
                  ),
                ),
                if (animation.value > 0.2 && animation.value < 2.8)
                  Opacity(
                    opacity: (1.0 - animation.value).clamp(0.0, 0.4),
                    child: ClipPath(
                      clipper: CircleRevealClipper(
                        fraction: (animation.value - 0.1).clamp(0.0, 3.0),
                        centerAlignment: Alignment.center,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
        
      case 4: // 百叶窗效果
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenSize = constraints.biggest;
            if (screenSize.isEmpty) return const SizedBox.shrink();
            
            final height = 1.0 / blindAnimations.length.clamp(1, 20);
            if (height.isNaN || height <= 0) return const SizedBox.shrink();
            
            return Stack(
              children: [
                // 添加一个渐变过渡层
                AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final fadeProgress = animation.value;
                    // 只在动画后半段显示渐变层
                    final opacity = fadeProgress > 0.5 ? 
                      ((fadeProgress - 0.5) * 2).clamp(0.0, 1.0) : 0.0;
                    
                    return Opacity(
                      opacity: opacity,
                      child: nextImage,
                    );
                  },
                ),
                
                // 百叶窗动画层
                ...List.generate(blindAnimations.length, (index) {
                  final topPosition = index * height * screenSize.height;
                  final blindHeight = height * screenSize.height;
                  
                  if (topPosition.isNaN || blindHeight.isNaN || 
                      topPosition < 0 || blindHeight <= 0) {
                    return const SizedBox.shrink();
                  }

                  return Positioned(
                    top: topPosition,
                    left: 0,
                    right: 0,
                    height: blindHeight,
                    child: AnimatedBuilder(
                      animation: blindAnimations[index],
                      builder: (context, child) {
                        final progress = blindAnimations[index].value;
                        if (progress.isNaN) return const SizedBox.shrink();
                        
                        // 调整百叶窗动画进度，使其在动画后期逐渐消失
                        final adjustedOpacity = progress < 0.7 ? 
                          1.0 : (1.0 - ((progress - 0.7) / 0.3)).clamp(0.0, 1.0);
                        
                        return Transform(
                          transform: Matrix4.identity()
                            ..translate(
                              -screenSize.width * (1 - progress).clamp(0.0, 1.0),
                              (1 - progress).clamp(0.0, 1.0) * 8.0,
                            )
                            ..scale(
                              1.0,
                              (0.92 + (progress * 0.08)).clamp(0.9, 1.0),
                            ),
                          child: Opacity(
                            opacity: adjustedOpacity,
                            child: child,
                          ),
                        );
                      },
                      child: nextImage,
                    ),
                  );
                }),
              ],
            );
          },
        );
        
      default:
        return FadeTransition(
          opacity: animation,
          child: nextImage,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _buildAnimatedImage(),
    );
  }
}

class _VideoHoldBgState extends State<VideoHoldBg> with TickerProviderStateMixin {
  // 样式常量
  static const int _blindCount = 12; // 百叶窗数量
  
  // 动画控制器
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _radialAnimation;
  late List<Animation<double>> _blindAnimations;
  
  // 背景状态
  final _backgroundState = ValueNotifier<BingBackgroundState>(
    BingBackgroundState(
      imageUrls: [],
      currentIndex: 0,
      nextIndex: 0,
      isAnimating: false,
      isTransitionLocked: false,
      currentAnimationType: 0,
      isBingLoaded: false,
    ),
  );
  
  // 定时器
  Timer? _timer;
  
  // 音柱动画控制
  final GlobalKey<DynamicAudioBarsState> _audioBarKey = GlobalKey();
  
  @override
  void initState() {
    super.initState();
    _setupAnimations();
    
    if (widget.showBingBackground) {
      _loadBingBackgrounds();
    }
  }

  void _setupAnimations() {
    // 主动画控制器
    _animationController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );

    // 淡入淡出动画
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic),
      reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic),
    );

    // 旋转动画
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeInOutBack),
    ));

    // 缩放动画
    _scaleAnimation = Tween<double>(
      begin: 1.4,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
    ));

    // 径向动画
    _radialAnimation = Tween<double>(
      begin: 0.0,
      end: 3.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutQuart),
    ));
    
    // 百叶窗动画
    _blindAnimations = List.generate(_blindCount, (index) {
      final startInterval = (index * 0.04).clamp(0.0, 0.6);
      final endInterval = ((index + 1) * 0.04 + 0.4).clamp(startInterval + 0.1, 1.0);
      
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          startInterval,
          endInterval,
          curve: Curves.easeInOutQuint,
        ),
      ));
    });

    // 设置动画完成监听
    _animationController.addStatusListener(_handleAnimationStatus);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (!mounted) return;
    
    if (status == AnimationStatus.completed) {
      _animationController.reset();
      
      final currentState = _backgroundState.value;
      _backgroundState.value = currentState.copyWith(
        isAnimating: false,
        currentIndex: currentState.nextIndex,
        currentAnimationType: _getRandomAnimationType(),
        isTransitionLocked: false,
      );
      
      // 预加载下一张图片
      if (currentState.imageUrls.length > 1) {
        final nextNextIndex = (currentState.currentIndex + 1) % currentState.imageUrls.length;
        precacheImage(
          NetworkImage(currentState.imageUrls[nextNextIndex]),
          context,
        );
      }
    }
  }

  int _getRandomAnimationType() {
    if (!mounted) return 0;
    
    final random = Random();
    final weights = [0.15, 0.25, 0.2, 0.2, 0.2];
    final value = random.nextDouble();
    
    try {
      double accumulator = 0;
      for (int i = 0; i < weights.length; i++) {
        accumulator += weights[i];
        if (value < accumulator) {
          return i;
        }
      }
      return 0;
    } catch (e) {
      LogUtil.logError('动画类型选择错误', e);
      return 0;
    }
  }

  Future<void> _loadBingBackgrounds() async {
    final currentState = _backgroundState.value;
    if (currentState.isBingLoaded || currentState.isTransitionLocked) return;
    
    try {
      _backgroundState.value = currentState.copyWith(
        isTransitionLocked: true,
      );
      
      final String? channelId = widget.currentChannelTitle;
      final List<String> urls = await BingUtil.getBingImgUrls(channelId: channelId);
      
      if (!mounted) return;
      
      if (urls.isNotEmpty) {
        _backgroundState.value = currentState.copyWith(
          imageUrls: urls,
          isBingLoaded: true,
          isTransitionLocked: false,
        );

        // 预加载第一张图片
        precacheImage(NetworkImage(urls[0]), context);

        // 设置定时切换
        _timer = Timer.periodic(const Duration(seconds: 45), (Timer timer) {
          final state = _backgroundState.value;
          if (!state.isAnimating && 
              mounted && 
              state.imageUrls.length > 1 && 
              !state.isTransitionLocked) {
            _startImageTransition();
          }
        });
      } else {
        LogUtil.e('未获取到任何 Bing 图片 URL');
        _backgroundState.value = currentState.copyWith(
          isBingLoaded: true,
          isTransitionLocked: false,
        );
      }
    } catch (e) {
      LogUtil.logError('加载 Bing 图片时发生错误', e);
      if (mounted) {
        _backgroundState.value = currentState.copyWith(
          isBingLoaded: true,
          isTransitionLocked: false,
        );
      }
    }
  }

  void _startImageTransition() {
    final currentState = _backgroundState.value;
    if (currentState.isAnimating) return;
    
    try {
      final nextIndex = (currentState.currentIndex + 1) % currentState.imageUrls.length;
      
      // 预加载下一张图片
      precacheImage(
        NetworkImage(currentState.imageUrls[nextIndex]),
        context,
        onError: (e, stackTrace) {
          LogUtil.logError('预加载图片失败', e);
          _backgroundState.value = currentState.copyWith(
            isTransitionLocked: false,
          );
        },
      ).then((_) {
        if (!mounted) return;
        
        _backgroundState.value = currentState.copyWith(
          isAnimating: true,
          nextIndex: nextIndex,
          isTransitionLocked: false,
          currentAnimationType: _getRandomAnimationType(),
        );
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _animationController.reset();
            _animationController.forward();
          }
        });
      });
    } catch (e) {
      LogUtil.logError('开始图片切换时发生错误', e);
      _backgroundState.value = currentState.copyWith(
        isTransitionLocked: false,
      );
    }
  }

  Widget _buildLocalBg() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          image: AssetImage('assets/images/video_bg.png'),
        ),
      ),
    );
  }

  Widget _buildBingBg() {
    final state = _backgroundState.value;
    if (state.imageUrls.isEmpty) {
      return _buildLocalBg();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 基础层 - 当前图片
        Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              fit: BoxFit.cover,
              image: NetworkImage(state.imageUrls[state.currentIndex]),
            ),
          ),
        ),
        
        // 动画过渡层
        if (state.isAnimating)
          BackgroundTransition(
            animation: _fadeAnimation,
            imageUrl: state.imageUrls[state.nextIndex],
            animationType: state.currentAnimationType,
            blindAnimations: _blindAnimations,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景层
          widget.showBingBackground ? _buildBingBg() : _buildLocalBg(),
          
          // 音频可视化层
          AudioBarsWrapper(
            audioBarKey: _audioBarKey,
            isActive: widget.toastString == null || widget.toastString == "HIDE_CONTAINER",
          ),
          
          // Logo层
          if (widget.currentChannelLogo != null)
            ChannelLogo(
              logoUrl: widget.currentChannelLogo,
              isPortrait: isPortrait,
            ),
          
          // Toast层
          if (widget.toastString != null && widget.toastString != "HIDE_CONTAINER")
            ToastDisplay(
              message: widget.toastString!,
              isPortrait: isPortrait,
            ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(VideoHoldBg oldWidget) {
    super.didUpdateWidget(oldWidget);
  
    // 处理音柱动画的暂停/恢复
    if (widget.showBingBackground) {
      if (oldWidget.toastString != widget.toastString) {
        if (widget.toastString != null && widget.toastString != "HIDE_CONTAINER") {  
          _audioBarKey.currentState?.pauseAnimation();
        } else {
          _audioBarKey.currentState?.resumeAnimation();
        }
      }
    }
  }

  @override
  void dispose() {
    final currentState = _backgroundState.value;
    _backgroundState.value = currentState.copyWith(
      isTransitionLocked: true,
      isAnimating: false,
    );
    
    _timer?.cancel();
    _timer = null;
    
    _animationController.removeStatusListener(_handleAnimationStatus);
    _animationController.dispose();
    
    super.dispose();
  }
}
