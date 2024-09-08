import 'package:flutter/material.dart'; // 导入 Flutter 的核心组件库
import 'package:itvapp_live_tv/util/m3u_util.dart'; // 导入自定义的 M3U 工具类，用于处理 M3U 数据
import 'generated/l10n.dart'; // 导入国际化资源类，用于多语言支持
import 'live_home_page.dart'; // 导入主界面页面

// 定义启动画面类，它是一个有状态的组件
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

// 定义启动画面的状态类
class _SplashScreenState extends State<SplashScreen> {
  late Future<Map<String, dynamic>> _m3uDataFuture; // 用于存储异步获取的 M3U 数据

  @override
  void initState() {
    super.initState();
    _m3uDataFuture = _fetchDataWithDelay(); // 初始化时调用方法获取数据
  }

  // 定义一个异步方法，用于获取远程数据并确保启动画面至少显示3秒
  Future<Map<String, dynamic>> _fetchDataWithDelay() async {
    try {
      // 使用 Future.wait 来并行等待 M3U 数据的获取和延时3秒的完成
      final results = await Future.wait([
        M3uUtil.getDefaultM3uData(), // 获取默认的 M3U 数据
        Future.delayed(Duration(seconds: 3)) // 延时3秒
      ]);
      return results[0] as Map<String, dynamic>; // 返回 M3U 数据
    } catch (e) {
      // 如果发生错误，返回一个空的 Map 以避免错误
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取当前设备的屏幕方向（横向或纵向）
    var orientation = MediaQuery.of(context).orientation;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand, // 使子组件填满 Stack
        children: [
          // 根据屏幕方向加载相应的启动图片
          Image.asset(
            orientation == Orientation.portrait
                ? 'assets/images/launch_image.png' // 纵向模式加载的图片
                : 'assets/images/launch_image_land.png', // 横向模式加载的图片
            fit: BoxFit.cover, // 图片覆盖整个屏幕
          ),
          FutureBuilder<Map<String, dynamic>>(
            future: _m3uDataFuture, // 传入异步计算的 Future
            builder: (context, snapshot) {
              // 根据异步计算的状态来决定显示的内容
              if (snapshot.connectionState == ConnectionState.waiting) {
                // 如果正在等待数据，显示加载动画和提示文字
                return _buildMessageUI(S.current.loadingData, isLoading: true);
              } else if (snapshot.hasError || (snapshot.hasData && snapshot.data!.isEmpty)) {
                // 如果数据加载失败或数据为空，显示错误提示和重试按钮
                return _buildMessageUI(S.current.errorLoadingData, showRetryButton: true);
              } else if (snapshot.hasData) {
                // 如果数据加载成功，导航到主界面
                return _navigateToHome();
              } else {
                // 默认情况：显示错误提示和重试按钮
                return _buildMessageUI(S.current.errorLoadingData, showRetryButton: true);
              }
            },
          ),
        ],
      ),
    );
  }

  // 构建加载动画和提示 UI 的方法
  Widget _buildMessageUI(String message, {bool isLoading = false, bool showRetryButton = false}) {
    return Align(
      alignment: Alignment.bottomCenter, // UI 内容在屏幕底部对齐
      child: Padding(
        padding: const EdgeInsets.only(bottom: 98.0), // 底部的内边距
        child: Column(
          mainAxisSize: MainAxisSize.min, // 列表仅占用其子组件的最小空间
          children: [
            if (isLoading)
              CircularProgressIndicator( // 如果是加载状态，显示加载动画
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEB144C)), // 加载动画颜色
                strokeWidth: 4.0, // 加载动画的粗细
              ),
            if (isLoading) SizedBox(height: 16), // 加载动画与提示文字之间的间距
            Text(
              message, // 提示信息文本
              style: TextStyle(
                fontSize: 16, // 字体大小
                color: Colors.white, // 文本颜色，确保在背景图片上清晰可见
              ),
              textAlign: TextAlign.center, // 提示文字居中对齐
            ),
            if (showRetryButton) ...[
              SizedBox(height: 16), // 提示文字与重试按钮之间的间距
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _m3uDataFuture = _fetchDataWithDelay(); // 重新发起请求获取数据
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFEB144C), // 按钮背景颜色
                  foregroundColor: Colors.white, // 按钮文字颜色
                  padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0), // 按钮的内边距
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30.0), // 圆角按钮设计
                  ),
                ),
                child: Text(S.current.retry, style: TextStyle(fontSize: 18)), // 按钮上的文本
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 导航到主界面的方法
  Widget _navigateToHome() {
    // 使用 WidgetsBinding.instance.addPostFrameCallback 确保在构建完成后进行导航
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const LiveHomePage(), // 创建主界面的路由
        ),
      );
    });
    return Container(); // 在导航过程中显示一个空的容器
  }
}
