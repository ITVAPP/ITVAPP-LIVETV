import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

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

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn(): super('zh_CN');

  @override
  String get appName => '电视宝直播';

  @override
  String get loading => '正在加载频道...';

  @override
  String lineToast(Object line, Object channel) {
    return '开始连接: $channel 线路$line';
  }

  @override
  String get playError => '此频道暂时无法播放，请等待修复';

  @override
  String switchLine(Object line) {
    return '切换线路$line ...';
  }

  @override
  String get playReconnect => '重试连接';

  @override
  String lineIndex(Object index) {
    return '线路$index';
  }

  @override
  String get exitTitle => '退出应用确认';

  @override
  String get exitMessage => '你确定要离开电视宝直播吗?';

  @override
  String get tipChannelList => '频道列表';

  @override
  String get tipChangeLine => '切换线路';

  @override
  String get portrait => '竖屏模式';

  @override
  String get landscape => '横屏模式';

  @override
  String get fullScreen => '全屏切换';

  @override
  String get settings => '设置';

  @override
  String get homePage => '主页';

  @override
  String get releaseHistory => '发布历史';

  @override
  String get checkUpdate => '检查更新';

  @override
  String newVersion(Object version) {
    return '新版本v$version';
  }

  @override
  String get update => '立即更新';

  @override
  String get latestVersion => '已是最新版本';

  @override
  String get findNewVersion => '发现新版本';

  @override
  String get updateContent => '更新内容';

  @override
  String get dialogTitle => '温馨提示';

  @override
  String get dataSourceContent => '确定添加此数据源吗？';

  @override
  String get dialogCancel => '取消';

  @override
  String get dialogConfirm => '确定';

  @override
  String get subscribe => '订阅';

  @override
  String get createTime => '创建时间';

  @override
  String get dialogDeleteContent => '确定删除此订阅吗？';

  @override
  String get delete => '删除';

  @override
  String get setDefault => '设为默认';

  @override
  String get inUse => '使用中';

  @override
  String get tvParseParma => '参数错误';

  @override
  String get tvParseSuccess => '推送成功';

  @override
  String get tvParsePushError => '请推送正确的链接';

  @override
  String get tvScanTip => '扫码添加订阅源';

  @override
  String pushAddress(Object address) {
    return '推送地址：$address';
  }

  @override
  String get tvPushContent => '在扫码结果页，输入新的订阅源，点击页面中的推送即可添加成功';

  @override
  String get pasterContent => '复制订阅源后，回到此页面可自动添加订阅源';

  @override
  String get addDataSource => '添加订阅源';

  @override
  String get addFiledHintText => '请输入或粘贴.m3u或.txt格式的订阅源链接';

  @override
  String get addRepeat => '已添加过此订阅源';

  @override
  String get addNoHttpLink => '请输入http/https链接';

  @override
  String get netTimeOut => '连接超时';

  @override
  String get netSendTimeout => '请求超时';

  @override
  String get netReceiveTimeout => '响应超时';

  @override
  String netBadResponse(Object code) {
    return '响应异常$code';
  }

  @override
  String get netCancel => '请求取消';

  @override
  String get parseError => '解析数据源出错';

  @override
  String get defaultText => '默认';

  @override
  String get getDefaultError => '获取默认数据源失败';

  @override
  String get okRefresh => '【OK键】刷新';

  @override
  String get refresh => '刷新';

  @override
  String get noEPG => '暂无节目信息';

  @override
  String get logtitle => '日志查看器';

  @override
  String get switchTitle => '记录日志';

  @override
  String get logSubtitle => '如非开发人员，无需打开日志开关';

  @override
  String get filterAll => '所有';

  @override
  String get filterVerbose => '详细';

  @override
  String get filterError => '错误';

  @override
  String get filterInfo => '信息';

  @override
  String get filterDebug => '调试';

  @override
  String get noLogs => '暂无日志';

  @override
  String get logCleared => '日志已清空';

  @override
  String get clearLogs => '清空日志';

  @override
  String get programListTitle => '节目单';

  @override
  String get foundStreamTitle => '找到视频流';

  @override
  String streamUrlContent(Object url) {
    return '流URL: $url\n\n你想播放这个流吗？';
  }

  @override
  String get cancelButton => '取消';

  @override
  String get playButton => '播放';

  @override
  String get downloading => '下载中...';

  @override
  String get fontTitle => '字体';

  @override
  String get backgroundImageTitle => '背景图';

  @override
  String get slogTitle => '日志';

  @override
  String get updateTitle => '更新';

  @override
  String get errorLoadingPage => '加载页面出错';

  @override
  String get backgroundImageDescription => '自动更换播放音频时的背景';

  @override
  String get dailyBing => '开启背景切换';

  @override
  String get use => '使用';

  @override
  String get languageSelection => '语言选择';

  @override
  String get fontSizeTitle => '字体大小';

  @override
  String get logCopied => '日志已复制到剪贴板';

  @override
  String get clipboardDataFetchError => '获取剪贴板数据失败';

  @override
  String get nofavorite => '暂无收藏';

  @override
  String get vpnplayError => '此频道在部分地区需要VPN才可以观看';

  @override
  String get retryplay => '连接出错，正在重试...';

  @override
  String get channelnofavorite => '当前频道无法收藏';

  @override
  String get removefavorite => '频道已从收藏中移除';

  @override
  String get newfavorite => '频道已添加到收藏';

  @override
  String get newfavoriteerror => '添加收藏失败';

  @override
  String get getm3udata => '正在获取播放数据...';

  @override
  String get getm3udataerror => '获取播放数据失败...';

  @override
  String get myfavorite => '我的收藏';

  @override
  String get addToFavorites => '添加收藏';

  @override
  String get removeFromFavorites => '取消收藏';

  @override
  String get allchannels => '其它频道';

  @override
  String get copy => '复制';

  @override
  String get copyok => '内容已复制到剪贴板';

  @override
  String get startsurlerror => '解析 URL 失败';

  @override
  String get gethttperror => '本地网络配置失败';

  @override
  String get exittip => '期待你下一次的访问';

  @override
  String get playpause => '暂停播放中...';

  @override
  String get remotehelp => '帮助';

  @override
  String get remotehelpup => '「点击上键」打开 线路切换菜单';

  @override
  String get remotehelpleft => '「点击左键」添加/取消 频道收藏';

  @override
  String get remotehelpdown => '「点击下键」打开 应用设置界面';

  @override
  String get remotehelpok => '「点击确认键」确认选择操作\n显示时间/暂停/播放';

  @override
  String get remotehelpright => '「点击右键」打开 频道选择抽屉';

  @override
  String get remotehelpback => '「点击返回键」退出/取消操作';

  @override
  String get remotehelpclose => '点击任意按键关闭帮助';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw(): super('zh_TW');

  @override
  String get appName => '電視寶直播';

  @override
  String get loading => '正在載入頻道...';

  @override
  String lineToast(Object line, Object channel) {
    return '開始連線: $channel 線路$line';
  }

  @override
  String get playError => '此頻道暫時無法播放，請等待修復';

  @override
  String switchLine(Object line) {
    return '切換線路$line ...';
  }

  @override
  String get playReconnect => '重試連線';

  @override
  String lineIndex(Object index) {
    return '線路$index';
  }

  @override
  String get exitTitle => '退出應用確認';

  @override
  String get exitMessage => '你確定要離開電視寶直播嗎?';

  @override
  String get tipChannelList => '頻道列表';

  @override
  String get tipChangeLine => '切換線路';

  @override
  String get portrait => '豎屏模式';

  @override
  String get landscape => '橫屏模式';

  @override
  String get fullScreen => '全屏切換';

  @override
  String get settings => '設定';

  @override
  String get homePage => '主頁';

  @override
  String get releaseHistory => '釋出歷史';

  @override
  String get checkUpdate => '檢查更新';

  @override
  String newVersion(Object version) {
    return '新版本v$version';
  }

  @override
  String get update => '立即更新';

  @override
  String get latestVersion => '已是最新版本';

  @override
  String get findNewVersion => '發現新版本';

  @override
  String get updateContent => '更新內容';

  @override
  String get dialogTitle => '溫馨提示';

  @override
  String get dataSourceContent => '確定新增此資料來源嗎？';

  @override
  String get dialogCancel => '取消';

  @override
  String get dialogConfirm => '確定';

  @override
  String get subscribe => '訂閱';

  @override
  String get createTime => '建立時間';

  @override
  String get dialogDeleteContent => '確定刪除此訂閱嗎？';

  @override
  String get delete => '刪除';

  @override
  String get setDefault => '設為預設';

  @override
  String get inUse => '使用中';

  @override
  String get tvParseParma => '引數錯誤';

  @override
  String get tvParseSuccess => '推送成功';

  @override
  String get tvParsePushError => '請推送正確的連結';

  @override
  String get tvScanTip => '掃碼新增訂閱源';

  @override
  String pushAddress(Object address) {
    return '推送地址：$address';
  }

  @override
  String get tvPushContent => '在掃碼結果頁，輸入新的訂閱源，點選頁面中的推送即可新增成功';

  @override
  String get pasterContent => '複製訂閱源後，回到此頁面可自動新增訂閱源';

  @override
  String get addDataSource => '新增訂閱源';

  @override
  String get addFiledHintText => '請輸入或貼上.m3u或.txt格式的訂閱源連結';

  @override
  String get addRepeat => '已新增過此訂閱源';

  @override
  String get addNoHttpLink => '請輸入http/https連結';

  @override
  String get netTimeOut => '連線超時';

  @override
  String get netSendTimeout => '請求超時';

  @override
  String get netReceiveTimeout => '響應超時';

  @override
  String netBadResponse(Object code) {
    return '響應異常$code';
  }

  @override
  String get netCancel => '請求取消';

  @override
  String get parseError => '解析資料來源出錯';

  @override
  String get defaultText => '預設';

  @override
  String get getDefaultError => '獲取預設資料來源失敗';

  @override
  String get okRefresh => '【OK鍵】重新整理';

  @override
  String get refresh => '重新整理';

  @override
  String get noEPG => '暂无節目資訊';

  @override
  String get logtitle => '日誌檢視器';

  @override
  String get switchTitle => '記錄日誌';

  @override
  String get logSubtitle => '如非開發人員，無需開啟日誌開關';

  @override
  String get filterAll => '所有';

  @override
  String get filterVerbose => '詳細';

  @override
  String get filterError => '錯誤';

  @override
  String get filterInfo => '資訊';

  @override
  String get filterDebug => '偵錯';

  @override
  String get noLogs => '暫無日誌';

  @override
  String get logCleared => '日誌已清空';

  @override
  String get clearLogs => '清空日誌';

  @override
  String get programListTitle => '節目單';

  @override
  String get foundStreamTitle => '找到影片流';

  @override
  String streamUrlContent(Object url) {
    return '流URL: $url\n\n你想播放這個流嗎？';
  }

  @override
  String get cancelButton => '取消';

  @override
  String get playButton => '播放';

  @override
  String get downloading => '下載中...';

  @override
  String get fontTitle => '字型';

  @override
  String get backgroundImageTitle => '背景圖';

  @override
  String get slogTitle => '日誌';

  @override
  String get updateTitle => '更新';

  @override
  String get errorLoadingPage => '載入頁面出錯';

  @override
  String get backgroundImageDescription => '自動更換播放音訊時的背景';

  @override
  String get dailyBing => '開啟背景切換';

  @override
  String get use => '使用';

  @override
  String get languageSelection => '語言選擇';

  @override
  String get fontSizeTitle => '字型大小';

  @override
  String get logCopied => '日誌已複製到剪貼簿';

  @override
  String get clipboardDataFetchError => '獲取剪貼簿資料失敗';

  @override
  String get nofavorite => '暫無收藏';

  @override
  String get vpnplayError => '此頻道在部分地區需要VPN纔可以觀看';

  @override
  String get retryplay => '連線出錯，正在重試...';

  @override
  String get channelnofavorite => '當前頻道無法收藏';

  @override
  String get removefavorite => '頻道已從收藏中移除';

  @override
  String get newfavorite => '頻道已新增到收藏';

  @override
  String get newfavoriteerror => '新增收藏失敗';

  @override
  String get getm3udata => '正在獲取播放資料...';

  @override
  String get getm3udataerror => '獲取播放資料失敗...';

  @override
  String get myfavorite => '我的收藏';

  @override
  String get addToFavorites => '新增收藏';

  @override
  String get removeFromFavorites => '取消收藏';

  @override
  String get allchannels => '其它頻道';

  @override
  String get copy => '複製';

  @override
  String get copyok => '內容已複製到剪貼簿';

  @override
  String get startsurlerror => '解析 URL 失敗';

  @override
  String get gethttperror => '本地網路配置失敗';

  @override
  String get exittip => '期待你下一次的訪問';

  @override
  String get playpause => '暫停播放中...';

  @override
  String get remotehelp => '幫助';

  @override
  String get remotehelpup => '「點選上鍵」開啟 線路切換選單';

  @override
  String get remotehelpleft => '「點選左鍵」新增/取消 頻道收藏';

  @override
  String get remotehelpdown => '「點選下鍵」開啟 應用設定界面';

  @override
  String get remotehelpok => '「點選確認鍵」確認選擇操作\n顯示時間/暫停/播放';

  @override
  String get remotehelpright => '「點選右鍵」開啟 頻道選擇抽屜';

  @override
  String get remotehelpback => '「點選返回鍵」退出/取消操作';

  @override
  String get remotehelpclose => '點選任意按鍵關閉幫助';
}
