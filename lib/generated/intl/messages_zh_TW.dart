import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_TW';

  static String m0(line, channel) => "線路${line}播放: ${channel}";

  static String m1(line) => "切換線路${line} ...";

  static String m2(index) => "線路${index}";

  static String m3(retryCount, maxRetries) => "正在獲取播放資料... (${retryCount}/${maxRetries})";

  static String m4(version) => "新版本 v${version}";

  static String m5(address) => "推送地址：${address}";

  static String m6(code) => "響應異常${code}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "appName": MessageLookupByLibrary.simpleMessage("電視寶直播"),
        "loading": MessageLookupByLibrary.simpleMessage("正在載入"),
        "lineToast": m0,
        "playError": MessageLookupByLibrary.simpleMessage("此頻道暫時無法播放，請等待修復"),
        "switchLine": m1,
        "playReconnect": MessageLookupByLibrary.simpleMessage("連線出錯，嘗試重新連線..."),
        "lineIndex": m2,
        "gettingData": m3,
        "loadingData": MessageLookupByLibrary.simpleMessage("正在獲取播放資料..."),
        "errorLoadingData": MessageLookupByLibrary.simpleMessage("獲取資料出錯，請稍後重試"),
        "retry": MessageLookupByLibrary.simpleMessage("重 試"),
        "tipChannelList": MessageLookupByLibrary.simpleMessage("頻道列表"),
        "tipChangeLine": MessageLookupByLibrary.simpleMessage("切換線路"),
        "portrait": MessageLookupByLibrary.simpleMessage("豎屏模式"),
        "landscape": MessageLookupByLibrary.simpleMessage("橫屏模式"),
        "fullScreen": MessageLookupByLibrary.simpleMessage("切換全屏"),
        "settings": MessageLookupByLibrary.simpleMessage("設定"),
        "homePage": MessageLookupByLibrary.simpleMessage("主頁"),
        "releaseHistory": MessageLookupByLibrary.simpleMessage("釋出歷史"),
        "checkUpdate": MessageLookupByLibrary.simpleMessage("檢查更新"),
        "newVersion": m4,
        "update": MessageLookupByLibrary.simpleMessage("立即更新"),
        "latestVersion": MessageLookupByLibrary.simpleMessage("已是最新版本"),
        "findNewVersion": MessageLookupByLibrary.simpleMessage("發現新版本"),
        "updateContent": MessageLookupByLibrary.simpleMessage("更新內容"),
        "dialogTitle": MessageLookupByLibrary.simpleMessage("提示"),
        "dataSourceContent": MessageLookupByLibrary.simpleMessage("確定新增資料來源嗎？"),
        "dialogCancel": MessageLookupByLibrary.simpleMessage("取消"),
        "dialogConfirm": MessageLookupByLibrary.simpleMessage("確定"),
        "subscribe": MessageLookupByLibrary.simpleMessage("IPTV訂閱"),
        "createTime": MessageLookupByLibrary.simpleMessage("建立時間"),
        "dialogDeleteContent": MessageLookupByLibrary.simpleMessage("確定刪除此訂閱嗎？"),
        "delete": MessageLookupByLibrary.simpleMessage("刪除"),
        "setDefault": MessageLookupByLibrary.simpleMessage("設為預設"),
        "inUse": MessageLookupByLibrary.simpleMessage("使用中"),
        "tvParseParma": MessageLookupByLibrary.simpleMessage("引數錯誤"),
        "tvParseSuccess": MessageLookupByLibrary.simpleMessage("推送成功"),
        "tvParsePushError": MessageLookupByLibrary.simpleMessage("請推送正確的連結"),
        "tvScanTip": MessageLookupByLibrary.simpleMessage("掃碼新增訂閱源"),
        "pushAddress": m5,
        "tvPushContent": MessageLookupByLibrary.simpleMessage("在掃碼結果頁，輸入新的訂閱源，點選頁面中的推送即可新增"),
        "pasterContent": MessageLookupByLibrary.simpleMessage("複製訂閱源後，回到此頁面可自動新增訂閱源"),
        "addDataSource": MessageLookupByLibrary.simpleMessage("新增訂閱源"),
        "addFiledHintText": MessageLookupByLibrary.simpleMessage("請輸入或貼上.m3u或.txt格式的訂閱源連結"),
        "addRepeat": MessageLookupByLibrary.simpleMessage("已新增過此訂閱源"),
        "addNoHttpLink": MessageLookupByLibrary.simpleMessage("請輸入http/https連結"),
        "netTimeOut": MessageLookupByLibrary.simpleMessage("連線超時"),
        "netSendTimeout": MessageLookupByLibrary.simpleMessage("請求超時"),
        "netReceiveTimeout": MessageLookupByLibrary.simpleMessage("響應超時"),
        "netBadResponse": m6,
        "netCancel": MessageLookupByLibrary.simpleMessage("請求取消"),
        "parseError": MessageLookupByLibrary.simpleMessage("解析播放資料出錯"),
        "defaultText": MessageLookupByLibrary.simpleMessage("預設"),
        "getDefaultError": MessageLookupByLibrary.simpleMessage("獲取播放資料失敗"),
        "okRefresh": MessageLookupByLibrary.simpleMessage("請按【OK鍵】重新整理"),
        "refresh": MessageLookupByLibrary.simpleMessage("重新整理"),
        "noEPG": MessageLookupByLibrary.simpleMessage("暂无節目資訊")
      };
}
