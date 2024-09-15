import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(index) => "Connecting to line ${index}...";

  static String m1(line, channel) => "Connecting: ${channel} Line ${line}";

  static String m2(code) => "Bad Response ${code}";

  static String m3(version) => "New Version v${version}";

  static String m4(address) => "Push Address: ${address}";

  static String m5(line) => "Switching to line ${line} ...";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "addDataSource":
            MessageLookupByLibrary.simpleMessage("Add Subscription Source"),
        "addFiledHintText": MessageLookupByLibrary.simpleMessage(
            "Please enter or paste a subscription source link in .m3u or .txt format"),
        "addNoHttpLink": MessageLookupByLibrary.simpleMessage(
            "Please enter an http/https link"),
        "addRepeat": MessageLookupByLibrary.simpleMessage(
            "This subscription source has already been added"),
        "appName": MessageLookupByLibrary.simpleMessage("ITVAPP LIVETV"),
        "checkUpdate":
            MessageLookupByLibrary.simpleMessage("Check for Updates"),
        "createTime": MessageLookupByLibrary.simpleMessage("Creation Time"),
        "dataSourceContent": MessageLookupByLibrary.simpleMessage(
            "Are you sure you want to add this data source?"),
        "defaultText": MessageLookupByLibrary.simpleMessage("Default"),
        "delete": MessageLookupByLibrary.simpleMessage("Delete"),
        "dialogCancel": MessageLookupByLibrary.simpleMessage("Cancel"),
        "dialogConfirm": MessageLookupByLibrary.simpleMessage("Confirm"),
        "dialogDeleteContent": MessageLookupByLibrary.simpleMessage(
            "Are you sure you want to delete this subscription?"),
        "dialogTitle":
            MessageLookupByLibrary.simpleMessage("Friendly Reminder"),
        "findNewVersion":
            MessageLookupByLibrary.simpleMessage("New version found"),
        "fullScreen":
            MessageLookupByLibrary.simpleMessage("Toggle Full Screen"),
        "getDefaultError": MessageLookupByLibrary.simpleMessage(
            "Failed to retrieve default data source"),
        "homePage": MessageLookupByLibrary.simpleMessage("Home Page"),
        "inUse": MessageLookupByLibrary.simpleMessage("In Use"),
        "landscape": MessageLookupByLibrary.simpleMessage("Landscape Mode"),
        "latestVersion": MessageLookupByLibrary.simpleMessage(
            "You are on the latest version"),
        "lineIndex": m0,
        "lineToast": m1,
        "loading": MessageLookupByLibrary.simpleMessage("Loading channels..."),
        "netBadResponse": m2,
        "netCancel": MessageLookupByLibrary.simpleMessage("Request Cancelled"),
        "netReceiveTimeout":
            MessageLookupByLibrary.simpleMessage("Response Timeout"),
        "netSendTimeout":
            MessageLookupByLibrary.simpleMessage("Request Timeout"),
        "netTimeOut":
            MessageLookupByLibrary.simpleMessage("Connection Timeout"),
        "newVersion": m3,
        "noEPG": MessageLookupByLibrary.simpleMessage(
            "No program information available"),
        "okRefresh": MessageLookupByLibrary.simpleMessage("[OK] to Refresh"),
        "parseError":
            MessageLookupByLibrary.simpleMessage("Error parsing data source"),
        "pasterContent": MessageLookupByLibrary.simpleMessage(
            "After copying the subscription source, return to this page to automatically add the subscription source"),
        "playError": MessageLookupByLibrary.simpleMessage(
            "This line is temporarily unavailable, please wait for it to be fixed"),
        "playReconnect": MessageLookupByLibrary.simpleMessage(
            "An error occurred, trying to reconnect..."),
        "portrait": MessageLookupByLibrary.simpleMessage("Portrait Mode"),
        "pushAddress": m4,
        "refresh": MessageLookupByLibrary.simpleMessage("Refresh"),
        "releaseHistory":
            MessageLookupByLibrary.simpleMessage("Release History"),
        "setDefault": MessageLookupByLibrary.simpleMessage("Set as Default"),
        "settings": MessageLookupByLibrary.simpleMessage("Settings"),
        "subscribe": MessageLookupByLibrary.simpleMessage("Subscribe"),
        "switchLine": m5,
        "tipChangeLine": MessageLookupByLibrary.simpleMessage("Switch Line"),
        "tipChannelList": MessageLookupByLibrary.simpleMessage("Channel List"),
        "tvParseParma": MessageLookupByLibrary.simpleMessage("Parameter Error"),
        "tvParsePushError": MessageLookupByLibrary.simpleMessage(
            "Please push a valid link"),
        "tvParseSuccess":
            MessageLookupByLibrary.simpleMessage("Pushed Successfully"),
        "tvPushContent": MessageLookupByLibrary.simpleMessage(
            "In the scan result page, enter a new subscription source, and click 'Push' on the page to add it successfully"),
        "tvScanTip": MessageLookupByLibrary.simpleMessage(
            "Scan to add subscription source"),
        "update": MessageLookupByLibrary.simpleMessage("Update Now"),
        "updateContent": MessageLookupByLibrary.simpleMessage("Update Content"),
        "logtitle": MessageLookupByLibrary.simpleMessage("Log Viewer"),
        "SwitchTitle": MessageLookupByLibrary.simpleMessage("Log Recording"),
        "logSubtitle": MessageLookupByLibrary.simpleMessage(
            "Unless debugging as a developer, there's no need to enable logs"),
        "filterAll": MessageLookupByLibrary.simpleMessage("All"),
        "filterVerbose": MessageLookupByLibrary.simpleMessage("Verbose"),
        "filterError": MessageLookupByLibrary.simpleMessage("Error"),
        "filterInfo": MessageLookupByLibrary.simpleMessage("Info"),
        "filterDebug": MessageLookupByLibrary.simpleMessage("Debug"),
        "noLogs": MessageLookupByLibrary.simpleMessage("No logs available"),
        "logCleared": MessageLookupByLibrary.simpleMessage("Logs cleared"),
        "clearLogs": MessageLookupByLibrary.simpleMessage("Clear Logs"),
        "programListTitle":
            MessageLookupByLibrary.simpleMessage("Channel List"),
        "foundStreamTitle": MessageLookupByLibrary.simpleMessage("Stream Found"),
        "streamUrlContent": (url) =>
            "Stream URL: ${url}\n\nDo you want to play this stream?",
        "cancelButton": MessageLookupByLibrary.simpleMessage("Cancel"),
        "playButton": MessageLookupByLibrary.simpleMessage("Play"),
        "downloading": (progress) =>
            "Downloading... ${progress}%",
        "fontTitle": MessageLookupByLibrary.simpleMessage("Font"),
        "backgroundImageTitle":
            MessageLookupByLibrary.simpleMessage("Background Image"),
        "slogTitle": MessageLookupByLibrary.simpleMessage("Logs"),
        "updateTitle": MessageLookupByLibrary.simpleMessage("Update"),
        "errorLoadingPage": MessageLookupByLibrary.simpleMessage("Error loading page"),
        "backgroundImageDescription": MessageLookupByLibrary.simpleMessage("Automatically change background when playing audio"),
        "dailyBing": MessageLookupByLibrary.simpleMessage("Enable background switching"),
        "clipboardDataFetchError": MessageLookupByLibrary.simpleMessage("Failed to fetch clipboard data")
      };
}
