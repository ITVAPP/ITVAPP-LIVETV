import 'package:flutter/material.dart'; // 引入Flutter的Material库
import 'package:intl/intl.dart'; // 引入国际化库Intl
import 'intl/messages_all.dart'; // 引入生成的国际化消息文件

// 国际化类，使用Intl包进行多语言支持
class S {
  S(); // 构造函数

  static S? _current;

  // 获取当前的国际化实例
  static S get current {
    assert(_current != null,
        'No instance of S was loaded. Try to initialize the S delegate before accessing S.current.'); // 确保当前实例已加载
    return _current!;
  }

  // 定义App的本地化委托
  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  // 加载指定语言环境的国际化资源
  static Future<S> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode // 如果国家代码为空，使用语言代码
        : locale.toString(); // 否则使用完整的语言环境字符串
    final localeName = Intl.canonicalizedLocale(name); // 标准化语言环境名称
    return initializeMessages(localeName).then((_) { // 初始化消息
      Intl.defaultLocale = localeName; // 设置默认语言环境
      final instance = S(); // 创建S的实例
      S._current = instance;

      return instance;
    });
  }

  // 从上下文中获取当前的国际化实例
  static S of(BuildContext context) {
    final instance = S.maybeOf(context); // 尝试获取实例
    assert(instance != null,
        'No instance of S present in the widget tree. Did you add S.delegate in localizationsDelegates?'); // 如果实例不存在，抛出异常
    return instance!;
  }

  // 尝试从上下文中获取当前的国际化实例
  static S? maybeOf(BuildContext context) {
    return Localizations.of<S>(context, S); // 从Localizations中获取实例
  }

  // 以下为生成的本地化字符串方法

  String get appName {
    return Intl.message(
      'ITVAPP LIVETV',
      name: 'appName',
      desc: '',
      args: [],
    );
  }

  String get loading {
    return Intl.message(
      'Loading',
      name: 'loading',
      desc: '',
      args: [],
    );
  }

  String lineToast(Object line, Object channel) {
    return Intl.message(
      'Line $line playing: $channel',
      name: 'lineToast',
      desc: '',
      args: [line, channel],
    );
  }

  String get playError {
    return Intl.message(
      'This video cannot be played, please switch to another channel',
      name: 'playError',
      desc: '',
      args: [],
    );
  }

  String switchLine(Object line) {
    return Intl.message(
      'Switching to line $line ...',
      name: 'switchLine',
      desc: '',
      args: [line],
    );
  }

  String get playReconnect {
    return Intl.message(
      'An error occurred, trying to reconnect...',
      name: 'playReconnect',
      desc: '',
      args: [],
    );
  }

  String lineIndex(Object index) {
    return Intl.message(
      'Line $index',
      name: 'lineIndex',
      desc: '',
      args: [index],
    );
  }

  String gettingData(Object retryCount, Object maxRetries) {
    return Intl.message(
      'Fetching data... (${retryCount}/${maxRetries})',
      name: 'gettingData',
      desc: '',
      args: [retryCount, maxRetries],
    );
  }

  String get loadingData {
    return Intl.message(
      'Fetching data...',
      name: 'loadingData',
      desc: '',
      args: [],
    );
  }

  String get errorLoadingData {
    return Intl.message(
      'Failed to load data, please try again later',
      name: 'errorLoadingData',
      desc: '',
      args: [],
    );
  }

  String get retry {
    return Intl.message(
      'Retry',
      name: 'retry',
      desc: '',
      args: [],
    );
  }

  String get tipChannelList {
    return Intl.message(
      'Channel List',
      name: 'tipChannelList',
      desc: '',
      args: [],
    );
  }

  String get tipChangeLine {
    return Intl.message(
      'Switch Line',
      name: 'tipChangeLine',
      desc: '',
      args: [],
    );
  }

  String get portrait {
    return Intl.message(
      'Portrait Mode',
      name: 'portrait',
      desc: '',
      args: [],
    );
  }

  String get landscape {
    return Intl.message(
      'Landscape Mode',
      name: 'landscape',
      desc: '',
      args: [],
    );
  }

  String get fullScreen {
    return Intl.message(
      'Full Screen Toggle',
      name: 'fullScreen',
      desc: '',
      args: [],
    );
  }

  String get settings {
    return Intl.message(
      'Settings',
      name: 'settings',
      desc: '',
      args: [],
    );
  }

  String get homePage {
    return Intl.message(
      'Home Page',
      name: 'homePage',
      desc: '',
      args: [],
    );
  }

  String get releaseHistory {
    return Intl.message(
      'Release History',
      name: 'releaseHistory',
      desc: '',
      args: [],
    );
  }

  String get checkUpdate {
    return Intl.message(
      'Check for Updates',
      name: 'checkUpdate',
      desc: '',
      args: [],
    );
  }

  String newVersion(Object version) {
    return Intl.message(
      'New Version v$version',
      name: 'newVersion',
      desc: '',
      args: [version],
    );
  }

  String get update {
    return Intl.message(
      'Update Now',
      name: 'update',
      desc: '',
      args: [],
    );
  }

  String get latestVersion {
    return Intl.message(
      'You are on the latest version',
      name: 'latestVersion',
      desc: '',
      args: [],
    );
  }

  String get findNewVersion {
    return Intl.message(
      'New version found',
      name: 'findNewVersion',
      desc: '',
      args: [],
    );
  }

  String get updateContent {
    return Intl.message(
      'Update Content',
      name: 'updateContent',
      desc: '',
      args: [],
    );
  }

  String get dialogTitle {
    return Intl.message(
      'Friendly Reminder',
      name: 'dialogTitle',
      desc: '',
      args: [],
    );
  }

  String get dataSourceContent {
    return Intl.message(
      'Are you sure you want to add this data source?',
      name: 'dataSourceContent',
      desc: '',
      args: [],
    );
  }

  String get dialogCancel {
    return Intl.message(
      'Cancel',
      name: 'dialogCancel',
      desc: '',
      args: [],
    );
  }

  String get dialogConfirm {
    return Intl.message(
      'Confirm',
      name: 'dialogConfirm',
      desc: '',
      args: [],
    );
  }

  String get subscribe {
    return Intl.message(
      'IPTV Subscription',
      name: 'subscribe',
      desc: '',
      args: [],
    );
  }

  String get createTime {
    return Intl.message(
      'Creation Time',
      name: 'createTime',
      desc: '',
      args: [],
    );
  }

  String get dialogDeleteContent {
    return Intl.message(
      'Are you sure you want to delete this subscription?',
      name: 'dialogDeleteContent',
      desc: '',
      args: [],
    );
  }

  String get delete {
    return Intl.message(
      'Delete',
      name: 'delete',
      desc: '',
      args: [],
    );
  }

  String get setDefault {
    return Intl.message(
      'Set as Default',
      name: 'setDefault',
      desc: '',
      args: [],
    );
  }

  String get inUse {
    return Intl.message(
      'In Use',
      name: 'inUse',
      desc: '',
      args: [],
    );
  }

  String get tvParseParma {
    return Intl.message(
      'Parameter Error',
      name: 'tvParseParma',
      desc: '',
      args: [],
    );
  }

  String get tvParseSuccess {
    return Intl.message(
      'Push Successful',
      name: 'tvParseSuccess',
      desc: '',
      args: [],
    );
  }

  String get tvParsePushError {
    return Intl.message(
      'Please push the correct link',
      name: 'tvParsePushError',
      desc: '',
      args: [],
    );
  }

  String get tvScanTip {
    return Intl.message(
      'Scan to add subscription source',
      name: 'tvScanTip',
      desc: '',
      args: [],
    );
  }

  String pushAddress(Object address) {
    return Intl.message(
      'Push Address: $address',
      name: 'pushAddress',
      desc: '',
      args: [address],
    );
  }

  String get tvPushContent {
    return Intl.message(
      'On the scan result page, enter the new subscription source, and click the push button to add it successfully',
      name: 'tvPushContent',
      desc: '',
      args: [],
    );
  }

  String get pasterContent {
    return Intl.message(
      'After copying the subscription source, return to this page to automatically add the subscription source',
      name: 'pasterContent',
      desc: '',
      args: [],
    );
  }

  String get addDataSource {
    return Intl.message(
      'Add Subscription Source',
      name: 'addDataSource',
      desc: '',
      args: [],
    );
  }

  String get addFiledHintText {
    return Intl.message(
      'Please enter or paste the .m3u or .txt format subscription link',
      name: 'addFiledHintText',
      desc: '',
      args: [],
    );
  }

  String get addRepeat {
    return Intl.message(
      'This subscription source has already been added',
      name: 'addRepeat',
      desc: '',
      args: [],
    );
  }

  String get addNoHttpLink {
    return Intl.message(
      'Please enter http/https link',
      name: 'addNoHttpLink',
      desc: '',
      args: [],
    );
  }

  String get netTimeOut {
    return Intl.message(
      'Connection Timeout',
      name: 'netTimeOut',
      desc: '',
      args: [],
    );
  }

  String get netSendTimeout {
    return Intl.message(
      'Request Timeout',
      name: 'netSendTimeout',
      desc: '',
      args: [],
    );
  }

  String get netReceiveTimeout {
    return Intl.message(
      'Response Timeout',
      name: 'netReceiveTimeout',
      desc: '',
      args: [],
    );
  }

  String netBadResponse(Object code) {
    return Intl.message(
      'Bad Response $code',
      name: 'netBadResponse',
      desc: '',
      args: [code],
    );
  }

  String get netCancel {
    return Intl.message(
      'Request Cancelled',
      name: 'netCancel',
      desc: '',
      args: [],
    );
  }

  String get parseError {
    return Intl.message(
      'Error Parsing Data Source',
      name: 'parseError',
      desc: '',
      args: [],
    );
  }

  String get defaultText {
    return Intl.message(
      'Default',
      name: 'defaultText',
      desc: '',
      args: [],
    );
  }

  String get getDefaultError {
    return Intl.message(
      'Failed to get default data source',
      name: 'getDefaultError',
      desc: '',
      args: [],
    );
  }

  String get okRefresh {
    return Intl.message(
      '【OK Key】 Refresh',
      name: 'okRefresh',
      desc: '',
      args: [],
    );
  }

  String get refresh {
    return Intl.message(
      'Refresh',
      name: 'refresh',
      desc: '',
      args: [],
    );
  }

  String get noEPG {
    return Intl.message(
      'No program information available',
      name: 'noEPG',
      desc: '',
      args: [],
    );
  }
}

// 定义应用程序本地化委托
class AppLocalizationDelegate extends LocalizationsDelegate<S> {
  const AppLocalizationDelegate();

  // 支持的语言环境列表
  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'), // 中文（中国）
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'), // 中文（台湾）
      Locale('en'), // 英语（适用于所有国家）
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale); // 判断是否支持指定的语言环境
  @override
  Future<S> load(Locale locale) => S.load(locale); // 加载指定语言环境的国际化资源
  @override
  bool shouldReload(AppLocalizationDelegate old) => false; // 确定是否应重新加载本地化委托

  // 私有方法，判断是否支持指定的语言环境
  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true; // 如果找到匹配的语言代码，返回true
      }
    }
    return false; // 如果未找到匹配的语言代码，返回false
  }
}
