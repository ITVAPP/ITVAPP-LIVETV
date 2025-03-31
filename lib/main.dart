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
  static const String appTitle = 'ITVAPP LIVETV';
  static const Duration screenCheckDuration = Duration(milliseconds: 500);
  static const Size defaultWindowSize = Size(414, 414 * aspectRatio); // 使用宽高比计算默认窗口大小
  static const Size minimumWindowSize = Size(300, 300 * aspectRatio); // 使用宽高比计算最小窗口大小
  static const String hardwareAccelerationKey = 'hardware_acceleration_enabled'; // 硬件加速缓存键
}

// 修改代码开始：提取 MultiProvider 的静态 providers 为常量
final List<Provider> _staticProviders = [
  ChangeNotifierProvider(create: (_) => DownloadProvider()),
  ChangeNotifierProvider(create: (_) => LanguageProvider()),
];
// 修改代码结束

// 应用程序的入口函数，使用 async 关键字以确保异步操作可以在启动时完成
void main() async {
  // 错误处理初始化
  FlutterError.onError = (FlutterErrorDetails details) {
    // 记录错误到日志中
    LogUtil.logError('Uncaught Flutter error', details.exception, details.stack);
    // 继续使用Flutter默认的错误报告
    FlutterError.dumpErrorToConsole(details);
  };

  // 确保 WidgetsFlutterBinding 已经初始化，必要时会为应用的生命周期提供必要的绑定
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化主题提供者并确保正确初始化完成
  ThemeProvider themeProvider = ThemeProvider();
  // 使用 Future.wait 优化并行初始化操作，包含 ThemeProvider 的初始化以减少启动时间
  await Future.wait([
    WakelockPlus.enable(), // 启用屏幕常亮
    SpUtil.getInstance(),  // 初始化本地存储工具
    themeProvider.initialize(), // 初始化主题提供者
  ]);

  // 如果当前环境不是移动端
  if (!EnvUtil.isMobile) {
    await _initializeDesktop();
  }

  // 硬件加速检测和缓存逻辑，添加错误反馈和详细日志
  try {
    // 检查缓存中是否已有硬件加速状态
    bool? isHardwareEnabled = SpUtil.getBool(AppConstants.hardwareAccelerationKey);
    if (isHardwareEnabled == null) {
      // 如果缓存中没有值，则检测并存入缓存
      isHardwareEnabled = await EnvUtil.isHardwareAccelerationEnabled();
      await SpUtil.putBool(AppConstants.hardwareAccelerationKey, isHardwareEnabled);
      LogUtil.d('首次检测硬件加速支持，结果: $isHardwareEnabled，已存入缓存');
    } else {
      LogUtil.d('从缓存读取硬件加速状态: $isHardwareEnabled');
    }
  } catch (e, stackTrace) {
    LogUtil.e('检查和设置硬件加速状态发生错误: ${e.toString()}', stackTrace: stackTrace); // 添加堆栈信息
    await SpUtil.putBool(AppConstants.hardwareAccelerationKey, false); // 出错时缓存默认值
    EasyLoading.showError('硬件加速检测失败，已禁用'); // 提供用户反馈
  }

  // 运行应用，并使用 MultiProvider 进行全局状态管理
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: themeProvider),
      ..._staticProviders, // 修改代码：使用提取的静态 providers
    ],
    child: const MyApp(),
  ));

  // 如果当前平台是 Android 或 iOS，设置状态栏为透明，确保跨平台一致性
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
  }
}

// 提取桌面端初始化的逻辑以提高代码的维护性，并添加错误处理
Future<void> _initializeDesktop() async {
  try {
    await windowManager.ensureInitialized();
    final windowOptions = WindowOptions(
      size: AppConstants.defaultWindowSize,
      minimumSize: AppConstants.minimumWindowSize,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: AppConstants.appTitle,
    );

    // 等待窗口准备好再显示，可并行执行显示和聚焦操作
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await Future.wait([
        windowManager.show(),
        windowManager.focus(),
      ]);
    });
  } catch (e, stackTrace) {
    LogUtil.e('桌面端窗口初始化失败: ${e.toString()}', stackTrace: stackTrace);
    // 默认行为：记录错误但不中断应用启动
  }
}

// 提取路由配置以提高代码的维护性
class AppRouter {
  static final Map<String, WidgetBuilder> routes = {
    RouterKeys.subScribe: (BuildContext context) => const SubScribePage(),
    RouterKeys.setting: (BuildContext context) => const SettingPage(),
    RouterKeys.settingFont: (BuildContext context) => const SettingFontPage(),
    RouterKeys.settingBeautify: (BuildContext context) => const SettingBeautifyPage(),
    RouterKeys.settinglog: (BuildContext context) => SettinglogPage(),
  };
}

// 主应用界面
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ThemeProvider _themeProvider;
  // 修改代码开始：添加 ThemeData 缓存
  final Map<String?, ThemeData> _themeCache = {};

  @override
  void initState() {
    super.initState();
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false); // 修改代码：修正 contextCONFIRMATION 为 context
    _initializeApp();
  }

  // 应用初始化操作
  Future<void> _initializeApp() async {
    await _themeProvider.checkAndSetIsTV(); // 检查并设置设备是否为电视
  }

  // 处理返回键的逻辑，确保正确的退出交互，并优化结构
  Future<bool> _handleBackPress(BuildContext context) async {
    // 修改代码开始：优化逻辑结构
    if (_isAtSplashScreen(context)) {
      return await ShowExitConfirm.ExitConfirm(context);
    }

    final orientationChanged = await _checkOrientationChange(context);
    if (!orientationChanged && !_canPop(context)) {
      return await ShowExitConfirm.ExitConfirm(context);
    }

    return false;
    // 修改代码结束
  }

  // 检查当前界面是否是启动画面，提取 Navigator.canPop 的逻辑
  bool _isAtSplashScreen(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    return currentRoute == SplashScreen().toString() || !_canPop(context);
  }

  // 提取 Navigator.canPop 为独立方法，避免重复调用
  bool _canPop(BuildContext context) {
    return Navigator.canPop(context);
  }

  // 检查设备方向是否改变，优化延迟逻辑以提升响应速度
  Future<bool> _checkOrientationChange(BuildContext context) async {
    final initialOrientation = MediaQuery.of(context).orientation;
    if (MediaQuery.of(context).orientation == initialOrientation) {
      return false;
    }
    await Future.delayed(AppConstants.screenCheckDuration);
    return MediaQuery.of(context).orientation != initialOrientation;
  }

  // 提取主题构建逻辑，并添加缓存
  ThemeData _buildTheme(String? fontFamily) {
    // 修改代码开始：使用缓存避免重复构建
    if (_themeCache.containsKey(fontFamily)) {
      return _themeCache[fontFamily]!;
    }

    final theme = ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.redAccent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      useMaterial3: true,
    );

    _themeCache[fontFamily] = theme;
    return theme;
    // 修改代码结束
  }

  @override
  Widget build(BuildContext context) {
    return Selector<LanguageProvider, Locale>(
      selector: (_, provider) => provider.currentLocale,
      builder: (context, locale, _) {
        return Selector<ThemeProvider, ({String fontFamily, double textScaleFactor})>(
          selector: (_, provider) => (
            fontFamily: provider.fontFamily,
            textScaleFactor: provider.textScaleFactor
          ),
          builder: _buildMaterialApp,
        );
      },
    );
  }

  // 提取 MaterialApp 的构建逻辑以提高代码维护性
  Widget _buildMaterialApp(
    BuildContext context,
    ({String fontFamily, double textScaleFactor}) data,
    Widget? child
  ) {
    final String? effectiveFontFamily = data.fontFamily == 'system' ? null : data.fontFamily;

    return MaterialApp(
      title: AppConstants.appTitle,
      theme: _buildTheme(effectiveFontFamily),
      locale: Provider.of<LanguageProvider>(context).currentLocale, // 修改代码：直接从 Provider 获取，避免重复定义
      routes: AppRouter.routes,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate
      ],
      supportedLocales: S.delegate.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale == null) {
          return supportedLocales.first;
        }

        // 修改代码开始：简化中文地区处理逻辑，使用映射替代重复判断
        const localeMap = {
          'zh_TW': Locale('zh', 'TW'),
          'zh_HK': Locale('zh', 'TW'),
          'zh_MO': Locale('zh', 'TW'),
          'zh_CN': Locale('zh', 'CN'),
          'zh': Locale('zh', 'CN'),
        };

        final key = locale.countryCode != null
            ? '${locale.languageCode}_${locale.countryCode}'
            : locale.languageCode;

        if (localeMap.containsKey(key)) {
          return localeMap[key];
        }

        return supportedLocales.firstWhere(
          (supportedLocale) =>
              supportedLocale.languageCode == locale.languageCode &&
              (supportedLocale.countryCode == locale.countryCode ||
                  supportedLocale.countryCode == null),
          orElse: () => supportedLocales.first,
        );
        // 修改代码结束
      },
      debugShowCheckedModeBanner: false,
      home: WillPopScope(
        onWillPop: () => _handleBackPress(context),
        child: SplashScreen(),
      ),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(data.textScaleFactor)
          ),
          child: FlutterEasyLoading(child: child),
        );
      },
    );
  }
}
