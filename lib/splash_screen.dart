import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; 
import 'package:itvapp_live_tv/provider/theme_provider.dart'; 
import 'package:itvapp_live_tv/util/log_util.dart'; 
import 'package:itvapp_live_tv/util/m3u_util.dart'; 
import 'package:itvapp_live_tv/entity/playlist_model.dart';
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
    _initializeApp(); // 在初始化时调用设备检查和数据获取方法
  }

  // 初始化应用，包括获取设备类型和数据
  Future<void> _initializeApp() async {
    try {
      LogUtil.safeExecute(() async {
        // 获取设备类型并存储到 Provider 中
        await Provider.of<ThemeProvider>(context, listen: false).checkAndSetIsTV();
        LogUtil.i('设备类型检查成功并已存储');

        // 然后获取 M3U 数据
        _m3uDataFuture = _fetchData();
      }, '获取设备类型时发生错误');
    } catch (error, stackTrace) {
      LogUtil.logError('初始化应用时发生错误', error, stackTrace);  // 记录错误日志
    }
  }

  // 统一错误处理的获取数据方法
  Future<M3uResult> _fetchData() async {
    try {
      LogUtil.safeExecute(() {
        setState(() {
          _message = '正在获取数据...'; // 显示数据获取提示
        });
      }, '获取 M3U 数据时发生错误');

      final result = await M3uUtil.getDefaultM3uData(onRetry: (attempt) {
        setState(() {
          _retryCount = attempt;
          _message = '错误: 获取失败\n重试中 ($_retryCount 次)'; // 更新重试次数提示信息
        });
        LogUtil.e('获取 M3U 数据失败，重试中 ($attempt 次)'); // 添加重试日志
      });

      if (result.data != null) {
        LogUtil.i('M3U 数据获取成功');
        return result;  // 直接返回 M3uResult 的 data
      } else {
        setState(() {
          _retryCount++;
          _message = '错误: ${result.errorMessage}\n重试中 ($_retryCount 次)'; // 显示错误信息
        });
        LogUtil.e('M3U 数据获取失败: ${result.errorMessage}'); // 添加错误日志
        return M3uResult(errorMessage: result.errorMessage);  // 返回带错误信息的 M3uResult
      }
    } catch (e, stackTrace) {
      setState(() {
        _retryCount++;  // 更新重试次数
        _message = '发生错误: $e\n重试中 ($_retryCount 次)'; // 更新错误信息
      });
      LogUtil.logError('获取 M3U 数据时发生错误', e, stackTrace); // 记录捕获到的异常
      return M3uResult(errorMessage: '发生错误: $e');
    }
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
                LogUtil.e('加载 M3U 数据时发生错误或数据为空'); // 添加错误日志
                // 如果加载失败，显示错误信息和刷新按钮
                return _buildMessageUI(S.current.getDefaultError, showRetryButton: true);
              } else if (snapshot.hasData && snapshot.data?.data != null) {
                // 如果加载成功，延迟 3 秒后导航到主页面，并传递获取到的数据
                Future.delayed(Duration(seconds: 3), () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => LiveHomePage(m3uData: snapshot.data!), // 传递 M3U 数据
                    ),
                  );
                });
                // 保持加载动画显示，直到页面跳转
                return _buildMessageUI(
                  '${S.current.loading} ${S.current.tipChannelList}...',
                  isLoading: true,
                );
              } else {
                // 处理其他情况，默认显示错误信息和刷新按钮
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
        padding: const EdgeInsets.only(bottom: 108.0), // 底部的内边距
        child: Column(
          mainAxisSize: MainAxisSize.min, // 列表仅占用其子组件的最小空间
          children: [
            if (isLoading)
              CircularProgressIndicator( // 如果是加载状态，显示加载动画
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEB144C)), // 加载动画颜色
                strokeWidth: 4.0, // 加载动画的粗细
              ),
            if (isLoading) const SizedBox(height: 16), // 加载动画与提示文字之间的间距
            Text(
              message, // 提示信息文本
              style: const TextStyle(
                fontSize: 16, // 字体大小
                color: Colors.white, // 文本颜色，确保在背景图片上清晰可见
              ),
              textAlign: TextAlign.center, // 提示文字居中对齐
            ),
            if (showRetryButton) ...[
              const SizedBox(height: 16), // 提示文字与重试按钮之间的间距
              ElevatedButton(
                onPressed: () {
                  LogUtil.safeExecute(() {
                    setState(() {
                      _retryCount = 0;  // 重置重试次数
                      _m3uDataFuture = _fetchData(); // 重新发起请求获取数据
                      LogUtil.i('重新尝试获取 M3U 数据');
                    });
                  }, '重试获取 M3U 数据时发生错误');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEB144C), // 按钮背景颜色
                  foregroundColor: Colors.white, // 按钮文字颜色
                  padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 5.0), // 按钮的内边距
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30.0), // 圆角按钮设计
                  ),
                ),
                child: Text(S.current.refresh, style: const TextStyle(fontSize: 18)), // 按钮上的文本
              ),
            ],
          ],
        ),
      ),
    );
  }
}
