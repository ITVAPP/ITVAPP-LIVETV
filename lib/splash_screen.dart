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
  final LocationService _locationService = LocationService(); // 初始化用户位置服务
  
  // 静态资源路径和样式，避免重复创建
  static const String _portraitImage = 'assets/images/launch_image.png'; // 纵向启动图路径
  static const String _landscapeImage = 'assets/images/launch_image_land.png'; // 横向启动图路径
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
  static const _verticalSpacing = SizedBox(height: 18); // 垂直间距组件

  DateTime? _lastUpdateTime; // 上次更新时间，用于节流
  static const _debounceDuration = Duration(milliseconds: 500); // 节流间隔 500ms
  
  // 缓存强制更新状态，避免重复检查
  bool? _isInForceUpdateState;
  
  // 定义超时时间常量
  static const _initTimeoutDuration = Duration(seconds: 30); // 初始化超时时间
  static const _conversionTimeoutDuration = Duration(seconds: 15); // 中文转换超时时间

  // 定义语言转换映射表，与M3uUtil和ZhConverter匹配
  static const Map<String, Map<String, String>> _languageConversionMap = {
    'zh_CN': {'zh_TW': 'zhHans2Hant'}, // 简体转繁体
    'zh_TW': {'zh_CN': 'zhHant2Hans'}, // 繁体转简体
  };

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
    return _isInForceUpdateState!; // 返回强制更新状态
  }

  /// 初始化应用，协调数据加载和页面跳转
  Future<void> _initializeApp() async {
    try {
      // 添加超时处理
      await LogUtil.safeExecute(() async {
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

        // 等待所有数据加载完成，添加超时处理
        final m3uResult = await m3uFuture.timeout(
          _initTimeoutDuration,
          onTimeout: () {
            LogUtil.e('获取M3U数据超时');
            return M3uResult(errorMessage: '网络请求超时，请检查网络连接');
          }
        );
        
        // 用户信息获取添加超时处理
        await userInfoFuture.timeout(
          _initTimeoutDuration,
          onTimeout: () {
            LogUtil.e('获取用户信息超时');
            return;
          }
        );
        
        // 数据就绪后跳转主页
        if (mounted && m3uResult.data != null && !_getForceUpdateState()) {
          await _navigateToHome(m3uResult.data!);
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

  /// 获取语言转换类型，返回M3uUtil.convertPlaylistModel支持的转换类型字符串
  String? _getConversionType(String playListLang, String userLang) {
    if (_languageConversionMap.containsKey(playListLang)) {
      final targetMap = _languageConversionMap[playListLang];
      if (targetMap != null && targetMap.containsKey(userLang)) {
        return targetMap[userLang]; // 返回转换类型
      }
    }
    return null; // 找不到对应的转换类型
  }

  /// 将语言代码规范化为"zh_XX"格式，处理各种可能的语言代码
  String _normalizeLanguageCode(Locale locale) {
    if (locale.languageCode == 'zh') {
      if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
        return 'zh_${locale.countryCode!}'; // 使用国家代码格式
      }
      return 'zh'; // 无国家代码返回zh
    } else if (locale.languageCode.startsWith('zh_')) {
      return locale.languageCode; // 已经是zh_XX格式
    } else if (locale.languageCode.startsWith('zh')) {
      if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
        return 'zh_${locale.countryCode!}'; // 其他zh开头格式使用国家代码
      }
      return locale.languageCode; // 无国家代码直接返回
    }
    
    if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
      return '${locale.languageCode}_${locale.countryCode!}'; // 非中文语言组合国家代码
    }
    
    return locale.languageCode; // 返回原始语言代码
  }

  /// 从缓存中获取用户语言设置
  Locale _getUserLocaleFromCache() {
    try {
      String? languageCode = SpUtil.getString('languageCode');
      String? countryCode = SpUtil.getString('countryCode');
      
      if (languageCode != null && languageCode.isNotEmpty) {
        if (countryCode != null && countryCode.isNotEmpty) {
          return Locale(languageCode, countryCode); // 返回缓存的语言环境
        }
        return Locale(languageCode); // 无国家代码的语言环境
      }
      
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      return languageProvider.currentLocale; // 使用Provider中的当前语言
    } catch (e, stackTrace) {
      LogUtil.logError('从缓存获取用户语言设置失败', e, stackTrace);
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      return languageProvider.currentLocale; // 错误时回退到Provider中的语言
    }
  }

  /// 跳转到主页，传递播放列表数据，添加延迟确保对话框关闭
  Future<void> _navigateToHome(PlaylistModel data) async {
    if (_getForceUpdateState()) {
      LogUtil.d('强制更新状态，阻止跳转到主页');
      return; // 强制更新时阻止跳转
    }

    if (mounted) {
      final userLocale = _getUserLocaleFromCache();
      PlaylistModel processedData = data;

      try {
        const playListLang = Config.playListlang; // 播放列表使用的语言
        final userLang = _normalizeLanguageCode(userLocale); // 规范化用户语言代码
        
        if (userLang.startsWith('zh') && 
            playListLang.startsWith('zh') && 
            userLang != playListLang) {
          
          _updateMessage('正在进行中文转换...');
          
          final conversionType = _getConversionType(playListLang, userLang);
          
          if (conversionType != null) {
            LogUtil.i('正在对播放列表进行中文转换: $playListLang -> $userLang ($conversionType)');
            
            processedData = await Future.timeout(
              _conversionTimeoutDuration,
              () => M3uUtil.convertPlaylistModel(data, conversionType)
            ).catchError((error, stackTrace) {
              LogUtil.logError('播放列表中文转换超时或失败', error, stackTrace);
              return data; // 转换失败回退到原始数据
            });
            
            LogUtil.i('播放列表中文转换完成');
          } else {
            LogUtil.i('无需对播放列表进行中文转换: 没有找到从 $playListLang 到 $userLang 的转换方法');
          }
        } else {
          final reason = !userLang.startsWith('zh') 
              ? '用户语言不是中文 ($userLang)' 
              : userLang == playListLang 
                  ? '用户语言 ($userLang) 与播放列表语言 ($playListLang) 相同' 
                  : '播放列表语言不是中文 ($playListLang)';
          LogUtil.i('无需对播放列表进行中文转换: $reason');
        }
      } catch (e, stackTrace) {
        LogUtil.logError('播放列表中文转换过程中发生错误，使用原始数据', e, stackTrace);
        processedData = data; // 转换失败回退到原始数据
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
            isLoading: !_getForceUpdateState(), // 强制更新状态下不显示加载动画
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
              _loadingIndicator, // 显示加载动画
              _verticalSpacing, // 添加垂直间距
            ],
            Text(
              message,
              style: _textStyle, // 应用提示文字样式
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
