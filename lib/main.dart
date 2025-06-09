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
import 'package:itvapp_live_tv/router_keys.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/setting/setting_font_page.dart';
import 'package:itvapp_live_tv/setting/subscribe_page.dart';
import 'package:itvapp_live_tv/setting/setting_log_page.dart';
import 'package:itvapp_live_tv/setting/setting_page.dart';
import 'package:itvapp_live_tv/setting/about_page.dart';
import 'package:itvapp_live_tv/setting/agreement_page.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/widget/show_exit_confirm.dart';
import 'package:itvapp_live_tv/live_home_page.dart';
import 'package:itvapp_live_tv/splash_screen.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

/// 应用常量类，管理全局配置
class AppConstants {
  static const double aspectRatio = 16 / 9; // 统一宽高比
  static const String appTitle = 'ITVAPP LIVETV'; // 应用标题
  static const Duration screenCheckDuration = Duration(milliseconds: 500); // 屏幕检查延迟
  static const Size defaultWindowSize = Size(414, 414 / 9 * 16); // 默认窗口大小
  static const Size minimumWindowSize = Size(300, 300 / 9 * 16); // 最小窗口大小
  static const String hardwareAccelerationKey = 'hardware_acceleration_enabled'; // 硬件加速缓存键
  static const int maxConcurrentImageCopy = 3; // 最大并发图片复制数

  /// 处理通用错误并记录
  static Future<void> handleError(Future<void> Function() task, String errorMessage) async {
    try {
      await task();
    } catch (e, stack) {
      LogUtil.logError(errorMessage, e, stack);
    }
  }
}

// 全局状态管理器列表
final List<ChangeNotifierProvider> _staticProviders = [
  ChangeNotifierProvider<DownloadProvider>(create: (_) => DownloadProvider()), // 下载状态管理
  ChangeNotifierProvider<LanguageProvider>(create: (_) => LanguageProvider()), // 语言状态管理
];

// 应用目录路径缓存键
const String appDirectoryPathKey = 'app_directory_path';

/// 应用入口，初始化组件
void main() async {
  // 捕获未处理的Flutter异常
  FlutterError.onError = (FlutterErrorDetails details) {
    LogUtil.logError('未捕获的Flutter错误', details.exception, details.stack);
    FlutterError.dumpErrorToConsole(details);
  };

  WidgetsFlutterBinding.ensureInitialized(); // 确保Flutter绑定初始化

  // 初始化SpUtil
  try {
    await SpUtil.getInstance();
    LogUtil.i('SpUtil初始化成功');
  } catch (e, stack) {
    LogUtil.logError('SpUtil初始化失败', e, stack);
  }

  // 初始化主题提供者
  final ThemeProvider themeProvider = ThemeProvider();

  // 并行执行初始化任务
  final List<Future<void>> initTasks = [
    AppConstants.handleError(() => WakelockPlus.enable(), '屏幕常亮初始化失败'),
    AppConstants.handleError(() => themeProvider.initialize(), '主题初始化失败'),
    _initializeImagesDirectory(), // 初始化图片目录
    AppConstants.handleError(() => EpgUtil.init(), 'EPG文件系统初始化失败'),
  ];

  // 桌面端窗口初始化
  if (!EnvUtil.isMobile) {
    initTasks.add(AppConstants.handleError(() => _initializeDesktop(), '桌面窗口初始化失败'));
  }

  // 并行执行初始化任务
  await Future.wait(initTasks);

  // 检查并缓存硬件加速状态
  try {
    bool? isHardwareEnabled = SpUtil.getBool(AppConstants.hardwareAccelerationKey);
    if (isHardwareEnabled == null) {
      isHardwareEnabled = await EnvUtil.isHardwareAccelerationEnabled();
      await SpUtil.putBool(AppConstants.hardwareAccelerationKey, isHardwareEnabled);
      LogUtil.d('硬件加速检测结果: $isHardwareEnabled');
    }
  } catch (e, stackTrace) {
    LogUtil.e('硬件加速检测失败');
    await SpUtil.putBool(AppConstants.hardwareAccelerationKey, false);
  }

  // 启动应用
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

/// 初始化图片目录
Future<void> _initializeImagesDirectory() async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    await SpUtil.putString(appDirectoryPathKey, appDir.path); // 保存应用目录路径
    final savedPath = SpUtil.getString(appDirectoryPathKey);
    if (savedPath != null && savedPath.isNotEmpty) {
      LogUtil.i('保存应用路径成功: $savedPath');
    } else {
      LogUtil.e('保存应用路径失败');
    }

    final imagesDir = Directory('${appDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true); // 创建images目录
      
      // 异步加载manifest
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      final imageAssets = manifestMap.keys
          .where((String key) => key.startsWith('assets/images/'))
          .toList();

      // 并发复制图片
      final List<Future<void>> copyTasks = [];
      for (int i = 0; i < imageAssets.length; i += AppConstants.maxConcurrentImageCopy) {
        final batch = imageAssets.skip(i).take(AppConstants.maxConcurrentImageCopy);
        final batchFuture = Future.wait(
          batch.map((assetPath) => _copyImageFile(assetPath, imagesDir)),
        );
        copyTasks.add(batchFuture);
      }
      
      // 等待所有批次完成
      await Future.wait(copyTasks);
    } else {
      LogUtil.i('images目录已存在: ${imagesDir.path}');
    }
  } catch (e, stackTrace) {
    LogUtil.logError('初始化图片目录失败', e, stackTrace);
  }
}

/// 复制图片文件
Future<void> _copyImageFile(String assetPath, Directory imagesDir) async {
  try {
    final fileName = assetPath.replaceFirst('assets/images/', '');
    final localPath = '${imagesDir.path}/$fileName';
    final localFile = File(localPath);
    
    // 文件已存在则跳过
    if (await localFile.exists()) {
      return;
    }
    
    await localFile.parent.create(recursive: true); // 确保父目录存在
    final byteData = await rootBundle.load(assetPath);
    await localFile.writeAsBytes(byteData.buffer.asUint8List()); // 复制图片
    LogUtil.v('图片复制到: $localPath');
  } catch (e, stackTrace) {
    LogUtil.logError('复制图片失败: $assetPath', e, stackTrace);
  }
}

/// 初始化桌面端窗口
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
    LogUtil.e('桌面窗口初始化失败');
  }
}

/// 应用路由表
class AppRouter {
  static final Map<String, WidgetBuilder> routes = {
    RouterKeys.about: (BuildContext context) => const AboutPage(),
    RouterKeys.subScribe: (BuildContext context) => const SubScribePage(),
    RouterKeys.setting: (BuildContext context) => const SettingPage(),
    RouterKeys.settingFont: (BuildContext context) => const SettingFontPage(),
    RouterKeys.settinglog: (BuildContext context) => SettinglogPage(),
    RouterKeys.agreement: (BuildContext context) => const AgreementPage(),
  };
}

/// 主应用界面，管理主题和语言
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

/// 主应用状态管理
class _MyAppState extends State<MyApp> {
  late final ThemeProvider _themeProvider; // 主题提供者
  final Map<String, ThemeData> _themeCache = {}; // 主题缓存
  static const int _maxThemeCacheSize = 4; // 最大主题缓存数量

  @override
  void initState() {
    super.initState();
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _initializeApp(); // 初始化应用
  }

  /// 检查设备类型
  Future<void> _initializeApp() async {
    await AppConstants.handleError(() => _themeProvider.checkAndSetIsTV(), 'TV设备检查失败');
  }

  /// 处理返回键逻辑
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

  /// 判断是否在启动界面
  bool _isAtSplashScreen(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    return currentRoute == SplashScreen().toString() || !_canPop(context);
  }

  /// 检查导航器是否可返回
  bool _canPop(BuildContext context) {
    return Navigator.canPop(context);
  }

  /// 检查屏幕方向变化
  Future<bool> _checkOrientationChange(BuildContext context) async {
    final initialOrientation = MediaQuery.of(context).orientation;
    if (MediaQuery.of(context).orientation == initialOrientation) {
      return false;
    }
    await Future.delayed(AppConstants.screenCheckDuration);
    return MediaQuery.of(context).orientation != initialOrientation;
  }
  
  // 语言映射表
  static const Map<String, Locale> _localeMap = {
    'zh_TW': Locale('zh', 'TW'),
    'zh_HK': Locale('zh', 'TW'),
    'zh_MO': Locale('zh', 'TW'),
    'zh_CN': Locale('zh', 'CN'),
    'zh': Locale('zh', 'CN'),
  };

  /// 构建并缓存主题数据
  ThemeData _buildTheme(String? fontFamily) {
    final cacheKey = fontFamily ?? 'system';
    
    if (_themeCache.containsKey(cacheKey)) {
      return _themeCache[cacheKey]!;
    }

    if (_themeCache.length >= _maxThemeCacheSize) {
      _themeCache.remove(_themeCache.keys.first);
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

  /// 构建MaterialApp界面
  Widget _buildMaterialApp(
    BuildContext context,
    ({String fontFamily, double textScaleFactor}) data,
    Widget? child
  ) {
    final String? effectiveFontFamily = data.fontFamily == 'system' ? null : data.fontFamily;
    
    // 获取设备类型和是否有用户设置
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final bool hasUserFontScale = SpUtil.containsKey('fontScale') ?? false;
    
    // TV设备且用户未设置字体大小时，保存1.2并使用
    double effectiveTextScale = data.textScaleFactor;
    if (themeProvider.isTV && !hasUserFontScale) {
      effectiveTextScale = 1.2;
      // 模拟用户设置，保存到SP
      SpUtil.putDouble('fontScale', 1.2);
      LogUtil.d('TV设备首次使用，自动设置字体缩放为1.2');
    }

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

        final key = locale.countryCode != null
            ? '${locale.languageCode}_${locale.countryCode}'
            : locale.languageCode;

        if (_localeMap.containsKey(key)) {
          return _localeMap[key];
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
            textScaler: TextScaler.linear(effectiveTextScale) // 使用计算后的值
          ),
          child: FlutterEasyLoading(child: child),
        );
      },
    );
  }
}
