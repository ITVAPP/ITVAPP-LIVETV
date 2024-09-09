import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart'; // 引入视频播放器
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

class _VideoHoldBgState extends State<VideoHoldBg> {
  late VideoPlayerController _controller;
  ImageProvider? bingImageProvider;

  @override
  void initState() {
    super.initState();
    _controller = widget.videoController;

    // 预加载 Bing 背景图
    _cacheBingImage();

    // 监听视频加载状态变化
    _controller.addListener(() {
      setState(() {});
    });

    _controller.initialize().then((_) {
      setState(() {}); // 初始化完成后刷新状态
    });
  }

  Future<void> _cacheBingImage() async {
    try {
      final bingUrl = await BingUtil.getBingImgUrl();
      bingImageProvider = NetworkImage(bingUrl);
    } catch (e) {
      bingImageProvider = const AssetImage('assets/images/video_bg.png');
    }
  }

  @override
  void dispose() {
    _controller.dispose(); // 释放控制器资源
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
      selector: (_, provider) => provider.isBingBg,
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
                    height: 5,
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Text(
                        widget.toastString ?? S.current.loading,
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

  // 构建视频播放器
  Widget _buildVideoPlayer(bool isPortrait, double screenWidth, double screenHeight) {
    return FittedBox(
      fit: BoxFit.cover, // 确保视频按比例填充屏幕
      child: SizedBox(
        width: screenWidth,
        height: isPortrait
            ? screenWidth / _controller.value.aspectRatio // 竖屏按宽度调整高度
            : screenHeight, // 横屏使用屏幕高度
        child: VideoPlayer(_controller),
      ),
    );
  }

  // 加载和缓冲时显示本地背景
  Widget _buildCustomLoadingBg(bool isPortrait, double screenWidth, double screenHeight) {
    return Container(
      width: screenWidth, // 宽度为屏幕宽度
      height: isPortrait
          ? screenWidth / 9 * 16 // 竖屏根据宽度按比例调整高度
          : screenHeight, // 横屏直接使用屏幕高度
      decoration: const BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover, // 确保背景图按比例填充全屏
          image: AssetImage('assets/images/loading_bg.png'), // 本地加载背景
        ),
      ),
    );
  }

  // 播放音频时显示 Bing 或本地背景
  Widget _buildBingOrLocalBg(bool isBingBg, bool isPortrait, double screenWidth, double screenHeight) {
    return isBingBg ? _buildBingBg(isPortrait, screenWidth, screenHeight) : _buildLocalBg(isPortrait, screenWidth, screenHeight);
  }

  // 获取 Bing 背景图
  Widget _buildBingBg(bool isPortrait, double screenWidth, double screenHeight) {
    return Container(
      width: screenWidth,
      height: isPortrait
          ? screenWidth / 9 * 16 // 竖屏按比例调整高度
          : screenHeight, // 横屏使用屏幕高度
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover, // 确保背景图按比例填充全屏
          image: bingImageProvider ?? const AssetImage('assets/images/video_bg.png'),
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
          fit: BoxFit.cover, // 确保背景图按比例填充全屏
          image: AssetImage('assets/images/video_bg.png'), // 使用本地背景
        ),
      ),
    );
  }
}
