import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 检测当前设备方向：横屏或竖屏
    var isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: Text('蓝牙语音遥控器 - 使用帮助'),
      ),
      body: Container(
        // 设置线性渐变背景
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1C1C1E), // 深灰色
              Color(0xFF4A4A4A), // 浅灰色
            ],
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: isLandscape
            ? Row(
                children: [
                  buildRemoteControl(), // 横屏时，遥控器和文本左右排列
                  SizedBox(width: 20),
                  Expanded(flex: 2, child: buildTextSection()),
                ],
              )
            : Column(
                children: [
                  buildRemoteControl(), // 竖屏时，遥控器和文本上下排列
                  SizedBox(height: 20),
                  Expanded(child: buildTextSection()),
                ],
              ),
      ),
    );
  }

  // 遥控器布局
  Widget buildRemoteControl() {
    return Expanded(
      flex: 1,
      child: Center(
        child: Container(
          width: 100, // 遥控器的宽度
          height: 420, // 遥控器的高度
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8), // 遥控器背景颜色
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              // 电源按钮
              Positioned(
                top: 20,
                left: 32,
                child: CircleAvatar(
                  radius: 18, // 按钮大小
                  backgroundColor: Colors.white,
                  child: Icon(Icons.power_settings_new, size: 20, color: Colors.black),
                ),
              ),
              // 语音按钮
              Positioned(
                top: 80,
                left: 32,
                child: CircleAvatar(
                  radius: 18, // 按钮大小
                  backgroundColor: Colors.white,
                  child: Icon(Icons.mic, size: 20, color: Colors.black),
                ),
              ),
              // 方向按钮（上下左右）
              Positioned(
                top: 140,
                left: 20,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: 5,
                        child: Icon(Icons.arrow_drop_up, size: 28, color: Colors.black),
                      ),
                      Positioned(
                        bottom: 5,
                        child: Icon(Icons.arrow_drop_down, size: 28, color: Colors.black),
                      ),
                      Positioned(
                        left: 5,
                        child: Icon(Icons.arrow_left, size: 28, color: Colors.black),
                      ),
                      Positioned(
                        right: 5,
                        child: Icon(Icons.arrow_right, size: 28, color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ),
              // 确定按钮
              Positioned(
                top: 180,
                left: 40,
                child: CircleAvatar(
                  radius: 22, // 调整“确定”按钮大小
                  backgroundColor: Colors.white,
                  child: Icon(Icons.check, size: 20, color: Colors.black), // 使用符号替代文字
                ),
              ),
              // 返回按钮
              Positioned(
                top: 250,
                left: 10,
                child: CircleAvatar(
                  radius: 18, // 调整按钮大小
                  backgroundColor: Colors.white,
                  child: Icon(Icons.arrow_back, size: 18, color: Colors.black),
                ),
              ),
              // 菜单按钮
              Positioned(
                top: 250,
                left: 40,
                child: CircleAvatar(
                  radius: 18, // 按钮大小
                  backgroundColor: Colors.white,
                  child: Icon(Icons.menu, size: 18, color: Colors.black),
                ),
              ),
              // 主页按钮
              Positioned(
                top: 250,
                left: 70,
                child: CircleAvatar(
                  radius: 18, // 按钮大小
                  backgroundColor: Colors.white,
                  child: Icon(Icons.home, size: 18, color: Colors.black),
                ),
              ),
              // 音量加减
              Positioned(
                top: 320,
                left: 42,
                child: Column(
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 24), // 增加图标
                    Container(
                      width: 2,
                      height: 60,
                      color: Colors.grey,
                    ),
                    Icon(Icons.remove, color: Colors.white, size: 24), // 减少图标
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 文本部分
  Widget buildTextSection() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '蓝牙语音遥控器',
            style: TextStyle(
              fontSize: 26, // 标题字体大小
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 20),
          buildTextDetail('电源: ',
              '关机状态/息屏状态: 短按开启电视。\n开机状态: 短按息屏或关机; 长按进入关机菜单(关机菜单里可选择息屏、关机、重启、延时关机)。'),
          buildTextDetail('语音: ', '按住可语音搜索。'),
          buildTextDetail('确定: ', '确认选择当前焦点，在视频播放界面可暂停/播放当前视频。'),
          buildTextDetail('方向: ', '控制焦点上下左右移动。在视频播放界面中，左右键为快进和快退功能。'),
          buildTextDetail('主页: ', '短按可快速回到桌面，双击可调出最近使用过的应用记录。'),
          buildTextDetail('返回: ', '回到上一级。'),
          buildTextDetail(
              '菜单: ', '短按显示当前界面的更多功能。\n例如：播放界面中显示相关视频设置，列表界面中显示更多分类条件等。'),
        ],
      ),
    );
  }

  // 构建文本细节
  Widget buildTextDetail(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: RichText(
        text: TextSpan(
          text: title,
          style: TextStyle(
            fontSize: 18,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          children: [
            TextSpan(
              text: description,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
