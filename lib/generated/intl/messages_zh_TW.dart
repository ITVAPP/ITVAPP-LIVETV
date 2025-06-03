import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'zh_CN';

  static String m0(index) => "線路${index}";

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
        "oldVersion": MessageLookupByLibrary.simpleMessage("您的版本已不再支援，請更新!"),
        "fullScreen": MessageLookupByLibrary.simpleMessage("全屏切換"),
        "getDefaultError": MessageLookupByLibrary.simpleMessage("獲取預設資料來源失敗"),
        "homePage": MessageLookupByLibrary.simpleMessage("主頁"),
        "inUse": MessageLookupByLibrary.simpleMessage("使用中"),
        "Use": MessageLookupByLibrary.simpleMessage("使用"),
        "languageSelection": MessageLookupByLibrary.simpleMessage("語言選擇"),
        "fontSizeTitle": MessageLookupByLibrary.simpleMessage("字型大小"),
        "landscape": MessageLookupByLibrary.simpleMessage("橫屏模式"),
        "latestVersion": MessageLookupByLibrary.simpleMessage("已是最新版本"),
        "lineIndex": m0,
        "lineToast": m1,
        "loading": MessageLookupByLibrary.simpleMessage("正在載入..."),
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
            MessageLookupByLibrary.simpleMessage("復制訂閱源後，回到此頁面可自動新增訂閱源"),
        "playError": MessageLookupByLibrary.simpleMessage("此頻道暫時無法播放，請等待修復"),
        "playReconnect": MessageLookupByLibrary.simpleMessage("重試連線"),
        "portrait": MessageLookupByLibrary.simpleMessage("豎屏模式"),
        "pushAddress": m4,
        "refresh": MessageLookupByLibrary.simpleMessage("重新整理"),
        "releaseHistory": MessageLookupByLibrary.simpleMessage("發布歷史"),
        "setDefault": MessageLookupByLibrary.simpleMessage("設爲預設"),
        "settings": MessageLookupByLibrary.simpleMessage("設定"),
        "subscribe": MessageLookupByLibrary.simpleMessage("訂閱"),
        "switchLine": m5,
        "exitTitle": MessageLookupByLibrary.simpleMessage("退出應用確認"),
        "exitMessage": MessageLookupByLibrary.simpleMessage("你確定要離開電視寶直播嗎?"),
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
        "logtitle": MessageLookupByLibrary.simpleMessage("日志檢視器"),
        "switchTitle": MessageLookupByLibrary.simpleMessage("記錄日志"),
        "logSubtitle": MessageLookupByLibrary.simpleMessage(
            "如非開發人員，無需開啟日志開關"),
        "filterAll": MessageLookupByLibrary.simpleMessage("所有"),
        "filterVerbose": MessageLookupByLibrary.simpleMessage("詳細"),
        "filterError": MessageLookupByLibrary.simpleMessage("錯誤"),
        "filterInfo": MessageLookupByLibrary.simpleMessage("資訊"),
        "filterDebug": MessageLookupByLibrary.simpleMessage("偵錯"),
        "noLogs": MessageLookupByLibrary.simpleMessage("暫無日志"),
        "logCleared": MessageLookupByLibrary.simpleMessage("日志已清空"),
        "clearLogs": MessageLookupByLibrary.simpleMessage("清空日志"),
        "programListTitle": MessageLookupByLibrary.simpleMessage("節目單"),
        "foundStreamTitle": MessageLookupByLibrary.simpleMessage("找到影片流"),
        "streamUrlContent": (url) =>
            "流URL: ${url}\n\n你想播放這個流嗎？",
        "cancelButton": MessageLookupByLibrary.simpleMessage("取消"),
        "playButton": MessageLookupByLibrary.simpleMessage("播放"),
        "downloading":  MessageLookupByLibrary.simpleMessage("下載中..."),
        "downloadSuccess":  MessageLookupByLibrary.simpleMessage("下載完成，請安裝！"),
        "downloadFailed":  MessageLookupByLibrary.simpleMessage("下載失敗，請稍後重試"),
        "fontTitle": MessageLookupByLibrary.simpleMessage("字型設定"),
        "langTip": MessageLookupByLibrary.simpleMessage("重啓後才可以完全應用新的語言設定"),
        "backgroundImageTitle": MessageLookupByLibrary.simpleMessage("背景圖"),
        "slogTitle": MessageLookupByLibrary.simpleMessage("日志"),
        "updateTitle": MessageLookupByLibrary.simpleMessage("更新"),
        "backgroundImageDescription": MessageLookupByLibrary.simpleMessage(
            "自動更換播放音訊時的背景"),
        "dailyBing": MessageLookupByLibrary.simpleMessage("開啓背景切換"),
        "logCopied": MessageLookupByLibrary.simpleMessage("日志已復制到剪貼板"),
        "clipboardDataFetchError":
            MessageLookupByLibrary.simpleMessage("獲取剪貼板資料失敗"),
        "nofavorite": MessageLookupByLibrary.simpleMessage("暫無收藏"),
        "vpnplayError": MessageLookupByLibrary.simpleMessage("此頻道在部分地區需要VPN才可以觀看"),
        "retryplay": MessageLookupByLibrary.simpleMessage("連線出錯，正在重試..."),
        "channelnofavorite": MessageLookupByLibrary.simpleMessage("當前頻道無法收藏"),
        "removefavorite": MessageLookupByLibrary.simpleMessage("頻道已從收藏中移除"),
        "newfavorite": MessageLookupByLibrary.simpleMessage("頻道已新增到收藏"),
        "newfavoriteerror": MessageLookupByLibrary.simpleMessage("新增收藏失敗"),
        "getm3udata": MessageLookupByLibrary.simpleMessage("正在獲取播放資料..."),
        "getm3udataerror": MessageLookupByLibrary.simpleMessage("獲取播放資料失敗..."),
        "myfavorite": MessageLookupByLibrary.simpleMessage("收藏"),
        "addToFavorites": MessageLookupByLibrary.simpleMessage("新增收藏"),
        "removeFromFavorites": MessageLookupByLibrary.simpleMessage("取消收藏"),
        "allchannels": MessageLookupByLibrary.simpleMessage("其它頻道"),
        "copy": MessageLookupByLibrary.simpleMessage("復制"),
        "copyok": MessageLookupByLibrary.simpleMessage("內容已復制到剪貼板"),
        "startsurlerror": MessageLookupByLibrary.simpleMessage("解析 URL 失敗"),
        "gethttperror": MessageLookupByLibrary.simpleMessage("本地網路配置失敗"),
        "exittip": MessageLookupByLibrary.simpleMessage("期待你下一次的訪問"),
        "playpause": MessageLookupByLibrary.simpleMessage("暫停播放中..."),
        "aboutApp": MessageLookupByLibrary.simpleMessage("關於我們"),
        "officialWebsite": MessageLookupByLibrary.simpleMessage("官方網站"),
        "officialEmail": MessageLookupByLibrary.simpleMessage("反饋建議郵箱"),
        "algorithmReport": MessageLookupByLibrary.simpleMessage("合作聯系郵箱"),
        "rateApp": MessageLookupByLibrary.simpleMessage("應用商店評分"),
        "rateAppDescription": MessageLookupByLibrary.simpleMessage("爲我們打分，支援開發"),
        "emailCopied": MessageLookupByLibrary.simpleMessage("已復制到剪貼板"),
        "copyFailed": MessageLookupByLibrary.simpleMessage("復制失敗"),
        "openingAppStore": MessageLookupByLibrary.simpleMessage("正在開啟應用商店..."),
        "openAppStoreFailed": MessageLookupByLibrary.simpleMessage("開啟應用商店失敗"),
        "platformNotSupported": MessageLookupByLibrary.simpleMessage("當前平臺不支援此功能"),
        "userAgreement": MessageLookupByLibrary.simpleMessage("使用者協議"),
        "loadFailed": MessageLookupByLibrary.simpleMessage("載入協議失敗"),
        "retry": MessageLookupByLibrary.simpleMessage("重試"),
        "updateDate": MessageLookupByLibrary.simpleMessage("更新日期"),
        "effectiveDate": MessageLookupByLibrary.simpleMessage("生效日期"),
        "remotehelp": MessageLookupByLibrary.simpleMessage("幫助"),
        "remotehelpup": MessageLookupByLibrary.simpleMessage("「點選上鍵」開啟 線路切換選單"),
        "remotehelpleft": MessageLookupByLibrary.simpleMessage("「點選左鍵」新增/取消 頻道收藏"),
        "remotehelpdown": MessageLookupByLibrary.simpleMessage("「點選下鍵」開啟 應用設定界面"),
        "remotehelpok": MessageLookupByLibrary.simpleMessage("「點選確認鍵」確認選擇操作\n顯示時間/暫停/播放"),
        "remotehelpright": MessageLookupByLibrary.simpleMessage("「點選右鍵」開啟 頻道選擇抽屜"),
        "remotehelpback": MessageLookupByLibrary.simpleMessage("「點選返回鍵」退出/取消操作"),
        "remotehelpclose": MessageLookupByLibrary.simpleMessage("點選任意按鍵關閉幫助")
      };
}
