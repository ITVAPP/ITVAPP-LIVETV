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
class ChannelLogo extends StatefulWidget {
  final String? logoUrl;
  final bool isPortrait;

  const ChannelLogo({
    Key? key,
    required this.logoUrl,
    required this.isPortrait,
  }) : super(key: key);

  @override
  State<ChannelLogo> createState() => _ChannelLogoState();
}

class _ChannelLogoState extends State<ChannelLogo> {
  static const double maxLogoSize = 58.0;
  
  // 获取缓存key
  String _getCacheKey(String url) {
    return 'logo_${Uri.parse(url).pathSegments.last}';
  }
  
  // 加载logo
  Future<Uint8List?> _loadLogo() async {
    if (widget.logoUrl == null || widget.logoUrl!.isEmpty) {
      return null;
    }

    try {
      final String cacheKey = _getCacheKey(widget.logoUrl!);

      // 1. 检查SP缓存
      final String? base64Data = SpUtil.getString(cacheKey);
      if (base64Data != null && base64Data.isNotEmpty) {
        try {
          return base64Decode(base64Data);
        } catch (e) {
          await SpUtil.remove(cacheKey);
          LogUtil.logError('缓存的logo数据已损坏,已删除', e);
        }
      }

      // 2. 从网络加载并缓存
      final response = await http.get(Uri.parse(widget.logoUrl!));
      if (response.statusCode == 200) {
        final Uint8List imageData = response.bodyBytes;
        await SpUtil.putString(cacheKey, base64Encode(imageData));
        return imageData;
      }
      
      return null;
    } catch (e) {
      LogUtil.logError('加载频道 logo 失败', e);
      return null;
    }
  }

  // 默认logo widget
  Widget get _defaultLogo => Image.asset(
    'assets/images/logo.png',
    fit: BoxFit.cover,
  );

  @override
  Widget build(BuildContext context) {
    final double logoSize = widget.isPortrait ? 38.0 : maxLogoSize;
    final double margin = widget.isPortrait ? 16.0 : 26.0;

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
            child: FutureBuilder<Uint8List?>(
              future: _loadLogo(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultLogo,
                  );
                }
                return _defaultLogo;
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
  return Stack(
    children: [
      // 主图层带位移效果
      SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, -0.02),  // 添加轻微上移
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.1, 0.9, curve: Curves.easeInOut),
          ),
          child: nextImage,
        ),
      ),
      // 添加渐变遮罩增强过渡效果
      if (animation.value < 0.7)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.3 * (1 - animation.value)),
                Colors.transparent,
              ],
            ),
          ),
        ),
    ],
  );
        
case 1: // 3D旋转效果
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      // 使用自定义曲线调整旋转过程
      final rotationProgress = Curves.easeInOutQuart.transform(animation.value);
      
      // 分段控制缩放
      final double scale;
      if (animation.value < 0.3) {
        scale = 1.0 + (animation.value * 0.15); // 开始轻微放大
      } else if (animation.value < 0.7) {
        scale = 1.15; // 保持放大状态
      } else {
        scale = 1.15 - ((animation.value - 0.7) * 0.5); // 平滑恢复
      }
      
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.002 + (0.001 * sin(pi * animation.value))) // 动态透视
          ..rotateY(rotationProgress * pi * 0.6) // 减小旋转角度
          ..scale(scale),
        child: FadeTransition(
          opacity: CurveTween(
            curve: const Interval(0.2, 0.8, curve: Curves.easeInOut)
          ).animate(animation),
          child: nextImage,
        ),
      );
    },
  );
        
case 2: // 缩放效果
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final scaleProgress = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ).value;
      
      // 调整缩放范围和过程
      final scale = 1.15 + (0.1 * (1 - scaleProgress));
      final rotation = (1 - scaleProgress) * 0.03; // 添加轻微旋转
      
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(scale)
          ..rotateZ(rotation)
          ..translate(
            0.0,
            15.0 * (1.0 - scaleProgress), // 减小位移量
          ),
        child: FadeTransition(
          opacity: animation,
          child: nextImage,
        ),
      );
    },
  );
        
case 3: // 径向扩散效果
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final revealProgress = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutQuart),
      ).value;
      
      // 动态中心点
      final centerX = 0.5 + 0.08 * sin(revealProgress * pi);
      final centerY = 0.5 + 0.08 * cos(revealProgress * pi);
      final center = Alignment(centerX, centerY);
      
      return Stack(
        children: [
          // 主径向扩散
          ClipPath(
            clipper: CircleRevealClipper(
              fraction: revealProgress * 2.2, // 调整扩散范围
              centerAlignment: center,
            ),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: const Interval(0.2, 0.9),
              ),
              child: nextImage,
            ),
          ),
          // 发光边框效果
          if (revealProgress > 0.1 && revealProgress < 0.9)
            ClipPath(
              clipper: CircleRevealClipper(
                fraction: (revealProgress - 0.1) * 2.0,
                centerAlignment: center,
              ),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.6 * (1 - revealProgress)),
                    width: 3.0,
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
      final blindHeight = screenSize.height / blindAnimations.length;
      
      return Stack(
        children: [
          // 基础渐变过渡
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final baseProgress = CurvedAnimation(
                parent: animation,
                curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
              ).value;
              return Opacity(
                opacity: baseProgress,
                child: nextImage,
              );
            },
          ),
          // 百叶窗层
          ...List.generate(blindAnimations.length, (index) {
            final isEven = index % 2 == 0;
            return Positioned(
              top: index * blindHeight,
              left: 0,
              right: 0,
              height: blindHeight,
              child: AnimatedBuilder(
                animation: blindAnimations[index],
                builder: (context, child) {
                  final progress = CurvedAnimation(
                    parent: blindAnimations[index],
                    curve: Curves.easeOutBack,
                  ).value;
                  
                  // 计算动画参数
                  final slideOffset = (1 - progress) * screenSize.width;
                  final scale = 0.95 + (0.05 * progress);
                  final rotation = (1 - progress) * (isEven ? 0.05 : -0.05);
                  
                  return Transform(
                    alignment: isEven ? Alignment.centerRight : Alignment.centerLeft,
                    transform: Matrix4.identity()
                      ..translate(
                        isEven ? -slideOffset : slideOffset,
                        (1 - progress) * 3.0,
                      )
                      ..scale(scale)
                      ..rotateZ(rotation),
                    child: Opacity(
                      opacity: progress,
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment(0, -1 + (2 * index / (blindAnimations.length - 1))),
                          child: nextImage,
                        ),
                      ),
                    ),
                  );
                },
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadBingBackgrounds();
      }
    });
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
        // 使用 ValueListenableBuilder 监听背景状态变化
        widget.showBingBackground 
          ? ValueListenableBuilder<BingBackgroundState>(
              valueListenable: _backgroundState,
              builder: (context, state, child) {
                return _buildBingBg();
              },
            )
          : _buildLocalBg(),
        
        // 音频可视化层
        AudioBarsWrapper(
          audioBarKey: _audioBarKey,
          isActive: widget.toastString == null || widget.toastString == "HIDE_CONTAINER",
        ),
        
        // Logo层
        if (widget.showBingBackground && widget.currentChannelLogo != null)
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

  // 处理背景显示状态变化
  if (!oldWidget.showBingBackground && widget.showBingBackground) {
    _loadBingBackgrounds();
  }
  
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
