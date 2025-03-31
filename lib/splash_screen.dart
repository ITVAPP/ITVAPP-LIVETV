import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/dialog_util.dart';
import 'package:itvapp_live_tv/util/m3u_util.dart';
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/util/location_service.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/live_home_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  M3uResult? result; // 用于捕获异常时访问
  String _message = ''; // 用于显示当前提示信息

  bool isDebugMode = false; // 调试模式开关，false代表关闭，true 代表开启
  // 获取用户信息
  final LocationService _locationService = LocationService();

  // 缓存资源路径和样式，避免重复创建
  static const String _portraitImage = 'assets/images/launch_image.png';
  static const String _landscapeImage = 'assets/images/launch_image_land.png';
  static const Color _defaultPrimaryColor = Color(0xFFEB144C); // 默认主题色

  @override
  void initState() {
    super.initState();
    _initializeApp(); // 初始化应用并获取播放列表数据
  }

  @override
  void dispose() {
    super.dispose();
    // 注意：若有未完成的可取消异步任务（如 Timer 或 Stream），应在此处取消
  }

  /// 应用初始化核心逻辑，负责协调数据加载和页面跳转
  Future<void> _initializeApp() async {
    try {
      // 安全执行初始化操作，捕获可能出现的异常
      LogUtil.safeExecute(() async {
        // 1. 获取 M3U 数据
        M3uResult m3uResult = await _fetchData();

        // 2. 并行获取用户信息和检查版本更新
        await Future.wait([
          _fetchUserInfo(), // 返回 Future<void>
          Future<void>.value(CheckVersionUtil.checkVersion(context, false, false, false)), // 强制转换为 Future<void>
        ]);

        // 3. 所有数据就绪后跳转页面
        if (mounted && m3uResult.data != null) {
          _navigateToHome(m3uResult.data!);
        } else {
          // 数据获取失败时更新提示信息
          _updateMessage(S.current.getm3udataerror);
        }
      }, '初始化应用时发生错误');
    } catch (error, stackTrace) {
      // 全局错误处理
      LogUtil.logError('初始化应用时发生错误', error, stackTrace);
      _updateMessage(S.current.getDefaultError);
    }
  }

  /// 获取用户信息（地理位置/设备信息）
  Future<void> _fetchUserInfo() async {
    if (mounted) { // 检查组件是否已挂载
      try {
        await _locationService.getUserAllInfo(context);
        LogUtil.i('用户信息获取成功');
      } catch (error, stackTrace) {
        LogUtil.logError('获取用户信息时发生错误', error, stackTrace);
      }
    }
  }

  /// 统一封装的M3U数据获取方法（含自动重试机制）
  Future<M3uResult> _fetchData() async {
    try {
      // 更新界面提示状态
      _updateMessage(S.current.getm3udata); // 显示"正在获取数据..."

      // 带自动重试的M3U数据获取
      result = await M3uUtil.getDefaultM3uData(onRetry: (attempt, remaining) {
        // 重试时更新提示信息
        _updateMessage('${S.current.getm3udata} (自动重试第 $attempt 次，剩余 $remaining 次)');
        LogUtil.e('获取 M3U 数据失败，自动重试第 $attempt 次，剩余 $remaining 次');
      });

      // 处理获取结果
      if (result != null && result!.data != null) {
        return result!; // 成功则返回 M3uResult 的数据
      } else {
        // 自动重试全部失败时显示错误
        _updateMessage(S.current.getm3udataerror);
        return M3uResult(errorMessage: result?.errorMessage ?? '未知错误');
      }
    } catch (e, stackTrace) {
      // 异常处理流程
      _updateMessage(S.current.getm3udataerror);
      LogUtil.logError('获取 M3U 数据时发生错误', e, stackTrace);
      return M3uResult(errorMessage: ': $e');
    }
  }

  /// 更新提示信息的统一方法，减少重复 setState 调用
  void _updateMessage(String message) {
    if (mounted) {
      setState(() {
        _message = message;
      });
    }
  }

  /// 显示调试日志的对话框
  void _showErrorLogs(BuildContext context) {
    if (isDebugMode) { // 仅在调试模式显示
      DialogUtil.showCustomDialog(
        context,
        title: S.current.logtitle,
        content: 'showlog', // 显示日志内容
        isCopyButton: true, // 启用复制按钮
      );
    }
  }

  /// 导航到主页面的方法
  void _navigateToHome(PlaylistModel data) {
    if (mounted) { // 确保组件未销毁
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => LiveHomePage(m3uData: data), // 传递解析后的播放列表数据
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var orientation = MediaQuery.of(context).orientation; // 缓存屏幕方向

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 根据屏幕方向加载不同的启动图
          Image.asset(
            orientation == Orientation.portrait ? _portraitImage : _landscapeImage,
            fit: BoxFit.cover,
          ),
          // 动态加载提示组件
          _buildMessageUI(
            _message.isEmpty ? '${S.current.loading}' : _message,
            isLoading: true,
          ),
        ],
      ),
      // 调试模式显示悬浮按钮
      floatingActionButton: isDebugMode
          ? FloatingActionButton(
              onPressed: () => _showErrorLogs(context),
              child: const Icon(Icons.bug_report),
              backgroundColor: _defaultPrimaryColor, // 使用默认主题色
            )
          : null,
    );
  }

  /// 构建动态提示界面（加载动画+文字）
  Widget _buildMessageUI(String message, {bool isLoading = false}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).orientation == Orientation.portrait ? 88.0 : 58.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              // 加载动画组件
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_defaultPrimaryColor),
                strokeWidth: 4.0,
              ),
              const SizedBox(height: 18),
            ],
            // 提示文字组件
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
