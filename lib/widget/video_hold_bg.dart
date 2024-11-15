import 'dart:async';
import 'dart:math';
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
  late Animation<double> _rotationAnimation; // 旋转动画效果
  late Animation<double> _scaleAnimation; // 缩放动画效果
  late Animation<double> _radialAnimation; // 径向扩散动画
  late List<Animation<double>> _blindAnimations; // 百叶窗动画列表
  static const int _blindCount = 12; // 增加百叶窗数量，使效果更细腻
  
  List<String> _bingImgUrls = [];  // 用于存储多个 Bing 背景图片 URL
  int _currentImgIndex = 0;  // 当前显示的背景图片索引
  Timer? _timer;  // 定时器，用于切换背景图片
  bool _isBingLoaded = false;  // 用于判断是否已经加载过 Bing 背景
  bool _isAnimating = false;  // 用于跟踪动画状态
  bool _isTransitionLocked = false; // 状态锁，防止并发操作
  late int _nextImgIndex;  // 下一张图片的索引
  late int _currentAnimationType; // 当前动画类型

  late AnimationController _textAnimationController; // 文字滚动动画控制器
  late Animation<Offset> _textAnimation; // 文字滚动动画
  double _textWidth = 0;
  double _containerWidth = 0;

  // 添加音柱控制相关的Key
  final GlobalKey<_DynamicAudioBarsState> _audioBarKey = GlobalKey();
  
@override
void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(seconds: 5),  // 动画时长5秒
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic),
      reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic),
    );

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeInOutBack),
    ));

    _scaleAnimation = Tween<double>(
      begin: 1.4,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
    ));

    _radialAnimation = Tween<double>(
      begin: 0.0,
      end: 3.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutQuart),
    ));
    
    _blindAnimations = List.generate(_blindCount, (index) {
     final startInterval = (index * 0.04).clamp(0.0, 0.6);
     final endInterval = ((index + 1) * 0.04 + 0.4).clamp(startInterval + 0.1, 1.0);
     
     return Tween<double>(
       begin: 0.0,
       end: 1.0,
     ).animate(CurvedAnimation(
       parent: _animationController,
       curve: Interval(
         startInterval,
         endInterval,
         curve: Curves.easeInOutQuint,
       ),
     ));
   });
   
   _currentAnimationType = _getRandomAnimationType();

   _animationController.addStatusListener((status) {
     if (!mounted) return;
     
     if (status == AnimationStatus.completed) {
       setState(() {
         _isAnimating = false;
         _currentImgIndex = _nextImgIndex;
         _currentAnimationType = _getRandomAnimationType();
         _isTransitionLocked = false;
       });
       _animationController.value = 0.0;
       
       if (_bingImgUrls.length > 1) {
         final nextNextIndex = (_currentImgIndex + 1) % _bingImgUrls.length;
         precacheImage(NetworkImage(_bingImgUrls[nextNextIndex]), context);
       }
     } else if (status == AnimationStatus.dismissed) {
       _isTransitionLocked = false;
     }
   });

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

   if (widget.showBingBackground && !_isBingLoaded) {
     _loadBingBackgrounds();
   }
}

// 添加监听toastString变化的方法
@override
void didUpdateWidget(VideoHoldBg oldWidget) {
  super.didUpdateWidget(oldWidget);
  
  // 仅在 showBingBackground=true 时处理音柱动画
  if (widget.showBingBackground) {
    if (oldWidget.toastString != widget.toastString) {
      if (widget.toastString != null) {
        // 有消息时暂停动画
        _audioBarKey.currentState?.pauseAnimation();
      } else {
        // 消息消失后继续动画
        _audioBarKey.currentState?.resumeAnimation();
      }
    }
  }
}

int _getRandomAnimationType() {
   if (!mounted) return 0;
   
   final random = Random();
   final weights = [0.15, 0.25, 0.2, 0.2, 0.2];
   final value = random.nextDouble();
   
   try {
     double accumulator = 0;
     for (int i = 0; i < weights.length; i++) {
       accumulator += weights[i];
       if (value < accumulator) {
         return i;
       }
     }
     return 0;
   } catch (e) {
     LogUtil.logError('动画类型选择错误', e);
     return 0;
   }
}

Future<void> _loadBingBackgrounds() async {
   if (_isBingLoaded || _isTransitionLocked) return;
   
   try {
     _isTransitionLocked = true;
     _bingImgUrls = await BingUtil.getBingImgUrls();
     
     if (!mounted) return;
     
     if (_bingImgUrls.isNotEmpty) {
       setState(() {
         _isBingLoaded = true;
         precacheImage(NetworkImage(_bingImgUrls[0]), context);
       });

       _timer = Timer.periodic(const Duration(seconds: 45), (Timer timer) {
         if (!_isAnimating && mounted && _bingImgUrls.length > 1 && !_isTransitionLocked) {
           _startImageTransition();
         }
       });
     } else {
       LogUtil.e('未获取到任何 Bing 图片 URL');
     }
   } catch (e) {
     LogUtil.logError('加载 Bing 图片时发生错误', e);
   } finally {
     if (mounted) {
       setState(() {
         _isBingLoaded = true;
         _isTransitionLocked = false;
       });
     }
   }
}
 
void _startImageTransition() {
   if (_isAnimating || 
       _isTransitionLocked || 
       _bingImgUrls.length <= 1 || 
       !mounted) return;
   
   try {
     _isTransitionLocked = true;
     
     final nextIndex = (_currentImgIndex + 1) % _bingImgUrls.length;
     
     precacheImage(
       NetworkImage(_bingImgUrls[nextIndex]),
       context,
       onError: (e, stackTrace) {
         LogUtil.logError('预加载图片失败', e);
         _isTransitionLocked = false;
       },
     ).then((_) {
       if (!mounted) return;
       
       setState(() {
         _isAnimating = true;
         _nextImgIndex = nextIndex;
       });
       
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
           _animationController.forward(from: 0.0);
         }
       });
     });
   } catch (e) {
     LogUtil.logError('开始图片切换时发生错误', e);
     _isTransitionLocked = false;
   }
}

@override
void dispose() {
   _isTransitionLocked = true;
   _isAnimating = false;
   
   _timer?.cancel();
   _timer = null;
   
   _animationController.stop();
   _animationController.dispose();
   
   _textAnimationController.stop();
   _textAnimationController.dispose();
   
   super.dispose();
}

Widget _buildAnimatedTransition() {
   if (_nextImgIndex >= _bingImgUrls.length || !mounted || _isTransitionLocked) {
     return const SizedBox.shrink();
   }

   try {
     precacheImage(NetworkImage(_bingImgUrls[_nextImgIndex]), context);
     
     final nextImage = Container(
       decoration: BoxDecoration(
         image: DecorationImage(
           fit: BoxFit.cover,
           image: NetworkImage(_bingImgUrls[_nextImgIndex]),
         ),
       ),
     );

     final fadeTransition = FadeTransition(
       opacity: _fadeAnimation,
       child: nextImage,
     );

     switch (_currentAnimationType) {
       case 0:
         return fadeTransition;
         
       case 1:
         return AnimatedBuilder(
           animation: _rotationAnimation,
           builder: (context, child) {
             if (_rotationAnimation.value.isNaN) return fadeTransition;
             
             return Transform(
               alignment: Alignment.center,
               transform: Matrix4.identity()
                 ..setEntry(3, 2, 0.003)
                 ..rotateY(_rotationAnimation.value * pi)
                 ..scale(_rotationAnimation.value < 0.5 ? 
                         1.0 + (_rotationAnimation.value * 0.4) :
                         1.4 - (_rotationAnimation.value * 0.4)),
               child: fadeTransition,
             );
           },
         );

       case 2:
         return AnimatedBuilder(
           animation: _scaleAnimation,
           builder: (context, child) {
             final progress = _scaleAnimation.value;
             if (progress.isNaN) return fadeTransition;
             
             final scale = Tween<double>(begin: 1.4, end: 1.0)
                 .transform(progress)
                 .clamp(0.8, 1.6);
             final opacity = Tween<double>(begin: 0.0, end: 1.0)
                 .transform(progress)
                 .clamp(0.0, 1.0);
             
             return Transform(
               alignment: Alignment.center,
               transform: Matrix4.identity()
                 ..scale(scale)
                 ..translate(
                   0.0,
                   30.0 * (1.0 - progress).clamp(0.0, 1.0),
                 ),
               child: Opacity(
                 opacity: opacity,
                 child: child,
               ),
             );
           },
           child: fadeTransition,
         );
         
       case 3:
         return AnimatedBuilder(
           animation: _radialAnimation,
           builder: (context, child) {
             if (_radialAnimation.value.isNaN) return fadeTransition;
             
             return Stack(
               children: [
                 ClipPath(
                   clipper: CircleRevealClipper(
                     fraction: _radialAnimation.value.clamp(0.0, 3.2),
                     centerAlignment: Alignment.center,
                   ),
                   child: fadeTransition,
                 ),
                 if (_radialAnimation.value > 0.2 && _radialAnimation.value < 2.8)
                   Opacity(
                     opacity: (1.0 - _radialAnimation.value).clamp(0.0, 0.4),
                     child: ClipPath(
                       clipper: CircleRevealClipper(
                         fraction: (_radialAnimation.value - 0.1).clamp(0.0, 3.0),
                         centerAlignment: Alignment.center,
                       ),
                       child: Container(
                         decoration: BoxDecoration(
                           border: Border.all(
                             color: Colors.white.withOpacity(0.4),
                             width: 2.5,
                           ),
                         ),
                       ),
                     ),
                   ),
               ],
             );
           },
         );
         
       case 4:
         final screenSize = MediaQuery.of(context).size;
         if (screenSize.isEmpty) return fadeTransition;
         
         final height = 1.0 / _blindCount.clamp(1, 20);
         if (height.isNaN || height <= 0) return fadeTransition;
         
         return Stack(
           children: List.generate(_blindCount, (index) {
             final topPosition = index * height * screenSize.height;
             final blindHeight = height * screenSize.height;
             
             if (topPosition.isNaN || blindHeight.isNaN || 
                 topPosition < 0 || blindHeight <= 0) {
               return const SizedBox.shrink();
             }

             return Positioned(
               top: topPosition,
               left: 0,
               right: 0,
               height: blindHeight,
               child: AnimatedBuilder(
                 animation: _blindAnimations[index],
                 builder: (context, child) {
                   final progress = _blindAnimations[index].value;
                   if (progress.isNaN) return const SizedBox.shrink();
                   
                   return Transform(
                     transform: Matrix4.identity()
                       ..translate(
                         -screenSize.width * (1 - progress).clamp(0.0, 1.0),
                         (1 - progress).clamp(0.0, 1.0) * 8.0,
                       )
                       ..scale(
                         1.0,
                         (0.92 + (progress * 0.08)).clamp(0.9, 1.0),
                       ),
                     child: Opacity(
                       opacity: progress.clamp(0.0, 1.0),
                       child: child,
                     ),
                   );
                 },
                 child: fadeTransition,
               ),
             );
           }),
         );
         
       default:
         return fadeTransition;
     }
   } catch (e) {
     LogUtil.logError('构建动画过渡效果时发生错误', e);
     return const SizedBox.shrink();
   }
}

@override
Widget build(BuildContext context) {
   final mediaQuery = MediaQuery.of(context);
   final bool isPortrait = mediaQuery.orientation == Orientation.portrait;

   double progressBarWidth = isPortrait ? mediaQuery.size.width * 0.5 : mediaQuery.size.width * 0.3;

   final EdgeInsets padding = EdgeInsets.only(bottom: isPortrait ? 10.0 : 15.0);
   final TextStyle textStyle = TextStyle(
     color: Colors.white,
     fontSize: isPortrait ? 16 : 18,
   );

   return Selector<ThemeProvider, bool>(
     selector: (_, provider) => provider.isBingBg,
     builder: (BuildContext context, bool isBingBg, Widget? child) {
       final bool shouldShowBingBg = widget.showBingBackground && 
                                   isBingBg && 
                                   _isBingLoaded && 
                                   _bingImgUrls.isNotEmpty;

       if (widget.showBingBackground && 
           isBingBg && 
           !_isBingLoaded && 
           !_isTransitionLocked) {
         _loadBingBackgrounds();
       }

       return Stack(
         children: [
           shouldShowBingBg ? _buildBingBg() : _buildLocalBg(),
           
           // 只在showBingBackground=true时显示音柱
           if (widget.showBingBackground)
             Positioned(
               left: 0,
               right: 0,
               bottom: 0,
               height: MediaQuery.of(context).size.height * 0.3,
               child: DynamicAudioBars(
                 key: _audioBarKey,
                 maxHeightPercentage: 0.6,
                 animationSpeed: const Duration(milliseconds: 100),
                 smoothness: 0.5,
               ),
             ),

           Align(
             alignment: Alignment.bottomCenter,
             child: Padding(
               padding: padding,
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   GradientProgressBar(
                     width: progressBarWidth,
                     height: 5,
                   ),
                   const SizedBox(height: 3),
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
       if (_isAnimating && !_isTransitionLocked)
         _buildAnimatedTransition(),
     ],
   );
}

Widget _buildLocalBg() {
   return Container(
     decoration: const BoxDecoration(
       image: DecorationImage(
         fit: BoxFit.cover,
         image: AssetImage('assets/images/video_bg.png'),
       ),
     ),
   );
}
}

class CircleRevealClipper extends CustomClipper<Path> {
 final double fraction;
 final Alignment centerAlignment;
 
 const CircleRevealClipper({
   required this.fraction,
   required this.centerAlignment,
 });

 @override
 Path getClip(Size size) {
   if (size.isEmpty || fraction.isNaN) {
     return Path();
   }
   
   try {
     final center = centerAlignment.alongSize(size);
     final maxRadius = sqrt(size.width * size.width + size.height * size.height) / 2;
     final radius = (maxRadius * fraction.clamp(0.0, 3.2)).clamp(0.0, maxRadius * 2.2);
     
     return Path()
       ..addOval(Rect.fromCircle(
         center: center,
         radius: radius,
       ));
   } catch (e) {
     LogUtil.logError('创建径向裁剪路径时发生错误', e);
     return Path();
   }
 }

 @override
 bool shouldReclip(CircleRevealClipper oldClipper) =>
   oldClipper.fraction != fraction || oldClipper.centerAlignment != centerAlignment;
}
