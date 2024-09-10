import 'package:flutter/material.dart';
import 'package:itvapp_live_tv/util/m3u_util.dart'; // 修改后的 M3uUtil
import 'package:itvapp_live_tv/entity/playlist_model.dart'; // 导入 PlaylistModel
import 'generated/l10n.dart';
import 'live_home_page.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late Future<M3uResult> _m3uDataFuture; // 用于存储异步获取的 M3U 数据结果
  int _retryCount = 0;  // 重试次数
  String _message = '';  // 用于显示当前的提示信息

  @override
  void initState() {
    super.initState();
    _m3uDataFuture = _fetchDataWithDelay(); // 初始化时调用方法获取数据
  }

  // 定义一个异步方法，用于获取远程数据并确保启动画面至少显示3秒
  Future<M3uResult> _fetchDataWithDelay() async {
    try {
      final results = await Future.wait([
        _fetchWithRetry(), // 带重试的获取 M3U 数据方法
        Future.delayed(Duration(seconds: 3)) // 延时3秒
      ]);
      return results[0] as M3uResult; // 返回 M3uResult 数据
    } catch (e) {
      return M3uResult(errorMessage: '加载数据失败: $e'); // 如果发生错误，返回错误信息
    }
  }

  // 带重试的 M3U 数据获取方法
  Future<M3uResult> _fetchWithRetry() async {
    while (_retryCount < 3) {  // 最多重试三次
      try {
        setState(() {
          _message = '正在获取数据...'; // 显示数据获取提示
        });
        final result = await M3uUtil.getDefaultM3uData();  // 使用远程数据获取方法
        if (result.data != null) {
          return result;  // 直接返回 M3uResult 的 data
        } else {
          setState(() {
            _retryCount++;
            _message = '错误: ${result.errorMessage}\n重试中 ($_retryCount)'; // 显示错误信息
          });
        }
      } catch (e) {
        setState(() {
          _retryCount++;  // 更新重试次数
          _message = '发生错误: $e\n重试中 ($_retryCount)'; // 更新错误信息
        });
      }
    }
    return M3uResult(errorMessage: '获取M3U数据失败，重试3次后仍未成功'); // 重试失败时返回错误信息
  }

  @override
  Widget build(BuildContext context) {
    var orientation = MediaQuery.of(context).orientation;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand, // 使子组件填满 Stack
        children: [
          Image.asset(
            orientation == Orientation.portrait
                ? 'assets/images/launch_image.png' // 纵向模式加载的图片
                : 'assets/images/launch_image_land.png', // 横向模式加载的图片
            fit: BoxFit.cover, // 图片覆盖整个屏幕
          ),
          FutureBuilder<M3uResult>(
            future: _m3uDataFuture, // 传入异步计算的 Future
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                // 显示加载动画和重试次数
                return _buildMessageUI(
                  _retryCount == 0 
                      ? '${S.current.loading} ${S.current.tipChannelList}...'  // 拼接两个本地化字符串
                      : _message, // 根据重试次数动态显示消息
                  isLoading: true,
                );
              } else if (snapshot.hasError || (snapshot.hasData && snapshot.data?.data == null)) {
                return _buildMessageUI(S.current.getDefaultError, showRetryButton: true);
              } else if (snapshot.hasData && snapshot.data?.data != null) {
                return _navigateToHome();
              } else {
                return _buildMessageUI(S.current.getDefaultError, showRetryButton: true);
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
                    _retryCount = 0;  // 重置重试次数
                    _m3uDataFuture = _fetchDataWithDelay(); // 重新发起请求获取数据
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFEB144C), // 按钮背景颜色
                  foregroundColor: Colors.white, // 按钮文字颜色
                  padding: EdgeInsets.symmetric(horizontal: 18.0, vertical: 5.0), // 按钮的内边距
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30.0), // 圆角按钮设计
                  ),
                ),
                child: Text(S.current.refresh, style: TextStyle(fontSize: 18)), // 按钮上的文本
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
