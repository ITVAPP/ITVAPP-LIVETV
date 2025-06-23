/// 语言翻译类
class IAppPlayerTranslations {
  /// 语言代码
  final String languageCode;
  /// 默认错误提示
  final String generalDefaultError;
  /// 无选项提示
  final String generalNone;
  /// 默认选项提示
  final String generalDefault;
  /// 重试提示
  final String generalRetry;
  /// 加载下一视频提示
  final String playlistLoadingNextVideo;
  /// 直播提示
  final String controlsLive;
  /// 下一视频倒计时提示
  final String controlsNextVideoIn;
  /// 播放速度菜单项
  final String overflowMenuPlaybackSpeed;
  /// 字幕菜单项
  final String overflowMenuSubtitles;
  /// 质量菜单项
  final String overflowMenuQuality;
  /// 音频轨道菜单项
  final String overflowMenuAudioTracks;
  /// 自动质量提示
  final String qualityAuto;

  IAppPlayerTranslations({
    this.languageCode = "en",
    this.generalDefaultError = "Video can't be played",
    this.generalNone = "None",
    this.generalDefault = "Default",
    this.generalRetry = "Retry",
    this.playlistLoadingNextVideo = "Loading next video",
    this.controlsLive = "LIVE",
    this.controlsNextVideoIn = "Next video in",
    this.overflowMenuPlaybackSpeed = "Playback speed",
    this.overflowMenuSubtitles = "Subtitles",
    this.overflowMenuQuality = "Quality",
    this.overflowMenuAudioTracks = "Audio",
    this.qualityAuto = "Auto",
  });

  /// 波兰语翻译
  factory IAppPlayerTranslations.polish() => IAppPlayerTranslations(
        languageCode: "pl",
        generalDefaultError: "Video nie może zostać odtworzone",
        generalNone: "Brak",
        generalDefault: "Domyślne",
        generalRetry: "Spróbuj ponownie",
        playlistLoadingNextVideo: "Ładowanie następnego filmu",
        controlsNextVideoIn: "Następne video za",
        overflowMenuPlaybackSpeed: "Szybkość odtwarzania",
        overflowMenuSubtitles: "Napisy",
        overflowMenuQuality: "Jakość",
        overflowMenuAudioTracks: "Dźwięk",
        qualityAuto: "Automatycznie",
      );

  /// 中文
  factory IAppPlayerTranslations.chinese() => IAppPlayerTranslations(
        languageCode: "zh",
        generalDefaultError: "无法播放视频",
        generalNone: "没有",
        generalDefault: "默认",
        generalRetry: "重試",
        playlistLoadingNextVideo: "正在加载下一个视频",
        controlsLive: "直播",
        controlsNextVideoIn: "下一部影片",
        overflowMenuPlaybackSpeed: "播放速度",
        overflowMenuSubtitles: "字幕",
        overflowMenuQuality: "质量",
        overflowMenuAudioTracks: "音轨",
        qualityAuto: "自动",
      );

  /// 印地语
  factory IAppPlayerTranslations.hindi() => IAppPlayerTranslations(
        languageCode: "hi",
        generalDefaultError: "वीडियो नहीं चलाया जा सकता",
        generalNone: "कोई नहीं",
        generalDefault: "चूक",
        generalRetry: "पुनः प्रयास करें",
        playlistLoadingNextVideo: "अगला वीडियो लोड हो रहा है",
        controlsLive: "लाइव",
        controlsNextVideoIn: "में अगला वीडियो",
        overflowMenuPlaybackSpeed: "प्लेबैक की गति",
        overflowMenuSubtitles: "उपशीर्षक",
        overflowMenuQuality: "गुणवत्ता",
        overflowMenuAudioTracks: "ऑडियो",
        qualityAuto: "ऑटो",
      );

  /// 阿拉伯语
  factory IAppPlayerTranslations.arabic() => IAppPlayerTranslations(
        languageCode: "ar",
        generalDefaultError: "لا يمكن تشغيل الفيديو",
        generalNone: "لا يوجد",
        generalDefault: "الاساسي",
        generalRetry: "اعادة المحاوله",
        playlistLoadingNextVideo: "تحميل الفيديو التالي",
        controlsLive: "مباشر",
        controlsNextVideoIn: "الفيديو التالي في",
        overflowMenuPlaybackSpeed: "سرعة التشغيل",
        overflowMenuSubtitles: "الترجمة",
        overflowMenuQuality: "الجودة",
        overflowMenuAudioTracks: "الصوت",
        qualityAuto: "ऑटو",
      );

  /// 土耳其语
  factory IAppPlayerTranslations.turkish() => IAppPlayerTranslations(
        languageCode: "tr",
        generalDefaultError: "Video oynatılamıyor",
        generalNone: "Hiçbiri",
        generalDefault: "Varsayılan",
        generalRetry: "Tekrar Dene",
        playlistLoadingNextVideo: "Sonraki video yükleniyor",
        controlsLive: "CANLI",
        controlsNextVideoIn: "Sonraki video oynatılmadan",
        overflowMenuPlaybackSpeed: "Oynatma hızı",
        overflowMenuSubtitles: "Altyazı",
        overflowMenuQuality: "Kalite",
        overflowMenuAudioTracks: "Ses",
        qualityAuto: "Otomatik",
      );

  /// 越南语
  factory IAppPlayerTranslations.vietnamese() => IAppPlayerTranslations(
        languageCode: "vi",
        generalDefaultError: "Video không thể phát bây giờ",
        generalNone: "Không có",
        generalDefault: "Mặc định",
        generalRetry: "Thử lại ngay",
        controlsLive: "Trực tiếp",
        playlistLoadingNextVideo: "Đang tải video tiếp theo",
        controlsNextVideoIn: "Video tiếp theo",
        overflowMenuPlaybackSpeed: "Tốc độ phát",
        overflowMenuSubtitles: "Phụ đề",
        overflowMenuQuality: "Chất lượng",
        overflowMenuAudioTracks: "Âm thanh",
        qualityAuto: "Tự động",
      );

  /// 西班牙语
  factory IAppPlayerTranslations.spanish() => IAppPlayerTranslations(
        languageCode: "es",
        generalDefaultError: "No se puede reproducir el video",
        generalNone: "Ninguno",
        generalDefault: "Por defecto",
        generalRetry: "Reintentar",
        controlsLive: "EN DIRECTO",
        playlistLoadingNextVideo: "Cargando siguiente video",
        controlsNextVideoIn: "Siguiente video en",
        overflowMenuPlaybackSpeed: "Velocidad",
        overflowMenuSubtitles: "Subtítulos",
        overflowMenuQuality: "Calidad",
        overflowMenuAudioTracks: "Audio",
        qualityAuto: "Automática",
      );
}
