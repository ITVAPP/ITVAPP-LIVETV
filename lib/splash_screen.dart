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

/// 启动页面组件，初始化应用并显示加载界面
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

/// 启动页面状态管理，处理数据加载与页面跳转
class _SplashScreenState extends State<SplashScreen> {
  M3uResult? result; // 存储 M3U 数据结果
  String _message = ''; // 当前提示信息
  bool isDebugMode = false; // 调试模式开关
  final LocationService _locationService = LocationService(); // 用户位置服务实例
  
  // 静态资源路径和样式
  static const String _portraitImage = 'assets/images/launch_image.png'; // 纵向启动图路径
  static const String _landscapeImage = 'assets/images/launch_image_land.png'; // 横向启动图路径
  static const Color _defaultPrimaryColor = Color(0xFFEB144C); // 默认主题颜色
  
  // UI常量
  static const _loadingIndicator = CircularProgressIndicator(
    valueColor: AlwaysStoppedAnimation<Color>(_defaultPrimaryColor),
    strokeWidth: 4.0, // 加载动画样式
  );
  static const _verticalSpacing = SizedBox(height: 18); // 垂直间距组件

  DateTime? _lastUpdateTime; // 上次更新时间
  static const _debounceDuration = Duration(milliseconds: 500); // 节流间隔 500ms
  
  // 缓存强制更新状态
  bool? _isInForceUpdateState;
  
  // 预编译语言转换映射表
  static const Map<String, Map<String, String>> _languageConversionMap = {
    'zh_CN': {'zh_TW': 'zhHans2Hant'}, // 简体转繁体
    'zh_TW': {'zh_CN': 'zhHant2Hans'}, // 繁体转简体
  };

  // 初始化任务取消标志
  bool _isCancelled = false;
  
  // 缓存用户语言
  Locale? _cachedUserLocale;

  @override
  void initState() {
    super.initState();
    _initializeApp(); // 启动应用初始化流程
  }

  @override
  void dispose() {
    _isCancelled = true; // 标记取消任务
    super.dispose();
  }

  /// 获取缓存的强制更新状态
  bool _getForceUpdateState() {
    _isInForceUpdateState ??= CheckVersionUtil.isInForceUpdateState();
    return _isInForceUpdateState!; // 返回强制更新状态
  }

  /// 初始化应用，协调数据加载与页面跳转
  Future<void> _initializeApp() async {
    if (_isCancelled) return; // 已取消则中断初始化
    _fetchUserInfo(); // 异步获取用户信息

    try {
      await LogUtil.safeExecute(() async {
        await _checkVersion(); // 检查版本更新
        if (_getForceUpdateState()) {
          _handleForceUpdate(); // 处理强制更新
          return;
        }
        
        // 并行加载 M3U 数据和用户信息
        final m3uFuture = _fetchData();
        final m3uResult = await m3uFuture;
        
        // 数据就绪后跳转主页
        if (!_isCancelled && mounted && m3uResult.data != null && !_getForceUpdateState()) {
          await _navigateToHome(m3uResult.data!);
        } else if (!_isCancelled && mounted && m3uResult.data == null) {
          _updateMessage(S.current.getm3udataerror); // 数据获取失败提示
        }
      }, '初始化应用失败');
    } catch (error, stackTrace) {
      if (!_isCancelled) {
        LogUtil.logError('初始化应用失败', error, stackTrace);
        _updateMessage(S.current.getDefaultError); // 全局错误提示
      }
    }
  }

  /// 处理强制更新，显示提示
  void _handleForceUpdate() {
    if (_isCancelled || !mounted) return;
    
    final message = S.current.oldVersion;
    _updateMessage(message);
    CustomSnackBar.showSnackBar(
      context, 
      message,
      duration: const Duration(seconds: 5), // 显示 5 秒提示
    );
  }

  /// 检查应用版本更新
  Future<void> _checkVersion() async {
    if (_isCancelled || !mounted) return;
    
    try {
      _updateMessage('检查版本更新...');
      await CheckVersionUtil.checkVersion(context, false, false, false);
      _isInForceUpdateState = CheckVersionUtil.isInForceUpdateState(); // 更新缓存状态
    } catch (e, stackTrace) {
      LogUtil.logError('检查版本更新失败', e, stackTrace);
    }
  }

  /// 获取用户地理位置与设备信息
  Future<void> _fetchUserInfo() async {
    if (_isCancelled || !mounted) return;
    
    try {
      await _locationService.getUserAllInfo(context);
      LogUtil.i('用户信息获取成功');
    } catch (error, stackTrace) {
      LogUtil.logError('获取用户信息失败', error, stackTrace);
    }
  }

  /// 获取 M3U 数据，支持自动重试
  Future<M3uResult> _fetchData() async {
    if (_isCancelled) return M3uResult(errorMessage: '操作已取消');
    
    try {
      _updateMessage(S.current.getm3udata);
      result = await M3uUtil.getDefaultM3uData(onRetry: (attempt, remaining) {
        if (!_isCancelled) {
          _updateMessage('${S.current.getm3udata} (重试 $attempt/$remaining 次)');
          LogUtil.e('获取 M3U 数据失败，重试 $attempt/$remaining 次');
        }
      });
      
      if (_isCancelled) return M3uResult(errorMessage: '操作已取消');
      
      if (result != null && result!.data != null) {
        return result!; // 返回 M3U 数据
      } else {
        _updateMessage(S.current.getm3udataerror);
        return M3uResult(errorMessage: result?.errorMessage ?? '未知错误');
      }
    } catch (e, stackTrace) {
      if (!_isCancelled) {
        _updateMessage(S.current.getm3udataerror);
        LogUtil.logError('获取 M3U 数据失败', e, stackTrace);
      }
      return M3uResult(errorMessage: e.toString());
    }
  }

  /// 更新提示信息，带节流机制
  void _updateMessage(String message) {
    if (_isCancelled || !mounted) return;
    
    final now = DateTime.now();
    if (_lastUpdateTime == null || now.difference(_lastUpdateTime!) >= _debounceDuration) {
      setState(() {
        _message = message; // 更新界面提示
      });
      _lastUpdateTime = now;
    }
  }

  /// 显示调试日志对话框
  void _showErrorLogs(BuildContext context) {
    if (_isCancelled || !mounted) return;
    
    if (isDebugMode) {
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
    return _languageConversionMap[playListLang]?[userLang];
  }

  /// 规范化语言代码
  String _normalizeLanguageCode(Locale locale) {
    final languageCode = locale.languageCode;
    final countryCode = locale.countryCode;
    
    if (languageCode == 'zh') {
      return countryCode?.isNotEmpty == true ? 'zh_$countryCode' : 'zh';
    }
    
    if (languageCode.startsWith('zh_')) {
      return languageCode;
    }
    
    return countryCode?.isNotEmpty == true 
        ? '${languageCode}_$countryCode'
        : languageCode;
  }

  /// 从缓存获取用户语言
  Locale _getUserLocaleFromCache() {
    if (_cachedUserLocale != null) {
      return _cachedUserLocale!;
    }
    
    try {
      final String? languageCode = SpUtil.getString('languageCode');
      final String? countryCode = SpUtil.getString('countryCode');
      
      Locale locale;
      if (languageCode?.isNotEmpty == true) {
        locale = countryCode?.isNotEmpty == true 
            ? Locale(languageCode!, countryCode!)
            : Locale(languageCode!);
      } else if (mounted && context.mounted) {
        try {
          final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
          locale = languageProvider.currentLocale;
        } catch (e) {
          locale = const Locale('zh', 'CN');
        }
      } else {
        locale = const Locale('zh', 'CN');
      }
      
      _cachedUserLocale = locale;
      return locale;
    } catch (e, stackTrace) {
      LogUtil.logError('获取用户语言失败', e, stackTrace);
      const fallbackLocale = Locale('zh', 'CN');
      _cachedUserLocale = fallbackLocale;
      return fallbackLocale;
    }
  }

  /// 执行播放列表中文转换
  Future<PlaylistModel> _performChineseConversion(
    PlaylistModel data, 
    String playListLang, 
    String userLang
  ) async {
    if (!userLang.startsWith('zh') || 
        !playListLang.startsWith('zh') || 
        userLang == playListLang) {
      return data; // 无需转换
    }
    
    final conversionType = _getConversionType(playListLang, userLang);
    
    if (conversionType == null) {
      return data; // 无转换方法
    }
    
    LogUtil.i('执行中文转换: $playListLang -> $userLang ($conversionType)');
    
    try {
      final convertedData = await M3uUtil.convertPlaylistModel(data, conversionType);
      return convertedData; // 返回转换后数据
    } catch (error, stackTrace) {
      LogUtil.logError('中文转换失败', error, stackTrace);
      return data; // 转换失败返回原数据
    }
  }

  /// 跳转到主页
  Future<void> _navigateToHome(PlaylistModel data) async {
    if (_isCancelled || !mounted) return;
    
    if (_getForceUpdateState()) {
      LogUtil.d('强制更新状态，阻止跳转');
      return; // 强制更新时阻止跳转
    }

    try {
      final userLocale = _getUserLocaleFromCache();
      final userLang = _normalizeLanguageCode(userLocale); // 规范化用户语言
      const playListLang = Config.playListlang; // 播放列表语言
      
      final processedData = await _performChineseConversion(data, playListLang, userLang);
      
      if (_isCancelled || !mounted || _getForceUpdateState()) return;
      
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (!_isCancelled && mounted && !_getForceUpdateState() && context.mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => LiveHomePage(m3uData: processedData), // 跳转主页
            ),
          );
        }
      });
    } catch (e, stackTrace) {
      LogUtil.logError('跳转主页失败', e, stackTrace);
      if (!_isCancelled && mounted && !_getForceUpdateState() && context.mounted) {
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted && !_getForceUpdateState()) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => LiveHomePage(m3uData: data), // 使用原始数据跳转
              ),
            );
          }
        });
      }
    }
  }

  /// 获取文字样式，支持TV模式
  TextStyle _getTextStyle(BuildContext context) {
    final isTV = context.read<ThemeProvider>().isTV;
    final double fontSize = isTV ? 22.0 : 16.0;
    
    return TextStyle(
      fontSize: fontSize,
      color: Colors.white,
    );
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
            isLoading: !_getForceUpdateState(), // 强制更新时隐藏加载动画
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

  /// 构建加载提示界面
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
              _loadingIndicator, // 显示加载动画
              _verticalSpacing, // 添加垂直间距
            ],
            Text(
              message,
              style: _getTextStyle(context), // 使用动态文字样式
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
