import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart'; // 引入视频播放器
import 'dart:async'; // 定时器需要的包
import '../generated/l10n.dart';
import '../provider/theme_provider.dart';
import '../gradient_progress_bar.dart'; // 引入渐变进度条

class VideoHoldBg extends StatelessWidget {
  final String? toastString;

  const VideoHoldBg({Key? key, required this.toastString}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度
    final double screenWidth = MediaQuery.of(context).size.width;
    // 设置进度条宽度为屏幕宽度的60%，可以根据需要调整比例
    final double progressBarWidth = screenWidth * 0.6;

    return Container(
      padding: const EdgeInsets.only(top: 30, bottom: 30),
      decoration: const BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          image: AssetImage('assets/images/video_bg.png'),
        ),
      ),
      child: Stack(
        children: [
          // 定义 Stack，使用 Positioned 控制距离底部的距离
          Positioned(
            bottom: 12, // 距离底部12像素
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min, // 控制列大小最小化
              mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
              crossAxisAlignment: CrossAxisAlignment.center, // 水平居中
              children: [
                GradientProgressBar(
                  width: progressBarWidth, // 动态设置进度条宽度
                  height: 5,  // 设置进度条高度为固定值
                  duration: const Duration(seconds: 3), // 动画持续时间
                ),
                const SizedBox(height: 8), // 设置进度条和文字之间的距离为8像素
                FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      toastString ?? S.current.loading,
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
  }
}
