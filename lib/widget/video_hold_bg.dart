import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  final bool isEnabled; // 是否启用Bing背景(对应ThemeProvider中的isBingBg)

  const BingBackgroundState({
    required this.imageUrls,
    required this.currentIndex,
    required this.nextIndex,
    required this.isAnimating,
    required this.isTransitionLocked,
    required this.currentAnimationType,
    required this.isBingLoaded,
    required this.isEnabled,
  });

  BingBackgroundState copyWith({
    List<String>? imageUrls,
    int? currentIndex,
    int? nextIndex,
    bool? isAnimating,
    bool? isTransitionLocked,
    int? currentAnimationType,
    bool? isBingLoaded,
    bool? isEnabled,
  }) {
    return BingBackgroundState(
      imageUrls: imageUrls ?? this.imageUrls,
      currentIndex: currentIndex ?? this.currentIndex,
      nextIndex: nextIndex ?? this.nextIndex,
      isAnimating: isAnimating ?? this.isAnimating,
      isTransitionLocked: isTransitionLocked ?? this.isTransitionLocked,
      currentAnimationType: currentAnimationType ?? this.currentAnimationType,
      isBingLoaded: isBingLoaded ?? this.isBingLoaded,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

/// 视频占位背景组件 - 保持不变
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
          return base64.decode(base64Data);
        } catch (e) {
          await SpUtil.remove(cacheKey);
          LogUtil.logError('缓存的logo数据已损坏,已删除', e);
        }
      }

      // 2. 从网络加载并缓存
      final response = await http.get(Uri.parse(widget.logoUrl!));
      if (response.statusCode == 200) {
        final Uint8List imageData = response.bodyBytes;
        await SpUtil.putString(cacheKey, base64.encode(imageData));
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
    final double logoSize = widget.isPortrait ? 48.0 : maxLogoSize;
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

  // 设置文本动画
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

  // 构建Toast消息
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

/// 径向显示裁剪器
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
      final radius = maxRadius * fraction.clamp(0.0, 3.2);

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
  final String imageUrl;
  final int animationType;
  final VoidCallback? onTransitionComplete;

  const BackgroundTransition({
    Key? key,
    required this.imageUrl,
    required this.animationType,
    this.onTransitionComplete,
  }) : super(key: key);

  // 构建高级淡入淡出效果
  Widget _buildFadeTransition(Widget child) {
    return child.animate(
      onPlay: (controller) {
        controller.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            onTransitionComplete?.call();
          }
        });
      },
    ).fadeIn(
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
    ).scale(
      alignment: Alignment.center,
      begin: const Offset(1.1, 1.1),
      end: const Offset(1.0, 1.0),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutQuart,
    ).blurXY(
      begin: 8,
      end: 0,
      duration: const Duration(milliseconds: 1000),
    ).moveY(
      begin: -10,
      end: 0,
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutQuart,
    );
  }

  // 构建3D旋转效果
  Widget _build3DRotationTransition(Widget child) {
    return child.animate(
      onPlay: (controller) {
        controller.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            onTransitionComplete?.call();
          }
        });
      },
    ).custom(
      duration: const Duration(milliseconds: 1500),
      builder: (context, value, child) {
        final angle = sin(value * pi) * pi;
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          alignment: Alignment.center,
          child: child,
        );
      },
    ).scale(
      alignment: Alignment.center,
      begin: const Offset(1.2, 1.2),
      end: const Offset(1.0, 1.0),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutExpo,
    ).fadeIn(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOut,
    );
  }

  // 构建缩放效果
  Widget _buildScaleTransition(Widget child) {
    return child.animate(
      onPlay: (controller) {
        controller.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            onTransitionComplete?.call();
          }
        });
      },
    ).scale(
      alignment: Alignment.center,
      begin: const Offset(1.3, 1.3),
      end: const Offset(1.0, 1.0),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutQuart,
    ).fadeIn(
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
    ).blurXY(
      begin: 10,
      end: 0,
      duration: const Duration(milliseconds: 800),
    ).moveY(
      begin: 20,
      end: 0,
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
    );
  }

  // 构建径向扩散效果
  Widget _buildRadialTransition(Widget child) {
    return child.animate(
      onPlay: (controller) {
        controller.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            onTransitionComplete?.call();
          }
        });
      },
    ).custom(
      duration: const Duration(milliseconds: 1500),
      builder: (context, value, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return RadialGradient(
              center: Alignment.center,
              radius: value * 2,
              colors: [
                Colors.white,
                Colors.white.withOpacity(0.8),
                Colors.transparent,
              ],
              stops: const [0.0, 0.7, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    ).scale(
      alignment: Alignment.center,
      begin: const Offset(1.1, 1.1),
      end: const Offset(1.0, 1.0),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeOutQuart,
    );
  }

  // 构建百叶窗效果
  Widget _buildBlindsTransition(Widget child, Size size) {
    const int blindCount = 8;
    final double blindHeight = size.height / blindCount;
    
    List<Widget> blinds = List.generate(blindCount, (index) {
      final isEven = index % 2 == 0;
      final delayDuration = Duration(milliseconds: (index * 80).toInt());
      
      return Positioned(
        top: index * blindHeight,
        left: 0,
        right: 0,
        height: blindHeight,
        child: ClipRect(
          child: Align(
            alignment: Alignment(0, -1 + (2 * index / (blindCount - 1))),
            child: child,
          ),
        ).animate(
          delay: delayDuration,
        ).moveX(
          begin: isEven ? -size.width : size.width,
          end: 0,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutQuint,
        ).fadeIn(
          duration: const Duration(milliseconds: 600),
        ).scale(
          alignment: Alignment.center,
          begin: const Offset(0.95, 0.95),
          end: const Offset(1.0, 1.0),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutBack,
        ).rotate(
          begin: isEven ? 0.05 : -0.05,
          end: 0,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
        ),
      );
    });

    return Stack(
      children: [
        // 基础渐变过渡
        child.animate(
          delay: const Duration(milliseconds: 600),
          onPlay: (controller) {
            controller.addStatusListener((status) {
              if (status == AnimationStatus.completed) {
                onTransitionComplete?.call();
              }
            });
          },
        ).fadeIn(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        ),
        // 百叶窗层
        ...blinds,
      ],
    );
  }

  // 构建新的交叉溶解效果
  Widget _buildCrossFadeTransition(Widget child) {
    return child.animate(
      onPlay: (controller) {
        controller.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            onTransitionComplete?.call();
          }
        });
      },
    ).custom(
      duration: const Duration(milliseconds: 1500),
      builder: (context, value, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withOpacity(value),
                Colors.white.withOpacity(value * 0.8),
              ],
              stops: const [0.0, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    ).scale(
      alignment: Alignment.center,
      begin: const Offset(1.05, 1.05),
      end: const Offset(1.0, 1.0),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutQuart,
    );
  }

  // 构建幻灯片效果
  Widget _buildSlideTransition(Widget child) {
    return child.animate(
      onPlay: (controller) {
        controller.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            onTransitionComplete?.call();
          }
        });
      },
    ).moveX(
      begin: MediaQuery.of(context).size.width * 0.3,
      end: 0,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
    ).fadeIn(
      duration: const Duration(milliseconds: 600),
    ).scale(
      alignment: Alignment.center,
      begin: const Offset(1.1, 1.1),
      end: const Offset(1.0, 1.0),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutQuart,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final nextImage = Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          image: NetworkImage(imageUrl),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        switch (animationType) {
          case 0:
            return _buildFadeTransition(nextImage);
          case 1:
            return _build3DRotationTransition(nextImage);
          case 2:
            return _buildScaleTransition(nextImage);
          case 3:
            return _buildRadialTransition(nextImage);
          case 4:
            return _buildBlindsTransition(
              nextImage,
              Size(constraints.maxWidth, constraints.maxHeight),
            );
          case 5:
            return _buildCrossFadeTransition(nextImage);
          case 6:
            return _buildSlideTransition(nextImage);
          default:
            return nextImage.animate(
              onPlay: (controller) {
                controller.addStatusListener((status) {
                  if (status == AnimationStatus.completed) {
                    onTransitionComplete?.call();
                  }
                });
              },
            ).fadeIn(
              duration: const Duration(milliseconds: 800),
            );
        }
      },
    );
  }
}

/// VideoHoldBg的State实现
class _VideoHoldBgState extends State<VideoHoldBg> with TickerProviderStateMixin {
  // 样式常量和其他变量保持不变
  Timer? _timer;
  final GlobalKey<DynamicAudioBarsState> _audioBarKey = GlobalKey();

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
      isEnabled: false,
    ),
  );

  @override
  void initState() {
    super.initState();
    
    if (widget.showBingBackground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadBingBackgrounds();
        }
      });
    }
  }

  // 获取随机动画类型 - 修改为支持新增的动画类型
  int _getRandomAnimationType() {
    if (!mounted) return 0;

    final random = Random();
    // 调整各个动画类型的权重
    final weights = [0.15, 0.15, 0.15, 0.15, 0.15, 0.15, 0.1]; // 7种动画类型的权重
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

  // 加载Bing背景图片 - 保持不变
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
              !state.isTransitionLocked &&
              state.isEnabled) {
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

  // 开始图片切换 - 修改以使用新的动画系统
  void _startImageTransition() {
    final currentState = _backgroundState.value;
    if (currentState.isAnimating || !currentState.isEnabled) return;

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
          isTransitionLocked: true,
          currentAnimationType: _getRandomAnimationType(),
        );
      });
    } catch (e) {
      LogUtil.logError('开始图片切换时发生错误', e);
      _backgroundState.value = currentState.copyWith(
        isTransitionLocked: false,
      );
    }
  }

  // 构建本地背景 - 保持不变
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

  // 构建Bing背景 - 修改为使用新的动画系统
  Widget _buildBingBg() {
    final state = _backgroundState.value;
    if (state.imageUrls.isEmpty || !state.isEnabled) {
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
            imageUrl: state.imageUrls[state.nextIndex],
            animationType: state.currentAnimationType,
            onTransitionComplete: () {
              if (!mounted) return;
              
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
            },
          ),
      ],
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return Selector<ThemeProvider, bool>(
      selector: (_, provider) => provider.isBingBg,
      builder: (context, isBingBg, child) {
        // 当 isBingBg 改变时更新状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final currentState = _backgroundState.value;
          if (currentState.isEnabled != isBingBg) {
            _backgroundState.value = currentState.copyWith(
              isEnabled: isBingBg,
            );
          }
        });

        return Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 同时检查 showBingBackground 和 isBingBg
              (widget.showBingBackground && isBingBg)
                ? ValueListenableBuilder<BingBackgroundState>(
                    valueListenable: _backgroundState,
                    builder: (context, state, child) {
                      return _buildBingBg();
                    },
                  )
                : _buildLocalBg(),

              // 音频可视化层
              if (widget.showBingBackground)
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
      },
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

    super.dispose();
  }
}
