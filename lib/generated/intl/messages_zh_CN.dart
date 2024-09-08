import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_CN';

  static String m0(line, channel) => "线路${line}播放: ${channel}";

  static String m1(line) => "切换线路${line} ...";

  static String m2(index) => "线路${index}";

  static String m3(retryCount, maxRetries) => "正在获取播放数据... (${retryCount}/${maxRetries})";

  static String m4(version) => "新版本 v${version}";

  static String m5(address) => "推送地址：${address}";

  static String m6(code) => "响应异常${code}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "appName": MessageLookupByLibrary.simpleMessage("电视宝直播"),
        "loading": MessageLookupByLibrary.simpleMessage("正在加载"),
        "lineToast": m0,
        "playError": MessageLookupByLibrary.simpleMessage("此频道暂时无法播放，请等待修复"),
        "switchLine": m1,
        "playReconnect": MessageLookupByLibrary.simpleMessage("连接出错，尝试重新连接..."),
        "lineIndex": m2,
        "gettingData": m3,
        "loadingData": MessageLookupByLibrary.simpleMessage("正在获取播放数据..."),
        "errorLoadingData": MessageLookupByLibrary.simpleMessage("获取数据出错，请稍后重试"),
        "retry": MessageLookupByLibrary.simpleMessage("重 试"),
        "tipChannelList": MessageLookupByLibrary.simpleMessage("频道列表"),
        "tipChangeLine": MessageLookupByLibrary.simpleMessage("切换线路"),
        "portrait": MessageLookupByLibrary.simpleMessage("竖屏模式"),
        "landscape": MessageLookupByLibrary.simpleMessage("横屏模式"),
        "fullScreen": MessageLookupByLibrary.simpleMessage("切换全屏"),
        "settings": MessageLookupByLibrary.simpleMessage("设置"),
        "homePage": MessageLookupByLibrary.simpleMessage("主页"),
        "releaseHistory": MessageLookupByLibrary.simpleMessage("发布历史"),
        "checkUpdate": MessageLookupByLibrary.simpleMessage("检查更新"),
        "newVersion": m4,
        "update": MessageLookupByLibrary.simpleMessage("立即更新"),
        "latestVersion": MessageLookupByLibrary.simpleMessage("已是最新版本"),
        "findNewVersion": MessageLookupByLibrary.simpleMessage("发现新版本"),
        "updateContent": MessageLookupByLibrary.simpleMessage("更新内容"),
        "dialogTitle": MessageLookupByLibrary.simpleMessage("提示"),
        "dataSourceContent": MessageLookupByLibrary.simpleMessage("确定添加数据源吗？"),
        "dialogCancel": MessageLookupByLibrary.simpleMessage("取消"),
        "dialogConfirm": MessageLookupByLibrary.simpleMessage("确定"),
        "subscribe": MessageLookupByLibrary.simpleMessage("IPTV订阅"),
        "createTime": MessageLookupByLibrary.simpleMessage("创建时间"),
        "dialogDeleteContent": MessageLookupByLibrary.simpleMessage("确定删除此订阅吗？"),
        "delete": MessageLookupByLibrary.simpleMessage("删除"),
        "setDefault": MessageLookupByLibrary.simpleMessage("设为默认"),
        "inUse": MessageLookupByLibrary.simpleMessage("使用中"),
        "tvParseParma": MessageLookupByLibrary.simpleMessage("参数错误"),
        "tvParseSuccess": MessageLookupByLibrary.simpleMessage("推送成功"),
        "tvParsePushError": MessageLookupByLibrary.simpleMessage("请推送正确的链接"),
        "tvScanTip": MessageLookupByLibrary.simpleMessage("扫码添加订阅源"),
        "pushAddress": m5,
        "tvPushContent": MessageLookupByLibrary.simpleMessage("在扫码结果页，输入新的订阅源，点击页面中的推送即可添加"),
        "pasterContent": MessageLookupByLibrary.simpleMessage("复制订阅源后，回到此页面可自动添加订阅源"),
        "addDataSource": MessageLookupByLibrary.simpleMessage("添加订阅源"),
        "addFiledHintText": MessageLookupByLibrary.simpleMessage("请输入或粘贴.m3u或.txt格式的订阅源链接"),
        "addRepeat": MessageLookupByLibrary.simpleMessage("已添加过此订阅源"),
        "addNoHttpLink": MessageLookupByLibrary.simpleMessage("请输入http/https链接"),
        "netTimeOut": MessageLookupByLibrary.simpleMessage("连接超时"),
        "netSendTimeout": MessageLookupByLibrary.simpleMessage("请求超时"),
        "netReceiveTimeout": MessageLookupByLibrary.simpleMessage("响应超时"),
        "netBadResponse": m6,
        "netCancel": MessageLookupByLibrary.simpleMessage("请求取消"),
        "parseError": MessageLookupByLibrary.simpleMessage("解析播放数据出错"),
        "defaultText": MessageLookupByLibrary.simpleMessage("默认"),
        "getDefaultError": MessageLookupByLibrary.simpleMessage("获取播放数据失败"),
        "okRefresh": MessageLookupByLibrary.simpleMessage("请按【OK键】刷新"),
        "refresh": MessageLookupByLibrary.simpleMessage("刷新"),
        "noEPG": MessageLookupByLibrary.simpleMessage("暂无节目信息")
      };
}
