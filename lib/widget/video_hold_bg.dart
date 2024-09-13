import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:itvapp_live_tv/util/bing_util.dart'; // 引入 Bing 工具类
import 'dart:async';
import '../generated/l10n.dart';
import '../provider/theme_provider.dart';
import '../gradient_progress_bar.dart';
import '../util/log_util.dart'; // 引入日志工具类

// Bing 背景图片的加载和切换（_fetchBingImages()、定时器切换背景图等）需要确定实现

class VideoHoldBg extends StatefulWidget {
  final String? toastString;
  final VideoPlayerController videoController; // 视频控制器

  const VideoHoldBg({
    Key? key,
    required this.toastString,
    required this.videoController,
  }) : super(key: key);

  @override
  _VideoHoldBgState createState() => _VideoHoldBgState();
}

class _VideoHoldBgState extends State<VideoHoldBg> with SingleTickerProviderStateMixin {
  List<String> bingImgUrls = []; // 存储 Bing 图片的 URL
  String currentBgUrl = 'assets/images/video_bg.png'; // 当前显示的背景图 URL
  int imgIndex = 0; // 当前 Bing 图片的索引
  Timer? _timer; // 定时器
  bool isLoading = true; // 是否处于加载状态
  bool isAudio = false; // 是否是音频
  bool showBgImage = true; // 控制背景图显示状态
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 初始化动画控制器和淡入淡出效果
    _animationController = AnimationController(duration: const Duration(seconds: 1), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);

    LogUtil.safeExecute(() {
      // 监听视频播放状态
      widget.videoController.addListener(() {
        setState(() {
          if (widget.videoController.value.isPlaying) {
            showBgImage = false; // 视频播放时移除背景图
          }

          // 判断播放内容是否为音频，尺寸为 null 或 0 认为是音频
          final size = widget.videoController.value.size;
          if (size == null || size.width == 0 || size.height == 0) {
            isAudio = true;
          } else {
            isAudio = false;
          }
        });
      });
    }, '初始化监听器失败');
  }

  @override
  void dispose() {
    _timer?.cancel(); // 界面销毁时取消定时器
    _animationController.dispose(); // 销毁动画控制器
    LogUtil.v('界面销毁，定时器和动画控制器取消');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double progressBarWidth = screenWidth * 0.6;

    // 显示本地背景图片和提示信息
    return Selector<ThemeProvider, bool>(
      selector: (_, provider) => provider.isBingBg,
      builder: (BuildContext context, bool isBingBg, Widget? child) {
        return FadeTransition(
          opacity: _fadeAnimation, // 应用淡入淡出效果
          child: Stack(
            children: [
              if (showBgImage) // 在播放前显示背景图
                Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      fit: BoxFit.cover,
                      image: AssetImage('assets/images/video_bg.png'),
                    ),
                  ),
                ),
              // 通过 toastString 控制进度条和提示文字的显示
              if (widget.toastString != null) // 只依赖 toastString
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GradientProgressBar(
                        width: progressBarWidth,
                        height: 5,
                        duration: const Duration(seconds: 3),
                      ),
                      const SizedBox(height: 8),
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
          ),
        );
      },
    );
  }
}
