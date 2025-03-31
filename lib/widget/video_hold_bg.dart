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
class BingBackgroundState {
  final List<String> imageUrls; // 改为本地文件路径列表
  final int currentIndex;
  final int nextIndex;
  final bool isAnimating;
  final bool isTransitionLocked;
  final int currentAnimationType;
  final bool isBingLoaded;
  final bool isEnabled;

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

class VideoHoldBg extends StatefulWidget {
  final String? toastString;
  final String? currentChannelLogo;
  final String? currentChannelTitle;
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

  String _getCacheKey(String url) {
    return 'logo_${Uri.parse(url).pathSegments.last}';
  }

  Future<Uint8List?> _loadCachedImage(String url) async {
    if (url.isEmpty) return null;

    try {
      final String cacheKey = _getCacheKey(url);
      final String? base64Data = SpUtil.getString(cacheKey);
      if (base64Data != null && base64Data.isNotEmpty) {
        try {
          return base64.decode(base64Data);
        } catch (e) {
          await SpUtil.remove(cacheKey);
          LogUtil.logError('缓存的Logo数据已损坏，已删除', e);
        }
      }

      final response = await HttpUtil().getRequestWithResponse(
        url,
        options: Options(
          extra: {
            'connectTimeout': const Duration(seconds: 5),
            'receiveTimeout': const Duration(seconds: 12),
          },
        ),
      );

      if (response?.statusCode == 200 && response?.data is Uint8List) {
        final Uint8List imageData = response!.data as Uint8List;
        await SpUtil.putString(cacheKey, base64.encode(imageData));
        return imageData;
      }

      return null;
    } catch (e) {
      LogUtil.logError('加载图片失败: $url', e);
      return null;
    }
  }

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

class BackgroundTransition extends StatelessWidget {
  final String imageUrl; // 改为本地文件路径
  final int animationType;
  final VoidCallback? onTransitionComplete;

  const BackgroundTransition({
    Key? key,
    required this.imageUrl,
    required this.animationType,
    this.onTransitionComplete,
  }) : super(key: key);

  static const Duration _fadeDuration = Duration(milliseconds: 3000);
  static const Duration _scaleDuration = Duration(milliseconds: 3500);
  static const Curve _easeInOut = Curves.easeInOut;
  static const Curve _easeOutCubic = Curves.easeOutCubic;

  Widget _buildBackgroundImage(String path) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          image: FileImage(File(path)), // 修改为使用本地文件
        ),
      ),
    );
  }

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
}

class VideoHoldBgState extends State<VideoHoldBg> with TickerProviderStateMixin {
  Timer? _timer;
  final GlobalKey<DynamicAudioBarsState> _audioBarKey = GlobalKey();
  bool _isTimerActive = false;

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

  int _getRandomAnimationType() {
    if (!mounted) return 0;

    final random = Random();
    const weights = [0.3, 0.2, 0.25, 0.25];
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

  /// 修改：加载Bing背景图片，从本地读取或网络下载
  Future<void> _loadBingBackgrounds() async {
    final currentState = _backgroundState.value;
    if (currentState.isBingLoaded || currentState.isTransitionLocked) return;

    try {
      _backgroundState.value = currentState.copyWith(isTransitionLocked: true);

      final String? channelId = widget.currentChannelTitle;
      final List<String> paths = await BingUtil.getBingImgUrls(channelId: channelId);

      if (!mounted) return;

      if (paths.isNotEmpty) {
        _backgroundState.value = currentState.copyWith(
          imageUrls: paths,
          isBingLoaded: true,
          isTransitionLocked: false,
        );

        // 预加载第一张图片到内存
        precacheImage(FileImage(File(paths[0])), context);

        _timer?.cancel();
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
        LogUtil.e('未获取到任何Bing图片路径');
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

  /// 修改：开始背景图片切换动画，使用本地路径
  void _startImageTransition() {
    final currentState = _backgroundState.value;
    if (currentState.isAnimating || !currentState.isEnabled) return;

    try {
      final nextIndex = (currentState.currentIndex + 1) % currentState.imageUrls.length;

      precacheImage(
        FileImage(File(currentState.imageUrls[nextIndex])),
        context,
        onError: (e, stackTrace) {
          LogUtil.logError('预加载图片失败', e);
          _backgroundState.value = currentState.copyWith(isTransitionLocked: false);
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
    if (state.imageUrls.isEmpty || !state.isEnabled) {
      return _buildLocalBg();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              fit: BoxFit.cover,
              image: FileImage(File(state.imageUrls[state.currentIndex])), // 使用本地文件
            ),
          ),
        ),
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

              if (currentState.imageUrls.length > 1) {
                final nextNextIndex =
                    (currentState.nextIndex + 1) % currentState.imageUrls.length;
                precacheImage(
                  FileImage(File(currentState.imageUrls[nextNextIndex])),
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
              (widget.showBingBackground && isBingBg)
                  ? ValueListenableBuilder<BingBackgroundState>(
                      valueListenable: _backgroundState,
                      builder: (context, state, child) {
                        return _buildBingBg();
                      },
                    )
                  : _buildLocalBg(),
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
      _loadBingBackgrounds();
    }

    if (widget.showBingBackground) {
      if (oldWidget.toastString != widget.toastString) {
        if (widget.toastString != null && !["HIDE_CONTAINER", ""].contains(widget.toastString)) {
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

    _isTimerActive = false;
    _timer?.cancel();
    _timer = null;

    super.dispose();
  }
}
