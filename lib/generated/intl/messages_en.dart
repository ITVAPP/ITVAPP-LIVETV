import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(index) => "line ${index}";

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
        "Use": MessageLookupByLibrary.simpleMessage("Use"),
        "languageSelection": MessageLookupByLibrary.simpleMessage("Language Selection"),
        "fontSizeTitle": MessageLookupByLibrary.simpleMessage("Font Size"),
        "landscape": MessageLookupByLibrary.simpleMessage("Landscape Mode"),
        "latestVersion": MessageLookupByLibrary.simpleMessage(
            "You are on the latest version"),
        "lineIndex": m0,
        "lineToast": m1,
        "loading": MessageLookupByLibrary.simpleMessage("Loading..."),
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
        "exitTitle": MessageLookupByLibrary.simpleMessage("Exit Application Confirmation"),
        "exitMessage": MessageLookupByLibrary.simpleMessage("Are you sure you want to leave ITV Live TV?"),
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
            MessageLookupByLibrary.simpleMessage("TV schedule"),
        "foundStreamTitle": MessageLookupByLibrary.simpleMessage("Stream Found"),
        "streamUrlContent": (url) =>
            "Stream URL: ${url}\n\nDo you want to play this stream?",
        "cancelButton": MessageLookupByLibrary.simpleMessage("Cancel"),
        "playButton": MessageLookupByLibrary.simpleMessage("Play"),
        "downloading": MessageLookupByLibrary.simpleMessage("Downloading..."), 
        "fontTitle": MessageLookupByLibrary.simpleMessage("Font"),
        "backgroundImageTitle":
            MessageLookupByLibrary.simpleMessage("Background Image"),
        "slogTitle": MessageLookupByLibrary.simpleMessage("Logs"),
        "updateTitle": MessageLookupByLibrary.simpleMessage("Update"),
        "errorLoadingPage": MessageLookupByLibrary.simpleMessage("Error loading page"),
        "backgroundImageDescription": MessageLookupByLibrary.simpleMessage("Automatically change background when playing audio"),
        "dailyBing": MessageLookupByLibrary.simpleMessage("Enable background switching"),
        "logCopied": MessageLookupByLibrary.simpleMessage("The log has been copied to the clipboard"),
        "clipboardDataFetchError": MessageLookupByLibrary.simpleMessage("Failed to fetch clipboard data"),
        "nofavorite": MessageLookupByLibrary.simpleMessage("No favorites"),
        "vpnplayError": MessageLookupByLibrary.simpleMessage("This channel requires a VPN in some regions"),
        "retryplay": MessageLookupByLibrary.simpleMessage("Connection error, retrying..."),
        "channelnofavorite": MessageLookupByLibrary.simpleMessage("This channel cannot be added to favorites"),
        "removefavorite": MessageLookupByLibrary.simpleMessage("Channel removed from favorites"),
        "newfavorite": MessageLookupByLibrary.simpleMessage("Channel added to favorites"),
        "newfavoriteerror": MessageLookupByLibrary.simpleMessage("Failed to add to favorites"),
        "getm3udata": MessageLookupByLibrary.simpleMessage("Fetching playback data..."),
        "getm3udataerror": MessageLookupByLibrary.simpleMessage("Failed to fetch playback data..."),
        "myfavorite": MessageLookupByLibrary.simpleMessage("My favorites"),
        "addToFavorites": MessageLookupByLibrary.simpleMessage("Add to Favorites"),
        "removeFromFavorites": MessageLookupByLibrary.simpleMessage("Remove from Favorites"),
        "allchannels": MessageLookupByLibrary.simpleMessage("Other channels"),
        "copy": MessageLookupByLibrary.simpleMessage("Copy"),
        "copyok": MessageLookupByLibrary.simpleMessage("Content copied to clipboard"),
        "startsurlerror": MessageLookupByLibrary.simpleMessage("Failed to parse URL"),
        "gethttperror": MessageLookupByLibrary.simpleMessage("Local network configuration failed"),
        "exittip": MessageLookupByLibrary.simpleMessage("We look forward to your next visit"),
        "playpause": MessageLookupByLibrary.simpleMessage("Pausing playback..."),
        "remotehelp": MessageLookupByLibrary.simpleMessage("Help"),
        "remotehelpup": MessageLookupByLibrary.simpleMessage("Press 'Up' to open the line switch menu"),
        "remotehelpleft": MessageLookupByLibrary.simpleMessage("Press 'Left' to add/remove channel from favorites"),
        "remotehelpdown": MessageLookupByLibrary.simpleMessage("Press 'Down' to open the application settings"),
        "remotehelpok": MessageLookupByLibrary.simpleMessage("Press 'OK' to confirm the selection\nShow time/Pause/Play"),
        "remotehelpright": MessageLookupByLibrary.simpleMessage("Press 'Right' to open the channel selection drawer"),
        "remotehelpback": MessageLookupByLibrary.simpleMessage("Press 'Back' to exit/cancel the operation"),
        "remotehelpclose": MessageLookupByLibrary.simpleMessage("Press any key to close the help")
      };
}
