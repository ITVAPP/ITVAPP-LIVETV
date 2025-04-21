import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(index) => "Line ${index}";
  static String m1(line, channel) => "Connecting: ${channel} Line ${line}";
  static String m2(code) => "Bad Response ${code}";
  static String m3(version) => "New Version v${version}";
  static String m4(address) => "Push Address: ${address}";
  static String m5(line) => "Switching to line ${line}...";
  static String m6(url) => "Stream URL: ${url}. Play this stream?";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        "addDataSource": MessageLookupByLibrary.simpleMessage("Add Source"),
        "addFiledHintText":
            MessageLookupByLibrary.simpleMessage("Enter .m3u/.txt link"),
        "addNoHttpLink":
            MessageLookupByLibrary.simpleMessage("Enter http/https link"),
        "addRepeat":
            MessageLookupByLibrary.simpleMessage("Source already added"),
        "appName": MessageLookupByLibrary.simpleMessage("ITVAPP LIVETV"),
        "checkUpdate":
            MessageLookupByLibrary.simpleMessage("Check for Updates"),
        "createTime": MessageLookupByLibrary.simpleMessage("Created"),
        "dataSourceContent":
            MessageLookupByLibrary.simpleMessage("Add this source?"),
        "defaultText": MessageLookupByLibrary.simpleMessage("Default"),
        "delete": MessageLookupByLibrary.simpleMessage("Delete"),
        "dialogCancel": MessageLookupByLibrary.simpleMessage("Cancel"),
        "oldVersion": MessageLookupByLibrary.simpleMessage("Your version is outdated, update required!"),
        "dialogConfirm": MessageLookupByLibrary.simpleMessage("Confirm"),
        "dialogDeleteContent":
            MessageLookupByLibrary.simpleMessage("Delete subscription?"),
        "dialogTitle": MessageLookupByLibrary.simpleMessage("Reminder"),
        "findNewVersion":
            MessageLookupByLibrary.simpleMessage("New version found"),
        "fullScreen": MessageLookupByLibrary.simpleMessage("Full Screen"),
        "getDefaultError":
            MessageLookupByLibrary.simpleMessage("Failed to get default source"),
        "homePage": MessageLookupByLibrary.simpleMessage("Home"),
        "inUse": MessageLookupByLibrary.simpleMessage("In Use"),
        "use": MessageLookupByLibrary.simpleMessage("Use"),
        "languageSelection":
            MessageLookupByLibrary.simpleMessage("Select Language"),
        "fontSizeTitle": MessageLookupByLibrary.simpleMessage("Font Size"),
        "landscape": MessageLookupByLibrary.simpleMessage("Landscape"),
        "latestVersion": MessageLookupByLibrary.simpleMessage("Latest Version"),
        "lineIndex": m0,
        "lineToast": m1,
        "loading": MessageLookupByLibrary.simpleMessage("Loading..."),
        "netBadResponse": m2,
        "netCancel": MessageLookupByLibrary.simpleMessage("Request Cancelled"),
        "netReceiveTimeout":
            MessageLookupByLibrary.simpleMessage("Response Timeout"),
        "netSendTimeout":
            MessageLookupByLibrary.simpleMessage("Request Timeout"),
        "netTimeOut": MessageLookupByLibrary.simpleMessage("Timeout"),
        "newVersion": m3,
        "noEPG": MessageLookupByLibrary.simpleMessage("No program info"),
        "okRefresh": MessageLookupByLibrary.simpleMessage("[OK] to Refresh"),
        "exitTitle": MessageLookupByLibrary.simpleMessage("Exit Confirmation"),
        "exitMessage":
            MessageLookupByLibrary.simpleMessage("Are you sure you want to leave?"),
        "parseError": MessageLookupByLibrary.simpleMessage("Parse Error"),
        "pasterContent": MessageLookupByLibrary.simpleMessage(
            "Paste and return to auto-add source."),
        "playError":
            MessageLookupByLibrary.simpleMessage("Line unavailable. Please wait."),
        "playReconnect": MessageLookupByLibrary.simpleMessage("Retry"),
        "portrait": MessageLookupByLibrary.simpleMessage("Portrait"),
        "pushAddress": m4,
        "refresh": MessageLookupByLibrary.simpleMessage("Refresh"),
        "releaseHistory":
            MessageLookupByLibrary.simpleMessage("Release History"),
        "setDefault": MessageLookupByLibrary.simpleMessage("Set Default"),
        "settings": MessageLookupByLibrary.simpleMessage("Settings"),
        "subscribe": MessageLookupByLibrary.simpleMessage("Subscribe"),
        "switchLine": m5,
        "tipChangeLine": MessageLookupByLibrary.simpleMessage("Switch Line"),
        "tipChannelList": MessageLookupByLibrary.simpleMessage("Channels"),
        "tvParseParma": MessageLookupByLibrary.simpleMessage("Parameter Error"),
        "tvParsePushError": MessageLookupByLibrary.simpleMessage("Invalid link"),
        "tvParseSuccess":
            MessageLookupByLibrary.simpleMessage("Pushed Successfully"),
        "tvPushContent": MessageLookupByLibrary.simpleMessage(
            "Enter source in the scan page and push it."),
        "tvScanTip": MessageLookupByLibrary.simpleMessage("Scan to add"),
        "update": MessageLookupByLibrary.simpleMessage("Update"),
        "updateContent": MessageLookupByLibrary.simpleMessage("Update details"),
        "logtitle": MessageLookupByLibrary.simpleMessage("Logs"),
        "switchTitle": MessageLookupByLibrary.simpleMessage("Log Recording"),
        "logSubtitle": MessageLookupByLibrary.simpleMessage("Enable logs only for debugging"),
        "filterAll": MessageLookupByLibrary.simpleMessage("All"),
        "filterVerbose": MessageLookupByLibrary.simpleMessage("Verbose"),
        "filterError": MessageLookupByLibrary.simpleMessage("Errors"),
        "filterInfo": MessageLookupByLibrary.simpleMessage("Info"),
        "filterDebug": MessageLookupByLibrary.simpleMessage("Debug"),
        "noLogs": MessageLookupByLibrary.simpleMessage("No logs"),
        "logCleared": MessageLookupByLibrary.simpleMessage("Logs cleared"),
        "clearLogs": MessageLookupByLibrary.simpleMessage("Clear Logs"),
        "programListTitle": MessageLookupByLibrary.simpleMessage("TV Schedule"),
        "foundStreamTitle": MessageLookupByLibrary.simpleMessage("Stream Found"),
        "streamUrlContent": m6,
        "cancelButton": MessageLookupByLibrary.simpleMessage("Cancel"),
        "playButton": MessageLookupByLibrary.simpleMessage("Play"),
        "downloading": MessageLookupByLibrary.simpleMessage("Downloading..."),
        "downloadSuccess": MessageLookupByLibrary.simpleMessage("Download complete, please install!"),
        "downloadFailed": MessageLookupByLibrary.simpleMessage("Download failed, please try again later"),
        "platformNotSupported": MessageLookupByLibrary.simpleMessage("The system does not support in-app updates"),
        "fontTitle": MessageLookupByLibrary.simpleMessage("Font"),
        "backgroundImageTitle": MessageLookupByLibrary.simpleMessage("Background"),
        "slogTitle": MessageLookupByLibrary.simpleMessage("Logs"),
        "updateTitle": MessageLookupByLibrary.simpleMessage("Update"),
        "errorLoadingPage": MessageLookupByLibrary.simpleMessage("Page Load Error"),
        "backgroundImageDescription":
            MessageLookupByLibrary.simpleMessage("Change background with audio"),
        "dailyBing":
            MessageLookupByLibrary.simpleMessage("Enable background switch"),
        "logCopied": MessageLookupByLibrary.simpleMessage("Log copied"),
        "clipboardDataFetchError":
            MessageLookupByLibrary.simpleMessage("Failed to fetch clipboard data"),
        "nofavorite": MessageLookupByLibrary.simpleMessage("No Favorites"),
        "vpnplayError":
            MessageLookupByLibrary.simpleMessage("VPN required for some regions"),
        "retryplay": MessageLookupByLibrary.simpleMessage("Connection error, retrying..."),
        "channelnofavorite":
            MessageLookupByLibrary.simpleMessage("Can't add to favorites"),
        "removefavorite":
            MessageLookupByLibrary.simpleMessage("Removed from favorites"),
        "newfavorite": MessageLookupByLibrary.simpleMessage("Added to favorites"),
        "newfavoriteerror":
            MessageLookupByLibrary.simpleMessage("Failed to add to favorites"),
        "getm3udata": MessageLookupByLibrary.simpleMessage("Fetching data..."),
        "getm3udataerror":
            MessageLookupByLibrary.simpleMessage("Failed to fetch data..."),
        "myfavorite": MessageLookupByLibrary.simpleMessage("Favorites"),
        "addToFavorites": MessageLookupByLibrary.simpleMessage("Add to Favorites"),
        "removeFromFavorites":
            MessageLookupByLibrary.simpleMessage("Remove from Favorites"),
        "allchannels": MessageLookupByLibrary.simpleMessage("Other Channels"),
        "copy": MessageLookupByLibrary.simpleMessage("Copy"),
        "copyok": MessageLookupByLibrary.simpleMessage("Copied to clipboard"),
        "startsurlerror": MessageLookupByLibrary.simpleMessage("URL Parse Error"),
        "gethttperror":
            MessageLookupByLibrary.simpleMessage("Network config failed"),
        "exittip":
            MessageLookupByLibrary.simpleMessage("We look forward to your next visit"),
        "playpause": MessageLookupByLibrary.simpleMessage("Paused"),
        "remotehelp": MessageLookupByLibrary.simpleMessage("Help"),
        "remotehelpup":
            MessageLookupByLibrary.simpleMessage("Press 'Up' for line switch"),
        "remotehelpleft":
            MessageLookupByLibrary.simpleMessage("Press 'Left' to favorite channel"),
        "remotehelpdown":
            MessageLookupByLibrary.simpleMessage("Press 'Down' for settings"),
        "remotehelpok": MessageLookupByLibrary.simpleMessage(
            "Press 'OK' to confirm\nShow time/Pause/Play"),
        "remotehelpright":
            MessageLookupByLibrary.simpleMessage("Press 'Right' to open channel menu"),
        "remotehelpback":
            MessageLookupByLibrary.simpleMessage("Press 'Back' to exit/cancel"),
        "remotehelpclose":
            MessageLookupByLibrary.simpleMessage("Press any key to close help")
      };
}
