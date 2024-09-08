import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../generated/l10n.dart';
import '../provider/theme_provider.dart';
import '../gradient_progress_bar.dart'; // 引入自定义的渐变进度条

class VideoHoldBg extends StatelessWidget {
  // 可选的 toastString，用于显示提示文本
  final String? toastString;

  // 构造函数，初始化 toastString
  const VideoHoldBg({Key? key, required this.toastString}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 获取屏幕的尺寸和方向
    final mediaQuery = MediaQuery.of(context);
    final bool isPortrait = mediaQuery.orientation == Orientation.portrait;

    // 根据屏幕方向设置进度条的宽度
    double progressBarWidth = isPortrait ? mediaQuery.size.width * 0.6 : mediaQuery.size.width * 0.4;

    return Selector<ThemeProvider, bool>(
      // 通过 Selector 获取 ThemeProvider 中的 isBingBg 属性，决定是否使用 Bing 背景
      selector: (_, provider) => provider.isBingBg,
      builder: (BuildContext context, bool isBingBg, Widget? child) {
        // 根据 isBingBg 的状态显示不同的背景图片
        if (isBingBg) {
          return FutureBuilder(
            future: BingUtil.getBingImgUrl(), // 异步获取 Bing 图片 URL
            builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
              late ImageProvider image;
              // 如果成功获取到 Bing 图片 URL，使用网络图片作为背景
              if (snapshot.hasData && snapshot.data != null) {
                image = NetworkImage(snapshot.data!);
              } else {
                // 否则使用本地默认背景图片
                image = const AssetImage('assets/images/video_bg.png');
              }
              return Container(
                padding: const EdgeInsets.only(top: 30, bottom: 30),
                decoration: BoxDecoration(
                  image: DecorationImage(
                    fit: BoxFit.cover,
                    image: image, // 设置背景图片
                  ),
                ),
                child: child, // 显示子组件
              );
            },
          );
        }

        // 如果不使用 Bing 背景，显示本地图片背景
        return Container(
          padding: const EdgeInsets.only(top: 30, bottom: 30),
          decoration: const BoxDecoration(
            image: DecorationImage(
              fit: BoxFit.cover,
              image: AssetImage('assets/images/video_bg.png'), // 本地背景图片
            ),
          ),
          child: child, // 显示子组件
        );
      },
      // 定义进度条和提示文本的布局
      child: Column(
        mainAxisSize: MainAxisSize.min, // 组件占最小高度
        children: [
          // FittedBox 用于自适应显示 toastString 文本内容
          FittedBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                toastString ?? S.current.loading, // 如果没有传入 toastString，显示默认的“加载中”
                style: const TextStyle(color: Colors.white, fontSize: 16), // 白色文字，字体大小 16
              ),
            ),
          ),
          const SizedBox(height: 15), // 文本与进度条之间的间距
          // 显示自定义的渐变进度条
          GradientProgressBar(
            width: progressBarWidth, // 动态调整进度条宽度
            height: 5, // 进度条高度固定为 5
          ),
        ],
      ),
    );
  }
}
