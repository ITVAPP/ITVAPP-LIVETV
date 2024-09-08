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

  @override
  void initState() {
    super.initState();
    _controller = widget.videoController;

    // 监听视频加载状态变化
    _controller.addListener(() {
      setState(() {});
    });

    _controller.initialize().then((_) {
      setState(() {}); // 初始化完成后刷新状态
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // 释放控制器资源
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bool isPortrait = mediaQuery.orientation == Orientation.portrait;
    double progressBarWidth = isPortrait ? mediaQuery.size.width * 0.6 : mediaQuery.size.width * 0.4;

    return Selector<ThemeProvider, bool>(
      selector: (_, provider) => provider.isBingBg,
      builder: (BuildContext context, bool isBingBg, Widget? child) {
        return Stack(
          children: [
            // 显示自定义背景（加载中）或播放状态下的背景
            _controller.value.isInitialized
                ? (_controller.value.size.width > 0 && _controller.value.size.height > 0)
                    ? _buildVideoPlayer() // 如果是视频内容，显示视频
                    : _buildBingOrLocalBg(isBingBg, isPortrait) // 如果是音频内容，显示 Bing 或本地背景
                : _buildCustomLoadingBg(isPortrait), // 加载状态显示自定义背景
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
  Widget _buildVideoPlayer() {
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: VideoPlayer(_controller),
    );
  }

  // 加载状态显示自定义背景
  Widget _buildCustomLoadingBg(bool isPortrait) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          image: AssetImage('assets/images/loading_bg.png'), // 使用自定义的本地加载背景图
        ),
      ),
      width: double.infinity,
      height: double.infinity,
    );
  }

  // 播放音频时显示 Bing 或本地背景图
  Widget _buildBingOrLocalBg(bool isBingBg, bool isPortrait) {
    return isBingBg ? _buildBingBg(isPortrait) : _buildLocalBg(isPortrait);
  }

  Widget _buildBingBg(bool isPortrait) {
    return FutureBuilder<String?>(
      future: BingUtil.getBingImgUrl(),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        late ImageProvider image;
        if (snapshot.hasData && snapshot.data != null) {
          image = NetworkImage(snapshot.data!);
        } else {
          image = const AssetImage('assets/images/video_bg.png');
        }
        return _buildBackground(image, isPortrait);
      },
    );
  }

  Widget _buildLocalBg(bool isPortrait) {
    return _buildBackground(const AssetImage('assets/images/video_bg.png'), isPortrait);
  }

  Widget _buildBackground(ImageProvider image, bool isPortrait) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: isPortrait ? BoxFit.cover : BoxFit.contain,
          image: image,
        ),
      ),
      width: double.infinity,
      height: double.infinity,
    );
  }
}
