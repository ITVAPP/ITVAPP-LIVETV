import 'dart:async'; // 引入异步操作和定时器相关的库
import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart'; // 引入视频播放器库，用于处理视频播放
import '../generated/l10n.dart';
import '../provider/theme_provider.dart';
import '../gradient_progress_bar.dart'; // 引入渐变进度条
import '../util/log_util.dart'; // 引入日志工具类，用于处理日志输出

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

  @override
  void initState() {
    super.initState();
    // 初始化动画控制器，设置动画持续时间为 1 秒
    _animationController = AnimationController(duration: const Duration(seconds: 1), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);

    // 启动动画
    _animationController.forward();

    // 监听视频播放状态，判断是否为音频
    widget.videoController.addListener(() {
      setState(() {}); // 触发UI更新
    });
  }

  @override
  void dispose() {
    _animationController.dispose(); // 销毁动画控制器
    LogUtil.v('界面销毁，动画控制器取消'); // 记录日志，说明界面销毁时进行了资源清理
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 获取当前屏幕的宽度和方向，确定是竖屏还是横屏
    final mediaQuery = MediaQuery.of(context);
    final bool isPortrait = mediaQuery.orientation == Orientation.portrait;

    // 根据屏幕方向设置进度条的宽度，竖屏时进度条较宽，横屏时较窄
    double progressBarWidth = isPortrait ? mediaQuery.size.width * 0.6 : mediaQuery.size.width * 0.4;

    return Selector<ThemeProvider, bool>(
      // 使用Selector从ThemeProvider中选择isBingBg属性，确定是否启用Bing背景
      selector: (_, provider) => provider.isBingBg,
      builder: (BuildContext context, bool isBingBg, Widget? child) {
        return Stack(
          children: [
            // 判断视频是否开始播放
            if (!widget.videoController.value.isInitialized || !widget.videoController.value.isPlaying)
              // 视频未开始播放，显示本地背景
              _buildLocalBg()
            else if (widget.videoController.value.isPlaying && !widget.videoController.value.isInitialized)
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
                padding: const EdgeInsets.only(bottom: 25.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // 列表组件占最小高度，居于底部显示
                  children: [
                    // 使用自定义的GradientProgressBar作为加载进度条
                    GradientProgressBar(
                      width: progressBarWidth, // 进度条宽度根据屏幕方向动态调整
                      height: 5, // 进度条的高度固定为5
                    ),
                    const SizedBox(height: 15), // 进度条与文本之间的间隔
                    // 使用FittedBox自适应的文本框，用于显示加载提示或错误信息
                    FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        // 显示toastString，如果未提供则显示国际化的“加载中”提示
                        child: Text(
                          widget.toastString ?? S.current.loading,
                          style: const TextStyle(color: Colors.white, fontSize: 16), // 白色文字，字号16
                        ),
                      ),
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

  // 动态加载Bing图片背景，如果Bing图片加载失败则使用本地默认图片
  Widget _buildBingBg() {
    return FutureBuilder<String?>(
      // 异步获取Bing每日图片URL
      future: BingUtil.getBingImgUrl(),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        late ImageProvider image;
        if (snapshot.hasData && snapshot.data != null) {
          // 如果成功获取到Bing图片URL，则使用网络图片作为背景
          image = NetworkImage(snapshot.data!);
        } else {
          // 如果Bing图片URL获取失败，使用本地默认背景图片
          image = const AssetImage('assets/images/video_bg.png');
        }
        return Container(
          // 使用BoxDecoration设置背景图片，图片根据容器大小覆盖整个背景
          decoration: BoxDecoration(
            image: DecorationImage(fit: BoxFit.cover, image: image),
          ),
        );
      },
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
