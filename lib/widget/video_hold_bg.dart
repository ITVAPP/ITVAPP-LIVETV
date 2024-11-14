import 'dart:async';
import 'dart:math';
import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import '../generated/l10n.dart';
import '../gradient_progress_bar.dart';

class VideoHoldBg extends StatefulWidget {
  final String? toastString;
  final bool showBingBackground; // 可选参数：是否显示 Bing 背景，默认 false

  const VideoHoldBg({Key? key, required this.toastString, this.showBingBackground = false}) : super(key: key);

  @override
  _VideoHoldBgState createState() => _VideoHoldBgState();
}

class _VideoHoldBgState extends State<VideoHoldBg> with TickerProviderStateMixin {
  late AnimationController _animationController; // 动画控制器，控制背景淡入淡出效果
  late Animation<double> _fadeAnimation; // 淡入淡出的动画效果
  late Animation<double> _rotationAnimation; // 旋转动画效果
  late Animation<double> _scaleAnimation; // 缩放动画效果
  late Animation<double> _radialAnimation; // 径向扩散动画
  late List<Animation<double>> _blindAnimations; // 百叶窗动画列表
  static const int _blindCount = 12; // 增加百叶窗数量，使效果更细腻
  
  List<String> _bingImgUrls = [];  // 用于存储多个 Bing 背景图片 URL
  int _currentImgIndex = 0;  // 当前显示的背景图片索引
  Timer? _timer;  // 定时器，用于切换背景图片
  bool _isBingLoaded = false;  // 用于判断是否已经加载过 Bing 背景
  bool _isAnimating = false;  // 用于跟踪动画状态
  bool _isTransitionLocked = false; // 状态锁，防止并发操作
  late int _nextImgIndex;  // 下一张图片的索引
  late int _currentAnimationType; // 当前动画类型

  late AnimationController _textAnimationController; // 文字滚动动画控制器
  late Animation<Offset> _textAnimation; // 文字滚动动画
  double _textWidth = 0;
  double _containerWidth = 0;
@override
  void initState() {
    super.initState();

    // 增加动画持续时间到3秒
    _animationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    // 调整淡入淡出动画曲线，使用更平滑的曲线，并延长过渡时间
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.1, 0.9, curve: Curves.easeInOutCubic),
      reverseCurve: const Interval(0.1, 0.9, curve: Curves.easeInOutCubic),
    );

    // 增加旋转角度并使用更动态的曲线，延长动画时间
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.85, // 增加旋转角度，让效果更明显
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.05, 0.95, curve: Curves.easeInOutBack),
    ));

    // 调整缩放范围和曲线，增加动画时间
    _scaleAnimation = Tween<double>(
      begin: 1.25, // 增加初始缩放比例
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      // 修改：使用 easeOutBack 替代 easeOutElastic
      curve: const Interval(0.1, 0.9, curve: Curves.easeOutBack),
    ));

    // 调整径向扩散动画，延长扩散时间
    _radialAnimation = Tween<double>(
      begin: 0.0,
      end: 2.8, // 增加扩散范围
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.85, curve: Curves.easeOutQuart),
    ));

    // 优化百叶窗动画效果，调整时间分配
    _blindAnimations = List.generate(_blindCount, (index) {
      // 确保生成的间隔在合理范围内
      final startInterval = (index * 0.06).clamp(0.0, 0.7);
      final endInterval = ((index + 1) * 0.06 + 0.3).clamp(startInterval + 0.1, 1.0);
      
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
    
    _currentAnimationType = _getRandomAnimationType();

    // 优化动画状态监听器，添加更多安全检查
    _animationController.addStatusListener((status) {
      if (!mounted) return;
      
      if (status == AnimationStatus.completed) {
        setState(() {
          _isAnimating = false;
          _currentImgIndex = _nextImgIndex;
          _currentAnimationType = _getRandomAnimationType();
          _isTransitionLocked = false;  // 解锁状态
        });
        _animationController.value = 0.0;
        
        // 预加载下下张图片
        if (_bingImgUrls.length > 1) {
          final nextNextIndex = (_currentImgIndex + 1) % _bingImgUrls.length;
          precacheImage(NetworkImage(_bingImgUrls[nextNextIndex]), context);
        }
      } else if (status == AnimationStatus.dismissed) {
        _isTransitionLocked = false;  // 确保在动画取消时也解锁状态
      }
    });

    // 初始化文字滚动动画控制器
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

    // 判断是否需要加载 Bing 背景
    if (widget.showBingBackground && !_isBingLoaded) {
      _loadBingBackgrounds();
    }
  }
  
// 获取随机动画类型，使用带权重的随机算法
  int _getRandomAnimationType() {
    if (!mounted) return 0;  // 添加安全检查，确保组件已挂载
    
    final random = Random();
    final weights = [0.15, 0.25, 0.2, 0.2, 0.2]; // 各个动画类型的权重分配
    final value = random.nextDouble();
    
    try {
      double accumulator = 0;
      for (int i = 0; i < weights.length; i++) {
        accumulator += weights[i];
        if (value < accumulator) {
          return i; // 返回匹配的动画类型索引
        }
      }
      return 0;  // 默认返回淡入淡出动画类型
    } catch (e) {
      LogUtil.logError('动画类型选择错误', e);
      return 0;  // 出现错误时返回淡入淡出动画
    }
  }

  // 优化异步加载 Bing 图片 URL 列表
  Future<void> _loadBingBackgrounds() async {
    if (_isBingLoaded || _isTransitionLocked) return; // 防止重复加载和并发操作
    
    try {
      _isTransitionLocked = true;
      _bingImgUrls = await BingUtil.getBingImgUrls();  // 获取Bing图片
      
      if (!mounted) return;  // 添加提前返回检查
      
      if (_bingImgUrls.isNotEmpty) {
        setState(() {
          _isBingLoaded = true;
          // 预加载第一张图片
          precacheImage(NetworkImage(_bingImgUrls[0]), context);
        });

        // 设置图片切换定时器，间隔时间为35秒
        _timer = Timer.periodic(const Duration(seconds: 35), (Timer timer) {
          if (!_isAnimating && mounted && _bingImgUrls.length > 1 && !_isTransitionLocked) {
            _startImageTransition();
          }
        });
      } else {
        LogUtil.e('未获取到任何 Bing 图片 URL');
      }
    } catch (e) {
      LogUtil.logError('加载 Bing 图片时发生错误', e);
    } finally {
      if (mounted) {
        setState(() {
          _isBingLoaded = true;  // 确保状态被更新
          _isTransitionLocked = false;  // 解锁状态
        });
      }
    }
  }

  // 优化图片切换逻辑
  void _startImageTransition() {
    // 添加更严格的状态检查
    if (_isAnimating || 
        _isTransitionLocked || 
        _bingImgUrls.length <= 1 || 
        !mounted) return;
    
    try {
      _isTransitionLocked = true;
      
      // 计算下一个图片索引
      final nextIndex = (_currentImgIndex + 1) % _bingImgUrls.length;
      
      // 预加载下一张图片
      precacheImage(
        NetworkImage(_bingImgUrls[nextIndex]),
        context,
        onError: (e, stackTrace) {
          LogUtil.logError('预加载图片失败', e);
          _isTransitionLocked = false;
        },
      ).then((_) {
        if (!mounted) return;
        
        setState(() {
          _isAnimating = true;
          _nextImgIndex = nextIndex;
        });
        
        // 确保UI已更新后再启动动画
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _animationController.forward(from: 0.0);
          }
        });
      });
    } catch (e) {
      LogUtil.logError('开始图片切换时发生错误', e);
      _isTransitionLocked = false;
    }
  }

  // 优化资源释放
  @override
  void dispose() {
    // 确保所有异步操作都被正确取消
    _isTransitionLocked = true;  // 防止新的动画开始
    _isAnimating = false;  // 停止当前动画状态
    
    _timer?.cancel();
    _timer = null;
    
    _animationController.stop();
    _animationController.dispose();
    
    _textAnimationController.stop();
    _textAnimationController.dispose();
    
    super.dispose();
  }
  
@override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bool isPortrait = mediaQuery.orientation == Orientation.portrait;

    // 根据屏幕方向设置进度条的宽度
    double progressBarWidth = isPortrait ? mediaQuery.size.width * 0.5 : mediaQuery.size.width * 0.3;

    // 动态设置 padding 和 fontSize
    final EdgeInsets padding = EdgeInsets.only(bottom: isPortrait ? 10.0 : 15.0);
    final TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: isPortrait ? 16 : 18,
    );

    return Selector<ThemeProvider, bool>(
      selector: (_, provider) => provider.isBingBg,
      builder: (BuildContext context, bool isBingBg, Widget? child) {
        final bool shouldShowBingBg = widget.showBingBackground && 
                                    isBingBg && 
                                    _isBingLoaded && 
                                    _bingImgUrls.isNotEmpty;

        // 确保在正确的时机加载背景
        if (widget.showBingBackground && 
            isBingBg && 
            !_isBingLoaded && 
            !_isTransitionLocked) {
          _loadBingBackgrounds();
        }

        return Stack(
          children: [
            shouldShowBingBg ? _buildBingBg() : _buildLocalBg(),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GradientProgressBar(
                      width: progressBarWidth,
                      height: 5,
                    ),
                    const SizedBox(height: 3),
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
          ],
        );
      },
    );
  }

  Widget _buildToast(TextStyle textStyle) {
    final text = widget.toastString ?? S.of(context).loading;
    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: double.infinity);
    _textWidth = textPainter.width;

    if (_textWidth > _containerWidth) {
      return SlideTransition(
        position: _textAnimation,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            text,
            style: textStyle,
          ),
        ),
      );
    } else {
      return Text(
        text,
        style: textStyle,
      );
    }
  }

  Widget _buildBingBg() {
    if (_bingImgUrls.isEmpty) {
      return _buildLocalBg();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              fit: BoxFit.cover,
              image: NetworkImage(_bingImgUrls[_currentImgIndex]),
            ),
          ),
        ),
        if (_isAnimating && !_isTransitionLocked)
          _buildAnimatedTransition(),
      ],
    );
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
  
// 构建动画过渡效果，根据当前动画类型动态切换
  Widget _buildAnimatedTransition() {
    // 添加安全检查
    if (_nextImgIndex >= _bingImgUrls.length || !mounted || _isTransitionLocked) {
      return const SizedBox.shrink();
    }

    try {
      // 预加载下一张图片
      precacheImage(NetworkImage(_bingImgUrls[_nextImgIndex]), context);
      
      final nextImage = Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            fit: BoxFit.cover,
            image: NetworkImage(_bingImgUrls[_nextImgIndex]),
          ),
        ),
      );

      // 基础淡入淡出效果
      final fadeTransition = FadeTransition(
        opacity: _fadeAnimation,
        child: nextImage,
      );

      // 根据当前动画类型返回不同的动画效果
      switch (_currentAnimationType) {
        case 0: // 淡入淡出
          return fadeTransition;
          
        case 1: // 旋转渐变 - 增强3D效果
          return AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (context, child) {
              if (_rotationAnimation.value.isNaN) return fadeTransition;
              
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.002) // 增强透视效果
                  ..rotateY(_rotationAnimation.value * pi)
                  ..scale(_rotationAnimation.value < 0.5 ? 
                          1.0 + (_rotationAnimation.value * 0.3) : 
                          1.3 - (_rotationAnimation.value * 0.3)), // 添加缩放效果增强3D感
                child: fadeTransition,
              );
            },
          );
          
        case 2: // 缩放 - 添加方向变化
          return AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              final progress = _scaleAnimation.value;
              if (progress.isNaN) return fadeTransition;
              
              final scale = Tween<double>(begin: 1.25, end: 1.0)
                  .transform(progress)
                  .clamp(0.8, 1.5);
              final opacity = Tween<double>(begin: 0.0, end: 1.0)
                  .transform(progress)
                  .clamp(0.0, 1.0);
              
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scale(scale)
                  ..translate(
                    0.0,
                    20.0 * (1.0 - progress).clamp(0.0, 1.0), // 添加垂直方向的移动
                  ),
                child: Opacity(
                  opacity: opacity,
                  child: child,
                ),
              );
            },
            child: fadeTransition,
          );
          
        case 3: // 径向扩散 - 增加波纹效果
          return AnimatedBuilder(
            animation: _radialAnimation,
            builder: (context, child) {
              if (_radialAnimation.value.isNaN) return fadeTransition;
              
              return Stack(
                children: [
                  // 主要扩散效果
                  ClipPath(
                    clipper: CircleRevealClipper(
                      fraction: _radialAnimation.value.clamp(0.0, 2.8),
                      centerAlignment: Alignment.center,
                    ),
                    child: fadeTransition,
                  ),
                  // 添加额外的波纹效果
                  if (_radialAnimation.value > 0.2 && _radialAnimation.value < 2.5)
                    Opacity(
                      opacity: (1.0 - _radialAnimation.value).clamp(0.0, 0.3),
                      child: ClipPath(
                        clipper: CircleRevealClipper(
                          fraction: (_radialAnimation.value - 0.1).clamp(0.0, 2.7),
                          centerAlignment: Alignment.center,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 2.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
          
        case 4: // 百叶窗 - 优化动画效果
          final screenSize = MediaQuery.of(context).size;
          if (screenSize.isEmpty) return fadeTransition;
          
          final height = 1.0 / _blindCount.clamp(1, 20); // 添加范围限制
          if (height.isNaN || height <= 0) return fadeTransition;
          
          return Stack(
            children: List.generate(_blindCount, (index) {
              // 计算每个百叶窗的位置和大小
              final topPosition = index * height * screenSize.height;
              final blindHeight = height * screenSize.height;
              
              // 确保位置和高度在有效范围内
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
                  animation: _blindAnimations[index],
                  builder: (context, child) {
                    final progress = _blindAnimations[index].value;
                    if (progress.isNaN) return const SizedBox.shrink();
                    
                    return Transform(
                      transform: Matrix4.identity()
                        ..translate(
                          -screenSize.width * (1 - progress).clamp(0.0, 1.0),
                          (1 - progress).clamp(0.0, 1.0) * 5.0, // 添加垂直方向的微小偏移
                        )
                        ..scale(
                          1.0,
                          (0.95 + (progress * 0.05)).clamp(0.9, 1.0), // 添加轻微的垂直缩放
                        ),
                      child: Opacity(
                        opacity: progress.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: fadeTransition,
                ),
              );
            }),
          );
          
        default:
          return fadeTransition;
      }
    } catch (e) {
      LogUtil.logError('构建动画过渡效果时发生错误', e);
      // 发生错误时返回空视图，避免界面崩溃
      return const SizedBox.shrink();
    }
  }
}

// 径向扩散效果的裁剪器
class CircleRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Alignment centerAlignment;
  
  const CircleRevealClipper({
    required this.fraction,
    required this.centerAlignment,
  });

  @override
  Path getClip(Size size) {
    // 添加尺寸和参数检查
    if (size.isEmpty || fraction.isNaN) {
      return Path();
    }
    
    try {
      final center = centerAlignment.alongSize(size);
      // 优化半径计算
      final maxRadius = sqrt(size.width * size.width + size.height * size.height) / 2;
      final radius = (maxRadius * fraction.clamp(0.0, 2.8)).clamp(0.0, maxRadius * 2);
      
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
    oldClipper.fraction != fraction || oldClipper.centerAlignment != centerAlignment;
}
