import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:itvapp_live_tv/util/bing_util.dart'; // 引入 Bing 工具类
import 'dart:async';
import '../generated/l10n.dart';
import '../provider/theme_provider.dart';
import '../gradient_progress_bar.dart';
import '../util/log_util.dart'; // 引入日志工具类

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
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 初始化动画控制器和淡入淡出效果
    _animationController = AnimationController(duration: const Duration(seconds: 1), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);

    LogUtil.safeExecute(() {
      // 监听视频播放结束或缓冲状态
      widget.videoController.addListener(() {
        setState(() {
          if (!widget.videoController.value.isPlaying && !widget.videoController.value.isBuffering) {
            _timer?.cancel(); // 停止定时器
            LogUtil.v('视频播放停止或缓冲结束，定时器取消');
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

  // 获取 Bing 图片 URL 列表
  Future<void> _fetchBingImages() async {
    setState(() {
      isLoading = true; // 开始加载时，显示进度条
    });

    try {
      List<String> urls = await BingUtil.getBingImgUrls();
      LogUtil.v('成功获取 Bing 图片 URL 列表');
      if (urls.isNotEmpty) {
        setState(() {
          bingImgUrls = urls;
          currentBgUrl = bingImgUrls[0]; // 初始设置为第一张图片
          isLoading = false; // 图片加载完成，隐藏进度条
          _startBingImageTimer(); // 开始 Bing 图片定时器
          LogUtil.v('Bing 图片加载成功，当前背景图为第 1 张');
        });
      }
    } catch (e, stackTrace) {
      LogUtil.logError('获取 Bing 图片失败', e, stackTrace);
      setState(() {
        isLoading = false; // 加载失败时隐藏进度条
        currentBgUrl = 'assets/images/video_bg.png'; // 使用本地背景图作为回退
        LogUtil.v('加载 Bing 图片失败，使用本地背景图');
      });
    }
  }

  // 开始定时切换 Bing 图片
  void _startBingImageTimer() {
    LogUtil.safeExecute(() {
      if (bingImgUrls.isNotEmpty) {
        _timer = Timer.periodic(Duration(seconds: 30), (timer) {
          setState(() {
            imgIndex = (imgIndex + 1) % bingImgUrls.length; // 循环切换 Bing 图片
            currentBgUrl = bingImgUrls[imgIndex];
            _animationController.forward(from: 0.0); // 触发淡入动画
            LogUtil.v('切换到第 $imgIndex 张 Bing 图片');
          });
        });
      }
    }, '启动 Bing 图片定时器失败');
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double progressBarWidth = screenWidth * 0.6;

    // 获取视频缓冲状态
    bool isBuffering = widget.videoController.value.isBuffering;

    // 如果播放的是音频，通过 Selector 来监听 ThemeProvider 中的 isBingBg 状态
    return isAudio
        ? Selector<ThemeProvider, bool>(
            selector: (_, provider) => provider.isBingBg,
            builder: (BuildContext context, bool isBingBg, Widget? child) {
              LogUtil.safeExecute(() {
                if (isBingBg && bingImgUrls.isEmpty) {
                  _fetchBingImages(); // 加载 Bing 图片
                  LogUtil.v('正在使用 Bing 背景图片');
                } else if (!isBingBg) {
                  currentBgUrl = 'assets/images/video_bg.png'; // 使用本地背景图片
                  LogUtil.v('正在使用本地背景图片');
                }
              }, '选择背景图片失败');

              return _buildBackground(isBuffering, progressBarWidth);
            },
          )
        : Container(); // 如果是视频，不显示背景图
  }

  Widget _buildBackground(bool isBuffering, double progressBarWidth) {
    return FadeTransition(
      opacity: _fadeAnimation, // 应用淡入淡出效果
      child: Container(
        padding: const EdgeInsets.only(top: 30, bottom: 30),
        decoration: BoxDecoration(
          image: DecorationImage(
            fit: BoxFit.cover,
            image: isBuffering
                ? NetworkImage(currentBgUrl) // 缓冲时显示当前的 Bing 图片
                : NetworkImage(currentBgUrl), // 显示当前 Bing 图片
          ),
        ),
        child: Stack(
          children: [
            if (isLoading || isBuffering) // 如果正在加载或缓冲，显示进度条
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
      ),
    );
  }
}
