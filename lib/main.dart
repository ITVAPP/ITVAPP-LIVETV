import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sp_util/sp_util.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/setting/setting_font_page.dart';
import 'package:itvapp_live_tv/setting/subscribe_page.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/live_home_page.dart';
import 'package:itvapp_live_tv/splash_screen.dart';
import 'package:itvapp_live_tv/router_keys.dart';
import 'package:itvapp_live_tv/setting/setting_beautify_page.dart';
import 'package:itvapp_live_tv/setting/setting_log_page.dart';
import 'package:itvapp_live_tv/setting/setting_page.dart';

// 添加应用常量类
class AppConstants {
  static const double aspectRatio = 16 / 9; // 定义统一的宽高比常量，避免重复计算
  static const String appTitle = 'ITVAPP LIVETV'; // 应用程序标题常量
  static const Duration screenCheckDuration = Duration(milliseconds: 500); // 屏幕检查延迟时间常量
  static const Size defaultWindowSize = Size(414, 414 * aspectRatio); // 使用宽高比计算默认窗口大小
  static const Size minimumWindowSize = Size(300, 300 * aspectRatio); // 使用宽高比计算最小窗口大小
  static const String hardwareAccelerationKey = 'hardware_acceleration_enabled'; // 硬件加速状态的缓存键
}

// 定义全局状态管理器列表，提供下载和语言功能的静态提供者
final List<ChangeNotifierProvider> _staticProviders = [
  ChangeNotifierProvider<DownloadProvider>(create: (_) => DownloadProvider()), // 下载功能的状态提供者
  ChangeNotifierProvider<LanguageProvider>(create: (_) => LanguageProvider()), // 语言切换的状态提供者
];

// 应用程序入口函数，异步初始化以确保启动时完成必要操作
void main() async {
  // 初始化 Flutter 错误处理，记录未捕获的异常
  FlutterError.onError = (FlutterErrorDetails details) {
    LogUtil.logError('Uncaught Flutter error', details.exception, details.stack); // 记录异常到日志
    FlutterError.dumpErrorToConsole(details); // 输出错误到控制台
  };

  WidgetsFlutterBinding.ensureInitialized(); // 确保 Flutter 绑定初始化完成

  // 初始化主题提供者并确保正确初始化完成
  ThemeProvider themeProvider = ThemeProvider();
  
  // 创建初始化任务列表，确保错误处理
  List<Future<void>> initTasks = [
    WakelockPlus.enable().catchError((e, stack) {
      LogUtil.logError('初始化屏幕常亮失败', e, stack); 
      return Future.value(); // 返回完成状态，防止整个初始化流程中断
    }),
    
    SpUtil.getInstance().catchError((e, stack) {
      LogUtil.logError('初始化本地存储失败', e, stack);
      return Future.value();
    }),
    
    themeProvider.initialize().catchError((e, stack) {
      LogUtil.logError('初始化主题失败', e, stack);
      return Future.value();
    }),
  ];

  // 并行执行初始化操作以优化启动时间
  await Future.wait(initTasks);

  // 初始化EPG文件系统，清理过期数据
  try {
    await EpgUtil.init();
  } catch (e, stack) {
    LogUtil.logError('初始化EPG文件系统失败', e, stack);
  }

  if (!EnvUtil.isMobile) { // 判断是否为非移动端环境
    await _initializeDesktop(); // 初始化桌面端窗口设置
  }

  // 检查并缓存硬件加速状态，提供错误处理和用户反馈
  try {
    bool? isHardwareEnabled = SpUtil.getBool(AppConstants.hardwareAccelerationKey); // 从缓存获取硬件加速状态
    if (isHardwareEnabled == null) {
      isHardwareEnabled = await EnvUtil.isHardwareAccelerationEnabled(); // 检测硬件加速支持
      await SpUtil.putBool(AppConstants.hardwareAccelerationKey, isHardwareEnabled); // 存入缓存
      LogUtil.d('首次检测硬件加速支持，结果: $isHardwareEnabled，已存入缓存'); // 记录检测结果
    } 
  } catch (e, stackTrace) {
    LogUtil.e('检查和设置硬件加速状态发生错误: ${e.toString()}'); // 记录硬件加速检测错误
    await SpUtil.putBool(AppConstants.hardwareAccelerationKey, false); // 出错时禁用硬件加速
  }

  // 启动应用并配置全局状态管理
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: themeProvider), // 提供主题状态管理
      ..._staticProviders, // 扩展静态提供者列表
    ],
    child: const MyApp(), // 加载主应用界面
  ));

  // 设置移动端状态栏为透明，确保跨平台一致性
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent), // 设置透明状态栏
    );
  }
}

// 初始化桌面端窗口配置，包含错误处理
Future<void> _initializeDesktop() async {
  try {
    await windowManager.ensureInitialized(); // 确保窗口管理器初始化完成
    final windowOptions = WindowOptions(
      size: AppConstants.defaultWindowSize, // 设置默认窗口大小
      minimumSize: AppConstants.minimumWindowSize, // 设置最小窗口大小
      center: true, // 窗口居中显示
      backgroundColor: Colors.transparent, // 窗口背景透明
      skipTaskbar: false, // 显示在任务栏
      titleBarStyle: TitleBarStyle.hidden, // 隐藏标题栏
      title: AppConstants.appTitle, // 设置窗口标题
    );

    // 等待窗口准备好后显示并聚焦
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      try {
        await Future.wait([
          windowManager.show(), // 显示窗口
          windowManager.focus(), // 聚焦窗口
        ]);
      } catch (e, stack) {
        LogUtil.e('桌面端窗口显示或聚焦失败'); // 记录窗口显示错误
      }
    });
  } catch (e, stackTrace) {
    LogUtil.e('桌面端窗口初始化失败: ${e.toString()}'); // 记录窗口初始化错误
  }
}

// 定义应用路由表，管理页面跳转
class AppRouter {
  static final Map<String, WidgetBuilder> routes = {
    RouterKeys.subScribe: (BuildContext context) => const SubScribePage(), // 订阅页面路由
    RouterKeys.setting: (BuildContext context) => const SettingPage(), // 设置页面路由
    RouterKeys.settingFont: (BuildContext context) => const SettingFontPage(), // 字体设置页面路由
    RouterKeys.settingBeautify: (BuildContext context) => const SettingBeautifyPage(), // 美化设置页面路由
    RouterKeys.settinglog: (BuildContext context) => SettinglogPage(), // 日志设置页面路由
  };
}

// 主应用界面类，管理应用状态和主题
class MyApp extends StatefulWidget {
  const MyApp({super.key}); // 构造函数，接收可选键值

  @override
  _MyAppState createState() => _MyAppState(); // 创建状态对象
}

class _MyAppState extends State<MyApp> {
  late final ThemeProvider _themeProvider; // 延迟初始化主题提供者
  // 缓存改为使用计算键，避免字体相同但实例不同导致的缓存miss
  final Map<String, ThemeData> _themeCache = {}; // 主题数据缓存

  @override
  void initState() {
    super.initState();
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false); // 获取主题提供者实例
    _initializeApp(); // 执行应用初始化
  }

  // 异步初始化应用，检查设备类型
  Future<void> _initializeApp() async {
    try {
      await _themeProvider.checkAndSetIsTV(); // 检查并设置是否为电视设备
    } catch (e, stack) {
      LogUtil.logError('检查TV设备失败', e, stack);
    }
  }

  // 处理返回键逻辑，决定是否退出应用
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_isAtSplashScreen(context)) { // 判断是否在启动界面
      return await ShowExitConfirm.ExitConfirm(context); // 显示退出确认对话框
    }

    final orientationChanged = await _checkOrientationChange(context); // 检查屏幕方向变化
    if (!orientationChanged && !_canPop(context)) { // 无方向变化且无法返回
      return await ShowExitConfirm.ExitConfirm(context); // 显示退出确认
    }

    return false; // 允许正常返回
  }

  // 判断当前是否为启动界面
  bool _isAtSplashScreen(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name; // 获取当前路由名称
    return currentRoute == SplashScreen().toString() || !_canPop(context); // 检查是否启动页
  }

  // 检查导航器是否可返回上一页
  bool _canPop(BuildContext context) {
    return Navigator.canPop(context); // 返回导航器可弹出状态
  }

  // 检查设备方向变化并延迟确认
  Future<bool> _checkOrientationChange(BuildContext context) async {
    final initialOrientation = MediaQuery.of(context).orientation; // 获取初始方向
    if (MediaQuery.of(context).orientation == initialOrientation) { // 方向未变
      return false; // 返回无变化
    }
    await Future.delayed(AppConstants.screenCheckDuration); // 延迟检查
    return MediaQuery.of(context).orientation != initialOrientation; // 返回方向是否改变
  }

  // 构建主题数据并使用缓存优化性能
  ThemeData _buildTheme(String? fontFamily) {
    // 使用可靠的缓存键
    final cacheKey = fontFamily ?? 'system';
    
    if (_themeCache.containsKey(cacheKey)) { // 检查缓存中是否已有字体
      return _themeCache[cacheKey]!; // 返回缓存字体
    }

    final theme = ThemeData(
      brightness: Brightness.dark, // 暗色主题
      scaffoldBackgroundColor: const Color(0xFF1A1A1A), // 深灰色背景，无渐变
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A), // 深灰色，与背景一致
        foregroundColor: Colors.white, // 前景色为白色，确保图标和文字高对比度
        elevation: 0, // 无阴影
        centerTitle: true, // 标题居中
      ),
      useMaterial3: true, // 保留 Material 3 支持
      fontFamily: fontFamily, // 支持动态字体
    );

    _themeCache[cacheKey] = theme; // 缓存新构建的主题
    return theme; // 返回主题数据
  }

  @override
  Widget build(BuildContext context) {
    return Selector<LanguageProvider, Locale>(
      selector: (_, provider) => provider.currentLocale, // 选择当前语言环境
      builder: (context, locale, _) {
        return Selector<ThemeProvider, ({String fontFamily, double textScaleFactor})>(
          selector: (_, provider) => (
            fontFamily: provider.fontFamily, // 选择字体
            textScaleFactor: provider.textScaleFactor // 选择文本缩放比例
          ),
          builder: _buildMaterialApp, // 构建 MaterialApp
        );
      },
    );
  }

  // 构建 MaterialApp，提供应用核心界面
  Widget _buildMaterialApp(
    BuildContext context,
    ({String fontFamily, double textScaleFactor}) data,
    Widget? child
  ) {
    final String? effectiveFontFamily = data.fontFamily == 'system' ? null : data.fontFamily; // 处理字体选择

    return MaterialApp(
      title: AppConstants.appTitle, // 设置应用标题
      theme: _buildTheme(effectiveFontFamily), // 应用主题配置
      locale: Provider.of<LanguageProvider>(context).currentLocale, // 设置当前语言环境
      routes: AppRouter.routes, // 配置路由表
      localizationsDelegates: const [
        S.delegate, // 本地化代理
        GlobalMaterialLocalizations.delegate, // Material 本地化
        GlobalCupertinoLocalizations.delegate, // Cupertino 本地化
        GlobalWidgetsLocalizations.delegate // Widgets 本地化
      ],
      supportedLocales: S.delegate.supportedLocales, // 支持的语言环境列表
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale == null) { // 如果语言环境为空
          return supportedLocales.first; // 返回默认语言
        }

        // 处理中文地区的语言映射
        const localeMap = {
          'zh_TW': Locale('zh', 'TW'), // 繁体中文（台湾）
          'zh_HK': Locale('zh', 'TW'), // 繁体中文（香港）
          'zh_MO': Locale('zh', 'TW'), // 繁体中文（澳门）
          'zh_CN': Locale('zh', 'CN'), // 简体中文（中国）
          'zh': Locale('zh', 'CN'), // 默认简体中文
        };

        final key = locale.countryCode != null
            ? '${locale.languageCode}_${locale.countryCode}' // 构建语言代码
            : locale.languageCode;

        if (localeMap.containsKey(key)) { // 检查映射表
          return localeMap[key]; // 返回映射语言
        }

        return supportedLocales.firstWhere(
          (supportedLocale) =>
              supportedLocale.languageCode == locale.languageCode && // 匹配语言代码
              (supportedLocale.countryCode == locale.countryCode || // 匹配国家代码
                  supportedLocale.countryCode == null),
          orElse: () => supportedLocales.first, // 默认返回首个支持语言
        );
      },
      debugShowCheckedModeBanner: false, // 隐藏调试横幅
      home: WillPopScope(
        onWillPop: () => _handleBackPress(context), // 处理返回键事件
        child: SplashScreen(), // 设置启动页面
      ),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(data.textScaleFactor) // 设置文本缩放比例
          ),
          child: FlutterEasyLoading(child: child), // 添加加载指示器
        );
      },
    );
  }
}
