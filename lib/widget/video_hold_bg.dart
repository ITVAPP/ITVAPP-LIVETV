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

  // 添加相等性比较
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BingBackgroundState &&
        listEquals(other.imageUrls, imageUrls) &&
        other.currentIndex == currentIndex &&
        other.nextIndex == nextIndex &&
        other.isAnimating == isAnimating &&
        other.isTransitionLocked == isTransitionLocked &&
        other.currentAnimationType == currentAnimationType &&
        other.isBingLoaded == isBingLoaded &&
        other.isEnabled == isEnabled;
  }

  // 添加哈希码实现
  @override
  int get hashCode =>
      Object.hash(
        Object.hashAll(imageUrls),
        currentIndex,
        nextIndex,
        isAnimating,
        isTransitionLocked,
        currentAnimationType,
        isBingLoaded,
        isEnabled,
      );
}

// 辅助函数：列表相等性比较
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
  
  // Logo目录缓存
  static Directory? _logoDirectory;
  
  // 常见图片扩展名列表
  static const List<String> _imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'];
  
  /// 从URL提取文件名，处理带参数的情况
  String _extractFileName(String url) {
    // 先提取路径最后一部分作为文件名
    String fileName = url.split('/').last;
    
    // 如果文件名含有参数（包含?号），只保留?号前面的部分
    if (fileName.contains('?')) {
      fileName = fileName.split('?').first;
    }
    
    // 如果提取后文件名为空，使用URL哈希值作为文件名
    if (fileName.isEmpty) {
      final hash = url.hashCode.abs().toString();
      return 'logo_$hash.png'; // 使用默认.png扩展名
    }
    
    // 确保文件名有合适的扩展名
    if (!_hasImageExtension(fileName)) {
      return '$fileName.png';
    }
    
    return fileName;
  }
  
  /// 检查文件名是否包含常见图像扩展名
  bool _hasImageExtension(String fileName) {
    return _imageExtensions.any((ext) => fileName.toLowerCase().endsWith(ext));
  }
  
  // 获取Logo存储目录
  static Future<Directory?> _getLogoDirectory() async {
    // 如果已有缓存目录，直接返回
    if (_logoDirectory != null) return _logoDirectory;
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final logoDir = Directory('${appDir.path}/channel_logos');
      
      if (await logoDir.exists()) {
        // 缓存目录实例
        _logoDirectory = logoDir;
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
      // 提取文件名，处理带参数的情况
      final fileName = _extractFileName(logoUrl);
      
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
    const BingBackgroundState(
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

    try {
      final random = Random();
      // 使用常量数组提高性能
      const List<double> weights = [0.3, 0.2, 0.25, 0.25]; // 动画类型权重
      final value = random.nextDouble();

      double accumulator = 0;
      for (int i = 0; i < weights.length; i++) {
        accumulator += weights[i];
        if (value < accumulator) {
          return i;
        }
      }
      return 0;
    } catch (e, stackTrace) {
      LogUtil.logError('动画类型选择错误', e, stackTrace);
      return 0;
    }
  }

  // 预加载图片到缓存
  Future<void> _precacheImage(String path) async {
    if (_precachedImages.contains(path)) return;
    
    try {
      final file = File(path);
      if (!(await file.exists())) {
        LogUtil.e('预加载图片失败：文件不存在 $path');
        return;
      }
      
      await precacheImage(
        FileImage(file),
        context,
        onError: (e, stackTrace) {
          LogUtil.logError('预加载图片失败: $path', e, stackTrace);
        },
      );
      _precachedImages.add(path);
    } catch (e, stackTrace) {
      LogUtil.logError('预加载图片过程中发生错误: $path', e, stackTrace);
    }
  }

  // 异步加载 Bing 背景图片
  Future<void> _loadBingBackgrounds() async {
    final currentState = _backgroundState.value;
    if (currentState.isBingLoaded || currentState.isTransitionLocked || !mounted) return;

    try {
      _updateBackgroundState(currentState.copyWith(isTransitionLocked: true));

      final String? channelId = widget.currentChannelTitle;
      final List<String> paths = await BingUtil.getBingImgUrls(channelId: channelId);

      if (!mounted) return;

      if (paths.isNotEmpty) {
        // 预加载逻辑优化：并行预加载以减少等待时间
        final preloadFutures = <Future>[];
        for (int i = 0; i < min(2, paths.length); i++) {
          preloadFutures.add(_precacheImage(paths[i]));
        }
        
        // 等待所有预加载完成
        await Future.wait(preloadFutures);

        if (!mounted) return;

        _updateBackgroundState(currentState.copyWith(
          imageUrls: paths,
          isBingLoaded: true,
          isTransitionLocked: false,
          isEnabled: true,
        ));

        _startTimer(paths.length); // 根据图片数量启动定时器
      } else {
        LogUtil.e('未获取到任何Bing图片路径');
        _updateBackgroundState(currentState.copyWith(
          isBingLoaded: true,
          isTransitionLocked: false,
        ));
      }
    } catch (e, stackTrace) {
      LogUtil.logError('加载Bing图片时发生错误', e, stackTrace);
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
    // 为提高性能，使用常量
    const int maxAnimationDuration = 4500; // 最长动画时长（毫秒）
    
    // 计算合适的间隔时间
    final int intervalSeconds = max(10, (maxAnimationDuration ~/ 1000) + (imageCount > 1 ? (30 ~/ imageCount) : 0));
    final interval = Duration(seconds: intervalSeconds);
    
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
    if (!mounted) return;
    if (_backgroundState.value != newState) {
      _backgroundState.value = newState;
    }
  }

  // 启动图片切换动画
  void _startImageTransition() {
    final currentState = _backgroundState.value;
    if (currentState.isAnimating || !currentState.isEnabled || !mounted) return;

    try {
      final nextIndex = (currentState.currentIndex + 1) % currentState.imageUrls.length;
      final nextImagePath = currentState.imageUrls[nextIndex];

      // 预先锁定状态，防止多次触发
      _updateBackgroundState(currentState.copyWith(isTransitionLocked: true));

      _precacheImage(nextImagePath).then((_) {
        if (!mounted) return;
        _updateBackgroundState(currentState.copyWith(
          isAnimating: true,
          nextIndex: nextIndex,
          currentAnimationType: _getRandomAnimationType(),
        ));
      }).catchError((e, stackTrace) {
        LogUtil.logError('预加载下一张图片失败', e, stackTrace);
        // 解除锁定，允许重试
        if (mounted) {
          _updateBackgroundState(currentState.copyWith(isTransitionLocked: false));
        }
      });
    } catch (e, stackTrace) {
      LogUtil.logError('开始图片切换时发生错误', e, stackTrace);
      if (mounted) {
        _updateBackgroundState(currentState.copyWith(isTransitionLocked: false));
      }
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

              // 优化：预加载下下张图片以提高流畅度
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
          if (currentState.isEnabled != isBingBg && mounted) {
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

    // 仅在需要时重新加载背景
    if (widget.showBingBackground && 
       (oldWidget.currentChannelTitle != widget.currentChannelTitle || 
        !_backgroundState.value.isBingLoaded)) {
      _loadBingBackgrounds(); 
    }

    // 音频条动画控制
    if (widget.showBingBackground && 
        oldWidget.toastString != widget.toastString && 
        _audioBarKey.currentState != null) {
      final toastStr = widget.toastString;
      if (toastStr != null && !["HIDE_CONTAINER", ""].contains(toastStr)) {
        _audioBarKey.currentState?.pauseAnimation(); // 暂停音频条动画
      } else {
        _audioBarKey.currentState?.resumeAnimation(); // 恢复音频条动画
      }
    }
  }

  @override
  void dispose() {
    // 清理状态，防止内存泄漏
    _isTimerActive = false;
    _timer?.cancel(); 
    _timer = null;
    _precachedImages.clear();
    _backgroundState.dispose();

    super.dispose();
  }
}
