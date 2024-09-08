import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(line, channel) => "Line ${line} playing: ${channel}";

  static String m1(line) => "Switching to line ${line} ...";

  static String m2(index) => "Line ${index}";

  static String m3(retryCount, maxRetries) => "Fetching data... (${retryCount}/${maxRetries})";

  static String m4(version) => "New Version v${version}";

  static String m5(address) => "Push Address: ${address}";

  static String m6(code) => "Abnormal response ${code}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "appName": MessageLookupByLibrary.simpleMessage("ITVAPP LIVETV"),
        "loading": MessageLookupByLibrary.simpleMessage("Loading"),
        "lineToast": m0,
        "playError": MessageLookupByLibrary.simpleMessage("This video cannot be played, please switch to another channel"),
        "switchLine": m1,
        "playReconnect": MessageLookupByLibrary.simpleMessage("An error occurred, trying to reconnect..."),
        "lineIndex": m2,
        "gettingData": m3,
        "loadingData": MessageLookupByLibrary.simpleMessage("Fetching data..."),
        "errorLoadingData": MessageLookupByLibrary.simpleMessage("Failed to load data, please try again later"),
        "retry": MessageLookupByLibrary.simpleMessage("Retry"),
        "tipChannelList": MessageLookupByLibrary.simpleMessage("Channel List"),
        "tipChangeLine": MessageLookupByLibrary.simpleMessage("Switch Line"),
        "portrait": MessageLookupByLibrary.simpleMessage("Portrait Mode"),
        "landscape": MessageLookupByLibrary.simpleMessage("Landscape Mode"),
        "fullScreen": MessageLookupByLibrary.simpleMessage("Full Screen Toggle"),
        "settings": MessageLookupByLibrary.simpleMessage("Settings"),
        "homePage": MessageLookupByLibrary.simpleMessage("Home Page"),
        "releaseHistory": MessageLookupByLibrary.simpleMessage("Release History"),
        "checkUpdate": MessageLookupByLibrary.simpleMessage("Check for Updates"),
        "newVersion": m4,
        "update": MessageLookupByLibrary.simpleMessage("Update Now"),
        "latestVersion": MessageLookupByLibrary.simpleMessage("You are on the latest version"),
        "findNewVersion": MessageLookupByLibrary.simpleMessage("New version found"),
        "updateContent": MessageLookupByLibrary.simpleMessage("Update Content"),
        "dialogTitle": MessageLookupByLibrary.simpleMessage("Friendly Reminder"),
        "dataSourceContent": MessageLookupByLibrary.simpleMessage("Are you sure you want to add this data source?"),
        "dialogCancel": MessageLookupByLibrary.simpleMessage("Cancel"),
        "dialogConfirm": MessageLookupByLibrary.simpleMessage("Confirm"),
        "subscribe": MessageLookupByLibrary.simpleMessage("IPTV Subscription"),
        "createTime": MessageLookupByLibrary.simpleMessage("Creation Time"),
        "dialogDeleteContent": MessageLookupByLibrary.simpleMessage("Are you sure you want to delete this subscription?"),
        "delete": MessageLookupByLibrary.simpleMessage("Delete"),
        "setDefault": MessageLookupByLibrary.simpleMessage("Set as Default"),
        "inUse": MessageLookupByLibrary.simpleMessage("In Use"),
        "tvParseParma": MessageLookupByLibrary.simpleMessage("Parameter Error"),
        "tvParseSuccess": MessageLookupByLibrary.simpleMessage("Push Successful"),
        "tvParsePushError": MessageLookupByLibrary.simpleMessage("Please push the correct link"),
        "tvScanTip": MessageLookupByLibrary.simpleMessage("Scan to add subscription source"),
        "pushAddress": m5,
        "tvPushContent": MessageLookupByLibrary.simpleMessage("On the scan result page, enter the new subscription source and click the push button to add successfully"),
        "pasterContent": MessageLookupByLibrary.simpleMessage("After copying the subscription source, return to this page to automatically add the subscription source"),
        "addDataSource": MessageLookupByLibrary.simpleMessage("Add Subscription Source"),
        "addFiledHintText": MessageLookupByLibrary.simpleMessage("Please enter or paste the .m3u or .txt format subscription link"),
        "addRepeat": MessageLookupByLibrary.simpleMessage("This subscription source has been added"),
        "addNoHttpLink": MessageLookupByLibrary.simpleMessage("Please enter an http/https link"),
        "netTimeOut": MessageLookupByLibrary.simpleMessage("Connection timed out"),
        "netSendTimeout": MessageLookupByLibrary.simpleMessage("Request timed out"),
        "netReceiveTimeout": MessageLookupByLibrary.simpleMessage("Response timed out"),
        "netBadResponse": m6,
        "netCancel": MessageLookupByLibrary.simpleMessage("Request Cancelled"),
        "parseError": MessageLookupByLibrary.simpleMessage("Error parsing data source"),
        "defaultText": MessageLookupByLibrary.simpleMessage("Default"),
        "getDefaultError": MessageLookupByLibrary.simpleMessage("Failed to get the default data source"),
        "okRefresh": MessageLookupByLibrary.simpleMessage("【OK key】 Refresh"),
        "refresh": MessageLookupByLibrary.simpleMessage("Refresh"),
        "noEPG": MessageLookupByLibrary.simpleMessage("NO EPG DATA")
      };
}
