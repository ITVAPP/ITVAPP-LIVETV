import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sp_util/sp_util.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

/// 全局配置常量
class AppConstants {
  /// 应用统一宽高比
  static const double aspectRatio = 16 / 9;
  /// 应用标题
  static const String appTitle = 'ITVAPP LIVETV';
  /// 最大并发图片复制数
  static const int maxConcurrentImageCopy = 3;

  /// 处理通用错误并记录日志
  static Future<void> handleError(Future<void> Function() task, String errorMessage) async {
    try {
      await task();
    } catch (e, stack) {
      LogUtil.logError(errorMessage, e, stack);
    }
  }
}

/// 初始化应用核心组件
void main() async {
  /// 捕获未处理的 Flutter 异常
  FlutterError.onError = (FlutterErrorDetails details) {
    LogUtil.logError('未捕获的 Flutter 错误', details.exception, details.stack);
    FlutterError.dumpErrorToConsole(details);
  };

  WidgetsFlutterBinding.ensureInitialized();

  /// 并行初始化核心组件并显示启动界面
  final futures = <Future>[];
  
  /// 初始化 SpUtil
  futures.add(SpUtil.getInstance());
  
  /// 初始化 ThemeProvider
  final themeProvider = ThemeProvider();
  futures.add(themeProvider.initialize());
  
  /// 提前创建其他 Provider 实例（延迟初始化）
  final downloadProvider = DownloadProvider();
  final languageProvider = LanguageProvider();

  /// 快速启动 - 使用优化后的单次 runApp
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEB144C)),
        ),
      ),
    ),
  ));

  /// 等待核心组件初始化完成
  await Future.wait(futures);

  /// 启动完整应用
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: themeProvider),
      ChangeNotifierProvider.value(value: downloadProvider),
      ChangeNotifierProvider.value(value: languageProvider),
    ],
    child: const MyApp(),
  ));

  /// 执行延迟初始化任务
  _performDeferredInitialization();
}

/// 执行延迟初始化任务
Future<void> _performDeferredInitialization() async {
  final List<Future<void>> initTasks = [
    AppConstants.handleError(() => WakelockPlus.enable(), '屏幕常亮初始化失败'),
    _initializeImagesDirectoryAsync(),
    AppConstants.handleError(() => EpgUtil.init(), 'EPG 文件系统初始化失败'),
  ];

  await Future.wait(initTasks);

  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
  }
}

/// 异步初始化图片目录
Future<void> _initializeImagesDirectoryAsync() async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    await SpUtil.putString('app_directory_path', appDir.path);

    Future.microtask(() async {
      try {
        final imagesDir = Directory('${appDir.path}/images');
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
          await _copyAllImages(imagesDir);
        }
      } catch (e, stack) {
        LogUtil.logError('图片复制失败', e, stack);
      }
    });
  } catch (e, stackTrace) {
    LogUtil.logError('图片目录初始化失败', e, stackTrace);
  }
}

/// 复制所有图片到指定目录
Future<void> _copyAllImages(Directory imagesDir) async {
  final manifestContent = await rootBundle.loadString('AssetManifest.json');
  final Map<String, dynamic> manifestMap = json.decode(manifestContent);
  final imageAssets = manifestMap.keys
      .where((String key) => key.startsWith('assets/images/'))
      .toList();

  final List<Future<void>> copyTasks = [];
  for (int i = 0; i < imageAssets.length; i += AppConstants.maxConcurrentImageCopy) {
    final batch = imageAssets.skip(i).take(AppConstants.maxConcurrentImageCopy);
    final batchFuture = Future.wait(
      batch.map((assetPath) => _copyImageFile(assetPath, imagesDir)),
      eagerError: false,
    );
    copyTasks.add(batchFuture);
  }

  await Future.wait(copyTasks, eagerError: false);
}

/// 复制图片文件到指定目录
Future<void> _copyImageFile(String assetPath, Directory imagesDir) async {
  try {
    final fileName = assetPath.replaceFirst('assets/images/', '');
    final localPath = '${imagesDir.path}/$fileName';
    final localFile = File(localPath);

    if (await localFile.exists()) {
      return;
    }

    await localFile.parent.create(recursive: true);
    final byteData = await rootBundle.load(assetPath);
    await localFile.writeAsBytes(byteData.buffer.asUint8List());
  } catch (e, stackTrace) {
    LogUtil.logError('图片复制失败: $assetPath', e, stackTrace);
  }
}

/// 应用路由管理
class AppRouter {
  /// 路由映射表
  static final Map<String, WidgetBuilder> routes = {
    RouterKeys.about: (BuildContext context) => const AboutPage(),
    RouterKeys.subScribe: (BuildContext context) => const SubScribePage(),
    RouterKeys.setting: (BuildContext context) => const SettingPage(),
    RouterKeys.settingFont: (BuildContext context) => const SettingFontPage(),
    RouterKeys.settinglog: (BuildContext context) => SettinglogPage(),
    RouterKeys.agreement: (BuildContext context) => const AgreementPage(),
  };
}

/// 主应用界面，管理主题和语言切换
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

/// 主应用状态管理
class _MyAppState extends State<MyApp> {
  /// 主题管理器
  late final ThemeProvider _themeProvider;
  /// 缓存的TV模式状态
  late final bool _isTV;

  @override
  void initState() {
    super.initState();
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    /// 初始化应用设备类型
    _initializeApp();
  }

  /// 初始化应用设备类型
  Future<void> _initializeApp() async {
    await AppConstants.handleError(() async {
      await _themeProvider.checkAndSetIsTV();
      _isTV = _themeProvider.isTV;
    }, '设备类型检查失败');
  }

  /// 处理返回键逻辑，区分TV和非TV模式
  Future<bool> _handleBackPress(BuildContext context) async {
    if (_isAtSplashScreen(context)) {
      return await ShowExitConfirm.ExitConfirm(context);
    }

    /// TV模式下跳过方向检查
    if (_isTV) {
      if (!_canPop(context)) {
        return await ShowExitConfirm.ExitConfirm(context);
      }
      return false;
    }

    /// 非TV模式保留原有逻辑
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

  /// 检查屏幕方向变化（仅非TV模式使用）
  Future<bool> _checkOrientationChange(BuildContext context) async {
    const orientationCheckDelay = Duration(milliseconds: 500);
    final initialOrientation = MediaQuery.of(context).orientation;
    await Future.delayed(orientationCheckDelay);
    final currentOrientation = MediaQuery.of(context).orientation;
    return currentOrientation != initialOrientation;
  }

  /// 语言映射表
  static const Map<String, Locale> _localeMap = {
    'zh_TW': Locale('zh', 'TW'),
    'zh_HK': Locale('zh', 'TW'),
    'zh_MO': Locale('zh', 'TW'),
    'zh_CN': Locale('zh', 'CN'),
    'zh': Locale('zh', 'CN'),
  };

  /// 构建主题数据
  ThemeData _buildTheme(String? fontFamily) {
    return ThemeData(
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

  /// 构建 MaterialApp 界面
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
            textScaler: TextScaler.linear(data.textScaleFactor)
          ),
          child: FlutterEasyLoading(child: child),
        );
      },
    );
  }
}
