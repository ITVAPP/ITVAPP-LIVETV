import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/dialog_util.dart';
import 'package:itvapp_live_tv/util/m3u_util.dart';
import 'package:itvapp_live_tv/util/check_version_util.dart';
import 'package:itvapp_live_tv/util/location_service.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/entity/playlist_model.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/live_home_page.dart';
import 'package:itvapp_live_tv/config.dart';

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
  final LocationService _locationService = LocationService(); // 直接初始化用户位置服务
  
  // 静态资源路径和样式，避免重复创建
  static const String _portraitImage = 'assets/images/launch_image.png'; // 纵向启动图
  static const String _landscapeImage = 'assets/images/launch_image_land.png'; // 横向启动图
  static const Color _defaultPrimaryColor = Color(0xFFEB144C); // 默认主题颜色
  
  // UI常量，避免在build方法中重复创建
  static const _loadingIndicator = CircularProgressIndicator(
    valueColor: AlwaysStoppedAnimation<Color>(_defaultPrimaryColor),
    strokeWidth: 4.0, // 加载动画样式
  );
  static const _textStyle = TextStyle(
    fontSize: 16,
    color: Colors.white, // 提示文字样式
  );
  static const _verticalSpacing = SizedBox(height: 18); // 间距组件

  DateTime? _lastUpdateTime; // 上次更新时间，用于节流
  static const _debounceDuration = Duration(milliseconds: 500); // 节流间隔 500ms
  
  // 缓存强制更新状态，避免重复检查
  bool? _isInForceUpdateState;

  @override
  void initState() {
    super.initState();
    _initializeApp(); // 启动应用初始化流程
  }

  @override
  void dispose() {
    super.dispose(); // 清理资源，异步任务需在此取消（若有）
  }

  /// 获取缓存的强制更新状态，避免重复调用
  bool _getForceUpdateState() {
    _isInForceUpdateState ??= CheckVersionUtil.isInForceUpdateState();
    return _isInForceUpdateState!;
  }

  /// 初始化应用，协调数据加载和页面跳转
  Future<void> _initializeApp() async {
    try {
      LogUtil.safeExecute(() async {
        // 先检查版本更新
        await _checkVersion();
        
        // 如果是强制更新状态，停止进一步加载
        if (_getForceUpdateState()) {
          final message = S.current.oldVersion;
          _updateMessage(message);
          // 在强制更新状态下显示提示信息
          if (mounted) {
            CustomSnackBar.showSnackBar(
              context, 
              message,
              duration: const Duration(seconds: 5)
            );
          }
          return; // 强制更新时中断初始化流程
        }
        
        // 并行获取M3U数据和用户信息，提高加载效率
        final Future<M3uResult> m3uFuture = _fetchData();
        final Future<void> userInfoFuture = _fetchUserInfo();

        // 等待所有数据加载完成
        final m3uResult = await m3uFuture;
        await userInfoFuture;
        
        // 数据就绪后跳转主页
        if (mounted && m3uResult.data != null && !_getForceUpdateState()) {
          _navigateToHome(m3uResult.data!);
        } else if (mounted && m3uResult.data == null) {
          _updateMessage(S.current.getm3udataerror); // 数据失败时更新提示
        }
      }, '初始化应用时发生错误');
    } catch (error, stackTrace) {
      LogUtil.logError('初始化应用时发生错误', error, stackTrace);
      _updateMessage(S.current.getDefaultError); // 全局错误提示
    }
  }

  /// 检查版本更新
  Future<void> _checkVersion() async {
    try {
      if (mounted) {
        _updateMessage("检查版本更新...");
        await CheckVersionUtil.checkVersion(context, false, false, false);
        // 检查完成后更新缓存的强制更新状态
        _isInForceUpdateState = CheckVersionUtil.isInForceUpdateState();
      }
    } catch (e, stackTrace) {
      LogUtil.logError('检查版本更新时发生错误', e, stackTrace);
    }
  }

  /// 获取用户信息（地理位置和设备信息）
  Future<void> _fetchUserInfo() async {
    if (mounted) {
      try {
        await _locationService.getUserAllInfo(context); // 获取用户位置和设备信息
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
        _message = message; // 更新提示信息
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
        content: 'showlog', // 显示日志内容
        isCopyButton: true, // 支持复制日志
      );
    }
  }

  /// 获取语言转换类型
  String? _getConversionType(String playListLang, String userLang) {
    const conversionMap = {
      ('zh_CN', 'zh_TW'): 'zhHans2Hant', // 简体转繁体
      ('zh_TW', 'zh_CN'): 'zhHant2Hans', // 繁体转简体
    };
    return conversionMap[(playListLang, userLang)];
  }

  /// 从缓存中获取用户语言设置
  Locale _getUserLocaleFromCache() {
    try {
      // 从持久化存储读取语言和国家代码
      String? languageCode = SpUtil.getString('languageCode');
      String? countryCode = SpUtil.getString('countryCode');
      
      if (languageCode != null && languageCode.isNotEmpty) {
        // 若语言代码有效，返回保存的语言环境
        if (countryCode != null && countryCode.isNotEmpty) {
          return Locale(languageCode, countryCode);
        } else {
          return Locale(languageCode);
        }
      }
      
      // 如果没有存储的语言设置，使用Provider中的当前值
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      return languageProvider.currentLocale;
    } catch (e, stackTrace) {
      LogUtil.logError('从缓存获取用户语言设置失败', e, stackTrace);
      // 发生错误时使用Provider中的当前值
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      return languageProvider.currentLocale;
    }
  }

  /// 跳转到主页，传递播放列表数据，添加延迟确保对话框关闭
  void _navigateToHome(PlaylistModel data) {
    // 如果处于强制更新状态，不应该跳转到主页
    if (_getForceUpdateState()) {
      LogUtil.d('强制更新状态，阻止跳转到主页');
      return;
    }

    if (mounted) {
      // 从缓存获取当前用户的语言环境
      final userLocale = _getUserLocaleFromCache();
      PlaylistModel processedData = data;

      try {
        const playListLang = Config.playListlang;
        String? conversionType;
        String? userLang;

        // 1. 检查是否包含 zh 并构造 userLang
        if (userLocale.languageCode.startsWith('zh')) {
          userLang = userLocale.languageCode == 'zh' && userLocale.countryCode != null
              ? 'zh_${userLocale.countryCode}' // 标准 zh + 国家代码
              : userLocale.languageCode; // 直接使用 languageCode（如 zh, zh_CN, zh_TW）

          // 2. 比较 userLang 和 playListLang
          if (userLang != playListLang) {
            // 3. 确定转换类型
            conversionType = _getConversionType(playListLang, userLang);
          }
        }

        // 4. 执行转换或记录无需转换
        if (conversionType != null) {
          LogUtil.i('正在对播放列表进行中文转换: $playListLang -> $userLang ($conversionType)');
          processedData = await M3uUtil.convertPlaylistModel(data, conversionType);
          LogUtil.i('播放列表中文转换完成');
        } else {
          String reason = userLang == null
              ? '用户语言不包含 zh (${userLocale.languageCode})'
              : userLang == playListLang
                  ? '用户语言 ($userLang) 与播放列表语言 ($playListLang) 相同'
                  : '无匹配的转换类型';
          LogUtil.i('无需对播放列表进行中文转换: $reason');
        }
      } catch (e, stackTrace) {
        LogUtil.logError('播放列表中文转换失败，使用原始数据', e, stackTrace);
        processedData = data; // 转换失败时回退到原始数据
      }

      // 延迟跳转到主页
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_getForceUpdateState()) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => LiveHomePage(m3uData: processedData), // 传递处理后的数据
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            orientation == Orientation.portrait ? _portraitImage : _landscapeImage,
            fit: BoxFit.cover, // 背景图适配屏幕
          ),
          _buildMessageUI(
            _message.isEmpty ? '${S.current.loading}' : _message,
            isLoading: !_getForceUpdateState(), // 如果是强制更新状态，不显示加载动画
            orientation: orientation,
          ),
        ],
      ),
      floatingActionButton: isDebugMode
          ? FloatingActionButton(
              onPressed: () => _showErrorLogs(context),
              child: const Icon(Icons.bug_report),
              backgroundColor: _defaultPrimaryColor, // 调试按钮颜色
            )
          : null,
    );
  }

  /// 构建加载提示界面，包含动画和文字
  Widget _buildMessageUI(String message, {bool isLoading = false, required Orientation orientation}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: orientation == Orientation.portrait ? 88.0 : 58.0, // 适配屏幕方向
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              _loadingIndicator, // 使用预定义常量
              _verticalSpacing, // 使用预定义间距
            ],
            Text(
              message,
              style: _textStyle, // 使用预定义样式
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
