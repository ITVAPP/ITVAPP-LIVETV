import 'dart:io';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart'; 
import 'package:itvapp_live_tv/setting/setting_font_page.dart';
import 'package:itvapp_live_tv/setting/subscribe_page.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'generated/l10n.dart';
import 'live_home_page.dart';
import 'splash_screen.dart';  // 导入 SplashScreen
import 'provider/download_provider.dart';
import 'router_keys.dart';
import 'setting/setting_beautify_page.dart';
import 'setting/setting_log_page.dart';
import 'setting/setting_page.dart';

// 入口函数，使用 async 关键字确保异步操作可以在程序启动时完成
void main() async {
  // 确保 WidgetsFlutterBinding 已经初始化，必要时会为应用的生命周期提供必要的绑定。
  WidgetsFlutterBinding.ensureInitialized();

  // 如果当前环境不是移动端
  if (!EnvUtil.isMobile) {
    // 初始化窗口管理器（用于桌面端窗口管理）
    await windowManager.ensureInitialized();

    // 设置窗口的选项，如窗口大小、最小大小、是否居中、背景透明等
    WindowOptions windowOptions = const WindowOptions(
      size: Size(414, 414 * 16 / 9), // 窗口初始大小
      minimumSize: Size(300, 300 * 9 / 16), // 窗口最小大小
      center: true, // 窗口居中显示
      backgroundColor: Colors.transparent, // 背景透明
      skipTaskbar: false, // 不从任务栏隐藏
      titleBarStyle: TitleBarStyle.hidden, // 隐藏标题栏
      title: 'ITVAPP LIVETV', // 窗口标题
    );

    try {
      // 等待窗口准备好后展示并聚焦
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show(); // 显示窗口
        await windowManager.focus(); // 聚焦窗口
      });
    } catch (e, stackTrace) {
      LogUtil.logError('初始化窗口时出错', e, stackTrace); // 捕获并记录窗口初始化时的错误
    }
  }

  // 启用 WakelockPlus 以防止屏幕锁定（用于移动设备）
  WakelockPlus.enable();

  try {
    // 初始化共享存储的工具实例，用于管理存储操作
    await SpUtil.getInstance();
  } catch (e, stackTrace) {
    LogUtil.logError('初始化 SpUtil 时出错', e, stackTrace); // 捕获并记录 SpUtil 初始化时的错误
  }

  try {
    // 注册 FVP 播放器，支持不同平台和解码器
    fvp.registerWith(options: {
      'platforms': ['android', 'ios'], // 支持的平台
      'video.decoders': ['FFmpeg'] // 使用 FFmpeg 进行视频解码
    });
  } catch (e, stackTrace) {
    LogUtil.logError('注册 FVP 播放器时出错', e, stackTrace); // 捕获并记录 FVP 播放器注册时的错误
  }

  // 运行应用，并使用 MultiProvider 来进行全局状态管理
  runApp(MultiProvider(
    providers: [
      // 状态管理：主题提供者
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      // 状态管理：下载管理提供者
      ChangeNotifierProvider(create: (_) => DownloadProvider()),
      // 状态管理：语言提供者
      ChangeNotifierProvider(create: (_) => LanguageProvider()),
    ],
    // 指定应用的根 widget 为 MyApp
    child: const MyApp(),
  ));

  // 如果当前平台是 Android，设置状态栏为透明
  if (Platform.isAndroid) {
    try {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
    } catch (e, stackTrace) {
      LogUtil.logError('设置 Android 系统栏样式时出错', e, stackTrace); // 捕获并记录设置系统栏样式时的错误
    }
  }
}

// 应用的主界面
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 获取当前语言设置
    final languageProvider = Provider.of<LanguageProvider>(context);

    // 使用 Selector 来监听主题相关的状态，并根据字体和文本缩放比例进行更新
    return Selector<ThemeProvider, ({String fontFamily, double textScaleFactor})>(
      selector: (_, provider) => (fontFamily: provider.fontFamily, textScaleFactor: provider.textScaleFactor),
      builder: (context, data, child) {
        // 如果字体设置为 'system'，使用默认字体
        String? fontFamily = data.fontFamily;
        if (fontFamily == 'system') {
          fontFamily = null;
        }

        // 返回 MaterialApp，配置应用的主题、语言、路由等
        return MaterialApp(
          title: 'ITVAPP LIVETV', // 应用标题

          // 设置应用的主题，包括亮度、颜色方案、字体和其他 UI 样式
          theme: ThemeData(
            brightness: Brightness.dark, // 使用暗色主题
            fontFamily: fontFamily, // 设置字体
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent, brightness: Brightness.dark), // 基于种子颜色生成色系
            scaffoldBackgroundColor: Colors.black, // 背景色设为黑色
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.black, // AppBar 背景色
              foregroundColor: Colors.white, // AppBar 文字颜色
              elevation: 0, // 移除阴影
              centerTitle: true, // 标题居中
            ),
            useMaterial3: true, // 使用 Material Design 3
          ),

          // 设置应用的语言
          locale: languageProvider.currentLocale,

          // 定义路由配置
          routes: {
            RouterKeys.subScribe: (BuildContext context) => const SubScribePage(), // 订阅页面
            RouterKeys.setting: (BuildContext context) => const SettingPage(), // 设置页面
            RouterKeys.settingFont: (BuildContext context) => const SettingFontPage(), // 字体设置页面
            RouterKeys.settingBeautify: (BuildContext context) => const SettingBeautifyPage(), // 美化设置页面
            RouterKeys.settinglog: (BuildContext context) => SettinglogPage(), // 日志查看页面
          },

          // 本地化代理，支持多语言
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],

          // 支持的语言列表
          supportedLocales: S.delegate.supportedLocales,

          // 语言回调，用于处理特定语言和地区的逻辑
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale != null) {
              // 处理中文的特殊区域
              if (locale.languageCode == 'zh' &&
                  (locale.countryCode == 'TW' || locale.countryCode == 'HK' || locale.countryCode == 'MO')) {
                return const Locale('zh', 'TW'); // 繁体中文
              }
              // 处理简体中文
              if (locale.languageCode == 'zh' && (locale.countryCode == 'CN' || locale.countryCode == null)) {
                return const Locale('zh', 'CN'); // 简体中文
              }
              // 匹配合适的语言和国家代码
              return supportedLocales.firstWhere(
                (supportedLocale) =>
                    supportedLocale.languageCode == locale.languageCode &&
                    (supportedLocale.countryCode == locale.countryCode || supportedLocale.countryCode == null),
                orElse: () => supportedLocales.first,
              );
            }
            return supportedLocales.first; // 默认使用第一个支持的语言
          },

          // 隐藏调试标志
          debugShowCheckedModeBanner: false,

          // 使用 SplashScreen 作为启动页
          home: SplashScreen(),

          // 全局构建器，处理文本缩放和加载动画
          builder: (context, child) {
            return Stack(
              children: [
                MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(data.textScaleFactor)),
                  child: FlutterEasyLoading(child: child),
                ),
                // 仅当 debugMode 为 true 时使用 ErrorWidget.builder
                if (LogUtil.debugMode) 
                {
                  // 捕获 Flutter 中的全局错误并显示 ErrorWidget
                  ErrorWidget.builder = (FlutterErrorDetails details) {
                    return Material(
                      color: Colors.redAccent,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error, size: 50, color: Colors.white),
                            const SizedBox(height: 20),
                            Text(
                              '发生错误：${details.exception}',
                              style: const TextStyle(color: Colors.white, fontSize: 18),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamed(context, RouterKeys.settinglog); // 跳转到日志查看页面
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEB144C), // 按钮背景颜色
                                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0), // 按钮内边距
                                shape: RoundedRectangleBorder( // 圆角样式
                                  borderRadius: BorderRadius.circular(10.0), // 设置圆角半径
                                ),
                              ),
                              child: const Text('查看日志'),
                            ),
                          ],
                        ),
                      ),
                    );
                  };
                }
              ],
            );
          },
        );
      },
    );
  }
}
