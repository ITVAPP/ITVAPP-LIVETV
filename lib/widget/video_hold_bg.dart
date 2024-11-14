import 'dart:async';
import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import '../generated/l10n.dart';
import '../gradient_progress_bar.dart';

class VideoHoldBg extends StatefulWidget {
  final String? toastString;
  final bool showBingBackground; // 可选参数：是否显示 Bing 背景，默认 false

  const VideoHoldBg({Key? key, required this.toastString, this.showBingBackground = false}) : super(key: key);

  @override
  _VideoHoldBgState createState() => _VideoHoldBgState();
}

class _VideoHoldBgState extends State<VideoHoldBg> with TickerProviderStateMixin {
  late AnimationController _animationController; // 动画控制器，控制背景淡入淡出效果
  late Animation<double> _fadeAnimation; // 淡入淡出的动画效果
  late Animation<Offset> _slideAnimation; // 幻灯片动画效果
  late Animation<double> _scaleAnimation; // 缩放动画效果
  List<String> _bingImgUrls = [];  // 用于存储多个 Bing 背景图片 URL
  int _currentImgIndex = 0;  // 当前显示的背景图片索引
  Timer? _timer;  // 定时器，用于切换背景图片
  bool _isBingLoaded = false;  // 用于判断是否已经加载过 Bing 背景
  bool _isAnimating = false;  // 用于跟踪动画状态
  late int _nextImgIndex;  // 下一张图片的索引
  late int _currentAnimationType; // 当前动画类型

  late AnimationController _textAnimationController; // 文字滚动动画控制器
  late Animation<Offset> _textAnimation; // 文字滚动动画
  double _textWidth = 0;
  double _containerWidth = 0;

  @override
  void initState() {
    super.initState();

    // 初始化动画控制器，使用更长的动画时间实现平滑过渡
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _currentAnimationType = _getRandomAnimationType();

    // 监听动画状态
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isAnimating = false;
          _currentImgIndex = _nextImgIndex;
          _currentAnimationType = _getRandomAnimationType();
        });
        _animationController.value = 0.0;
      }
    });

    // 初始化文字滚动动画控制器
    _textAnimationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _textAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: const Offset(-1.0, 0.0),
    ).animate(_textAnimationController);

    _textAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _textAnimationController.reset();
        _textAnimationController.forward();
      }
    });

    _textAnimationController.forward();

    // 判断是否需要加载 Bing 背景
    if (widget.showBingBackground && !_isBingLoaded) {
      _loadBingBackgrounds();
    }
  }

  int _getRandomAnimationType() {
    return DateTime.now().millisecondsSinceEpoch % 3;
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

        // 设置图片切换定时器
        _timer = Timer.periodic(const Duration(seconds: 30), (Timer timer) {
          if (!_isAnimating && mounted && _bingImgUrls.length > 1) {
            _startImageTransition();
          }
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

  // 新增：处理图片切换的方法
  void _startImageTransition() {
    if (_isAnimating || _bingImgUrls.length <= 1) return;
    
    setState(() {
      _isAnimating = true;
      _nextImgIndex = (_currentImgIndex + 1) % _bingImgUrls.length;
    });
    
    _animationController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _animationController.dispose(); // 销毁动画控制器
    _textAnimationController.dispose(); // 销毁文字滚动动画控制器
    _timer?.cancel();  // 销毁定时器
    _timer = null;  // 将定时器置空，防止多次调用
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
        // 判断是否启用 Bing 背景，取决于外部传入的 showBingBackground 参数
        if (widget.showBingBackground && isBingBg && !_isBingLoaded) {
          _loadBingBackgrounds();
        }

        final bool shouldShowBingBg = widget.showBingBackground && isBingBg;

        return Stack(
          children: [
            // 根据showBingBackground决定背景
            shouldShowBingBg ? _buildBingBg() : _buildLocalBg(),
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

  // 优化后的 Bing 背景构建方法
  Widget _buildBingBg() {
    if (_bingImgUrls.isEmpty) {
      return _buildLocalBg();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              fit: BoxFit.cover,
              image: NetworkImage(_bingImgUrls[_currentImgIndex]),
            ),
          ),
        ),
        if (_isAnimating)
          _buildAnimatedTransition(),
      ],
    );
  }

  Widget _buildAnimatedTransition() {
    final nextImage = Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          image: NetworkImage(_bingImgUrls[_nextImgIndex]),
        ),
      ),
    );

    switch (_currentAnimationType) {
      case 0: // 淡入淡出
        return FadeTransition(
          opacity: _fadeAnimation,
          child: nextImage,
        );
      case 1: // 幻灯片
        return SlideTransition(
          position: _slideAnimation,
          child: nextImage,
        );
      case 2: // 缩放
        return ScaleTransition(
          scale: _scaleAnimation,
          child: nextImage,
        );
      default:
        return FadeTransition(
          opacity: _fadeAnimation,
          child: nextImage,
        );
    }
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
