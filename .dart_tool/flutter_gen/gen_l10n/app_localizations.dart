import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen_l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'ITVAPP LIVETV'**
  String get appName;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @lineToast.
  ///
  /// In en, this message translates to:
  /// **'Connecting: {channel} Line {line}'**
  String lineToast(Object line, Object channel);

  /// No description provided for @playError.
  ///
  /// In en, this message translates to:
  /// **'Line unavailable. Please wait.'**
  String get playError;

  /// No description provided for @switchLine.
  ///
  /// In en, this message translates to:
  /// **'Switching to line {line}...'**
  String switchLine(Object line);

  /// No description provided for @playReconnect.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get playReconnect;

  /// No description provided for @lineIndex.
  ///
  /// In en, this message translates to:
  /// **'Line {index}'**
  String lineIndex(Object index);

  /// No description provided for @exitTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit Confirmation'**
  String get exitTitle;

  /// No description provided for @exitMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to leave?'**
  String get exitMessage;

  /// No description provided for @tipChannelList.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get tipChannelList;

  /// No description provided for @tipChangeLine.
  ///
  /// In en, this message translates to:
  /// **'Switch Line'**
  String get tipChangeLine;

  /// No description provided for @portrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get portrait;

  /// No description provided for @landscape.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get landscape;

  /// No description provided for @fullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full Screen'**
  String get fullScreen;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @homePage.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homePage;

  /// No description provided for @releaseHistory.
  ///
  /// In en, this message translates to:
  /// **'Release History'**
  String get releaseHistory;

  /// No description provided for @checkUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get checkUpdate;

  /// No description provided for @newVersion.
  ///
  /// In en, this message translates to:
  /// **'New Version v{version}'**
  String newVersion(Object version);

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @latestVersion.
  ///
  /// In en, this message translates to:
  /// **'Latest Version'**
  String get latestVersion;

  /// No description provided for @findNewVersion.
  ///
  /// In en, this message translates to:
  /// **'New version found'**
  String get findNewVersion;

  /// No description provided for @updateContent.
  ///
  /// In en, this message translates to:
  /// **'Update details'**
  String get updateContent;

  /// No description provided for @dialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get dialogTitle;

  /// No description provided for @dataSourceContent.
  ///
  /// In en, this message translates to:
  /// **'Add this source?'**
  String get dataSourceContent;

  /// No description provided for @dialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dialogCancel;

  /// No description provided for @dialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get dialogConfirm;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

  /// No description provided for @createTime.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get createTime;

  /// No description provided for @dialogDeleteContent.
  ///
  /// In en, this message translates to:
  /// **'Delete subscription?'**
  String get dialogDeleteContent;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @setDefault.
  ///
  /// In en, this message translates to:
  /// **'Set Default'**
  String get setDefault;

  /// No description provided for @inUse.
  ///
  /// In en, this message translates to:
  /// **'In Use'**
  String get inUse;

  /// No description provided for @tvParseParma.
  ///
  /// In en, this message translates to:
  /// **'Parameter Error'**
  String get tvParseParma;

  /// No description provided for @tvParseSuccess.
  ///
  /// In en, this message translates to:
  /// **'Pushed Successfully'**
  String get tvParseSuccess;

  /// No description provided for @tvParsePushError.
  ///
  /// In en, this message translates to:
  /// **'Invalid link'**
  String get tvParsePushError;

  /// No description provided for @tvScanTip.
  ///
  /// In en, this message translates to:
  /// **'Scan to add'**
  String get tvScanTip;

  /// No description provided for @pushAddress.
  ///
  /// In en, this message translates to:
  /// **'Push Address: {address}'**
  String pushAddress(Object address);

  /// No description provided for @tvPushContent.
  ///
  /// In en, this message translates to:
  /// **'Enter source in the scan page and push it.'**
  String get tvPushContent;

  /// No description provided for @pasterContent.
  ///
  /// In en, this message translates to:
  /// **'Paste and return to auto-add source.'**
  String get pasterContent;

  /// No description provided for @addDataSource.
  ///
  /// In en, this message translates to:
  /// **'Add Source'**
  String get addDataSource;

  /// No description provided for @addFiledHintText.
  ///
  /// In en, this message translates to:
  /// **'Enter .m3u/.txt link'**
  String get addFiledHintText;

  /// No description provided for @addRepeat.
  ///
  /// In en, this message translates to:
  /// **'Source already added'**
  String get addRepeat;

  /// No description provided for @addNoHttpLink.
  ///
  /// In en, this message translates to:
  /// **'Enter http/https link'**
  String get addNoHttpLink;

  /// No description provided for @netTimeOut.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get netTimeOut;

  /// No description provided for @netSendTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request Timeout'**
  String get netSendTimeout;

  /// No description provided for @netReceiveTimeout.
  ///
  /// In en, this message translates to:
  /// **'Response Timeout'**
  String get netReceiveTimeout;

  /// No description provided for @netBadResponse.
  ///
  /// In en, this message translates to:
  /// **'Bad Response {code}'**
  String netBadResponse(Object code);

  /// No description provided for @netCancel.
  ///
  /// In en, this message translates to:
  /// **'Request Cancelled'**
  String get netCancel;

  /// No description provided for @parseError.
  ///
  /// In en, this message translates to:
  /// **'Parse Error'**
  String get parseError;

  /// No description provided for @defaultText.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultText;

  /// No description provided for @getDefaultError.
  ///
  /// In en, this message translates to:
  /// **'Failed to get default source'**
  String get getDefaultError;

  /// No description provided for @okRefresh.
  ///
  /// In en, this message translates to:
  /// **'[OK] to Refresh'**
  String get okRefresh;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @noEPG.
  ///
  /// In en, this message translates to:
  /// **'No program info'**
  String get noEPG;

  /// No description provided for @logtitle.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logtitle;

  /// No description provided for @switchTitle.
  ///
  /// In en, this message translates to:
  /// **'Log Recording'**
  String get switchTitle;

  /// No description provided for @logSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable logs only for debugging'**
  String get logSubtitle;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterVerbose.
  ///
  /// In en, this message translates to:
  /// **'Verbose'**
  String get filterVerbose;

  /// No description provided for @filterError.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get filterError;

  /// No description provided for @filterInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get filterInfo;

  /// No description provided for @filterDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get filterDebug;

  /// No description provided for @noLogs.
  ///
  /// In en, this message translates to:
  /// **'No logs'**
  String get noLogs;

  /// No description provided for @logCleared.
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logCleared;

  /// No description provided for @clearLogs.
  ///
  /// In en, this message translates to:
  /// **'Clear Logs'**
  String get clearLogs;

  /// No description provided for @programListTitle.
  ///
  /// In en, this message translates to:
  /// **'TV Schedule'**
  String get programListTitle;

  /// No description provided for @foundStreamTitle.
  ///
  /// In en, this message translates to:
  /// **'Stream Found'**
  String get foundStreamTitle;

  /// No description provided for @streamUrlContent.
  ///
  /// In en, this message translates to:
  /// **'Stream URL: {url}. Play this stream?'**
  String streamUrlContent(Object url);

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @playButton.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playButton;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get downloading;

  /// No description provided for @fontTitle.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get fontTitle;

  /// No description provided for @backgroundImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get backgroundImageTitle;

  /// No description provided for @slogTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get slogTitle;

  /// No description provided for @updateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateTitle;

  /// No description provided for @errorLoadingPage.
  ///
  /// In en, this message translates to:
  /// **'Page Load Error'**
  String get errorLoadingPage;

  /// No description provided for @backgroundImageDescription.
  ///
  /// In en, this message translates to:
  /// **'Change background with audio'**
  String get backgroundImageDescription;

  /// No description provided for @dailyBing.
  ///
  /// In en, this message translates to:
  /// **'Enable background switch'**
  String get dailyBing;

  /// No description provided for @use.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get use;

  /// No description provided for @languageSelection.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get languageSelection;

  /// No description provided for @fontSizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSizeTitle;

  /// No description provided for @logCopied.
  ///
  /// In en, this message translates to:
  /// **'Log copied'**
  String get logCopied;

  /// No description provided for @clipboardDataFetchError.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch clipboard data'**
  String get clipboardDataFetchError;

  /// No description provided for @nofavorite.
  ///
  /// In en, this message translates to:
  /// **'No Favorites'**
  String get nofavorite;

  /// No description provided for @vpnplayError.
  ///
  /// In en, this message translates to:
  /// **'VPN required for some regions'**
  String get vpnplayError;

  /// No description provided for @retryplay.
  ///
  /// In en, this message translates to:
  /// **'Connection error, retrying...'**
  String get retryplay;

  /// No description provided for @channelnofavorite.
  ///
  /// In en, this message translates to:
  /// **'Can\'t add to favorites'**
  String get channelnofavorite;

  /// No description provided for @removefavorite.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get removefavorite;

  /// No description provided for @newfavorite.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get newfavorite;

  /// No description provided for @newfavoriteerror.
  ///
  /// In en, this message translates to:
  /// **'Failed to add to favorites'**
  String get newfavoriteerror;

  /// No description provided for @getm3udata.
  ///
  /// In en, this message translates to:
  /// **'Fetching data...'**
  String get getm3udata;

  /// No description provided for @getm3udataerror.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch data...'**
  String get getm3udataerror;

  /// No description provided for @myfavorite.
  ///
  /// In en, this message translates to:
  /// **'My Favorites'**
  String get myfavorite;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get addToFavorites;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
  String get removeFromFavorites;

  /// No description provided for @allchannels.
  ///
  /// In en, this message translates to:
  /// **'Other Channels'**
  String get allchannels;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copyok.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copyok;

  /// No description provided for @startsurlerror.
  ///
  /// In en, this message translates to:
  /// **'URL Parse Error'**
  String get startsurlerror;

  /// No description provided for @gethttperror.
  ///
  /// In en, this message translates to:
  /// **'Network config failed'**
  String get gethttperror;

  /// No description provided for @exittip.
  ///
  /// In en, this message translates to:
  /// **'We look forward to your next visit'**
  String get exittip;

  /// No description provided for @playpause.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get playpause;

  /// No description provided for @remotehelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get remotehelp;

  /// No description provided for @remotehelpup.
  ///
  /// In en, this message translates to:
  /// **'Press \'Up\' for line switch'**
  String get remotehelpup;

  /// No description provided for @remotehelpleft.
  ///
  /// In en, this message translates to:
  /// **'Press \'Left\' to favorite channel'**
  String get remotehelpleft;

  /// No description provided for @remotehelpdown.
  ///
  /// In en, this message translates to:
  /// **'Press \'Down\' for settings'**
  String get remotehelpdown;

  /// No description provided for @remotehelpok.
  ///
  /// In en, this message translates to:
  /// **'Press \'OK\' to confirm\nShow time/Pause/Play'**
  String get remotehelpok;

  /// No description provided for @remotehelpright.
  ///
  /// In en, this message translates to:
  /// **'Press \'Right\' to open channel menu'**
  String get remotehelpright;

  /// No description provided for @remotehelpback.
  ///
  /// In en, this message translates to:
  /// **'Press \'Back\' to exit/cancel'**
  String get remotehelpback;

  /// No description provided for @remotehelpclose.
  ///
  /// In en, this message translates to:
  /// **'Press any key to close help'**
  String get remotehelpclose;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh': {
  switch (locale.countryCode) {
    case 'CN': return AppLocalizationsZhCn();
case 'TW': return AppLocalizationsZhTw();
   }
  break;
   }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
