import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/dialog_util.dart';
import 'package:itvapp_live_tv/util/m3u_util.dart';
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/live_home_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late Future<M3uResult> _m3uDataFuture; // 用于存储异步获取的 M3U 数据结果
  M3uResult? result; // 用于捕获异常时访问
  String _message = ''; // 用于显示当前提示信息

  bool isDebugMode = true; // 调试模式开关，false 代表关闭，true 代表开启

  // 缓存资源路径和样式，避免重复创建
  static const String _portraitImage = 'assets/images/launch_image.png';
  static const String _landscapeImage = 'assets/images/launch_image_land.png';
  static const Color _primaryColor = Color(0xFFEB144C);

  // 缓存通用按钮样式（不再使用，但保留定义以保持代码完整性）
  static final ButtonStyle _retryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFFEB144C),
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 5.0),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30.0),
    ),
  );

  @override
  void initState() {
    super.initState();
    _initializeApp(); // 初始化应用并获取播放列表数据
  }

  @override
  void dispose() {
    super.dispose(); // 移除 _retryButtonFocusNode.dispose()，因为不再需要
  }

  // 初始化应用的方法
  Future<void> _initializeApp() async {
    try {
      LogUtil.safeExecute(() async {
        setState(() {
          _m3uDataFuture = _fetchData(); // 开始异步获取 M3U 数据
        });
      }, '初始化应用时发生错误');
    } catch (error, stackTrace) {
      LogUtil.logError('初始化应用时发生错误', error, stackTrace); // 记录错误日志
    }
  }

  // 统一错误处理的数据获取方法
  Future<M3uResult> _fetchData() async {
    try {
      setState(() {
        _message = S.current.getm3udata; // 更新当前操作信息为正在获取
      });

      result = await M3uUtil.getDefaultM3uData(onRetry: (attempt, remaining) { // 修改为接受两个参数
        setState(() {
          _message = '${S.current.getm3udata} (自动重试第 $attempt 次，剩余 $remaining 次)';
        });
        LogUtil.e('获取 M3U 数据失败，自动重试第 $attempt 次，剩余 $remaining 次');
      });

      if (result?.data != null) {
        return result!; // 成功则返回 M3uResult 的数据
      } else {
        setState(() {
          _message = S.current.getm3udataerror; // 自动重试失败后显示错误信息
        });
        return M3uResult(errorMessage: result?.errorMessage);
      }
    } catch (e, stackTrace) {
      setState(() {
        _message = S.current.getm3udataerror; // 更新错误信息
      });
      LogUtil.logError('获取 M3U 数据时发生错误', e, stackTrace); // 记录捕获到的异常日志
      return M3uResult(errorMessage: ': $e');
    }
  }

  // 显示日志的自定义对话框方法
  void _showErrorLogs(BuildContext context) {
    if (isDebugMode) {
      DialogUtil.showCustomDialog(
        context,
        title: S.current.logtitle,
        content: 'showlog', // 显示日志内容
        isCopyButton: true, // 是否显示复制按钮
      );
    }
  }

  // 跳转到主页面的方法
  void _navigateToHome(PlaylistModel data) {
    if (mounted) { // 确保组件仍然插入在构建树中
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => LiveHomePage(m3uData: data), // 创建主页并传递数据
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var orientation = MediaQuery.of(context).orientation; // 获取屏幕方向
    return Scaffold(
      body: Stack(
        fit: StackFit.expand, // 使子组件填满 Stack
        children: [
          Image.asset(
            orientation == Orientation.portrait
                ? _portraitImage // 选择竖屏或横屏的启动图片
                : _landscapeImage,
            fit: BoxFit.cover, // 图片覆盖整个屏幕
          ),
          FutureBuilder<M3uResult>(
            future: _m3uDataFuture, // 传入异步 Future
            builder: (context, snapshot) {
              return _buildFutureBuilderContent(context, snapshot); // 提取逻辑到独立方法
            },
          ),
        ],
      ),
      floatingActionButton: isDebugMode // 判断是否显示调试按钮
          ? FloatingActionButton(
              onPressed: () => _showErrorLogs(context), // 显示日志信息
              child: const Icon(Icons.bug_report), // 使用 const 优化
              backgroundColor: _primaryColor, // 使用缓存的颜色
            )
          : null,
    );
  }

  // 处理 FutureBuilder 中的状态显示逻辑
  Widget _buildFutureBuilderContent(BuildContext context, AsyncSnapshot<M3uResult> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      // 异步操作正在进行中
      return _buildMessageUI(
        _message.isEmpty ? '${S.current.loading}' : _message, // 显示动态消息
        isLoading: true,
      );
    } else if (snapshot.hasError || (snapshot.hasData && snapshot.data?.data == null)) {
      // 加载过程出错或返回数据为空
      LogUtil.e('加载 M3U 数据时发生错误或数据为空'); // 输出错误日志
      return _buildMessageUI(_message); // 显示错误信息
    } else if (snapshot.hasData && snapshot.data?.data != null) {
      // 数据加载成功且不为空
      Future.delayed(Duration(seconds: 1), () async {
        // 延迟执行以展示加载过程
        if (!mounted) return;

        try {
          await CheckVersionUtil.checkVersion(
            context,
            false, // 是否弹窗显示
            false, // 是否强制更新
            false // 是否可取消
          );

          if (mounted) {
            await Future.delayed(Duration(seconds: 2)); // 添加额外延迟
            _navigateToHome(snapshot.data!.data!); // 跳转到主页面
          }
        } catch (e, stackTrace) {
          LogUtil.logError('版本检测时发生错误', e, stackTrace); // 记录版本检测错误日志
          if (mounted) {
            _navigateToHome(snapshot.data!.data!); // 无论版本检测成败都跳转
          }
        }
      });

      return _buildMessageUI(
        '${S.current.loading}...', // 显示加载完成信息
        isLoading: true,
      );
    } else {
      // 其他不可预期情况下的处理
      return _buildMessageUI(S.current.getDefaultError);
    }
  }

  // 构建加载动画和提示 UI 的方法
  Widget _buildMessageUI(String message, {bool isLoading = false}) { // 移除 showRetryButton 参数
    // 用于显示加载过程或错误提示界面
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).orientation == Orientation.portrait ? 88.0 : 58.0
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // 使列最小化
          children: [
            if (isLoading) ...[
              // 如果正在加载则显示进度指示器
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primaryColor), // 设置进度条颜色
                strokeWidth: 4.0,
              ),
              const SizedBox(height: 18),
            ],
            Text(
              message, // 显示传入的信息
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
              ),
              textAlign: TextAlign.center, // 设置文本居中
            ),
          ],
        ),
      ),
    );
  }
}
