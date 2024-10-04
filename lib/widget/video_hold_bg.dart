import 'dart:async';
import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import '../generated/l10n.dart';
import '../gradient_progress_bar.dart';

class VideoHoldBg extends StatefulWidget {
  final String? toastString;
  final VideoPlayerController videoController;
  const VideoHoldBg({Key? key, required this.toastString, required this.videoController}) : super(key: key);

  @override
  _VideoHoldBgState createState() => _VideoHoldBgState();
}

class _VideoHoldBgState extends State<VideoHoldBg> with TickerProviderStateMixin {
  late AnimationController _animationController; // 动画控制器，控制背景淡入淡出效果
  late Animation<double> _fadeAnimation; // 淡入淡出的动画效果
  List<String> _bingImgUrls = [];  // 用于存储多个 Bing 背景图片 URL
  int _currentImgIndex = 0;  // 当前显示的背景图片索引
  Timer? _timer;  // 定时器，用于切换背景图片
  bool _isBingLoaded = false;  // 用于判断是否已经加载过 Bing 背景

  late AnimationController _textAnimationController; // 文字滚动动画控制器
  late Animation<Offset> _textAnimation; // 文字滚动动画
  double _textWidth = 0;
  double _containerWidth = 0;

  @override
  void initState() {
    super.initState();

    // 初始化动画控制器，设置动画持续时间为 1 秒
    _animationController = AnimationController(duration: const Duration(seconds: 1), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);

    // 启动动画
    _animationController.forward();

    // 监听视频播放状态，判断是否为音频，并且仅当状态变化时更新 UI
    widget.videoController.addListener(_handleVideoUpdate);

    // 初始化时检查是否播放音频，直接判断当前状态
    final videoSize = widget.videoController.value.size;
    final isPlayingAudio = widget.videoController.value.isPlaying &&
        (videoSize == null || videoSize.width == 0 || videoSize.height == 0);
    if (isPlayingAudio && !_isBingLoaded) {
      _loadBingBackgrounds();
    }

    // 初始化文字滚动动画控制器
    _textAnimationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _textAnimation = Tween<Offset>(
      begin: Offset(1.0, 0.0),
      end: Offset(-1.0, 0.0),
    ).animate(_textAnimationController);

    _textAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _textAnimationController.reset();
        _textAnimationController.forward();
      }
    });

    _textAnimationController.forward();
  }

  // 处理视频播放状态变化，仅在状态变化时更新 UI
  void _handleVideoUpdate() {
    final videoSize = widget.videoController.value.size;
    final isPlayingAudio = widget.videoController.value.isPlaying &&
        (videoSize == null || videoSize.width == 0 || videoSize.height == 0);

    // 仅当状态发生变化时才更新 UI
    if (isPlayingAudio && !_isBingLoaded) {
      setState(() {});
    }
  }

  // 异步加载 Bing 图片 URL 列表
  Future<void> _loadBingBackgrounds() async {
    if (_isBingLoaded) return; // 防止重复加载
    try {
      _bingImgUrls = await BingUtil.getBingImgUrls();  // 获取Bing图片
      if (_bingImgUrls.isNotEmpty) {
        setState(() {
          _isBingLoaded = true;  // 只加载一次 Bing 图片
        });

        // 只有在加载到 Bing 图片时才启动定时器
        _timer = Timer.periodic(Duration(seconds: 30), (Timer timer) {
          setState(() {
            _currentImgIndex = (_currentImgIndex + 1) % _bingImgUrls.length;  // 轮换图片
            _animationController.forward(from: 0.0);  // 每次切换图片时重新播放淡入动画
          });
        });
      } else {
        LogUtil.e('未获取到任何 Bing 图片 URL');
        _isBingLoaded = true;  // 防止重复尝试加载
      }
    } catch (e) {
      LogUtil.logError('加载 Bing 图片时发生错误', e);  // 记录详细错误
      _isBingLoaded = true;  // 防止重复尝试加载
    }
  }

  @override
  void dispose() {
    _animationController.dispose(); // 销毁动画控制器
    _textAnimationController.dispose(); // 销毁文字滚动动画控制器
    _timer?.cancel();  // 销毁定时器
    _timer = null;  // 将定时器置空，防止多次调用
    widget.videoController.removeListener(_handleVideoUpdate); // 移除监听器，防止内存泄漏
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bool isPortrait = mediaQuery.orientation == Orientation.portrait;

    // 根据屏幕方向设置进度条的宽度，竖屏时进度条较宽，横屏时较窄
    double progressBarWidth = isPortrait ? mediaQuery.size.width * 0.5 : mediaQuery.size.width * 0.3;

    // 动态设置 padding 和 fontSize
    final EdgeInsets padding = EdgeInsets.only(bottom: isPortrait ? 15.0 : 20.0);
    final TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: isPortrait ? 16 : 18,
    );

    return Selector<ThemeProvider, bool>(
      // 使用Selector从ThemeProvider中选择isBingBg属性，确定是否启用Bing背景
      selector: (_, provider) => provider.isBingBg,
      builder: (BuildContext context, bool isBingBg, Widget? child) {
        // 判断是否启用 Bing 背景并且视频正在播放音频（通过尺寸判断）
        final videoSize = widget.videoController.value.size;
        final isPlayingAudio = widget.videoController.value.isPlaying &&
            (videoSize == null || videoSize.width == 0 || videoSize.height == 0);

        if (isBingBg && isPlayingAudio && !_isBingLoaded) {
          // 如果启用Bing背景且播放的是音频，并且未加载过，开始加载Bing图片
          _loadBingBackgrounds();
        }

        return Stack(
          children: [
            // 判断视频是否开始播放
            if (!widget.videoController.value.isInitialized || !widget.videoController.value.isPlaying)
              // 视频未开始播放，显示本地背景
              _buildLocalBg()
            else if (isPlayingAudio)
              // 视频播放音频时，根据isBingBg决定背景
              AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation.value,
                    child: isBingBg ? _buildBingBg() : _buildLocalBg(),
                  );
                },
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min, // 列表组件占最小高度，居于底部显示
                  children: [
                    // 使用自定义的GradientProgressBar作为加载进度条
                    GradientProgressBar(
                      width: progressBarWidth, // 进度条宽度根据屏幕方向动态调整
                      height: 5, // 进度条的高度固定为5
                    ),
                    const SizedBox(height: 8), // 进度条与文本之间的间隔
                    // 使用FittedBox自适应的文本框，用于显示加载提示或错误信息
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

  // 动态加载Bing图片背景，支持多张图片轮换展示
  Widget _buildBingBg() {
    return Container(
      decoration: BoxDecoration(
        image: _bingImgUrls.isNotEmpty
            ? DecorationImage(
                fit: BoxFit.cover,
                image: NetworkImage(_bingImgUrls[_currentImgIndex]), // 轮换展示的背景图片
              )
            : const DecorationImage(
                fit: BoxFit.cover,
                image: AssetImage('assets/images/video_bg.png'), // 若无Bing图片，使用本地默认背景
              ),
      ),
    );
  }

  // 使用本地图片背景，当未启用Bing背景或未能加载Bing背景时调用此方法
  Widget _buildLocalBg() {
    return Container(
      decoration: const BoxDecoration(
        // 本地图片作为背景，图片根据容器大小覆盖整个背景
        image: DecorationImage(
          fit: BoxFit.cover,
          image: AssetImage('assets/images/video_bg.png'),
        ),
      ),
    );
  }
}
