import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io'; 
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/widget/music_bars.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 定义背景状态类，管理 Bing 图片切换相关属性
class BingBackgroundState {
  final List<String> imageUrls; // 存储图片 URL 的列表
  final int currentIndex; // 当前显示的图片索引
  final int nextIndex; // 下一张待显示图片的索引
  final bool isAnimating; // 标记是否正在执行动画
  final bool isTransitionLocked; // 标记切换状态是否被锁定
  final int currentAnimationType; // 当前使用的动画类型
  final bool isBingLoaded; // 标记 Bing 图片是否加载完成
  final bool isEnabled; // 标记是否启用 Bing 背景

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

  // 创建新状态副本，支持部分属性更新
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

// 视频占位背景组件，支持显示 Bing 图片或默认背景
class VideoHoldBg extends StatefulWidget {
  final String? toastString; // 显示的提示文本
  final String? currentChannelLogo; // 当前频道的标志 URL
  final String? currentChannelTitle; // 当前频道的标题
  final bool showBingBackground; // 是否启用 Bing 背景

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

// 频道标志组件，支持加载远程图片或默认标志
class ChannelLogo extends StatefulWidget {
  final String? logoUrl; // 标志图片的 URL
  final bool isPortrait; // 是否为竖屏模式

  const ChannelLogo({
    Key? key,
    required this.logoUrl,
    required this.isPortrait,
  }) : super(key: key);

  @override  
  State<ChannelLogo> createState() => _ChannelLogoState();
}

class _ChannelLogoState extends State<ChannelLogo> {
  static const double maxLogoSize = 58.0; // 标志的最大尺寸
  
  // 获取Logo存储目录
  static Future<Directory?> _getLogoDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final logoDir = Directory('${appDir.path}/channel_logos');
      
      if (await logoDir.exists()) {
        return logoDir;
      }
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('获取Logo目录失败', e, stackTrace);
      return null;
    }
  }
  
  // 检查本地是否有保存的logo
  Future<String?> _getLocalLogoPath(String? logoUrl) async {
    if (logoUrl == null || logoUrl.isEmpty) return null;
    
    try {
      // 提取文件名
      final fileName = logoUrl.split('/').last;
      if (fileName.isEmpty) return null;
      
      final logoDir = await _getLogoDirectory();
      if (logoDir == null) return null;
      
      final localPath = '${logoDir.path}/$fileName';
      final file = File(localPath);
      
      // 检查文件是否存在
      if (await file.exists()) {
        LogUtil.i('使用BetterPlayerConfig下载的Logo: $localPath');
        return localPath;
      }
      
      return null;
    } catch (e, stackTrace) {
      LogUtil.logError('检查本地Logo失败', e, stackTrace);
      return null;
    }
  }

  // 返回默认标志图片
  Widget get _defaultLogo => Image.asset(
        'assets/images/logo-2.png',
        fit: BoxFit.cover,
      );

  @override
  Widget build(BuildContext context) {
    final double logoSize = widget.isPortrait ? 48.0 : maxLogoSize; // 根据屏幕方向调整尺寸
    final double margin = widget.isPortrait ? 16.0 : 26.0; // 根据屏幕方向调整边距

    return Positioned(
      left: margin,
      top: margin,
      child: RepaintBoundary(
        child: Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle, // 圆形容器
            color: Colors.black26, // 背景色
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3), // 阴影颜色
                blurRadius: 10, // 模糊半径
                spreadRadius: 2, // 扩展半径
              ),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: FutureBuilder<String?>(
              future: _getLocalLogoPath(widget.logoUrl),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  // 使用本地已下载的logo
                  return Image.file(
                    File(snapshot.data!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      // 本地文件加载失败，尝试使用网络图片
                      return widget.logoUrl != null 
                        ? Image.network(
                            widget.logoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _defaultLogo,
                          )
                        : _defaultLogo;
                    },
                  );
                } else if (widget.logoUrl != null) {
                  // 本地没有找到文件，直接使用网络图片
                  return Image.network(
                    widget.logoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultLogo,
                  );
                } else {
                  return _defaultLogo;
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

// 音频条包装组件，控制音频可视化效果显示
class AudioBarsWrapper extends StatelessWidget {
  final GlobalKey<DynamicAudioBarsState> audioBarKey; // 音频条的状态键
  final bool isActive; // 是否激活音频条

  const AudioBarsWrapper({
    Key? key,
    required this.audioBarKey,
    this.isActive = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink(); // 未激活时返回空占位

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: MediaQuery.of(context).size.height * 0.3, // 占屏幕高度的30%
      child: RepaintBoundary(
        child: DynamicAudioBars(
          key: audioBarKey,
        ),
      ),
    );
  }
}

// 背景切换动画组件，支持多种过渡效果
class BackgroundTransition extends StatelessWidget {
  final String imageUrl; // 背景图片的 URL
  final int animationType; // 动画类型编号
  final VoidCallback? onTransitionComplete; // 动画完成时的回调

  const BackgroundTransition({
    Key? key,
    required this.imageUrl,
    required this.animationType,
    this.onTransitionComplete,
  }) : super(key: key);

  static const Duration _fadeDuration = Duration(milliseconds: 3000); // 淡入淡出动画时长
  static const Duration _scaleDuration = Duration(milliseconds: 3500); // 缩放动画时长
  static const Curve _easeInOut = Curves.easeInOut; // 缓入缓出曲线
  static const Curve _easeOutCubic = Curves.easeOutCubic; // 缓出立方曲线

  // 构建背景图片容器
  Widget _buildBackgroundImage(String path) {
    return Container(
      decoration: DecorationImage(
        fit: BoxFit.cover,
        image: FileImage(File(path)),
      ).toBoxDecoration(),
    );
  }

  // 平滑淡入过渡效果
  Widget _buildSmoothFadeTransition(Widget child) {
    return child
        .animate(
          onComplete: (controller) => onTransitionComplete?.call(), // 动画完成回调
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

  // Ken Burns 风格过渡效果
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

  // 方向性过渡效果
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

  // 交叉淡入过渡效果
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
        return _buildSmoothFadeTransition(nextImage); // 平滑淡入
      case 1:
        return _buildKenBurnsTransition(nextImage); // Ken Burns 效果  
      case 2:
        return _buildDirectionalTransition(nextImage); // 方向性过渡
      case 3:
        return _buildCrossFadeTransition(nextImage); // 交叉淡入
      default:
        return _buildSmoothFadeTransition(nextImage); // 默认平滑淡入
    }
  }
}

// 添加扩展方法，将 DecorationImage 转换为 BoxDecoration
extension DecorationImageExtension on DecorationImage {
  BoxDecoration toBoxDecoration() {
    return BoxDecoration(image: this);
  }
}

class VideoHoldBgState extends State<VideoHoldBg> with TickerProviderStateMixin {
  Timer? _timer; // 定时器，用于控制图片切换
  final GlobalKey<DynamicAudioBarsState> _audioBarKey = GlobalKey(); // 音频条的状态键
  bool _isTimerActive = false; // 标记定时器是否激活
  final Set<String> _precachedImages = {}; // 存储已预加载的图片路径

  // 背景状态通知器，管理背景切换状态
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

  // 缓存的默认背景装饰
  static final Decoration _defaultBackgroundDecoration = const BoxDecoration(
    image: DecorationImage(
      fit: BoxFit.cover,
      image: AssetImage('assets/images/video_bg.png'),
    ),
  );

  @override
  void initState() {
    super.initState();

    if (widget.showBingBackground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadBingBackgrounds(); // 初始化加载 Bing 背景图片
        }
      });
    }
  }

  // 基于权重随机选择动画类型
  int _getRandomAnimationType() {
    if (!mounted) return 0;

    final random = Random();
    const weights = [0.3, 0.2, 0.25, 0.25]; // 动画类型权重
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

  // 预加载图片到缓存
  Future<void> _precacheImage(String path) async {
    if (!_precachedImages.contains(path)) {
      await precacheImage(
        FileImage(File(path)),
        context,
        onError: (e, stackTrace) {
          LogUtil.logError('预加载图片失败: $path', e, stackTrace);
        },
      );
      _precachedImages.add(path);
    }
  }

  // 异步加载 Bing 背景图片
  Future<void> _loadBingBackgrounds() async {
    final currentState = _backgroundState.value;
    if (currentState.isBingLoaded || currentState.isTransitionLocked) return;

    try {
      _updateBackgroundState(currentState.copyWith(isTransitionLocked: true));

      final String? channelId = widget.currentChannelTitle;
      final List<String> paths = await BingUtil.getBingImgUrls(channelId: channelId);

      if (!mounted) return;

      if (paths.isNotEmpty) {
        for (int i = 0; i < min(2, paths.length); i++) {
          await _precacheImage(paths[i]); // 预加载最多两张图片
        }

        _updateBackgroundState(currentState.copyWith(
          imageUrls: paths,
          isBingLoaded: true,
          isTransitionLocked: false,
        ));

        _startTimer(paths.length); // 根据图片数量启动定时器
      } else {
        LogUtil.e('未获取到任何Bing图片路径');
        _updateBackgroundState(currentState.copyWith(
          isBingLoaded: true,
          isTransitionLocked: false,
        ));
      }
    } catch (e) {
      LogUtil.logError('加载Bing图片时发生错误', e);
      if (mounted) {
        _updateBackgroundState(currentState.copyWith(
          isBingLoaded: true,
          isTransitionLocked: false,
        ));
      }
    }
  }

  // 动态管理定时器，控制图片切换间隔
  void _startTimer(int imageCount) {
    _timer?.cancel();
    if (imageCount <= 1) {
      _isTimerActive = false;
      return;
    }

    _isTimerActive = true;
    const maxAnimationDuration = 4500; // 最长动画时长（毫秒）
    final interval = Duration(
      seconds: max(10, (maxAnimationDuration ~/ 1000) + (imageCount > 1 ? (30 ~/ imageCount) : 0)),
    );
    _timer = Timer.periodic(interval, (Timer timer) {
      if (!_isTimerActive || !mounted) return;
      final state = _backgroundState.value;
      if (!state.isAnimating &&
          state.imageUrls.length > 1 &&
          !state.isTransitionLocked &&
          state.isEnabled) {
        _startImageTransition(); // 触发图片切换
      }
    });
  }

  // 更新背景状态，仅在必要时触发
  void _updateBackgroundState(BingBackgroundState newState) {
    if (mounted && _backgroundState.value != newState) {
      _backgroundState.value = newState;
    }
  }

  // 启动图片切换动画
  void _startImageTransition() {
    final currentState = _backgroundState.value;
    if (currentState.isAnimating || !currentState.isEnabled) return;

    try {
      final nextIndex = (currentState.currentIndex + 1) % currentState.imageUrls.length;

      _precacheImage(currentState.imageUrls[nextIndex]).then((_) {
        if (!mounted) return;
        _updateBackgroundState(currentState.copyWith(
          isAnimating: true,
          nextIndex: nextIndex,
          isTransitionLocked: true,
          currentAnimationType: _getRandomAnimationType(),
        ));
      });
    } catch (e) {
      LogUtil.logError('开始图片切换时发生错误', e);
      _updateBackgroundState(currentState.copyWith(isTransitionLocked: false));
    }
  }

  // 构建背景装饰
  Decoration _buildBackgroundDecoration(ImageProvider image) {
    return BoxDecoration(
      image: DecorationImage(
        fit: BoxFit.cover,
        image: image,
      ),
    );
  }

  // 使用缓存的默认背景
  Widget _buildLocalBg() {
    return Container(
      decoration: _defaultBackgroundDecoration,
    );
  }

  // 构建支持动画切换的 Bing 背景
  Widget _buildBingBg() {
    final state = _backgroundState.value;
    if (state.imageUrls.isEmpty || !state.isEnabled) {
      return _buildLocalBg();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: _buildBackgroundDecoration(FileImage(File(state.imageUrls[state.currentIndex]))),
        ),
        if (state.isAnimating)
          BackgroundTransition(
            imageUrl: state.imageUrls[state.nextIndex],
            animationType: state.currentAnimationType,
            onTransitionComplete: () {
              if (!mounted) return;

              final currentState = _backgroundState.value;
              _updateBackgroundState(currentState.copyWith(
                isAnimating: false,
                currentIndex: currentState.nextIndex,
                currentAnimationType: _getRandomAnimationType(),
                isTransitionLocked: false,
              ));

              if (currentState.imageUrls.length > 1) {
                final nextNextIndex =
                    (currentState.nextIndex + 1) % currentState.imageUrls.length;
                _precacheImage(currentState.imageUrls[nextNextIndex]); // 预加载下一张图片
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
      selector: (_, provider) => provider.isBingBg, // 监听主题中的 Bing 背景开关
      builder: (context, isBingBg, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final currentState = _backgroundState.value;
          if (currentState.isEnabled != isBingBg) {
            _updateBackgroundState(currentState.copyWith(isEnabled: isBingBg));
          }
        });

        return Container(
          color: Colors.black, // 背景底色
          child: Stack(
            fit: StackFit.expand,
            children: [
              (widget.showBingBackground && isBingBg)
                  ? ValueListenableBuilder<BingBackgroundState>(
                      valueListenable: _backgroundState,
                      builder: (context, state, child) {
                        return _buildBingBg(); // 构建 Bing 背景
                      },
                    )
                  : _buildLocalBg(), // 构建默认背景
              if (widget.showBingBackground)
                AudioBarsWrapper(
                  audioBarKey: _audioBarKey,
                ),
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

    if (widget.showBingBackground) {
      _loadBingBackgrounds(); // 更新时重新加载背景
    }

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

  @override
  void dispose() {
    final currentState = _backgroundState.value;
    _updateBackgroundState(currentState.copyWith(
      isTransitionLocked: true,
      isAnimating: false,
      imageUrls: [],
    ));

    _isTimerActive = false;
    _timer?.cancel(); // 清理定时器
    _timer = null;
    _precachedImages.clear(); // 清理预加载记录
    _backgroundState.dispose(); // 释放通知器资源

    super.dispose();
  }
}
