import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/music_bars.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

/// 背景图片状态管理类
/// - 此类封装了背景图片的相关状态，比如当前图片索引、动画状态、是否启用Bing背景等
/// - 支持通过 `copyWith` 方法生成新状态对象，保持状态不可变性
class BingBackgroundState {
  final List<String> imageUrls; // 图片URL列表，存储从Bing加载的背景图片URL
  final int currentIndex; // 当前显示的图片索引
  final int nextIndex; // 即将显示的下一张图片索引
  final bool isAnimating; // 标志是否正在执行背景切换动画
  final bool isTransitionLocked; // 标志是否锁定背景切换，避免冲突
  final int currentAnimationType; // 当前使用的背景切换动画类型
  final bool isBingLoaded; // 标志是否成功加载了Bing图片
  final bool isEnabled; // 标志是否启用了Bing背景功能

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

  /// 创建状态副本，支持更新特定字段
  /// - 参数为可选类型，传入新值时会替换对应字段
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

/// 视频占位背景组件
/// - 该组件用于显示频道信息、Bing背景图等
/// - 支持可选的Bing背景模式
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
  VideoHoldBgState createState() => VideoHoldBgState();
}

/// 频道Logo组件
/// - 用于显示频道Logo，支持从网络加载和缓存机制
class ChannelLogo extends StatefulWidget {
  final String? logoUrl; // 频道Logo的URL
  final bool isPortrait; // 是否为纵向模式

  const ChannelLogo({
    Key? key,
    required this.logoUrl,
    required this.isPortrait,
  }) : super(key: key);

  @override  
  State<ChannelLogo> createState() => _ChannelLogoState();
}

class _ChannelLogoState extends State<ChannelLogo> {
  static const double maxLogoSize = 58.0; // Logo的最大尺寸

  /// 根据URL生成缓存的Key
  String _getCacheKey(String url) {
    return 'logo_${Uri.parse(url).pathSegments.last}';
  }

// 修改代码开始
  /// 加载带缓存的图片
  /// - 优先从缓存加载图片，若缓存不可用则从网络获取并缓存
  /// - 返回图片字节数据，失败时返回 null
  Future<Uint8List?> _loadCachedImage(String url) async {
    if (url.isEmpty) return null;

    try {
      final String cacheKey = _getCacheKey(url);
      
      // 1. 尝试从缓存加载
      final String? base64Data = SpUtil.getString(cacheKey);
      if (base64Data != null && base64Data.isNotEmpty) {
        try {
          return base64.decode(base64Data); // 解码Base64数据
        } catch (e) {
          await SpUtil.remove(cacheKey); // 缓存损坏，移除无效数据
          LogUtil.logError('缓存的Logo数据已损坏，已删除', e);
        }
      }

      // 2. 从网络加载
      final response = await HttpUtil().getRequestWithResponse(
        url,
        options: Options(
          extra: {
            'connectTimeout': const Duration(seconds: 5),  // 连接超时 5 秒
            'receiveTimeout': const Duration(seconds: 12), // 下载超时 12 秒
          },
        ),
      );

      if (response?.statusCode == 200 && response?.data is Uint8List) {
        final Uint8List imageData = response!.data as Uint8List;
        await SpUtil.putString(cacheKey, base64.encode(imageData)); // 缓存数据
        return imageData;
      }

      return null; // 加载失败
    } catch (e) {
      LogUtil.logError('加载图片失败: $url', e);
      return null;
    }
  }
// 修改代码结束

  /// 默认的Logo Widget
  Widget get _defaultLogo => Image.asset(
        'assets/images/logo-2.png',
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
              future: _loadCachedImage(widget.logoUrl ?? ''),
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

/// 音频可视化组件
/// - 包裹音频可视化条，控制显示与隐藏
class AudioBarsWrapper extends StatelessWidget {
  final GlobalKey<DynamicAudioBarsState> audioBarKey; // 动态音频条组件的Key
  final bool isActive; // 是否激活音频条显示

  const AudioBarsWrapper({
    Key? key,
    required this.audioBarKey,
    this.isActive = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink(); // 如果未激活，返回空组件

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: MediaQuery.of(context).size.height * 0.3, // 音频条高度为屏幕高度的30%
      child: RepaintBoundary(
        child: DynamicAudioBars(
          key: audioBarKey,
        ),
      ),
    );
  }
}

/// 背景动画组件
/// - 根据指定的动画类型实现背景切换的过渡效果
class BackgroundTransition extends StatelessWidget {
  final String imageUrl; // 图片URL
  final int animationType; // 动画类型
  final VoidCallback? onTransitionComplete; // 动画完成后的回调

  const BackgroundTransition({
    Key? key,
    required this.imageUrl,
    required this.animationType,
    this.onTransitionComplete,
  }) : super(key: key);

// 修改代码开始
  // 定义动画参数常量，避免重复
  static const Duration _fadeDuration = Duration(milliseconds: 3000);
  static const Duration _scaleDuration = Duration(milliseconds: 3500);
  static const Curve _easeInOut = Curves.easeInOut;
  static const Curve _easeOutCubic = Curves.easeOutCubic;

  /// 创建背景图片组件
  Widget _buildBackgroundImage(String url) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          image: NetworkImage(url),
        ),
      ),
    );
  }

  /// 平滑渐变过渡效果
  Widget _buildSmoothFadeTransition(Widget child) {
    return child
        .animate(
          onComplete: (controller) => onTransitionComplete?.call(),
        )
        .fade(
          begin: 0.0,
          end: 1.0,
          duration: _fadeDuration,
          curve: _easeInOut,
        )
        .scale(
          begin: const Offset(1.1, 1.1),
          end: const Offset(1.0, 1.0),
          duration: _scaleDuration,
          curve: _easeOutCubic,
        )
        .blur(
          begin: const Offset(8, 8),
          end: const Offset(0, 0),
          duration: _fadeDuration,
          curve: _easeInOut,
        );
  }

  /// Ken Burns 动画效果
  Widget _buildKenBurnsTransition(Widget child) {
    return child
        .animate(
          onComplete: (controller) => onTransitionComplete?.call(),
        )
        .fade(
          begin: 0.0,
          end: 1.0,
          duration: _fadeDuration,
          curve: _easeInOut,
        )
        .scale(
          begin: const Offset(1.0, 1.0),
          end: const Offset(1.15, 1.15),
          duration: Duration(milliseconds: 4500),
          curve: Curves.easeInOutCubic,
        )
        .blur(
          begin: const Offset(10, 10),
          end: const Offset(0, 0),
          duration: _fadeDuration,
          curve: _easeInOut,
        );
  }

  /// 方向性滑动切换效果
  Widget _buildDirectionalTransition(Widget child) {
    return child
        .animate(
          onComplete: (controller) => onTransitionComplete?.call(),
        )
        .fade(
          begin: 0.0,
          end: 1.0,
          duration: _fadeDuration,
          curve: _easeInOut,
        )
        .slideX(
          begin: 0.3,
          end: 0.0,
          duration: _scaleDuration,
          curve: _easeOutCubic,
        )
        .scale(
          begin: const Offset(1.1, 1.1),
          end: const Offset(1.0, 1.0),
          delay: 500.ms,
          duration: _fadeDuration,
          curve: _easeOutCubic,
        )
        .blur(
          begin: const Offset(12, 12),
          end: const Offset(0, 0),
          duration: _fadeDuration,
          curve: _easeInOut,
        );
  }

  /// 交叉淡入淡出效果
  Widget _buildCrossFadeTransition(Widget child) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child
            .animate(
              onComplete: (controller) => onTransitionComplete?.call(),
            )
            .fadeIn(
              duration: _fadeDuration,
              curve: _easeInOut,
            )
            .scale(
              begin: const Offset(1.05, 1.05),
              end: const Offset(1.0, 1.0),
              delay: 500.ms,
              duration: _scaleDuration,
              curve: _easeOutCubic,
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nextImage = _buildBackgroundImage(imageUrl);

    switch (animationType) {
      case 0:
        return _buildSmoothFadeTransition(nextImage);
      case 1:
        return _buildKenBurnsTransition(nextImage);  
      case 2:
        return _buildDirectionalTransition(nextImage);
      case 3:
        return _buildCrossFadeTransition(nextImage);
      default:
        return _buildSmoothFadeTransition(nextImage);
    }
  }
// 修改代码结束
}

/// VideoHoldBg的State实现
/// - 负责管理背景显示、频道Logo及音频可视化等逻辑
/// - 实现必应背景图片的加载和定时切换
class VideoHoldBgState extends State<VideoHoldBg> with TickerProviderStateMixin {
  Timer? _timer; // 定时器，用于控制背景图片切换
  final GlobalKey<DynamicAudioBarsState> _audioBarKey = GlobalKey(); // 动态音频条组件的Key
  bool _isTimerActive = false; // 标志定时器是否活跃

  // 背景状态管理
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

    // 如果需要显示必应背景图片，则在初始化完成后加载背景图片
    if (widget.showBingBackground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadBingBackgrounds();
        }
      });
    }
  }

// 修改代码开始
  /// 获取随机动画类型
  /// - 基于权重随机选择动画效果，确保权重总和为1
  int _getRandomAnimationType() {
    if (!mounted) return 0;

    final random = Random();
    // 动画权重设置，总和为1
    const weights = [0.3, 0.2, 0.25, 0.25]; // 平滑渐变、Ken Burns、方向性滑动、交叉淡入淡出
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

  /// 加载Bing背景图片
  /// - 调用工具类方法获取必应图片URL，并更新状态
  /// - 减少不必要的状态更新，合并为单次操作
  Future<void> _loadBingBackgrounds() async {
    final currentState = _backgroundState.value;
    if (currentState.isBingLoaded || currentState.isTransitionLocked) return;

    try {
      // 锁定状态
      _backgroundState.value = currentState.copyWith(isTransitionLocked: true);

      // 获取当前频道背景图片URL
      final String? channelId = widget.currentChannelTitle;
      final List<String> urls = await BingUtil.getBingImgUrls(channelId: channelId);

      if (!mounted) return;

      if (urls.isNotEmpty) {
        // 更新状态并预加载第一张图片
        _backgroundState.value = currentState.copyWith(
          imageUrls: urls,
          isBingLoaded: true,
          isTransitionLocked: false,
        );
        precacheImage(NetworkImage(urls[0]), context);

        // 设置定时切换
        _timer?.cancel(); // 确保旧定时器被取消
        _isTimerActive = true;
        _timer = Timer.periodic(const Duration(seconds: 45), (Timer timer) {
          if (!_isTimerActive || !mounted) return;
          final state = _backgroundState.value;
          if (!state.isAnimating &&
              state.imageUrls.length > 1 &&
              !state.isTransitionLocked &&
              state.isEnabled) {
            _startImageTransition();
          }
        });
      } else {
        LogUtil.e('未获取到任何Bing图片URL');
        _backgroundState.value = currentState.copyWith(
          isBingLoaded: true,
          isTransitionLocked: false,
        );
      }
    } catch (e) {
      LogUtil.logError('加载Bing图片时发生错误', e);
      if (mounted) {
        _backgroundState.value = currentState.copyWith(
          isBingLoaded: true,
          isTransitionLocked: false,
        );
      }
    }
  }

  /// 开始背景图片切换动画
  /// - 预加载下一张图片并触发动画，包含错误处理
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
          _backgroundState.value = currentState.copyWith(isTransitionLocked: false);
          return; // 提前返回，避免状态异常
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
      _backgroundState.value = currentState.copyWith(isTransitionLocked: false);
    }
  }

  /// 构建本地背景
  /// - 显示默认本地背景图片
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
// 修改代码结束

  /// 构建Bing背景
  /// - 根据当前状态显示背景图片，并支持动画切换
  Widget _buildBingBg() {
    final state = _backgroundState.value;
    if (state.imageUrls.isEmpty || !state.isEnabled) {
      return _buildLocalBg();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 当前图片层
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

              // 预加载下一个即将显示的图片
              if (currentState.imageUrls.length > 1) {
                final nextNextIndex =
                    (currentState.nextIndex + 1) % currentState.imageUrls.length;
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
              // 背景图片
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
                ),

              // Logo层
              if (widget.showBingBackground && widget.currentChannelLogo != null)
                ChannelLogo(
                  logoUrl: widget.currentChannelLogo,
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

    // 处理Bing背景显示状态的变化
    // - 如果新组件启用了Bing背景，而旧组件未启用，则加载背景图片
    if (widget.showBingBackground) {
      _loadBingBackgrounds(); // 调用加载Bing背景的方法
    }

    // 处理音频条动画的状态更新
    // - 当Toast文本内容变化时，决定音频条动画是暂停还是恢复
    if (widget.showBingBackground) {
      if (oldWidget.toastString != widget.toastString) {
        if (widget.toastString != null && !["HIDE_CONTAINER", ""].contains(widget.toastString)) {
          _audioBarKey.currentState?.pauseAnimation(); // 暂停音频条动画
        } else {
          _audioBarKey.currentState?.resumeAnimation(); // 恢复音频条动画
        }
      }
    }
  }

// 修改代码开始
  @override
  void dispose() {
    // 更新状态并停止定时器
    final currentState = _backgroundState.value;
    _backgroundState.value = currentState.copyWith(
      isTransitionLocked: true,
      isAnimating: false,
    );

    _isTimerActive = false; // 标记定时器不活跃
    _timer?.cancel();
    _timer = null;

    super.dispose();
  }
// 修改代码结束
}
