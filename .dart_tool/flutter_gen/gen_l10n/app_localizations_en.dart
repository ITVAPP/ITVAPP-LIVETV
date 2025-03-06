import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'ITVAPP LIVETV';

  @override
  String get loading => 'Loading...';

  @override
  String lineToast(Object line, Object channel) {
    return 'Connecting: $channel Line $line';
  }

  @override
  String get playError => 'Line unavailable. Please wait.';

  @override
  String switchLine(Object line) {
    return 'Switching to line $line...';
  }

  @override
  String get playReconnect => 'Retry';

  @override
  String lineIndex(Object index) {
    return 'Line $index';
  }

  @override
  String get exitTitle => 'Exit Confirmation';

  @override
  String get exitMessage => 'Are you sure you want to leave?';

  @override
  String get tipChannelList => 'Channels';

  @override
  String get tipChangeLine => 'Switch Line';

  @override
  String get portrait => 'Portrait';

  @override
  String get landscape => 'Landscape';

  @override
  String get fullScreen => 'Full Screen';

  @override
  String get settings => 'Settings';

  @override
  String get homePage => 'Home';

  @override
  String get releaseHistory => 'Release History';

  @override
  String get checkUpdate => 'Check for Updates';

  @override
  String newVersion(Object version) {
    return 'New Version v$version';
  }

  @override
  String get update => 'Update';

  @override
  String get latestVersion => 'Latest Version';

  @override
  String get findNewVersion => 'New version found';

  @override
  String get updateContent => 'Update details';

  @override
  String get dialogTitle => 'Reminder';

  @override
  String get dataSourceContent => 'Add this source?';

  @override
  String get dialogCancel => 'Cancel';

  @override
  String get dialogConfirm => 'Confirm';

  @override
  String get subscribe => 'Subscribe';

  @override
  String get createTime => 'Created';

  @override
  String get dialogDeleteContent => 'Delete subscription?';

  @override
  String get delete => 'Delete';

  @override
  String get setDefault => 'Set Default';

  @override
  String get inUse => 'In Use';

  @override
  String get tvParseParma => 'Parameter Error';

  @override
  String get tvParseSuccess => 'Pushed Successfully';

  @override
  String get tvParsePushError => 'Invalid link';

  @override
  String get tvScanTip => 'Scan to add';

  @override
  String pushAddress(Object address) {
    return 'Push Address: $address';
  }

  @override
  String get tvPushContent => 'Enter source in the scan page and push it.';

  @override
  String get pasterContent => 'Paste and return to auto-add source.';

  @override
  String get addDataSource => 'Add Source';

  @override
  String get addFiledHintText => 'Enter .m3u/.txt link';

  @override
  String get addRepeat => 'Source already added';

  @override
  String get addNoHttpLink => 'Enter http/https link';

  @override
  String get netTimeOut => 'Timeout';

  @override
  String get netSendTimeout => 'Request Timeout';

  @override
  String get netReceiveTimeout => 'Response Timeout';

  @override
  String netBadResponse(Object code) {
    return 'Bad Response $code';
  }

  @override
  String get netCancel => 'Request Cancelled';

  @override
  String get parseError => 'Parse Error';

  @override
  String get defaultText => 'Default';

  @override
  String get getDefaultError => 'Failed to get default source';

  @override
  String get okRefresh => '[OK] to Refresh';

  @override
  String get refresh => 'Refresh';

  @override
  String get noEPG => 'No program info';

  @override
  String get logtitle => 'Logs';

  @override
  String get switchTitle => 'Log Recording';

  @override
  String get logSubtitle => 'Enable logs only for debugging';

  @override
  String get filterAll => 'All';

  @override
  String get filterVerbose => 'Verbose';

  @override
  String get filterError => 'Errors';

  @override
  String get filterInfo => 'Info';

  @override
  String get filterDebug => 'Debug';

  @override
  String get noLogs => 'No logs';

  @override
  String get logCleared => 'Logs cleared';

  @override
  String get clearLogs => 'Clear Logs';

  @override
  String get programListTitle => 'TV Schedule';

  @override
  String get foundStreamTitle => 'Stream Found';

  @override
  String streamUrlContent(Object url) {
    return 'Stream URL: $url. Play this stream?';
  }

  @override
  String get cancelButton => 'Cancel';

  @override
  String get playButton => 'Play';

  @override
  String get downloading => 'Downloading...';

  @override
  String get fontTitle => 'Font';

  @override
  String get backgroundImageTitle => 'Background';

  @override
  String get slogTitle => 'Logs';

  @override
  String get updateTitle => 'Update';

  @override
  String get errorLoadingPage => 'Page Load Error';

  @override
  String get backgroundImageDescription => 'Change background with audio';

  @override
  String get dailyBing => 'Enable background switch';

  @override
  String get use => 'Use';

  @override
  String get languageSelection => 'Select Language';

  @override
  String get fontSizeTitle => 'Font Size';

  @override
  String get logCopied => 'Log copied';

  @override
  String get clipboardDataFetchError => 'Failed to fetch clipboard data';

  @override
  String get nofavorite => 'No Favorites';

  @override
  String get vpnplayError => 'VPN required for some regions';

  @override
  String get retryplay => 'Connection error, retrying...';

  @override
  String get channelnofavorite => 'Can\'t add to favorites';

  @override
  String get removefavorite => 'Removed from favorites';

  @override
  String get newfavorite => 'Added to favorites';

  @override
  String get newfavoriteerror => 'Failed to add to favorites';

  @override
  String get getm3udata => 'Fetching data...';

  @override
  String get getm3udataerror => 'Failed to fetch data...';

  @override
  String get myfavorite => 'My Favorites';

  @override
  String get addToFavorites => 'Add to Favorites';

  @override
  String get removeFromFavorites => 'Remove from Favorites';

  @override
  String get allchannels => 'Other Channels';

  @override
  String get copy => 'Copy';

  @override
  String get copyok => 'Copied to clipboard';

  @override
  String get startsurlerror => 'URL Parse Error';

  @override
  String get gethttperror => 'Network config failed';

  @override
  String get exittip => 'We look forward to your next visit';

  @override
  String get playpause => 'Paused';

  @override
  String get remotehelp => 'Help';

  @override
  String get remotehelpup => 'Press \'Up\' for line switch';

  @override
  String get remotehelpleft => 'Press \'Left\' to favorite channel';

  @override
  String get remotehelpdown => 'Press \'Down\' for settings';

  @override
  String get remotehelpok => 'Press \'OK\' to confirm\nShow time/Pause/Play';

  @override
  String get remotehelpright => 'Press \'Right\' to open channel menu';

  @override
  String get remotehelpback => 'Press \'Back\' to exit/cancel';

  @override
  String get remotehelpclose => 'Press any key to close help';
}
