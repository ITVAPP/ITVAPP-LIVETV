import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:itvapp_live_tv/util/bing_util.dart'; // 引入 Bing 工具类
import 'dart:async';
import '../generated/l10n.dart';
import '../provider/theme_provider.dart';
import '../gradient_progress_bar.dart';

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

class _VideoHoldBgState extends State<VideoHoldBg> {
  List<String> bingImgUrls = []; // 存储 Bing 图片的 URL
  String currentBgUrl = ''; // 当前显示的背景图 URL
  int imgIndex = 0; // 当前 Bing 图片的索引
  Timer? _timer; // 定时器
  bool isLocalBg = true; // 默认使用本地背景图片
  bool isLoading = true; // 是否处于加载状态

  @override
  void initState() {
    super.initState();
    
    // 监听视频播放结束或缓冲状态
    widget.videoController.addListener(() {
      setState(() {
        if (!widget.videoController.value.isPlaying && !widget.videoController.value.isBuffering) {
          _timer?.cancel(); // 停止定时器
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // 界面销毁时取消定时器
    super.dispose();
  }

  // 获取 Bing 图片 URL 列表
  Future<void> _fetchBingImages() async {
    setState(() {
      isLoading = true; // 开始加载时，显示进度条
    });

    try {
      List<String> urls = await BingUtil.getBingImgUrls();
      if (urls.isNotEmpty) {
        setState(() {
          bingImgUrls = urls;
          currentBgUrl = bingImgUrls[0]; // 初始设置为第一张图片
          isLoading = false; // 图片加载完成，隐藏进度条
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false; // 加载失败时隐藏进度条
        currentBgUrl = 'assets/images/video_bg.png'; // 使用本地背景图作为回退
      });
    }
  }

  // 开始定时切换 Bing 图片
  void _startBingImageTimer() {
    if (bingImgUrls.isNotEmpty) {
      _timer = Timer.periodic(Duration(seconds: 30), (timer) {
        if (imgIndex < bingImgUrls.length - 1) {
          setState(() {
            imgIndex++;
            currentBgUrl = bingImgUrls[imgIndex]; // 切换到下一张图片
          });
        } else {
          timer.cancel(); // 如果图片切换完毕，停止定时器
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double progressBarWidth = screenWidth * 0.6;

    // 获取视频缓冲状态
    bool isBuffering = widget.videoController.value.isBuffering;

    // 使用 Selector 来监听 ThemeProvider 中的 isBingBg 状态
    return Selector<ThemeProvider, bool>(
      selector: (_, provider) => provider.isBingBg,
      builder: (BuildContext context, bool isBingBg, Widget? child) {
        // 如果 isBingBg 为 true，获取 Bing 背景图片并开始切换
        if (isBingBg && bingImgUrls.isEmpty) {
          _fetchBingImages();
          _startBingImageTimer();
        } else {
          // 使用本地背景图片
          currentBgUrl = 'assets/images/video_bg.png';
        }

        // 在缓冲状态下保持显示当前的 Bing 图片或视频帧
        return Container(
          padding: const EdgeInsets.only(top: 30, bottom: 30),
          decoration: BoxDecoration(
            image: DecorationImage(
              fit: BoxFit.cover,
              image: isBuffering
                  ? (widget.videoController.value.isPlaying
                      ? NetworkImage(currentBgUrl) // 缓冲时显示当前的 Bing 图片或视频帧
                      : AssetImage('assets/images/video_bg.png') as ImageProvider) // 保持 Bing 图片或使用本地图片
                  : (isBingBg
                      ? NetworkImage(currentBgUrl) // 显示 Bing 图片
                      : AssetImage('assets/images/video_bg.png') as ImageProvider), // 显示本地图片
            ),
          ),
          child: Stack(
            children: [
              // 注释掉中间的进度条
              // if (isLoading)
              //   Center(
              //     child: GradientProgressBar(
              //       width: progressBarWidth,
              //       height: 5,
              //       duration: const Duration(seconds: 3),
              //     ),
              //   ),
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
        );
      },
    );
  }
}
