import 'package:flutter/material.dart';

/// 可滚动的Toast消息组件
/// 当消息文本超出容器宽度时自动启用滚动动画
class ScrollingToastMessage extends StatefulWidget {
 final String message; // 滚动提示消息内容
 final double containerWidth; // 外部容器的宽度，用于计算文字是否需要滚动
 final bool isLandscape; // 是否为横屏模式，用于调整文字样式
 final Duration animationDuration; // 滚动动画持续时间
 final Curve animationCurve; // 滚动动画曲线效果

 const ScrollingToastMessage({
   Key? key,
   required this.message,
   required this.containerWidth,
   this.isLandscape = true,
   this.animationDuration = const Duration(seconds: 10),
   this.animationCurve = Curves.linear,
 }) : super(key: key);

 @override
 State<ScrollingToastMessage> createState() => _ScrollingToastMessageState();
}

class _ScrollingToastMessageState extends State<ScrollingToastMessage> with SingleTickerProviderStateMixin {
 late final AnimationController _textAnimationController; // 动画控制器，控制文字滚动动画
 late final Animation<Offset> _textAnimation; // 偏移动画，用于实现文字的滚动效果
 late double _textWidth; // 文本内容的宽度，用于判断是否需要滚动
 bool _needsScroll = false; // 标记文字是否需要滚动

 // 根据屏幕方向动态调整文字样式
 TextStyle get _textStyle => TextStyle(
       color: Colors.white, // 设置文字颜色为白色
       fontSize: widget.isLandscape ? 18.0 : 16.0, // 根据横屏或竖屏调整字体大小
       shadows: [
         Shadow(
           offset: const Offset(1.0, 1.0),
           blurRadius: 3.0,
           color: Colors.black.withOpacity(0.7),
         ),
         Shadow(
           offset: const Offset(-1.0, -1.0), 
           blurRadius: 3.0,
           color: Colors.black.withOpacity(0.7),
         ),
       ],
     );

 @override
 void initState() {
   super.initState();
   _measureText(); // 测量文本宽度，确定是否需要滚动
   _setupTextAnimation(); // 初始化滚动动画
 }

 // 测量文字宽度，判断是否超出容器宽度
 void _measureText() {
   final textSpan = TextSpan(text: widget.message, style: _textStyle); // 创建文本样式对象
   final textPainter = TextPainter(
     text: textSpan,
     textDirection: TextDirection.ltr, // 设置文字绘制方向为从左到右
   );
   textPainter.layout(minWidth: 0, maxWidth: double.infinity); // 计算文字的宽度
   _textWidth = textPainter.width; // 获取文字宽度
   _needsScroll = _textWidth > widget.containerWidth; // 判断文字是否需要滚动
 }

 // 初始化滚动动画
 void _setupTextAnimation() {
   _textAnimationController = AnimationController(
     duration: widget.animationDuration, // 动画时长
     vsync: this, // 提供 TickerProvider
   );

   _textAnimation = Tween<Offset>(
     begin: const Offset(-1.0, 0.0), // 结束位置为容器左侧
     end: const Offset(1.0, 0.0), // 起始位置为容器右侧
   ).animate(CurvedAnimation(
     parent: _textAnimationController, // 动画控制器
     curve: widget.animationCurve, // 动画曲线
   ));

   if (_needsScroll) {
     // 如果文字需要滚动，设置监听器并启动动画
     _textAnimationController.addStatusListener(_onAnimationStatus);
     _textAnimationController.forward(); // 启动动画
   }
 }

 // 监听动画状态，当动画完成时重启动画
 void _onAnimationStatus(AnimationStatus status) {
   if (status == AnimationStatus.completed) {
     _textAnimationController.reset(); // 重置动画
     _textAnimationController.forward(); // 重新启动动画
   }
 }

 @override
 void dispose() {
   _textAnimationController.dispose(); // 释放动画控制器资源
   super.dispose();
 }

 @override
 Widget build(BuildContext context) {
   if (!_needsScroll) {
     // 如果文字宽度小于容器宽度，直接显示文字居中对齐 
     return Text(
       widget.message,
       style: _textStyle, // 应用文字样式
       textAlign: TextAlign.center, // 居中显示文字
     );
   }

   // 如果文字需要滚动，使用 SlideTransition 实现滚动效果
   return RepaintBoundary(
     child: SlideTransition(
       position: _textAnimation, // 应用滚动动画
       child: Text(
         widget.message,
         style: _textStyle, // 应用文字样式
       ),
     ),
   );
 }
}
