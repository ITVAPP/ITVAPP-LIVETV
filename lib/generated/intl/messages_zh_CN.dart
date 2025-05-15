import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_CN';

  static String m0(index) => "线路${index}";

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
        "oldVersion": MessageLookupByLibrary.simpleMessage("您的版本已不再支持，请更新!"),
        "fullScreen": MessageLookupByLibrary.simpleMessage("全屏切换"),
        "getDefaultError": MessageLookupByLibrary.simpleMessage("获取默认数据源失败"),
        "homePage": MessageLookupByLibrary.simpleMessage("主页"),
        "inUse": MessageLookupByLibrary.simpleMessage("使用中"),
        "Use": MessageLookupByLibrary.simpleMessage("使用"),
        "languageSelection": MessageLookupByLibrary.simpleMessage("语言选择"),
        "fontSizeTitle": MessageLookupByLibrary.simpleMessage("字体大小"),
        "landscape": MessageLookupByLibrary.simpleMessage("横屏模式"),
        "latestVersion": MessageLookupByLibrary.simpleMessage("已是最新版本"),
        "lineIndex": m0,
        "lineToast": m1,
        "loading": MessageLookupByLibrary.simpleMessage("正在加载..."),
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
        "playError": MessageLookupByLibrary.simpleMessage("此频道暂时无法播放，请等待修复"),
        "playReconnect": MessageLookupByLibrary.simpleMessage("重试连接"),
        "portrait": MessageLookupByLibrary.simpleMessage("竖屏模式"),
        "pushAddress": m4,
        "refresh": MessageLookupByLibrary.simpleMessage("刷新"),
        "releaseHistory": MessageLookupByLibrary.simpleMessage("发布历史"),
        "setDefault": MessageLookupByLibrary.simpleMessage("设为默认"),
        "settings": MessageLookupByLibrary.simpleMessage("设置"),
        "subscribe": MessageLookupByLibrary.simpleMessage("订阅"),
        "switchLine": m5,
        "exitTitle": MessageLookupByLibrary.simpleMessage("退出应用确认"),
        "exitMessage": MessageLookupByLibrary.simpleMessage("你确定要离开电视宝直播吗?"),
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
        "switchTitle": MessageLookupByLibrary.simpleMessage("记录日志"),
        "logSubtitle": MessageLookupByLibrary.simpleMessage(
            "如非开发人员，无需打开日志开关"),
        "filterAll": MessageLookupByLibrary.simpleMessage("所有"),
        "filterVerbose": MessageLookupByLibrary.simpleMessage("详细"),
        "filterError": MessageLookupByLibrary.simpleMessage("错误"),
        "filterInfo": MessageLookupByLibrary.simpleMessage("信息"),
        "filterDebug": MessageLookupByLibrary.simpleMessage("调试"),
        "noLogs": MessageLookupByLibrary.simpleMessage("暂无日志"),
        "logCleared": MessageLookupByLibrary.simpleMessage("日志已清空"),
        "clearLogs": MessageLookupByLibrary.simpleMessage("清空日志"),
        "programListTitle": MessageLookupByLibrary.simpleMessage("节目单"),
        "foundStreamTitle": MessageLookupByLibrary.simpleMessage("找到视频流"),
        "streamUrlContent": (url) =>
            "流URL: ${url}\n\n你想播放这个流吗？",
        "cancelButton": MessageLookupByLibrary.simpleMessage("取消"),
        "playButton": MessageLookupByLibrary.simpleMessage("播放"),
        "downloading":  MessageLookupByLibrary.simpleMessage("下载中..."),
        "downloadSuccess":  MessageLookupByLibrary.simpleMessage("下载完成，请安装！"),
        "downloadFailed":  MessageLookupByLibrary.simpleMessage("下载失败，请稍后重试"),
        "platformNotSupported":  MessageLookupByLibrary.simpleMessage("系统不支持应用内更新"),
        "fontTitle": MessageLookupByLibrary.simpleMessage("字体"),
        "langTip": MessageLookupByLibrary.simpleMessage("重启应用后，频道信息才可以应用新的语言设置"),
        "backgroundImageTitle": MessageLookupByLibrary.simpleMessage("背景图"),
        "slogTitle": MessageLookupByLibrary.simpleMessage("日志"),
        "updateTitle": MessageLookupByLibrary.simpleMessage("更新"),
        "backgroundImageDescription": MessageLookupByLibrary.simpleMessage(
            "自动更换播放音频时的背景"),
        "dailyBing": MessageLookupByLibrary.simpleMessage("开启背景切换"),
        "logCopied": MessageLookupByLibrary.simpleMessage("日志已复制到剪贴板"),
        "clipboardDataFetchError":
            MessageLookupByLibrary.simpleMessage("获取剪贴板数据失败"),
        "nofavorite": MessageLookupByLibrary.simpleMessage("暂无收藏"),
        "vpnplayError": MessageLookupByLibrary.simpleMessage("此频道在部分地区需要VPN才可以观看"),
        "retryplay": MessageLookupByLibrary.simpleMessage("连接出错，正在重试..."),
        "channelnofavorite": MessageLookupByLibrary.simpleMessage("当前频道无法收藏"),
        "removefavorite": MessageLookupByLibrary.simpleMessage("频道已从收藏中移除"),
        "newfavorite": MessageLookupByLibrary.simpleMessage("频道已添加到收藏"),
        "newfavoriteerror": MessageLookupByLibrary.simpleMessage("添加收藏失败"),
        "getm3udata": MessageLookupByLibrary.simpleMessage("正在获取播放数据..."),
        "getm3udataerror": MessageLookupByLibrary.simpleMessage("获取播放数据失败..."),
        "myfavorite": MessageLookupByLibrary.simpleMessage("收藏"),
        "addToFavorites": MessageLookupByLibrary.simpleMessage("添加收藏"),
        "removeFromFavorites": MessageLookupByLibrary.simpleMessage("取消收藏"),
        "allchannels": MessageLookupByLibrary.simpleMessage("其它频道"),
        "copy": MessageLookupByLibrary.simpleMessage("复制"),
        "copyok": MessageLookupByLibrary.simpleMessage("内容已复制到剪贴板"),
        "startsurlerror": MessageLookupByLibrary.simpleMessage("解析 URL 失败"),
        "gethttperror": MessageLookupByLibrary.simpleMessage("本地网络配置失败"),
        "exittip": MessageLookupByLibrary.simpleMessage("期待你下一次的访问"),
        "playpause": MessageLookupByLibrary.simpleMessage("暂停播放中..."),
        "remotehelp": MessageLookupByLibrary.simpleMessage("帮助"),
        "remotehelpup": MessageLookupByLibrary.simpleMessage("「点击上键」打开 线路切换菜单"),
        "remotehelpleft": MessageLookupByLibrary.simpleMessage("「点击左键」添加/取消 频道收藏"),
        "remotehelpdown": MessageLookupByLibrary.simpleMessage("「点击下键」打开 应用设置界面"),
        "remotehelpok": MessageLookupByLibrary.simpleMessage("「点击确认键」确认选择操作\n显示时间/暂停/播放"),
        "remotehelpright": MessageLookupByLibrary.simpleMessage("「点击右键」打开 频道选择抽屉"),
        "remotehelpback": MessageLookupByLibrary.simpleMessage("「点击返回键」退出/取消操作"),
        "remotehelpclose": MessageLookupByLibrary.simpleMessage("点击任意按键关闭帮助")
      };
}
