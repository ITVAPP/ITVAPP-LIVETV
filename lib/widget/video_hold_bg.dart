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
  List<String> _bingImgUrls = [];  // 用于存储多个 Bing 背景图片 URL
  int _currentImgIndex = 0;  // 当前显示的背景图片索引
  Timer? _timer;  // 定时器，用于切换背景图片
  bool _isBingLoaded = false;  // 用于判断是否已经加载过 Bing 背景

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

  // 异步加载 Bing 图片 URL 列表
  Future<void> _loadBingBackgrounds() async {
    if (_isBingLoaded) return; // 防止重复加载
    try {
      _bingImgUrls = await BingUtil.getBingImgUrls();  // 获取最多 15 张 Bing 图片 URL
      if (_bingImgUrls.isNotEmpty) {
        setState(() {
          _isBingLoaded = true;  // 只加载一次 Bing 图片
        });

        // 只有在加载到 Bing 图片时才启动定时器
        _timer = Timer.periodic(Duration(seconds: 15), (Timer timer) {
          setState(() {
            _currentImgIndex = (_currentImgIndex + 1) % _bingImgUrls.length;  // 轮换图片
            _animationController.forward(from: 0.0);  // 每次切换图片时重新播放淡入动画
          });
        });
      } else {
        LogUtil.e('未获取到任何 Bing 图片 URL');
      }
    } catch (e) {
      LogUtil.logError('加载 Bing 图片时发生错误', e);  // 记录错误日志
    }
  }

  @override
  void dispose() {
    _animationController.dispose(); // 销毁动画控制器
    _timer?.cancel();  // 销毁定时器
    _timer = null;  // 将定时器置空，防止多次调用
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
        if (isBingBg && !_isBingLoaded) {
          // 如果启用Bing背景且未加载过，开始加载Bing图片
          _loadBingBackgrounds();
        }
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
