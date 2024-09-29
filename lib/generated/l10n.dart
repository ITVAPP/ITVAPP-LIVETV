import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'intl/messages_all.dart';

class S {
  S();

  static S? _current;

  static S get current {
    assert(_current != null,
        'No instance of S was loaded. Try to initialize the S delegate before accessing S.current.');
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<S> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return initializeMessages(localeName).then((_) {
      Intl.defaultLocale = localeName;
      final instance = S();
      S._current = instance;

      return instance;
    });
  }

  static S of(BuildContext context) {
    final instance = S.maybeOf(context);
    assert(instance != null,
        'No instance of S present in the widget tree. Did you add S.delegate in localizationsDelegates?');
    return instance!;
  }

  static S? maybeOf(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  // 基础信息
  String get appName {
    return Intl.message(
      '电视宝直播',
      name: 'appName',
      desc: '',
      args: [],
    );
  }

  String get loading {
    return Intl.message(
      '正在加载频道...',
      name: 'loading',
      desc: '',
      args: [],
    );
  }

  // 占位符文本
  String lineToast(Object line, Object channel) {
    return Intl.message(
      '开始连接: $channel 线路$line',
      name: 'lineToast',
      desc: '',
      args: [line, channel],
    );
  }

  String get playError {
    return Intl.message(
      '此频道暂时无法播放，请等待修复',
      name: 'playError',
      desc: '',
      args: [],
    );
  }

  String switchLine(Object line) {
    return Intl.message(
      '切换线路$line ...',
      name: 'switchLine',
      desc: '',
      args: [line],
    );
  }

  String get playReconnect {
    return Intl.message(
      '出错了，尝试重新连接...',
      name: 'playReconnect',
      desc: '',
      args: [],
    );
  }

  String lineIndex(Object index) {
    return Intl.message(
      '线路$index',
      name: 'lineIndex',
      desc: '',
      args: [index],
    );
  }

  String get tipChannelList {
    return Intl.message(
      '频道列表',
      name: 'tipChannelList',
      desc: '',
      args: [],
    );
  }

  String get tipChangeLine {
    return Intl.message(
      '切换线路',
      name: 'tipChangeLine',
      desc: '',
      args: [],
    );
  }

  String get portrait {
    return Intl.message(
      '竖屏模式',
      name: 'portrait',
      desc: '',
      args: [],
    );
  }

  String get landscape {
    return Intl.message(
      '横屏模式',
      name: 'landscape',
      desc: '',
      args: [],
    );
  }

  String get fullScreen {
    return Intl.message(
      '全屏切换',
      name: 'fullScreen',
      desc: '',
      args: [],
    );
  }

  String get settings {
    return Intl.message(
      '设置',
      name: 'settings',
      desc: '',
      args: [],
    );
  }

  String get homePage {
    return Intl.message(
      '主页',
      name: 'homePage',
      desc: '',
      args: [],
    );
  }

  String get releaseHistory {
    return Intl.message(
      '发布历史',
      name: 'releaseHistory',
      desc: '',
      args: [],
    );
  }

  String get checkUpdate {
    return Intl.message(
      '检查更新',
      name: 'checkUpdate',
      desc: '',
      args: [],
    );
  }

  String newVersion(Object version) {
    return Intl.message(
      '新版本v$version',
      name: 'newVersion',
      desc: '',
      args: [version],
    );
  }

  String get update {
    return Intl.message(
      '立即更新',
      name: 'update',
      desc: '',
      args: [],
    );
  }

  String get latestVersion {
    return Intl.message(
      '已是最新版本',
      name: 'latestVersion',
      desc: '',
      args: [],
    );
  }

  String get findNewVersion {
    return Intl.message(
      '发现新版本',
      name: 'findNewVersion',
      desc: '',
      args: [],
    );
  }

  String get updateContent {
    return Intl.message(
      '更新内容',
      name: 'updateContent',
      desc: '',
      args: [],
    );
  }

  String get dialogTitle {
    return Intl.message(
      '温馨提示',
      name: 'dialogTitle',
      desc: '',
      args: [],
    );
  }

  String get dataSourceContent {
    return Intl.message(
      '确定添加此数据源吗？',
      name: 'dataSourceContent',
      desc: '',
      args: [],
    );
  }

  String get dialogCancel {
    return Intl.message(
      '取消',
      name: 'dialogCancel',
      desc: '',
      args: [],
    );
  }

  String get dialogConfirm {
    return Intl.message(
      '确定',
      name: 'dialogConfirm',
      desc: '',
      args: [],
    );
  }

  String get subscribe {
    return Intl.message(
      '订阅',
      name: 'subscribe',
      desc: '',
      args: [],
    );
  }

  String get createTime {
    return Intl.message(
      '创建时间',
      name: 'createTime',
      desc: '',
      args: [],
    );
  }

  String get dialogDeleteContent {
    return Intl.message(
      '确定删除此订阅吗？',
      name: 'dialogDeleteContent',
      desc: '',
      args: [],
    );
  }

  String get delete {
    return Intl.message(
      '删除',
      name: 'delete',
      desc: '',
      args: [],
    );
  }

  String get setDefault {
    return Intl.message(
      '设为默认',
      name: 'setDefault',
      desc: '',
      args: [],
    );
  }

  String get inUse {
    return Intl.message(
      '使用中',
      name: 'inUse',
      desc: '',
      args: [],
    );
  }

  String get tvParseParma {
    return Intl.message(
      '参数错误',
      name: 'tvParseParma',
      desc: '',
      args: [],
    );
  }

  String get tvParseSuccess {
    return Intl.message(
      '推送成功',
      name: 'tvParseSuccess',
      desc: '',
      args: [],
    );
  }

  String get tvParsePushError {
    return Intl.message(
      '请推送正确的链接',
      name: 'tvParsePushError',
      desc: '',
      args: [],
    );
  }

  String get tvScanTip {
    return Intl.message(
      '扫码添加订阅源',
      name: 'tvScanTip',
      desc: '',
      args: [],
    );
  }

  String pushAddress(Object address) {
    return Intl.message(
      '推送地址：$address',
      name: 'pushAddress',
      desc: '',
      args: [address],
    );
  }

  String get tvPushContent {
    return Intl.message(
      '在扫码结果页，输入新的订阅源，点击页面中的推送即可添加成功',
      name: 'tvPushContent',
      desc: '',
      args: [],
    );
  }

  String get pasterContent {
    return Intl.message(
      '复制订阅源后，回到此页面可自动添加订阅源',
      name: 'pasterContent',
      desc: '',
      args: [],
    );
  }

  String get addDataSource {
    return Intl.message(
      '添加订阅源',
      name: 'addDataSource',
      desc: '',
      args: [],
    );
  }

  String get addFiledHintText {
    return Intl.message(
      '请输入或粘贴.m3u或.txt格式的订阅源链接',
      name: 'addFiledHintText',
      desc: '',
      args: [],
    );
  }

  String get addRepeat {
    return Intl.message(
      '已添加过此订阅源',
      name: 'addRepeat',
      desc: '',
      args: [],
    );
  }

  String get addNoHttpLink {
    return Intl.message(
      '请输入http/https链接',
      name: 'addNoHttpLink',
      desc: '',
      args: [],
    );
  }

  String get netTimeOut {
    return Intl.message(
      '连接超时',
      name: 'netTimeOut',
      desc: '',
      args: [],
    );
  }

  String get netSendTimeout {
    return Intl.message(
      '请求超时',
      name: 'netSendTimeout',
      desc: '',
      args: [],
    );
  }

  String get netReceiveTimeout {
    return Intl.message(
      '响应超时',
      name: 'netReceiveTimeout',
      desc: '',
      args: [],
    );
  }

  String netBadResponse(Object code) {
    return Intl.message(
      '响应异常$code',
      name: 'netBadResponse',
      desc: '',
      args: [code],
    );
  }

  String get netCancel {
    return Intl.message(
      '请求取消',
      name: 'netCancel',
      desc: '',
      args: [],
    );
  }

  String get parseError {
    return Intl.message(
      '解析数据源出错',
      name: 'parseError',
      desc: '',
      args: [],
    );
  }

  String get defaultText {
    return Intl.message(
      '默认',
      name: 'defaultText',
      desc: '',
      args: [],
    );
  }

  String get getDefaultError {
    return Intl.message(
      '获取默认数据源失败',
      name: 'getDefaultError',
      desc: '',
      args: [],
    );
  }

  String get okRefresh {
    return Intl.message(
      '【OK键】刷新',
      name: 'okRefresh',
      desc: '',
      args: [],
    );
  }

  String get refresh {
    return Intl.message(
      '刷新',
      name: 'refresh',
      desc: '',
      args: [],
    );
  }

  String get noEPG {
    return Intl.message(
      '暂无节目信息',
      name: 'noEPG',
      desc: '',
      args: [],
    );
  }

  // 新增部分
  String get logtitle {
    return Intl.message(
      '日志查看器',
      name: 'logtitle',
      desc: '',
      args: [],
    );
  }

  String get SwitchTitle {
    return Intl.message(
      '记录日志',
      name: 'SwitchTitle',
      desc: '',
      args: [],
    );
  }

  String get logSubtitle {
    return Intl.message(
      '如非开发人员，无需打开日志开关',
      name: 'logSubtitle',
      desc: '',
      args: [],
    );
  }

  String get filterAll {
    return Intl.message(
      '所有',
      name: 'filterAll',
      desc: '',
      args: [],
    );
  }

  String get filterVerbose {
    return Intl.message(
      '详细',
      name: 'filterVerbose',
      desc: '',
      args: [],
    );
  }

  String get filterError {
    return Intl.message(
      '错误',
      name: 'filterError',
      desc: '',
      args: [],
    );
  }

  String get filterInfo {
    return Intl.message(
      '信息',
      name: 'filterInfo',
      desc: '',
      args: [],
    );
  }

  String get filterDebug {
    return Intl.message(
      '调试',
      name: 'filterDebug',
      desc: '',
      args: [],
    );
  }

  String get noLogs {
    return Intl.message(
      '暂无日志',
      name: 'noLogs',
      desc: '',
      args: [],
    );
  }

  String get logCleared {
    return Intl.message(
      '日志已清空',
      name: 'logCleared',
      desc: '',
      args: [],
    );
  }

  String get clearLogs {
    return Intl.message(
      '清空日志',
      name: 'clearLogs',
      desc: '',
      args: [],
    );
  }

  String get programListTitle {
    return Intl.message(
      '节目单',
      name: 'programListTitle',
      desc: '',
      args: [],
    );
  }

  String get foundStreamTitle {
    return Intl.message(
      '找到视频流',
      name: 'foundStreamTitle',
      desc: '',
      args: [],
    );
  }

  String streamUrlContent(Object url) {
    return Intl.message(
      '流URL: $url\n\n你想播放这个流吗？',
      name: 'streamUrlContent',
      desc: '',
      args: [url],
    );
  }

  String get cancelButton {
    return Intl.message(
      '取消',
      name: 'cancelButton',
      desc: '',
      args: [],
    );
  }

  String get playButton {
    return Intl.message(
      '播放',
      name: 'playButton',
      desc: '',
      args: [],
    );
  }

  String get downloading {
    return Intl.message(
      '下载中...',
      name: 'downloading',
      desc: '',
      args: [],
    );
  }

  String get fontTitle {
    return Intl.message(
      '字体',
      name: 'fontTitle',
      desc: '',
      args: [],
    );
  }

  String get backgroundImageTitle {
    return Intl.message(
      '背景图',
      name: 'backgroundImageTitle',
      desc: '',
      args: [],
    );
  }

  String get slogTitle {
    return Intl.message(
      '日志',
      name: 'slogTitle',
      desc: '',
      args: [],
    );
  }

  String get updateTitle {
    return Intl.message(
      '更新',
      name: 'updateTitle',
      desc: '',
      args: [],
    );
  }

  String get errorLoadingPage {
    return Intl.message(
      '加载页面出错',
      name: 'errorLoadingPage',
      desc: '',
      args: [],
    );
  }

  String get backgroundImageDescription {
    return Intl.message(
      '自动更换播放音频时的背景',
      name: 'backgroundImageDescription',
      desc: '',
      args: [],
    );
  }

  String get dailyBing {
    return Intl.message(
      '开启背景切换',
      name: 'dailyBing',
      desc: '',
      args: [],
    );
  }

  String get use {
    return Intl.message(
      '使用',
      name: 'use',
      desc: '',
      args: [],
    );
  }

  String get languageSelection {
    return Intl.message(
      '语言选择',
      name: 'languageSelection',
      desc: '',
      args: [],
    );
  }

  String get fontSizeTitle {
    return Intl.message(
      '字体大小',
      name: 'fontSizeTitle',
      desc: '',
      args: [],
    );
  }

  String get logCopied {
    return Intl.message(
      '日志已复制到剪贴板',
      name: 'logCopied',
      desc: '',
      args: [],
    );
  }

  String get clipboardDataFetchError {
    return Intl.message(
      '获取剪贴板数据失败',
      name: 'clipboardDataFetchError',
      desc: '',
      args: [],
    );
  }
}

class AppLocalizationDelegate extends LocalizationsDelegate<S> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'), // 中文（中国）
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'), // 中文（台湾）
      Locale('en'), // 英语（适用于所有国家）
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale);
  @override
  Future<S> load(Locale locale) => S.load(locale);
  @override
  bool shouldReload(AppLocalizationDelegate old) => false;

  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }
}
