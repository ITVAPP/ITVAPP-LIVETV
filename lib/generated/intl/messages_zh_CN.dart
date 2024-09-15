import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_CN';

  static String m0(index) => "连接线路${index}...";

  static String m1(line, channel) => "开始连接: ${channel} 线路${line}";

  static String m2(code) => "响应异常${code}";

  static String m3(version) => "新版本v${version}";

  static String m4(address) => "推送地址：${address}";

  static String m5(line) => "切换线路${line} ...";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "addDataSource": MessageLookupByLibrary.simpleMessage("添加订阅源"),
        "addFiledHintText":
            MessageLookupByLibrary.simpleMessage("请输入或粘贴.m3u或.txt格式的订阅源链接"),
        "addNoHttpLink":
            MessageLookupByLibrary.simpleMessage("请输入http/https链接"),
        "addRepeat": MessageLookupByLibrary.simpleMessage("已添加过此订阅源"),
        "appName": MessageLookupByLibrary.simpleMessage("电视宝直播"),
        "checkUpdate": MessageLookupByLibrary.simpleMessage("检查更新"),
        "createTime": MessageLookupByLibrary.simpleMessage("创建时间"),
        "dataSourceContent": MessageLookupByLibrary.simpleMessage("确定添加此数据源吗？"),
        "defaultText": MessageLookupByLibrary.simpleMessage("默认"),
        "delete": MessageLookupByLibrary.simpleMessage("删除"),
        "dialogCancel": MessageLookupByLibrary.simpleMessage("取消"),
        "dialogConfirm": MessageLookupByLibrary.simpleMessage("确定"),
        "dialogDeleteContent":
            MessageLookupByLibrary.simpleMessage("确定删除此订阅吗？"),
        "dialogTitle": MessageLookupByLibrary.simpleMessage("温馨提示"),
        "findNewVersion": MessageLookupByLibrary.simpleMessage("发现新版本"),
        "fullScreen": MessageLookupByLibrary.simpleMessage("全屏切换"),
        "getDefaultError": MessageLookupByLibrary.simpleMessage("获取默认数据源失败"),
        "homePage": MessageLookupByLibrary.simpleMessage("主页"),
        "inUse": MessageLookupByLibrary.simpleMessage("使用中"),
        "landscape": MessageLookupByLibrary.simpleMessage("横屏模式"),
        "latestVersion": MessageLookupByLibrary.simpleMessage("已是最新版本"),
        "lineIndex": m0,
        "lineToast": m1,
        "loading": MessageLookupByLibrary.simpleMessage("正在加载频道..."),
        "netBadResponse": m2,
        "netCancel": MessageLookupByLibrary.simpleMessage("请求取消"),
        "netReceiveTimeout": MessageLookupByLibrary.simpleMessage("响应超时"),
        "netSendTimeout": MessageLookupByLibrary.simpleMessage("请求超时"),
        "netTimeOut": MessageLookupByLibrary.simpleMessage("连接超时"),
        "newVersion": m3,
        "noEPG": MessageLookupByLibrary.simpleMessage("暂无节目信息"),
        "okRefresh": MessageLookupByLibrary.simpleMessage("【OK键】刷新"),
        "parseError": MessageLookupByLibrary.simpleMessage("解析数据源出错"),
        "pasterContent":
            MessageLookupByLibrary.simpleMessage("复制订阅源后，回到此页面可自动添加订阅源"),
        "playError": MessageLookupByLibrary.simpleMessage("此线路暂时无法播放，请等待修复"),
        "playReconnect": MessageLookupByLibrary.simpleMessage("出错了，尝试重新连接..."),
        "portrait": MessageLookupByLibrary.simpleMessage("竖屏模式"),
        "pushAddress": m4,
        "refresh": MessageLookupByLibrary.simpleMessage("刷新"),
        "releaseHistory": MessageLookupByLibrary.simpleMessage("发布历史"),
        "setDefault": MessageLookupByLibrary.simpleMessage("设为默认"),
        "settings": MessageLookupByLibrary.simpleMessage("设置"),
        "subscribe": MessageLookupByLibrary.simpleMessage("订阅"),
        "switchLine": m5,
        "tipChangeLine": MessageLookupByLibrary.simpleMessage("切换线路"),
        "tipChannelList": MessageLookupByLibrary.simpleMessage("频道列表"),
        "tvParseParma": MessageLookupByLibrary.simpleMessage("参数错误"),
        "tvParsePushError": MessageLookupByLibrary.simpleMessage("请推送正确的链接"),
        "tvParseSuccess": MessageLookupByLibrary.simpleMessage("推送成功"),
        "tvPushContent": MessageLookupByLibrary.simpleMessage(
            "在扫码结果页，输入新的订阅源，点击页面中的推送即可添加成功"),
        "tvScanTip": MessageLookupByLibrary.simpleMessage("扫码添加订阅源"),
        "update": MessageLookupByLibrary.simpleMessage("立即更新"),
        "updateContent": MessageLookupByLibrary.simpleMessage("更新内容"),
        "netReceiveTimeout": MessageLookupByLibrary.simpleMessage("响应超时"),
        "netSendTimeout": MessageLookupByLibrary.simpleMessage("请求超时"),
        "errorLoadingPage": MessageLookupByLibrary.simpleMessage("加载页面出错"),
        "logtitle": MessageLookupByLibrary.simpleMessage("日志查看器"),
        "SwitchTitle": MessageLookupByLibrary.simpleMessage("记录日志"),
        "logSubtitle": MessageLookupByLibrary.simpleMessage(
            "如非开发人员调试，无需打开日志开关"),
        "filterAll": MessageLookupByLibrary.simpleMessage("所有"),
        "filterVerbose": MessageLookupByLibrary.simpleMessage("详细"),
        "filterError": MessageLookupByLibrary.simpleMessage("错误"),
        "filterInfo": MessageLookupByLibrary.simpleMessage("信息"),
        "filterDebug": MessageLookupByLibrary.simpleMessage("调试"),
        "noLogs": MessageLookupByLibrary.simpleMessage("暂无日志"),
        "logCleared": MessageLookupByLibrary.simpleMessage("日志已清空"),
        "clearLogs": MessageLookupByLibrary.simpleMessage("清空日志"),
        "programListTitle": MessageLookupByLibrary.simpleMessage("频道列表"),
        "foundStreamTitle": MessageLookupByLibrary.simpleMessage("找到视频流"),
        "streamUrlContent": (url) =>
            "流URL: ${url}\n\n你想播放这个流吗？",
        "cancelButton": MessageLookupByLibrary.simpleMessage("取消"),
        "playButton": MessageLookupByLibrary.simpleMessage("播放"),
        "downloading": (progress) => "下载中...${progress}%",
        "fontTitle": MessageLookupByLibrary.simpleMessage("字体"),
        "backgroundImageTitle": MessageLookupByLibrary.simpleMessage("背景图"),
        "slogTitle": MessageLookupByLibrary.simpleMessage("日志"),
        "updateTitle": MessageLookupByLibrary.simpleMessage("更新"),
        "backgroundImageDescription": MessageLookupByLibrary.simpleMessage(
            "自动更换播放音频时的背景"),
        "dailyBing": MessageLookupByLibrary.simpleMessage("开启背景切换"),
        "logCopied": MessageLookupByLibrary.simpleMessage("日志已复制到剪贴板"),
        "clipboardDataFetchError":
            MessageLookupByLibrary.simpleMessage("获取剪贴板数据失败")
      };
}
