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
import 'provider/download_provider.dart';
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
  static const String appTitle = 'ITVAPP LIVETV';
  static const Duration screenCheckDuration = Duration(milliseconds: 500);
  static const Size defaultWindowSize = Size(414, 414 * 16 / 9);
  static const Size minimumWindowSize = Size(300, 300 * 9 / 16);
}

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

  // 使用 Future.wait 优化并行初始化操作
  await Future.wait([
    WakelockPlus.enable(),
    SpUtil.getInstance(),
  ]);

  // 初始化主题提供者并确保正确初始化完成
  ThemeProvider themeProvider = ThemeProvider();
  await themeProvider.initialize();

  // 如果当前环境不是移动端
  if (!EnvUtil.isMobile) {
    await _initializeDesktop();
  }

  // 运行应用，并使用 MultiProvider 进行全局状态管理
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: themeProvider),
      ChangeNotifierProvider(create: (_) => DownloadProvider()),
      ChangeNotifierProvider(create: (_) => LanguageProvider()),
    ],
    child: const MyApp(),
  ));

  // 如果当前平台是 Android，设置状态栏为透明
  if (Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent)
    );
  }
}

// 提取桌面端初始化的逻辑以提高代码的维护性
Future<void> _initializeDesktop() async {
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

  @override
  void initState() {
    super.initState();
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _initializeApp();
  }

  // 应用初始化操作
  Future<void> _initializeApp() async {
    await _themeProvider.checkAndSetIsTV(); // 检查并设置设备是否为电视
  }

  // 处理返回键的逻辑，确保正确的退出交互
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_isAtSplashScreen(context)) {
      return await ShowExitConfirm.ExitConfirm(context); // 显示退出确认对话框
    }
    
    final orientationChanged = await _checkOrientationChange(context);
    if (!orientationChanged && !Navigator.canPop(context)) {
      return await ShowExitConfirm.ExitConfirm(context); // 仅在非方向更改和不可弹出导航时退出
    }
    
    return false; // 默认返回 false，不处理返回键
  }

  // 检查当前界面是否是启动画面
  bool _isAtSplashScreen(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    return currentRoute == SplashScreen().toString() || !Navigator.canPop(context);
  }

  // 检查设备方向是否改变
  Future<bool> _checkOrientationChange(BuildContext context) async {
    final initialOrientation = MediaQuery.of(context).orientation;
    await Future.delayed(AppConstants.screenCheckDuration);
    return MediaQuery.of(context).orientation != initialOrientation;
  }

  // 提取主题构建逻辑，提高代码的可维护性
  ThemeData _buildTheme(String? fontFamily) {
    return ThemeData(
      brightness: Brightness.dark, // 设置亮度为暗色
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.redAccent, // 使用种子颜色生成颜色方案
        brightness: Brightness.dark
      ),
      scaffoldBackgroundColor: Colors.black, // 设置背景色为黑色
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true, // 标题居中
      ),
      useMaterial3: true, // 使用Material3设计规范
    );
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
          builder: _buildMaterialApp, // 使用提取的构建逻辑
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
    final languageProvider = Provider.of<LanguageProvider>(context);
    final String? effectiveFontFamily = data.fontFamily == 'system' ? null : data.fontFamily;
    
    return MaterialApp(
      title: AppConstants.appTitle,
      theme: _buildTheme(effectiveFontFamily),
      locale: languageProvider.currentLocale,
      routes: AppRouter.routes,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate
      ],
      supportedLocales: S.delegate.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale != null) {
          // 针对中文地区的特殊处理
          if (locale.languageCode == 'zh' &&
              (locale.countryCode == 'TW' || locale.countryCode == 'HK' || locale.countryCode == 'MO')) {
            return const Locale('zh', 'TW');
          }
          if (locale.languageCode == 'zh' &&
              (locale.countryCode == 'CN' || locale.countryCode == null)) {
            return const Locale('zh', 'CN');
          }
          // 查找支持的地区并返回匹配的地区
          return supportedLocales.firstWhere(
            (supportedLocale) =>
                supportedLocale.languageCode == locale.languageCode &&
                (supportedLocale.countryCode == locale.countryCode ||
                    supportedLocale.countryCode == null),
            orElse: () => supportedLocales.first,
          );
        }
        return supportedLocales.first; // 默认返回第一个支持的地区
      },
      debugShowCheckedModeBanner: false, // 关闭调试模式标志
      home: WillPopScope(
        onWillPop: () => _handleBackPress(context), // 绑定返回键处理函数
        child: SplashScreen(), // 启动画面
      ),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(data.textScaleFactor) // 设置文本缩放因子
          ),
          child: FlutterEasyLoading(child: child), // 包裹子组件以显示加载动画
        );
      },
    );
  }
}
