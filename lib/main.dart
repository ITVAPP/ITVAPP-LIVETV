import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sp_util/sp_util.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
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
import 'package:itvapp_live_tv/setting/setting_log_page.dart';
import 'package:itvapp_live_tv/setting/setting_page.dart';
import 'package:itvapp_live_tv/about_page.dart';  // 添加 AboutPage 导入

// 定义应用常量类，集中管理全局配置
class AppConstants {
  static const double aspectRatio = 16 / 9; // 统一宽高比，避免重复计算
  static const String appTitle = 'ITVAPP LIVETV'; // 应用标题
  static const Duration screenCheckDuration = Duration(milliseconds: 500); // 屏幕检查延迟时间
  static const Size defaultWindowSize = Size(414, 414 / 9 * 16); // 默认窗口大小
  static const Size minimumWindowSize = Size(300, 300 / 9 * 16); // 最小窗口大小
  static const String hardwareAccelerationKey = 'hardware_acceleration_enabled'; // 硬件加速缓存键

  // 通用错误处理方法，记录并处理异常
  static Future<void> handleError(Future<void> Function() task, String errorMessage) async {
    try {
      await task();
    } catch (e, stack) {
      LogUtil.logError(errorMessage, e, stack);
    }
  }
}

// 全局状态管理器列表，提供下载和语言功能
final List<ChangeNotifierProvider> _staticProviders = [
  ChangeNotifierProvider<DownloadProvider>(create: (_) => DownloadProvider()), // 下载状态管理
  ChangeNotifierProvider<LanguageProvider>(create: (_) => LanguageProvider()), // 语言状态管理
];

// 应用目录路径缓存键
const String appDirectoryPathKey = 'app_directory_path';

// 应用入口，异步初始化必要组件
void main() async {
  // 捕获未处理的Flutter异常并记录
  FlutterError.onError = (FlutterErrorDetails details) {
    LogUtil.logError('未捕获的Flutter错误', details.exception, details.stack);
    FlutterError.dumpErrorToConsole(details);
  };

  WidgetsFlutterBinding.ensureInitialized(); // 确保Flutter绑定初始化

  // 初始化SpUtil以支持缓存操作
  try {
    await SpUtil.getInstance();
    LogUtil.i('SpUtil初始化成功');
  } catch (e, stack) {
    LogUtil.logError('SpUtil初始化失败', e, stack);
  }

  // 初始化默认通知图片，复制assets/images目录
  try {
    final appDir = await getApplicationDocumentsDirectory();
    await SpUtil.putString(appDirectoryPathKey, appDir.path); // 保存应用目录路径
    final savedPath = SpUtil.getString(appDirectoryPathKey);
    if (savedPath != null && savedPath.isNotEmpty) {
      LogUtil.i('应用路径保存成功: $savedPath');
    } else {
      LogUtil.e('应用路径保存失败');
    }

    final imagesDir = Directory('${appDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true); // 创建images目录
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      final imageAssets = manifestMap.keys
          .where((String key) => key.startsWith('assets/images/'))
          .toList();

      for (final assetPath in imageAssets) {
        final fileName = assetPath.replaceFirst('assets/images/', '');
        final localPath = '${imagesDir.path}/$fileName';
        final localFile = File(localPath);
        await localFile.parent.create(recursive: true); // 确保父目录存在
        final byteData = await rootBundle.load(assetPath);
        await localFile.writeAsBytes(byteData.buffer.asUint8List()); // 复制图片
        LogUtil.i('图片复制到: $localPath');
      }
    } else {
      LogUtil.i('images目录已存在: ${imagesDir.path}');
    }
  } catch (e, stackTrace) {
    LogUtil.logError('初始化images目录失败', e, stackTrace);
  }

  // 初始化主题提供者
  final ThemeProvider themeProvider = ThemeProvider();

  // 并行执行初始化任务
  await Future.wait([
    AppConstants.handleError(() => WakelockPlus.enable(), '屏幕常亮初始化失败'),
    AppConstants.handleError(() => themeProvider.initialize(), '主题初始化失败'),
  ]);

  // 初始化EPG文件系统并清理过期数据
  await AppConstants.handleError(() => EpgUtil.init(), 'EPG文件系统初始化失败');

  if (!EnvUtil.isMobile) {
    await _initializeDesktop(); // 初始化桌面端窗口
  }

  // 检查并缓存硬件加速状态
  try {
    bool? isHardwareEnabled = SpUtil.getBool(AppConstants.hardwareAccelerationKey);
    if (isHardwareEnabled == null) {
      isHardwareEnabled = await EnvUtil.isHardwareAccelerationEnabled();
      await SpUtil.putBool(AppConstants.hardwareAccelerationKey, isHardwareEnabled);
      LogUtil.d('硬件加速检测结果: $isHardwareEnabled');
    }
  } catch (e, stackTrace) {
    LogUtil.e('硬件加速检测失败: ${e.toString()}');
    await SpUtil.putBool(AppConstants.hardwareAccelerationKey, false);
  }

  // 启动应用并配置状态管理
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: themeProvider), // 主题状态管理
      ..._staticProviders, // 扩展静态提供者
    ],
    child: const MyApp(),
  ));

  // 设置移动端透明状态栏
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
  }
}

// 初始化桌面端窗口配置
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

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      try {
        await Future.wait([
          windowManager.show(),
          windowManager.focus(),
        ]);
      } catch (e, stack) {
        LogUtil.e('窗口显示或聚焦失败');
      }
    });
  } catch (e, stackTrace) {
    LogUtil.e('桌面窗口初始化失败: ${e.toString()}');
  }
}

// 定义应用路由表
class AppRouter {
  static final Map<String, WidgetBuilder> routes = {
    RouterKeys.about: (BuildContext context) => const AboutPage(),
    RouterKeys.subScribe: (BuildContext context) => const SubScribePage(),
    RouterKeys.setting: (BuildContext context) => const SettingPage(),
    RouterKeys.settingFont: (BuildContext context) => const SettingFontPage(),
    RouterKeys.settinglog: (BuildContext context) => SettinglogPage(),
  };
}

// 主应用界面，管理主题和语言状态
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ThemeProvider _themeProvider; // 主题提供者
  final Map<String, ThemeData> _themeCache = {}; // 主题缓存

  @override
  void initState() {
    super.initState();
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _initializeApp(); // 初始化应用
  }

  // 异步检查设备类型
  Future<void> _initializeApp() async {
    await AppConstants.handleError(() => _themeProvider.checkAndSetIsTV(), 'TV设备检查失败');
  }

  // 处理返回键逻辑
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_isAtSplashScreen(context)) {
      return await ShowExitConfirm.ExitConfirm(context);
    }

    final orientationChanged = await _checkOrientationChange(context);
    if (!orientationChanged && !_canPop(context)) {
      return await ShowExitConfirm.ExitConfirm(context);
    }

    return false;
  }

  // 判断是否在启动界面
  bool _isAtSplashScreen(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    return currentRoute == SplashScreen().toString() || !_canPop(context);
  }

  // 检查导航器是否可返回
  bool _canPop(BuildContext context) {
    return Navigator.canPop(context);
  }

  // 检查屏幕方向变化
  Future<bool> _checkOrientationChange(BuildContext context) async {
    final initialOrientation = MediaQuery.of(context).orientation;
    if (MediaQuery.of(context).orientation == initialOrientation) {
      return false;
    }
    await Future.delayed(AppConstants.screenCheckDuration);
    return MediaQuery.of(context).orientation != initialOrientation;
  }

  // 构建主题数据并缓存
  ThemeData _buildTheme(String? fontFamily) {
    final cacheKey = fontFamily ?? 'system';
    if (_themeCache.containsKey(cacheKey)) {
      return _themeCache[cacheKey]!;
    }

    final theme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      useMaterial3: true,
      fontFamily: fontFamily,
    );

    _themeCache[cacheKey] = theme;
    return theme;
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

  // 构建MaterialApp核心界面
  Widget _buildMaterialApp(
    BuildContext context,
    ({String fontFamily, double textScaleFactor}) data,
    Widget? child
  ) {
    final String? effectiveFontFamily = data.fontFamily == 'system' ? null : data.fontFamily;

    return MaterialApp(
      title: AppConstants.appTitle,
      theme: _buildTheme(effectiveFontFamily),
      locale: Provider.of<LanguageProvider>(context).currentLocale,
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
      },
      debugShowCheckedModeBanner: false,
      home: WillPopScope(
        onWillPop: () => _handleBackPress(context),
        child: const SplashScreen(),
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
