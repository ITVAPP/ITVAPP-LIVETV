import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:flutter_animate/flutter_animate.dart';
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

  // 平滑渐变过渡效果
  Widget _buildSmoothFadeTransition(Widget child) {
    return child
      .animate(
        onComplete: (controller) => onTransitionComplete?.call(),
      )
      .fade(
        begin: 0.0,
        end: 1.0,
        duration: const Duration(milliseconds: 4000),
        curve: Curves.easeOutCubic,
      )
      .scale(
        begin: const Offset(1.05, 1.05),
        end: const Offset(1.0, 1.0),
        duration: const Duration(milliseconds: 4000),
        curve: Curves.easeOutCubic,
      )
      .blur(
        begin: const Offset(8, 8),
        end: const Offset(0, 0),
        duration: const Duration(milliseconds: 3500),
        curve: Curves.easeOutCubic,
      );
  }

  // 放大渐变效果
  Widget _buildZoomFadeTransition(Widget child) {
    return child
      .animate(
        onComplete: (controller) => onTransitionComplete?.call(),
      )
      .fade(
        begin: 0.0,
        end: 1.0,
        duration: const Duration(milliseconds: 4000),
        curve: Curves.easeOutCubic,
      )
      .scale(
        begin: const Offset(1.2, 1.2),
        end: const Offset(1.0, 1.0),
        duration: const Duration(milliseconds: 4500),
        curve: Curves.easeOutExpo,
      )
      .blur(
        begin: const Offset(12, 12),
        end: const Offset(0, 0),
        duration: const Duration(milliseconds: 3500),
        curve: Curves.easeOutCubic,
      );
  }

  // 平移渐变效果
  Widget _buildSlideFadeTransition(Widget child) {
    return child
      .animate(
        onComplete: (controller) => onTransitionComplete?.call(),
      )
      .fade(
        begin: 0.0,
        end: 1.0,
        duration: const Duration(milliseconds: 4000),
        curve: Curves.easeOutCubic,
      )
      .slideY(
        begin: 0.05,
        end: 0,
        duration: const Duration(milliseconds: 4000),
        curve: Curves.easeOutCubic,
      )
      .scale(
        begin: const Offset(1.1, 1.1),
        end: const Offset(1.0, 1.0),
        duration: const Duration(milliseconds: 4000),
        curve: Curves.easeOutCubic,
      )
      .blur(
        begin: const Offset(10, 10),
        end: const Offset(0, 0),
        duration: const Duration(milliseconds: 3500),
        curve: Curves.easeOutCubic,
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

    switch (animationType) {
      case 0:
        return _buildSmoothFadeTransition(nextImage);
      case 1:
        return _buildZoomFadeTransition(nextImage);
      case 2:
        return _buildSlideFadeTransition(nextImage);
      default:
        return _buildSmoothFadeTransition(nextImage);
    }
  }
}

/// VideoHoldBg的State实现
class _VideoHoldBgState extends State<VideoHoldBg> with TickerProviderStateMixin {
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

  // 获取随机动画类型
  int _getRandomAnimationType() {
    if (!mounted) return 0;

    final random = Random();
    // 现在有3种动画效果，调整权重
    final weights = [0.4, 0.3, 0.3]; // 平滑渐变效果权重较大
    final value = random.nextDouble();

    try {
      double accumulator = 0;
      for (int i = 0; i < weights.length; i++) {
        accumulator += weights[i];
        if (value < accumulator) {
          return i;
        }
      }
      return 0; // 默认返回平滑渐变效果
    } catch (e) {
      LogUtil.logError('动画类型选择错误', e);
      return 0;
    }
  }

  // 加载Bing背景图片
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

        // 设置定时切换 - 每45秒切换一次图片
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

  // 开始图片切换
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
  
  // 构建本地背景
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

  // 构建Bing背景
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
                final nextNextIndex = (currentState.nextIndex + 1) % currentState.imageUrls.length;
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
