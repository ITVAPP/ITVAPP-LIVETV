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

// 启动页面组件，负责应用初始化和显示加载界面
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

// 启动页面状态管理类，处理数据加载和页面跳转逻辑
class _SplashScreenState extends State<SplashScreen> {
  M3uResult? result; // 存储 M3U 数据结果，异常时可访问
  String _message = ''; // 当前显示的提示信息
  bool isDebugMode = false; // 调试模式开关，控制日志显示
  late final LocationService _locationService; // 延迟初始化用户位置服务

  // 静态资源路径和样式，避免重复创建
  static const String _portraitImage = 'assets/images/launch_image.png'; // 纵向启动图
  static const String _landscapeImage = 'assets/images/launch_image_land.png'; // 横向启动图
  static const Color _defaultPrimaryColor = Color(0xFFEB144C); // 默认主题颜色

  late Orientation _orientation; // 缓存屏幕方向，优化性能
  DateTime? _lastUpdateTime; // 上次更新时间，用于节流
  static const _debounceDuration = Duration(milliseconds: 300); // 节流间隔 300ms

  @override
  void initState() {
    super.initState();
    _locationService = LocationService(); // 初始化位置服务
    _orientation = MediaQuery.of(context).orientation; // 缓存初始屏幕方向
    _initializeApp(); // 启动应用初始化流程
  }

  @override
  void dispose() {
    super.dispose(); // 清理资源，异步任务需在此取消（若有）
  }

  /// 初始化应用，协调数据加载和页面跳转
  Future<void> _initializeApp() async {
    try {
      LogUtil.safeExecute(() async {
        // 获取 M3U 数据
        M3uResult m3uResult = await _fetchData();
        // 并行加载用户信息和检查版本
        await Future.wait([
          _fetchUserInfo(),
          Future<void>.value(CheckVersionUtil.checkVersion(context, false, false, false)),
        ]);
        // 数据就绪后跳转主页
        if (mounted && m3uResult.data != null) {
          _navigateToHome(m3uResult.data!);
        } else {
          _updateMessage(S.current.getm3udataerror); // 数据失败时更新提示
        }
      }, '初始化应用时发生错误');
    } catch (error, stackTrace) {
      LogUtil.logError('初始化应用时发生错误', error, stackTrace);
      _updateMessage(S.current.getDefaultError); // 全局错误提示
    }
  }

  /// 获取用户信息（地理位置和设备信息）
  Future<void> _fetchUserInfo() async {
    if (mounted) {
      try {
        await _locationService.getUserAllInfo(context);
        LogUtil.i('用户信息获取成功');
      } catch (error, stackTrace) {
        LogUtil.logError('获取用户信息时发生错误', error, stackTrace);
      }
    }
  }

  /// 获取 M3U 数据，包含自动重试机制
  Future<M3uResult> _fetchData() async {
    try {
      _updateMessage(S.current.getm3udata); // 显示获取数据提示
      result = await M3uUtil.getDefaultM3uData(onRetry: (attempt, remaining) {
        _updateMessage('${S.current.getm3udata} (自动重试第 $attempt 次，剩余 $remaining 次)');
        LogUtil.e('获取 M3U 数据失败，自动重试第 $attempt 次，剩余 $remaining 次');
      });
      if (result != null && result!.data != null) {
        return result!; // 返回成功结果
      } else {
        _updateMessage(S.current.getm3udataerror); // 重试失败提示
        return M3uResult(errorMessage: result?.errorMessage ?? '未知错误');
      }
    } catch (e, stackTrace) {
      _updateMessage(S.current.getm3udataerror); // 异常时更新提示
      LogUtil.logError('获取 M3U 数据时发生错误', e, stackTrace);
      return M3uResult(errorMessage: ': $e');
    }
  }

  /// 更新提示信息，带节流机制减少重复刷新
  void _updateMessage(String message) {
    if (!mounted) return; // 确保组件挂载
    final now = DateTime.now();
    if (_lastUpdateTime == null || now.difference(_lastUpdateTime!) >= _debounceDuration) {
      setState(() {
        _message = message;
      });
      _lastUpdateTime = now;
    }
  }

  /// 显示调试日志对话框，仅调试模式生效
  void _showErrorLogs(BuildContext context) {
    if (isDebugMode && mounted) { // 检查挂载状态，确保上下文安全
      DialogUtil.showCustomDialog(
        context,
        title: S.current.logtitle,
        content: 'showlog',
        isCopyButton: true,
      );
    }
  }

  /// 跳转到主页，传递播放列表数据，添加延迟确保对话框关闭
  void _navigateToHome(PlaylistModel data) {
    if (mounted) {
      Future.delayed(const Duration(milliseconds: 100), () { // 延迟 100ms
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => LiveHomePage(m3uData: data),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _orientation == Orientation.portrait ? _portraitImage : _landscapeImage,
            fit: BoxFit.cover, // 背景图适配屏幕
          ),
          _buildMessageUI(
            _message.isEmpty ? '${S.current.loading}' : _message,
            isLoading: true, // 显示加载动画
          ),
        ],
      ),
      floatingActionButton: isDebugMode
          ? FloatingActionButton(
              onPressed: () => _showErrorLogs(context),
              child: const Icon(Icons.bug_report),
              backgroundColor: _defaultPrimaryColor,
            )
          : null,
    );
  }

  /// 构建加载提示界面，包含动画和文字
  Widget _buildMessageUI(String message, {bool isLoading = false}) {
    const loadingIndicator = CircularProgressIndicator(
      valueColor: AlwaysStoppedAnimation<Color>(_defaultPrimaryColor),
      strokeWidth: 4.0, // 加载动画样式
    );
    const textStyle = TextStyle(
      fontSize: 16,
      color: Colors.white, // 提示文字样式
    );

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: _orientation == Orientation.portrait ? 88.0 : 58.0, // 适配屏幕方向
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              loadingIndicator,
              const SizedBox(height: 18), // 间距组件
            ],
            Text(
              message,
              style: textStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
