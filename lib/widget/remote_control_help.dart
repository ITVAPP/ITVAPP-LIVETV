import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RemoteControlHelp extends StatelessWidget {
  const RemoteControlHelp({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const RemoteControlHelp(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent) {
          Navigator.of(context).pop();
        }
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Stack(
            children: [
              const RemoteControlContent(),
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Text(
                  '点击任意按键关闭使用帮助 (18)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 16,
                    height: 1.6,
                    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RemoteControlContent extends StatelessWidget {
 const RemoteControlContent({Key? key}) : super(key: key);

 @override
 Widget build(BuildContext context) {
   return Center(
     child: LayoutBuilder(
       builder: (context, constraints) {
         final designWidth = 1920.0;
         final designHeight = 1080.0;
         final scaleX = constraints.maxWidth / designWidth;
         final scaleY = constraints.maxHeight / designHeight;
         final scale = scaleX < scaleY ? scaleX : scaleY;
         
         return Transform.scale(
           scale: scale,
           alignment: Alignment.center,
           transformHitTests: true,
           child: SizedBox(
             width: designWidth,
             height: designHeight * 0.6,
             child: const ContentContainer(),
           ),
         );
       },
     ),
   );
 }
}

class ContentContainer extends StatelessWidget {
 const ContentContainer({Key? key}) : super(key: key);

 @override
 Widget build(BuildContext context) {
   return SizedBox(
     width: 1920,
     height: 500,
     child: Stack(
       alignment: Alignment.center,
       children: [
         Positioned.fill(
           child: _buildRemoteControl(),
         ),
         ..._buildConnectionLines(),
         ..._buildDots(),
         ..._buildLabels(),
       ],
     ),
   );
 }
 
 Widget _buildRemoteControl() {
   return Center(
     child: Container(
       width: 380,
       height: 520,
       transform: Matrix4.translationValues(0, -166, 0), // 520 * 0.32 ≈ 166
       decoration: BoxDecoration(
         border: Border(
           top: BorderSide(color: Colors.white.withOpacity(0.5), width: 3),
           left: BorderSide(color: Colors.white.withOpacity(0.5), width: 3),
           right: BorderSide(color: Colors.white.withOpacity(0.5), width: 3),
         ),
         borderRadius: const BorderRadius.only(
           topLeft: Radius.circular(30),
           topRight: Radius.circular(30),
         ),
         gradient: LinearGradient(
           begin: Alignment.topCenter,
           end: Alignment.bottomCenter,
           stops: const [0.0, 0.5, 1.0],
           colors: [
             const Color(0xFF444444).withOpacity(0.5),
             const Color(0xFF444444).withOpacity(0.3),
             const Color(0xFF444444).withOpacity(0.1),
           ],
         ),
       ),
       child: Stack(
         alignment: Alignment.center,
         children: [
           Positioned(
             top: -30,
             child: _buildDirectionPad(),
           ),
           Positioned(
             top: 280,
             left: 380 * 0.78,
             child: _buildReturnButton(),
           ),
         ],
       ),
     ),
   );
 }

 Widget _buildDirectionPad() {
   return Container(
     width: 280,
     height: 280,
     decoration: BoxDecoration(
       shape: BoxShape.circle,
       color: const Color(0xFF444444).withOpacity(0.5),
       border: Border.all(
         color: Colors.white.withOpacity(0.5),
         width: 3,
       ),
     ),
     child: Stack(
       alignment: Alignment.center,
       fit: StackFit.expand,
       children: [
         Center(child: _buildArrow('up')),
         Align(alignment: Alignment.centerRight, child: _buildArrow('right')),
         Center(child: _buildArrow('down')),
         Align(alignment: Alignment.centerLeft, child: _buildArrow('left')),
         _buildCenterCircle(),
       ],
     ),
   );
 }
 
 Widget _buildArrow(String direction) {
   return Positioned(
     top: direction == 'up' ? -(280 * 0.03) : null,
     right: direction == 'right' ? -(280 * 0.03) : null,
     bottom: direction == 'down' ? -(280 * 0.03) : null,
     left: direction == 'left' ? -(280 * 0.03) : null,
     child: CustomPaint(
       size: const Size(56, 56),
       painter: ArrowPainter(
         direction: direction,
         color: Colors.white.withOpacity(0.8),
       ),
     ),
   );
 }

 Widget _buildCenterCircle() {
   return Center(
     child: Container(
       width: 120,
       height: 120,
       decoration: BoxDecoration(
         shape: BoxShape.circle,
         color: const Color(0xFF333333).withOpacity(0.7),
         border: Border.all(
           color: Colors.white.withOpacity(0.5),
           width: 3,
         ),
       ),
     ),
   );
 }

 Widget _buildReturnButton() {
   return Container(
     width: 50,
     height: 50,
     decoration: BoxDecoration(
       shape: BoxShape.circle,
       border: Border.all(
         color: Colors.white.withOpacity(0.8),
         width: 3,
       ),
     ),
     child: Center(
       child: Container(
         width: 20,
         height: 20,
         decoration: BoxDecoration(
           border: Border(
             left: BorderSide(color: Colors.white.withOpacity(0.8), width: 5),
             bottom: BorderSide(color: Colors.white.withOpacity(0.8), width: 5),
           ),
         ),
         transform: Matrix4.rotationZ(45 * 3.14159 / 180),
       ),
     ),
   );
 }
 
 List<Widget> _buildConnectionLines() {
   final leftLines = [
     {'top': -50.0, 'width': 250.0, 'marginLeft': -270.0},
     {'top': 50.0, 'width': 150.0, 'marginLeft': -270.0},
     {'top': 170.0, 'width': 245.0, 'marginLeft': -270.0},
   ];
   final rightLines = [
     {'top': 10.0, 'width': 225.0, 'marginLeft': 60.0},
     {'top': 85.0, 'width': 180.0, 'marginLeft': 110.0},
     {'top': 238.0, 'width': 175.0, 'marginLeft': 110.0},
   ];

   final lines = <Widget>[];
   // Add left and right lines
   [...leftLines, ...rightLines].forEach((line) {
     lines.add(
       Positioned(
         top: line['top'],
         left: 960 + (line['marginLeft'] as double),
         child: Container(
           width: line['width'] as double,
           height: 3,
           color: Colors.white.withOpacity(0.3),
         ),
       ),
     );
   });

   return lines;
 }

 List<Widget> _buildDots() {
   final leftDots = [
     {'top': -52.0, 'marginLeft': -275.0},
     {'top': 48.0, 'marginLeft': -275.0},
     {'top': 168.0, 'marginLeft': -275.0},
   ];
   final rightDots = [
     {'top': 8.0, 'marginLeft': 282.0},
     {'top': 83.0, 'marginLeft': 282.0},
     {'top': 235.0, 'marginLeft': 282.0},
   ];

   final dots = <Widget>[];
   [...leftDots, ...rightDots].forEach((dot) {
     dots.add(
       Positioned(
         top: dot['top'],
         left: 960 + (dot['marginLeft'] as double),
         child: Transform.rotate(
           angle: 45 * 3.14159 / 180,
           child: Container(
             width: 8,
             height: 8,
             color: Colors.white.withOpacity(0.8),
           ),
         ),
       ),
     );
   });

   return dots;
 }
 
 List<Widget> _buildLabels() {
   final leftLabels = [
     {'text': '「点击上键」打开 线路切换菜单', 'top': -75.0},
     {'text': '「点击左键」添加/取消 频道收藏', 'top': 25.0},
     {'text': '「点击下键」打开 应用设置界面', 'top': 148.0},
   ];

   final rightLabels = [
     {'text': '「点击确认键」确认选择操作\n显示时间/暂停/播放', 'top': -50.0},
     {'text': '「点击右键」打开 频道选择抽屉', 'top': 65.0}, 
     {'text': '「点击返回键」退出/取消操作', 'top': 215.0},
   ];

   final labels = <Widget>[];
   
   // Add left labels
   leftLabels.forEach((label) {
     labels.add(
       Positioned(
         top: label['top'] as double,
         left: 960 - 695,
         child: SizedBox(
           width: double.infinity,
           constraints: const BoxConstraints(maxWidth: 400),
           child: Text(
             label['text'] as String,
             style: const TextStyle(
               color: Colors.white,
               fontSize: 28,
               height: 1.6,
             ),
             textAlign: TextAlign.right,
           ),
         ),
       ),
     );
   });

   // Add right labels
   rightLabels.forEach((label) {
     labels.add(
       Positioned(
         top: label['top'] as double,
         left: 960 + 285,
         child: SizedBox(
           width: double.infinity,
           constraints: const BoxConstraints(maxWidth: 400),
           child: Text(
             label['text'] as String,
             style: const TextStyle(
               color: Colors.white,
               fontSize: 28,
               height: 1.6,
             ),
             textAlign: TextAlign.left,
           ),
         ),
       ),
     );
   });

   return labels;
 }
}

class ArrowPainter extends CustomPainter {
 final String direction;
 final Color color;
 
 ArrowPainter({
   required this.direction,
   required this.color,
 });
 
 @override
 void paint(Canvas canvas, Size size) {
   final paint = Paint()
     ..color = color
     ..style = PaintingStyle.fill;

   final path = Path();
   
   switch(direction) {
     case 'up':
       path
         ..moveTo(size.width/2, 0)
         ..lineTo(size.width, size.height)
         ..lineTo(0, size.height)
         ..close();
       break;
     case 'right':
       path
         ..moveTo(0, 0)
         ..lineTo(size.width, size.height/2)
         ..lineTo(0, size.height)
         ..close();
       break;
     case 'down':
       path
         ..moveTo(0, 0)
         ..lineTo(size.width, 0)
         ..lineTo(size.width/2, size.height)
         ..close();
       break;
     case 'left':
       path
         ..moveTo(size.width, 0)
         ..lineTo(size.width, size.height)
         ..lineTo(0, size.height/2)
         ..close();
       break;
   }
   
   canvas.drawPath(path, paint);
 }
 
 @override
 bool shouldRepaint(ArrowPainter oldDelegate) {
   return color != oldDelegate.color || direction != oldDelegate.direction;
 }
}
