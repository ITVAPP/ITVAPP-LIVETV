import 'dart:convert';
import 'dart:io';
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
import 'package:itvapp_live_tv/util/zhConverter.dart';
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
  
  /// 中文转换器
  ZhConverter? _s2tConverter; // 简体转繁体中文转换器
  ZhConverter? _t2sConverter; // 繁体转简体中文转换器
  bool _zhConvertersInitializing = false; // 中文转换器是否正在初始化
  bool _zhConvertersInitialized = false; // 中文转换器初始化完成标识
  
  /// 启动图路径常量
  static const String _portraitImage = 'assets/images/launch_image.png';
  static const String _landscapeImage = 'assets/images/launch_image_land.png';
  static const Color _primaryColor = Color(0xFFEB144C);
  static const Color _backgroundColor = Color(0xFF1A1A1A);
  
  /// 加载指示器组件
  static const _loadingIndicator = CircularProgressIndicator(
    valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
    strokeWidth: 4.0,
  );
  /// 垂直间距组件
  static const _verticalSpacing = SizedBox(height: 18);
  /// 提示条显示时长
  static const _snackBarDuration = Duration(seconds: 5);

  /// 状态缓存
  bool? _cachedIsTV;
  bool? _isInForceUpdateState;
  Locale? _cachedUserLocale;
  DateTime? _lastUpdateTime;
  
  /// 节流间隔
  static const _debounceDuration = Duration(milliseconds: 500);
  
  /// 语言转换映射表
  static const Map<String, Map<String, String>> _languageConversionMap = {
    'zh_CN': {'zh_TW': 'zhHans2Hant'},
    'zh_TW': {'zh_CN': 'zhHant2Hans'},
  };

  /// 初始化任务取消标志
  bool _isCancelled = false;
  /// 导航完成标志，防止重复导航
  bool _hasNavigated = false;
  
  /// 异步任务的Future引用
  Future<Map<String, dynamic>?>? _locationFuture;
  Future<void>? _zhConvertersFuture;

  @override
  void initState() {
    super.initState();
    /// 缓存 TV 模式状态
    _cachedIsTV = context.read<ThemeProvider>().isTV;
    /// 启动应用初始化
    _initializeApp();
  }

  @override
  void dispose() {
    _isCancelled = true;
    _s2tConverter = null;
    _t2sConverter = null;
    super.dispose();
  }

  /// 检查是否可继续执行
  bool _canContinue() => !_isCancelled && mounted;

  /// 获取强制更新状态
  bool _getForceUpdateState() {
    _isInForceUpdateState ??= CheckVersionUtil.isInForceUpdateState();
    return _isInForceUpdateState!;
  }

  /// 初始化繁简体中文转换器
  Future<void> _initializeZhConverters() async {
    if (_zhConvertersInitialized || _zhConvertersInitializing) return;
    _zhConvertersInitializing = true;
    try {
      await Future.wait([
        if (_s2tConverter == null) (_s2tConverter = ZhConverter('s2t')).initialize(),
        if (_t2sConverter == null) (_t2sConverter = ZhConverter('t2s')).initialize(),
      ]);
      _zhConvertersInitialized = true;
    } catch (e) {
      LogUtil.e('中文转换器初始化失败: $e');
    } finally {
      _zhConvertersInitializing = false;
    }
  }

  /// 根据用户地理位置信息对播放列表进行智能排序 - 优化版本
  Future<void> _sortVideoMap(PlaylistModel videoMap, Map<String, dynamic>? userInfo) async {
    if (videoMap.playList?.isEmpty ?? true) return;
    
    String? regionPrefix;
    String? cityPrefix;
    
    // 解析用户地理信息（不进行转换，使用原始数据）
    if (userInfo != null) {
      try {
        final Map<String, dynamic>? locationData = userInfo['location'];
        if (locationData != null) {
          String? region = locationData['region'] as String?;
          String? city = locationData['city'] as String?;
          
          if ((region?.isNotEmpty ?? false) || (city?.isNotEmpty ?? false)) {
            regionPrefix = (region?.length ?? 0) >= 2 ? region!.substring(0, 2) : region;
            cityPrefix = (city?.length ?? 0) >= 2 ? city!.substring(0, 2) : city;
            LogUtil.i('地理信息: 地区=$regionPrefix, 城市=$cityPrefix');
          }
        } else {
          LogUtil.i('无location字段');
        }
      } catch (e) {
        LogUtil.e('解析地理信息失败: $e');
      }
    } else {
      LogUtil.i('无地理信息');
    }
    
    if (regionPrefix?.isEmpty ?? true) {
      LogUtil.i('无地区前缀，跳过排序');
      return;
    }
    
    // 优化后的排序算法 - 从 O(n³) 降至 O(n)
    videoMap.playList!.forEach((category, groups) {
      if (groups is! Map<String, Map<String, PlayModel>>) {
        LogUtil.e('分类 $category 类型无效');
        return;
      }
      
      // 保持原始逻辑：先检查是否需要排序（使用 contains）
      final groupList = groups.keys.toList();
      bool categoryNeedsSort = groupList.any((group) => group.contains(regionPrefix!));
      if (!categoryNeedsSort) return;
      
      // 使用两个列表进行分区，避免多次遍历
      final List<MapEntry<String, Map<String, PlayModel>>> matchedGroups = [];
      final List<MapEntry<String, Map<String, PlayModel>>> otherGroups = [];
      
      // 一次遍历完成分区（使用 startsWith 进行实际分组）
      groups.entries.forEach((entry) {
        if (entry.key.startsWith(regionPrefix!)) {
          // 如果需要城市级别排序，在这里处理
          if (cityPrefix?.isNotEmpty ?? false) {
            final channels = entry.value;
            if (channels is Map<String, PlayModel>) {
              // 对频道进行城市级别排序
              final sortedChannels = _sortChannelsByCity(channels, cityPrefix!);
              matchedGroups.add(MapEntry(entry.key, sortedChannels));
            } else {
              matchedGroups.add(entry);
            }
          } else {
            matchedGroups.add(entry);
          }
        } else {
          otherGroups.add(entry);
        }
      });
      
      // 如果没有匹配的组，跳过
      if (matchedGroups.isEmpty) return;
      
      // 重建groups - 匹配的组排在前面
      final newGroups = <String, Map<String, PlayModel>>{};
      
      // 先添加匹配的组
      for (var entry in matchedGroups) {
        newGroups[entry.key] = entry.value;
      }
      
      // 再添加其他组
      for (var entry in otherGroups) {
        newGroups[entry.key] = entry.value;
      }
      
      videoMap.playList![category] = newGroups;
      LogUtil.i('分类 $category 排序完成');
    });
  }
  
  /// 按城市前缀排序频道 - 辅助方法
  Map<String, PlayModel> _sortChannelsByCity(Map<String, PlayModel> channels, String cityPrefix) {
    final List<MapEntry<String, PlayModel>> matchedChannels = [];
    final List<MapEntry<String, PlayModel>> otherChannels = [];
    
    // 一次遍历完成分区
    channels.entries.forEach((entry) {
      if (entry.key.startsWith(cityPrefix)) {
        matchedChannels.add(entry);
      } else {
        otherChannels.add(entry);
      }
    });
    
    // 如果没有匹配的频道，直接返回原始数据
    if (matchedChannels.isEmpty) {
      return channels;
    }
    
    // 重建排序后的频道Map
    final sortedChannels = <String, PlayModel>{};
    
    // 先添加匹配的频道
    for (var entry in matchedChannels) {
      sortedChannels[entry.key] = entry.value;
    }
    
    // 再添加其他频道
    for (var entry in otherChannels) {
      sortedChannels[entry.key] = entry.value;
    }
    
    return sortedChannels;
  }

  /// 初始化应用，协调数据加载与页面跳转
  Future<void> _initializeApp() async {
    if (!_canContinue()) return;
    
    try {
      await LogUtil.safeExecute(() async {
        // 步骤1: 立即启动异步任务（不等待）
        _startAsyncTasks();
        
        // 步骤2: 执行版本检查并处理更新
        await _checkVersionAndHandle();
        
        if (!_canContinue()) return;
        
        // 如果是强制更新，不会执行到这里（在_checkVersionAndHandle中已处理）
        if (_getForceUpdateState()) {
          return;
        }
        
        // 步骤3: 获取M3U数据
        final m3uResult = await _fetchData();
        
        if (!_canContinue()) return;
        
        /// 数据就绪后进行地理排序并跳转主页
        if (m3uResult.data != null) {
          // 获取地理位置信息（如果已完成）
          Map<String, dynamic>? userInfo;
          try {
            if (_locationFuture != null) {
              userInfo = await _locationFuture!.timeout(
                const Duration(milliseconds: 100),
                onTimeout: () => null,
              );
            }
          } catch (e) {
            LogUtil.i('地理位置获取未完成，跳过排序');
          }
          
          // 使用获取到的地理信息进行排序
          await _sortVideoMap(m3uResult.data!, userInfo);
          
          if (!_canContinue()) return;
          
          await _navigateToHome(m3uResult.data!);
        } else {
          _updateMessage(S.current.getm3udataerror);
        }
      }, '应用初始化失败');
    } catch (error, stackTrace) {
      if (_canContinue()) {
        LogUtil.logError('应用初始化失败', error, stackTrace);
        _updateMessage(S.current.getDefaultError);
      }
    }
  }

  /// 启动异步任务（不等待完成）
  void _startAsyncTasks() {
    // 保存异步任务的Future引用
    _locationFuture = _fetchUserInfo();
    _zhConvertersFuture = _initializeZhConverters();
  }

  /// 检查版本并处理更新逻辑
  Future<void> _checkVersionAndHandle() async {
    if (!_canContinue()) return;
    
    try {
      _updateMessage('检查版本更新...');
      
      // 直接调用 checkRelease 获取版本信息，避免被 shouldShowPrompt 跳过
      final versionEntity = await CheckVersionUtil.checkRelease(false, false);
      
      if (!_canContinue()) return;
      
      // 更新强制更新状态
      _isInForceUpdateState = CheckVersionUtil.isInForceUpdateState();
      
      // 如果需要更新
      if (versionEntity != null && mounted) {
        if (_getForceUpdateState()) {
          // 强制更新，进入循环处理
          await _handleForceUpdateLoop();
          // 这里不会返回，会一直在循环中
        } else {
          // 普通更新，显示一次弹窗
          final result = await CheckVersionUtil.showUpdateDialog(context);
          
          // 等待弹窗完全关闭
          await Future.delayed(const Duration(milliseconds: 500));

          // 保存提示日期
          await CheckVersionUtil.saveLastPromptDate();
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('版本检查处理失败', e, stackTrace);
      // 版本检查失败不影响应用启动
    }
  }

  /// 处理强制更新循环
  Future<void> _handleForceUpdateLoop() async {
    _updateMessage(S.current.oldVersion);
    
    // 持续显示强制更新弹窗
    while (_canContinue() && _getForceUpdateState()) {
      try {
        // 显示更新弹窗
        final result = await CheckVersionUtil.showUpdateDialog(context);
        
        // 等待一段时间再重新显示
        await Future.delayed(const Duration(milliseconds: 500));
        
        // 如果弹窗被关闭，显示提示
        if (result != true && mounted) {
          CustomSnackBar.showSnackBar(
            context, 
            S.current.oldVersion,
            duration: const Duration(seconds: 3),
          );
        }
      } catch (e) {
        LogUtil.e('强制更新弹窗显示失败: $e');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// 获取用户地理位置与设备信息
  Future<Map<String, dynamic>?> _fetchUserInfo() async {
    if (!_canContinue()) return null;
    
    try {
      final userInfo = await _locationService.getUserAllInfo(context);
      return userInfo;
    } catch (error, stackTrace) {
      LogUtil.logError('用户信息获取失败', error, stackTrace);
      return null;
    }
  }

  /// 获取 M3U 数据
  Future<M3uResult> _fetchData() async {
    if (_isCancelled) return M3uResult(errorMessage: '操作已取消');
    
    try {
      _updateMessage(S.current.getm3udata);
      // 直接调用 getDefaultM3uData，不再传递 onRetry 回调
      final result = await M3uUtil.getDefaultM3uData();
      
      if (_isCancelled) return M3uResult(errorMessage: '操作已取消');
      
      if (result.data != null) {
        return result;
      } else {
        _updateMessage(S.current.getm3udataerror);
        return M3uResult(errorMessage: result.errorMessage ?? '未知错误');
      }
    } catch (e, stackTrace) {
      if (!_isCancelled && mounted) {
        _updateMessage(S.current.getm3udataerror);
        LogUtil.logError('M3U 数据获取失败', e, stackTrace);
      }
      return M3uResult(errorMessage: e.toString());
    }
  }

  /// 更新提示信息，带节流机制
  void _updateMessage(String message) {
    if (!_canContinue()) return;
    
    final now = DateTime.now();
    if (_lastUpdateTime == null || now.difference(_lastUpdateTime!) >= _debounceDuration) {
      if (mounted) {
        setState(() {
          _message = message;
        });
        _lastUpdateTime = now;
      }
    }
  }

  /// 显示调试日志对话框
  void _showErrorLogs(BuildContext context) {
    if (!_canContinue() || !isDebugMode) return;
    
    DialogUtil.showCustomDialog(
      context,
      title: S.current.logtitle,
      content: 'showlog',
      isCopyButton: true,
    );
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
      LogUtil.logError('用户语言获取失败', e, stackTrace);
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
      // 确定转换器类型
      String converterType;
      if (conversionType == 'zhHans2Hant') {
        converterType = 's2t';
      } else if (conversionType == 'zhHant2Hans') {
        converterType = 't2s';
      } else {
        LogUtil.i('无效转换类型: $conversionType，跳过转换');
        return data;
      }

      if (data.playList.isEmpty) {
        LogUtil.i('播放列表为空，无需转换');
        return data;
      }

      // 确保转换器已初始化
      if (!_zhConvertersInitialized) {
        await _initializeZhConverters();
        if (!_zhConvertersInitialized) {
          LogUtil.e('中文转换器初始化失败，返回原始数据');
          return data;
        }
      }

      // 选择正确的转换器
      final converter = converterType == 's2t' ? _s2tConverter : _t2sConverter;
      if (converter == null) {
        LogUtil.e('转换器为空，返回原始数据');
        return data;
      }
      
      final Map<String, dynamic> originalPlayList = data.playList;
      final Map<String, Map<String, Map<String, PlayModel>>> newPlayList = {};
      final Set<String> textsToConvert = {};
      final Map<String, String> convertCache = {};
      
      // 收集所有需要转换的文本
      for (final categoryEntry in originalPlayList.entries) {
        textsToConvert.add(categoryEntry.key);
        final dynamic groupMapValue = categoryEntry.value;
        
        if (groupMapValue is Map<String, dynamic>) {
          for (final groupEntry in groupMapValue.entries) {
            textsToConvert.add(groupEntry.key);
            final dynamic channelMapValue = groupEntry.value;
            
            if (channelMapValue is Map<String, dynamic>) {
              for (final channelEntry in channelMapValue.entries) {
                textsToConvert.add(channelEntry.key);
                final dynamic playModelValue = channelEntry.value;
                
                if (playModelValue is PlayModel) {
                  if (playModelValue.title?.isNotEmpty ?? false) {
                    textsToConvert.add(playModelValue.title!);
                  }
                  if (playModelValue.group?.isNotEmpty ?? false) {
                    textsToConvert.add(playModelValue.group!);
                  }
                }
              }
            }
          }
        }
      }
      
      // 批量转换文本
      final List<String> textsList = textsToConvert.toList();
      final int batchSize = 100;
      
      for (int i = 0; i < textsList.length; i += batchSize) {
        final int end = (i + batchSize < textsList.length) ? i + batchSize : textsList.length;
        final batch = textsList.sublist(i, end);
        
        final futures = batch.map((text) async {
          if (text.isEmpty) return MapEntry(text, text);
          try {
            final converted = await converter.convert(text);
            return MapEntry(text, converted);
          } catch (e) {
            LogUtil.e('转换失败: $text, 错误: $e');
            return MapEntry(text, text);
          }
        });
        
        final results = await Future.wait(futures);
        for (final entry in results) {
          convertCache[entry.key] = entry.value;
        }
      }
      
      // 构建新的播放列表
      for (final categoryEntry in originalPlayList.entries) {
        final String categoryKey = categoryEntry.key;
        final dynamic groupMapValue = categoryEntry.value;
        
        if (groupMapValue is! Map<String, dynamic>) {
          newPlayList[categoryKey] = <String, Map<String, PlayModel>>{};
          continue;
        }
        
        final String newCategoryKey = convertCache[categoryKey] ?? categoryKey;
        newPlayList[newCategoryKey] = <String, Map<String, PlayModel>>{};
        
        for (final groupEntry in groupMapValue.entries) {
          final String groupKey = groupEntry.key;
          final dynamic channelMapValue = groupEntry.value;
          
          if (channelMapValue is! Map<String, dynamic>) {
            newPlayList[newCategoryKey]![groupKey] = <String, PlayModel>{};
            continue;
          }
          
          final String newGroupKey = convertCache[groupKey] ?? groupKey;
          newPlayList[newCategoryKey]![newGroupKey] = <String, PlayModel>{};
          
          for (final channelEntry in channelMapValue.entries) {
            final String channelKey = channelEntry.key;
            final dynamic playModelValue = channelEntry.value;
            
            if (playModelValue is! PlayModel) {
              continue;
            }
            
            final String newChannelKey = convertCache[channelKey] ?? channelKey;
            final String? newTitle = playModelValue.title != null ? 
                (convertCache[playModelValue.title!] ?? playModelValue.title) : null;
            final String? newGroup = playModelValue.group != null ? 
                (convertCache[playModelValue.group!] ?? playModelValue.group) : null;
            
            final newPlayModel = playModelValue.copyWith(
              title: newTitle,
              group: newGroup
            );
            
            newPlayList[newCategoryKey]![newGroupKey]![newChannelKey] = newPlayModel;
          }
        }
      }
      
      LogUtil.i('中文转换完成: 共转换 ${convertCache.length} 个唯一词条');
      
      return PlaylistModel(
        epgUrl: data.epgUrl,
        playList: newPlayList,
      );
    } catch (error, stackTrace) {
      LogUtil.logError('中文转换失败', error, stackTrace);
      return data;
    }
  }

  /// 执行页面导航至主页 - 使用更安全的导航方式
  void _performNavigation(PlaylistModel data) {
    if (!_canContinue() || _getForceUpdateState() || !context.mounted || _hasNavigated) return;
    
    // 标记已导航，防止重复
    _hasNavigated = true;
    
    // 使用 addPostFrameCallback 确保在当前帧渲染完成后导航
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canContinue() && !_getForceUpdateState() && context.mounted && _hasNavigated) {
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
    if (!_canContinue() || _getForceUpdateState() || _hasNavigated) return;

    try {
      final userLocale = _getUserLocaleFromCache();
      final userLang = _normalizeLanguageCode(userLocale);
      const playListLang = Config.playListlang;
      
      final processedData = await _performChineseConversion(data, playListLang, userLang);
      
      if (!_canContinue() || _getForceUpdateState() || _hasNavigated) return;
      
      // 直接导航，不需要延迟
      _performNavigation(processedData);
    } catch (e, stackTrace) {
      LogUtil.logError('主页跳转失败', e, stackTrace);
      if (!_hasNavigated) {
        _performNavigation(data);
      }
    }
  }

  /// 获取文字样式，适配 TV 模式
  TextStyle _getTextStyle() {
    final double fontSize = (_cachedIsTV ?? false) ? 20.0 : 16.0;
    
    return TextStyle(
      fontSize: fontSize,
      color: Colors.white,
    );
  }

  /// 根据设备类型和屏幕方向选择启动图片
  String _getLaunchImage() {
    /// TV 模式返回横屏图片
    if (_cachedIsTV ?? false) {
      return _landscapeImage;
    }
    
    /// 根据屏幕方向选择图片
    final orientation = MediaQuery.of(context).orientation;
    return orientation == Orientation.portrait 
        ? _portraitImage 
        : _landscapeImage;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          /// 显示启动图片
          Image.asset(
            _getLaunchImage(),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: _backgroundColor);
            },
          ),
          /// 显示加载提示
          _buildMessageUI(
            _message.isEmpty ? S.current.loading : _message,
            isLoading: !_getForceUpdateState(),
          ),
        ],
      ),
      floatingActionButton: isDebugMode
          ? FloatingActionButton(
              onPressed: () => _showErrorLogs(context),
              backgroundColor: _primaryColor,
              child: const Icon(Icons.bug_report),
            )
          : null,
    );
  }

  /// 构建加载提示界面，适配 TV 模式底部间距
  Widget _buildMessageUI(String message, {bool isLoading = false}) {
    final bottomPadding = (_cachedIsTV ?? false) ? 58.0 : 88.0;
    
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              _loadingIndicator,
              _verticalSpacing,
            ],
            Text(
              message,
              style: _getTextStyle(),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
