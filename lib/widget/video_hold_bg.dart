import 'package:itvapp_live_tv/util/bing_util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../generated/l10n.dart';
import '../provider/theme_provider.dart';
import '../gradient_progress_bar.dart'; // 引入渐变进度条

class VideoHoldBg extends StatelessWidget {
  // 可选的 toastString，用于显示提示文本
  final String? toastString;

  // 构造函数，初始化 toastString
  const VideoHoldBg({Key? key, required this.toastString}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 获取当前屏幕的尺寸和方向
    final mediaQuery = MediaQuery.of(context);
    final bool isPortrait = mediaQuery.orientation == Orientation.portrait;

    // 根据屏幕方向设置进度条的宽度
    double progressBarWidth = isPortrait ? mediaQuery.size.width * 0.6 : mediaQuery.size.width * 0.4;

    return Selector<ThemeProvider, bool>(
      // 通过 Selector 获取 ThemeProvider 中的 isBingBg 属性，决定是否使用 Bing 背景
      selector: (_, provider) => provider.isBingBg,
      builder: (BuildContext context, bool isBingBg, Widget? child) {
        return Stack(
          children: [
            // 背景图片处理，根据横屏或竖屏调整fit属性
            isBingBg ? _buildBingBg(isPortrait) : _buildLocalBg(isPortrait),
            // 进度条和提示文字布局
            Positioned(
              bottom: 18, // 进度条距离底部18像素
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min, // 仅占用必要的空间
                children: [
                  // 自定义的渐变进度条
                  GradientProgressBar(
                    width: progressBarWidth, // 动态调整进度条宽度
                    height: 5, // 进度条高度固定为5
                  ),
                  const SizedBox(height: 12), // 进度条与文字之间的间隔
                  // 提示文本
                  FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Text(
                        toastString ?? S.current.loading, // 如果没有传入 toastString，显示默认的“加载中”
                        style: const TextStyle(color: Colors.white, fontSize: 16), // 白色文字，字体大小16
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // 使用 Bing 背景图，动态调整fit属性
  Widget _buildBingBg(bool isPortrait) {
    return FutureBuilder<String?>(
      future: BingUtil.getBingImgUrl(),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        late ImageProvider image;
        if (snapshot.hasData && snapshot.data != null) {
          image = NetworkImage(snapshot.data!);
        } else {
          image = const AssetImage('assets/images/video_bg.png');
        }
        return _buildBackground(image, isPortrait);
      },
    );
  }

  // 使用本地背景图，动态调整fit属性
  Widget _buildLocalBg(bool isPortrait) {
    return _buildBackground(const AssetImage('assets/images/video_bg.png'), isPortrait);
  }

  // 构建背景的通用方法，根据屏幕方向调整fit属性
  Widget _buildBackground(ImageProvider image, bool isPortrait) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: isPortrait ? BoxFit.cover : BoxFit.contain, // 竖屏时填充，横屏时保持比例
          image: image,
        ),
      ),
      width: double.infinity, // 背景填满屏幕
      height: double.infinity,
    );
  }
}
