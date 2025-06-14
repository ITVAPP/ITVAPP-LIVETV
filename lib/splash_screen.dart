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

/// 启动页面组件，显示加载界面并初始化应用
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

/// 管理启动页面状态，处理数据加载与导航
class _SplashScreenState extends State<SplashScreen> {
  /// 当前提示信息
  String _message = '';
  /// 调试模式开关
  bool isDebugMode = false;
  /// 用户位置服务实例
  final LocationService _locationService = LocationService();
  
  /// 纵向启动图路径
  static const String _portraitImage = 'assets/images/launch_image.png';
  /// 横向启动图路径
  static const String _landscapeImage = 'assets/images/launch_image_land.png';
  /// 默认主题颜色
  static const Color _defaultPrimaryColor = Color(0xFFEB144C);
  
  /// 加载动画组件
  static const _loadingIndicator = CircularProgressIndicator(
    valueColor: AlwaysStoppedAnimation<Color>(_defaultPrimaryColor),
    strokeWidth: 4.0,
  );
  /// 垂直间距组件
  static const _verticalSpacing = SizedBox(height: 18);
  /// 导航延迟时间
  static const _navigationDelay = Duration(milliseconds: 2000);
  /// SnackBar 显示时长
  static const _snackBarDuration = Duration(seconds: 5);

  /// 上次更新时间
  DateTime? _lastUpdateTime;
  /// 节流间隔 500ms
  static const _debounceDuration = Duration(milliseconds: 500);
  
  /// 缓存强制更新状态
  bool? _isInForceUpdateState;
  
  /// 预编译语言转换映射表
  static const Map<String, Map<String, String>> _languageConversionMap = {
    'zh_CN': {'zh_TW': 'zhHans2Hant'},
    'zh_TW': {'zh_CN': 'zhHant2Hans'},
  };

  /// 初始化任务取消标志
  bool _isCancelled = false;
  
  /// 缓存用户语言
  Locale? _cachedUserLocale;

  @override
  void initState() {
    super.initState();
    /// 启动应用初始化
    _initializeApp();
  }

  @override
  void dispose() {
    /// 标记取消任务
    _isCancelled = true;
    super.dispose();
  }

  /// 检查是否可继续执行
  bool _canContinue() => !_isCancelled && mounted;

  /// 获取缓存的强制更新状态
  bool _getForceUpdateState() {
    _isInForceUpdateState ??= CheckVersionUtil.isInForceUpdateState();
    return _isInForceUpdateState!;
  }

  /// 初始化应用，协调数据加载与页面跳转
  Future<void> _initializeApp() async {
    if (!_canContinue()) return;
    
    /// 延迟确保 UI 渲染
    await Future.delayed(const Duration(milliseconds: 50));
    
    if (!_canContinue()) return;
    
    /// 异步获取用户信息
    _fetchUserInfo();

    try {
      await LogUtil.safeExecute(() async {
        await _checkVersion();
        if (_getForceUpdateState()) {
          _handleForceUpdate();
          return;
        }
        
        /// 并行加载 M3U 数据
        final m3uFuture = _fetchData();
        final m3uResult = await m3uFuture;
        
        /// 数据就绪后跳转主页
        if (_canContinue() && m3uResult.data != null && !_getForceUpdateState()) {
          await _navigateToHome(m3uResult.data!);
        } else if (_canContinue() && m3uResult.data == null) {
          _updateMessage(S.current.getm3udataerror);
        }
      }, '初始化应用失败');
    } catch (error, stackTrace) {
      if (_canContinue()) {
        LogUtil.logError('初始化应用失败', error, stackTrace);
        _updateMessage(S.current.getDefaultError);
      }
    }
  }

  /// 处理强制更新，显示提示
  void _handleForceUpdate() {
    if (!_canContinue()) return;
    
    final message = S.current.oldVersion;
    _updateMessage(message);
    CustomSnackBar.showSnackBar(
      context, 
      message,
      duration: _snackBarDuration,
    );
  }

  /// 检查应用版本更新
  Future<void> _checkVersion() async {
    if (!_canContinue()) return;
    
    try {
      _updateMessage('检查版本更新...');
      await CheckVersionUtil.checkVersion(context, false, false, false);
      _isInForceUpdateState = CheckVersionUtil.isInForceUpdateState();
    } catch (e, stackTrace) {
      LogUtil.logError('检查版本更新失败', e, stackTrace);
    }
  }

  /// 获取用户地理位置与设备信息
  Future<void> _fetchUserInfo() async {
    if (!_canContinue()) return;
    
    try {
      await _locationService.getUserAllInfo(context);
    } catch (error, stackTrace) {
      LogUtil.logError('获取用户信息失败', error, stackTrace);
    }
  }

  /// 获取 M3U 数据，支持自动重试
  Future<M3uResult> _fetchData() async {
    if (_isCancelled) return M3uResult(errorMessage: '操作已取消');
    
    try {
      _updateMessage(S.current.getm3udata);
      final result = await M3uUtil.getDefaultM3uData(onRetry: (attempt, remaining) {
        if (!_isCancelled) {
          _updateMessage('${S.current.getm3udata} (重试 $attempt/$remaining 次)');
          LogUtil.e('获取 M3U 数据失败，重试 $attempt/$remaining 次');
        }
      });
      
      if (_isCancelled) return M3uResult(errorMessage: '操作已取消');
      
      if (result?.data != null) {
        return result!;
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
    if (!_canContinue()) return;
    
    final now = DateTime.now();
    if (_lastUpdateTime == null || now.difference(_lastUpdateTime!) >= _debounceDuration) {
      setState(() {
        _message = message;
      });
      _lastUpdateTime = now;
    }
  }

  /// 显示调试日志对话框
  void _showErrorLogs(BuildContext context) {
    if (!_canContinue()) return;
    
    if (isDebugMode) {
      DialogUtil.showCustomDialog(
        context,
        title: S.current.logtitle,
        content: 'showlog',
        isCopyButton: true,
      );
    }
  }

  /// 获取语言转换类型
  String? _getConversionType(String playListLang, String userLang) {
    return _languageConversionMap[playListLang]?[userLang];
  }

  /// 规范化语言代码，处理中文及国家代码组合
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
      return data;
    }
    
    final conversionType = _getConversionType(playListLang, userLang);
    
    if (conversionType == null) {
      return data;
    }
    
    try {
      final convertedData = await M3uUtil.convertPlaylistModel(data, conversionType);
      return convertedData;
    } catch (error, stackTrace) {
      LogUtil.logError('中文转换失败', error, stackTrace);
      return data;
    }
  }

  /// 执行页面导航至主页
  void _performNavigation(PlaylistModel data) {
    if (!_canContinue() || _getForceUpdateState() || !context.mounted) return;
    
    Future.delayed(_navigationDelay, () {
      if (_canContinue() && !_getForceUpdateState() && context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => LiveHomePage(m3uData: data),
          ),
        );
      }
    });
  }

  /// 跳转至主页，处理语言转换
  Future<void> _navigateToHome(PlaylistModel data) async {
    if (!_canContinue()) return;
    
    if (_getForceUpdateState()) {
      LogUtil.d('强制更新状态，阻止跳转');
      return;
    }

    try {
      final userLocale = _getUserLocaleFromCache();
      final userLang = _normalizeLanguageCode(userLocale);
      const playListLang = Config.playListlang;
      
      final processedData = await _performChineseConversion(data, playListLang, userLang);
      
      if (!_canContinue() || _getForceUpdateState()) return;
      
      _performNavigation(processedData);
    } catch (e, stackTrace) {
      LogUtil.logError('跳转主页失败', e, stackTrace);
      _performNavigation(data);
    }
  }

  /// 获取文字样式，适配 TV 模式
  TextStyle _getTextStyle(BuildContext context) {
    try {
      final isTV = context.read<ThemeProvider>().isTV;
      final double fontSize = isTV ? 20.0 : 16.0;
      
      return TextStyle(
        fontSize: fontSize,
        color: Colors.white,
      );
    } catch (e) {
      return const TextStyle(
        fontSize: 16.0,
        color: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          /// 显示启动图片，适配屏幕方向
          Image.asset(
            orientation == Orientation.portrait 
                ? _portraitImage 
                : _landscapeImage,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              LogUtil.e('启动图片加载失败: $error');
              return Container(
                color: const Color(0xFF1A1A1A),
              );
            },
          ),
          _buildMessageUI(
            _message.isEmpty ? S.current.loading : _message,
            isLoading: !_getForceUpdateState(),
            orientation: orientation,
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

  /// 构建加载提示界面，适配屏幕方向
  Widget _buildMessageUI(String message, {bool isLoading = false, required Orientation orientation}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: orientation == Orientation.portrait ? 88.0 : 58.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              _loadingIndicator,
              _verticalSpacing,
            ],
            Text(
              message,
              style: _getTextStyle(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
