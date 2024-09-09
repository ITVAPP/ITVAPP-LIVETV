import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart'; // 引入视频播放器
import 'dart:async'; // 定时器需要的包
import '../generated/l10n.dart';
import '../provider/theme_provider.dart';
import '../gradient_progress_bar.dart'; // 引入渐变进度条

class VideoHoldBg extends StatefulWidget {
  final String? toastString;
  final VideoPlayerController videoController; // 视频控制器

  const VideoHoldBg({Key? key, required this.toastString, required this.videoController}) : super(key: key);

  @override
  _VideoHoldBgState createState() => _VideoHoldBgState();
}

class _VideoHoldBgState extends State<VideoHoldBg> with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  List<ImageProvider> bingImageProviders = []; // 用于存储预加载的 Bing 背景图片
  int currentImageIndex = 0; // 当前显示的 Bing 背景图片索引
  Timer? _timer; // 定时器用于定期切换背景图片
  late AnimationController _animationController; // 控制淡入淡出的动画控制器
  late Animation<double> _fadeAnimation; // 用于淡入淡出动画的透明度控制

  @override
  void initState() {
    super.initState();
    _controller = widget.videoController;

    // 初始化淡入淡出动画，动画持续时间为 2 秒
    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    // 预加载 Bing 背景图片
    _cacheBingImages();

    // 监听视频或音频的播放状态变化
    _controller.addListener(_onVideoPlayerStateChanged);

    // 初始化视频控制器
    _controller.initialize().then((_) {
      setState(() {}); // 初始化完成后刷新状态
    });
  }

  // 监听视频/音频状态，启动或停止背景切换
  void _onVideoPlayerStateChanged() {
    // 仅当使用 Bing 背景时处理图片轮换
    final isBingBg = Provider.of<ThemeProvider>(context, listen: false).isBingBg;
    if (isBingBg) {
      if (_controller.value.isPlaying) {
        // 如果音频正在播放且没有定时器，启动图片轮换
        if (_timer == null || !_timer!.isActive) {
          _startImageRotation();
        }
      } else {
        // 音频暂停或停止时，取消图片轮换
        _stopImageRotation();
      }
    }
  }

  // 异步方法：预加载 Bing 背景图片
  Future<void> _cacheBingImages() async {
    try {
      final bingUrls = await BingUtil.getBingImgUrls(); // 从 Bing 获取多个背景图片 URL
      setState(() {
        // 将获取到的 URL 转换为 NetworkImage 并存储
        bingImageProviders = bingUrls.map((url) => NetworkImage(url)).toList();
      });
    } catch (e) {
      // 如果获取图片失败，使用本地图片作为替代
      setState(() {
        bingImageProviders = [const AssetImage('assets/images/video_bg.png')];
      });
    }
  }

  // 启动定时器每 30 秒切换一次背景图片
  void _startImageRotation() {
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      setState(() {
        // 切换到下一张 Bing 背景图片
        currentImageIndex = (currentImageIndex + 1) % bingImageProviders.length;
        // 重置并启动淡入淡出动画
        _animationController.reset();
        _animationController.forward(); // 播放淡入淡出动画
      });
    });
  }

  // 停止背景图片轮换
  void _stopImageRotation() {
    _timer?.cancel(); // 取消定时器
  }

  @override
  void dispose() {
    _controller.dispose(); // 释放视频控制器资源
    _timer?.cancel(); // 取消定时器
    _animationController.dispose(); // 释放动画控制器资源
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 提前获取屏幕宽高以优化性能
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    double progressBarWidth = isPortrait ? screenWidth * 0.6 : screenWidth * 0.4;

    return Selector<ThemeProvider, bool>(
      selector: (_, provider) => provider.isBingBg, // 选择是否使用 Bing 背景
      builder: (BuildContext context, bool isBingBg, Widget? child) {
        return Stack(
          children: [
            // 根据视频状态决定显示内容
            if (_controller.value.isInitialized) ...[
              if (_controller.value.size.width > 0 && _controller.value.size.height > 0)
                // 视频播放时显示视频内容
                _buildVideoPlayer(isPortrait, screenWidth, screenHeight)
              else
                // 音频播放时，根据 isBingBg 决定显示 Bing 或本地背景
                _buildBingOrLocalBg(isBingBg, isPortrait, screenWidth, screenHeight)
            ] else
              // 加载和缓冲时显示本地背景
              _buildCustomLoadingBg(isPortrait, screenWidth, screenHeight),

            // 进度条和提示信息
            Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GradientProgressBar(
                    width: progressBarWidth,
                    height: 5, // 渐变进度条的高度
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Text(
                        widget.toastString ?? S.current.loading, // 显示加载提示信息
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // 构建视频播放器组件
  Widget _buildVideoPlayer(bool isPortrait, double screenWidth, double screenHeight) {
    return FittedBox(
      fit: BoxFit.cover, // 确保视频按比例填充屏幕
      child: SizedBox(
        width: screenWidth,
        height: isPortrait
            ? screenWidth / _controller.value.aspectRatio // 竖屏按宽度调整高度
            : screenHeight, // 横屏使用屏幕高度
        child: VideoPlayer(_controller), // 显示视频内容
      ),
    );
  }

  // 加载和缓冲时显示本地背景图片
  Widget _buildCustomLoadingBg(bool isPortrait, double screenWidth, double screenHeight) {
    return Container(
      width: screenWidth, // 设置背景宽度为屏幕宽度
      height: isPortrait
          ? screenWidth / 9 * 16 // 竖屏根据宽度按比例调整高度
          : screenHeight, // 横屏使用屏幕高度
      decoration: const BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover, // 背景图按比例填充全屏
          image: AssetImage('assets/images/loading_bg.png'), // 使用本地加载背景
        ),
      ),
    );
  }

  // 根据是否启用 Bing 背景来决定显示 Bing 或本地背景
  Widget _buildBingOrLocalBg(bool isBingBg, bool isPortrait, double screenWidth, double screenHeight) {
    return isBingBg ? _buildAnimatedBingBg(isPortrait, screenWidth, screenHeight) : _buildLocalBg(isPortrait, screenWidth, screenHeight);
  }

  // 带有淡入淡出效果的 Bing 背景
  Widget _buildAnimatedBingBg(bool isPortrait, double screenWidth, double screenHeight) {
    return FadeTransition(
      opacity: _fadeAnimation, // 淡入淡出效果
      child: Container(
        width: screenWidth,
        height: isPortrait
            ? screenWidth / 9 * 16 // 竖屏按比例调整高度
            : screenHeight, // 横屏使用屏幕高度
        decoration: BoxDecoration(
          image: DecorationImage(
            fit: BoxFit.cover, // 背景图片按比例填充
            image: bingImageProviders.isNotEmpty
                ? bingImageProviders[currentImageIndex] // 显示当前 Bing 背景图片
                : const AssetImage('assets/images/video_bg.png'), // 如果没有 Bing 图片则显示本地图片
          ),
        ),
      ),
    );
  }

  // 显示本地背景图
  Widget _buildLocalBg(bool isPortrait, double screenWidth, double screenHeight) {
    return Container(
      width: screenWidth,
      height: isPortrait
          ? screenWidth / 9 * 16 // 竖屏按比例调整高度
          : screenHeight, // 横屏使用屏幕高度
      decoration: const BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover, // 本地背景图按比例填充
          image: AssetImage('assets/images/video_bg.png'), // 使用本地背景图片
        ),
      ),
    );
  }
}
