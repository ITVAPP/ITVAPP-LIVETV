import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_TW';

  static String m0(index) => "連線線路${index}...";

  static String m1(line, channel) => "開始連線: ${channel} 線路${line}";

  static String m2(code) => "響應異常${code}";

  static String m3(version) => "新版本v${version}";

  static String m4(address) => "推送地址：${address}";

  static String m5(line) => "切換線路${line} ...";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "addDataSource": MessageLookupByLibrary.simpleMessage("新增訂閱源"),
        "addFiledHintText":
            MessageLookupByLibrary.simpleMessage("請輸入或貼上.m3u或.txt格式的訂閱源連結"),
        "addNoHttpLink":
            MessageLookupByLibrary.simpleMessage("請輸入http/https連結"),
        "addRepeat": MessageLookupByLibrary.simpleMessage("已新增過此訂閱源"),
        "appName": MessageLookupByLibrary.simpleMessage("電視寶直播"),
        "checkUpdate": MessageLookupByLibrary.simpleMessage("檢查更新"),
        "createTime": MessageLookupByLibrary.simpleMessage("建立時間"),
        "dataSourceContent": MessageLookupByLibrary.simpleMessage("確定新增此資料來源嗎？"),
        "defaultText": MessageLookupByLibrary.simpleMessage("預設"),
        "delete": MessageLookupByLibrary.simpleMessage("刪除"),
        "dialogCancel": MessageLookupByLibrary.simpleMessage("取消"),
        "dialogConfirm": MessageLookupByLibrary.simpleMessage("確定"),
        "dialogDeleteContent":
            MessageLookupByLibrary.simpleMessage("確定刪除此訂閱嗎？"),
        "dialogTitle": MessageLookupByLibrary.simpleMessage("溫馨提示"),
        "findNewVersion": MessageLookupByLibrary.simpleMessage("發現新版本"),
        "fullScreen": MessageLookupByLibrary.simpleMessage("全屏切換"),
        "getDefaultError": MessageLookupByLibrary.simpleMessage("獲取預設資料來源失敗"),
        "homePage": MessageLookupByLibrary.simpleMessage("主頁"),
        "inUse": MessageLookupByLibrary.simpleMessage("使用中"),
        "landscape": MessageLookupByLibrary.simpleMessage("橫屏模式"),
        "latestVersion": MessageLookupByLibrary.simpleMessage("已是最新版本"),
        "lineIndex": m0,
        "lineToast": m1,
        "loading": MessageLookupByLibrary.simpleMessage("正在載入頻道..."),
        "netBadResponse": m2,
        "netCancel": MessageLookupByLibrary.simpleMessage("請求取消"),
        "netReceiveTimeout": MessageLookupByLibrary.simpleMessage("響應超時"),
        "netSendTimeout": MessageLookupByLibrary.simpleMessage("請求超時"),
        "netTimeOut": MessageLookupByLibrary.simpleMessage("連線超時"),
        "newVersion": m3,
        "noEPG": MessageLookupByLibrary.simpleMessage("暫無節目資訊"),
        "okRefresh": MessageLookupByLibrary.simpleMessage("【OK鍵】重新整理"),
        "parseError": MessageLookupByLibrary.simpleMessage("解析資料來源出錯"),
        "pasterContent":
            MessageLookupByLibrary.simpleMessage("複製訂閱源後，回到此頁面可自動新增訂閱源"),
        "playError": MessageLookupByLibrary.simpleMessage("此頻道暫時無法播放，請等待修復"),
        "playReconnect": MessageLookupByLibrary.simpleMessage("出錯了，嘗試重新連線..."),
        "portrait": MessageLookupByLibrary.simpleMessage("豎屏模式"),
        "pushAddress": m4,
        "refresh": MessageLookupByLibrary.simpleMessage("重新整理"),
        "releaseHistory": MessageLookupByLibrary.simpleMessage("釋出歷史"),
        "setDefault": MessageLookupByLibrary.simpleMessage("設為預設"),
        "settings": MessageLookupByLibrary.simpleMessage("設定"),
        "subscribe": MessageLookupByLibrary.simpleMessage("訂閱"),
        "switchLine": m5,
        "tipChangeLine": MessageLookupByLibrary.simpleMessage("切換線路"),
        "tipChannelList": MessageLookupByLibrary.simpleMessage("頻道列表"),
        "tvParseParma": MessageLookupByLibrary.simpleMessage("引數錯誤"),
        "tvParsePushError": MessageLookupByLibrary.simpleMessage("請推送正確的連結"),
        "tvParseSuccess": MessageLookupByLibrary.simpleMessage("推送成功"),
        "tvPushContent": MessageLookupByLibrary.simpleMessage(
            "在掃碼結果頁，輸入新的訂閱源，點選頁面中的推送即可新增成功"),
        "tvScanTip": MessageLookupByLibrary.simpleMessage("掃碼新增訂閱源"),
        "update": MessageLookupByLibrary.simpleMessage("立即更新"),
        "updateContent": MessageLookupByLibrary.simpleMessage("更新內容"),
        "netReceiveTimeout": MessageLookupByLibrary.simpleMessage("響應超時"),
        "netSendTimeout": MessageLookupByLibrary.simpleMessage("請求超時"),
        "errorLoadingPage": MessageLookupByLibrary.simpleMessage("載入頁面出錯"),
        "logtitle": MessageLookupByLibrary.simpleMessage("日誌檢視器"),
        "SwitchTitle": MessageLookupByLibrary.simpleMessage("記錄日誌"),
        "logSubtitle": MessageLookupByLibrary.simpleMessage(
            "如非開發人員，無需開啟日誌開關"),
        "filterAll": MessageLookupByLibrary.simpleMessage("所有"),
        "filterVerbose": MessageLookupByLibrary.simpleMessage("詳細"),
        "filterError": MessageLookupByLibrary.simpleMessage("錯誤"),
        "filterInfo": MessageLookupByLibrary.simpleMessage("資訊"),
        "filterDebug": MessageLookupByLibrary.simpleMessage("偵錯"),
        "noLogs": MessageLookupByLibrary.simpleMessage("暫無日誌"),
        "logCleared": MessageLookupByLibrary.simpleMessage("日誌已清空"),
        "clearLogs": MessageLookupByLibrary.simpleMessage("清空日誌"),
        "programListTitle": MessageLookupByLibrary.simpleMessage("節目單"),
        "foundStreamTitle": MessageLookupByLibrary.simpleMessage("找到影片流"),
        "streamUrlContent": (url) =>
            "流URL: ${url}\n\n你想播放這個流嗎？",
        "cancelButton": MessageLookupByLibrary.simpleMessage("取消"),
        "playButton": MessageLookupByLibrary.simpleMessage("播放"),
        "downloading": (progress) => "下載中...${progress}%",
        "fontTitle": MessageLookupByLibrary.simpleMessage("字型"),
        "backgroundImageTitle": MessageLookupByLibrary.simpleMessage("背景圖"),
        "slogTitle": MessageLookupByLibrary.simpleMessage("日誌"),
        "updateTitle": MessageLookupByLibrary.simpleMessage("更新"),
        "backgroundImageDescription": MessageLookupByLibrary.simpleMessage(
            "自動更換播放音訊時的背景"),
        "dailyBing": MessageLookupByLibrary.simpleMessage("開啟背景切換"),
        "logCopied": MessageLookupByLibrary.simpleMessage("日誌已複製到剪貼簿"),
        "clipboardDataFetchError":
            MessageLookupByLibrary.simpleMessage("獲取剪貼簿資料失敗")
      };
}
