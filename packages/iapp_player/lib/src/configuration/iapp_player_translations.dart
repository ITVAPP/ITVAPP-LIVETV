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
  /// 播放列表
  final String playlistTitle;
  /// 播放列表不可用
  final String playlistUnavailable;
  /// 视频项目（用于格式化）
  final String videoItem;
  /// 音频项目（用于格式化）
  final String audioItem;
  /// 曲目项目（用于格式化）
  final String trackItem;

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
    this.playlistTitle = "Playlist",
    this.playlistUnavailable = "Playlist unavailable",
    this.videoItem = "Video {index}",
    this.audioItem = "Track {index}",
    this.trackItem = "Track {index}",
  });

  /// 波兰语翻译
  factory IAppPlayerTranslations.polish() => IAppPlayerTranslations(
        languageCode: "pl",
        generalDefaultError: "Nie można odtworzyć wideo",
        generalNone: "Brak",
        generalDefault: "Domyślne",
        generalRetry: "Ponów",
        playlistLoadingNextVideo: "Ładowanie kolejnego wideo",
        controlsLive: "NA ŻYWO",
        controlsNextVideoIn: "Następne wideo za",
        overflowMenuPlaybackSpeed: "Prędkość",
        overflowMenuSubtitles: "Napisy",
        overflowMenuQuality: "Jakość",
        overflowMenuAudioTracks: "Audio",
        qualityAuto: "Auto",
        playlistTitle: "Playlista",
        playlistUnavailable: "Playlista niedostępna",
        videoItem: "Wideo {index}",
        audioItem: "Ścieżka {index}",
        trackItem: "Utwór {index}",
      );

  /// 中文
  factory IAppPlayerTranslations.chinese() => IAppPlayerTranslations(
        languageCode: "zh",
        generalDefaultError: "无法播放视频",
        generalNone: "无",
        generalDefault: "默认",
        generalRetry: "重试",
        playlistLoadingNextVideo: "加载下个视频",
        controlsLive: "直播",
        controlsNextVideoIn: "下个视频",
        overflowMenuPlaybackSpeed: "播放速度",
        overflowMenuSubtitles: "字幕",
        overflowMenuQuality: "画质",
        overflowMenuAudioTracks: "音频",
        qualityAuto: "自动",
        playlistTitle: "播放列表",
        playlistUnavailable: "播放列表不可用",
        videoItem: "视频 {index}",
        audioItem: "音轨 {index}",
        trackItem: "曲目 {index}",
      );

  /// 印地语
  factory IAppPlayerTranslations.hindi() => IAppPlayerTranslations(
        languageCode: "hi",
        generalDefaultError: "वीडियो नहीं चल सका",
        generalNone: "कोई नहीं",
        generalDefault: "डिफ़ॉल्ट",
        generalRetry: "दोबारा करें",
        playlistLoadingNextVideo: "अगला वीडियो लोड हो रहा",
        controlsLive: "लाइव",
        controlsNextVideoIn: "अगला वीडियो",
        overflowMenuPlaybackSpeed: "स्पीड",
        overflowMenuSubtitles: "सबटाइटल",
        overflowMenuQuality: "क्वालिटी",
        overflowMenuAudioTracks: "ऑडियो",
        qualityAuto: "ऑटो",
        playlistTitle: "प्लेलिस्ट",
        playlistUnavailable: "प्लेलिस्ट उपलब्ध नहीं",
        videoItem: "वीडियो {index}",
        audioItem: "ट्रैक {index}",
        trackItem: "गाना {index}",
      );

  /// 阿拉伯语
  factory IAppPlayerTranslations.arabic() => IAppPlayerTranslations(
        languageCode: "ar",
        generalDefaultError: "تعذر تشغيل الفيديو",
        generalNone: "لا شيء",
        generalDefault: "افتراضي",
        generalRetry: "إعادة المحاولة",
        playlistLoadingNextVideo: "تحميل الفيديو التالي",
        controlsLive: "مباشر",
        controlsNextVideoIn: "الفيديو التالي في",
        overflowMenuPlaybackSpeed: "السرعة",
        overflowMenuSubtitles: "الترجمة",
        overflowMenuQuality: "الجودة",
        overflowMenuAudioTracks: "الصوت",
        qualityAuto: "تلقائي",
        playlistTitle: "قائمة التشغيل",
        playlistUnavailable: "قائمة التشغيل غير متاحة",
        videoItem: "فيديو {index}",
        audioItem: "مقطع {index}",
        trackItem: "أغنية {index}",
      );

  /// 土耳其语
  factory IAppPlayerTranslations.turkish() => IAppPlayerTranslations(
        languageCode: "tr",
        generalDefaultError: "Video oynatılamadı",
        generalNone: "Yok",
        generalDefault: "Varsayılan",
        generalRetry: "Tekrar Dene",
        playlistLoadingNextVideo: "Sonraki video yükleniyor",
        controlsLive: "CANLI",
        controlsNextVideoIn: "Sonraki video",
        overflowMenuPlaybackSpeed: "Hız",
        overflowMenuSubtitles: "Altyazı",
        overflowMenuQuality: "Kalite",
        overflowMenuAudioTracks: "Ses",
        qualityAuto: "Otomatik",
        playlistTitle: "Çalma Listesi",
        playlistUnavailable: "Çalma listesi kullanılamıyor",
        videoItem: "Video {index}",
        audioItem: "Parça {index}",
        trackItem: "Şarkı {index}",
      );

  /// 越南语
  factory IAppPlayerTranslations.vietnamese() => IAppPlayerTranslations(
        languageCode: "vi",
        generalDefaultError: "Không thể phát video",
        generalNone: "Không có",
        generalDefault: "Mặc định",
        generalRetry: "Thử lại",
        controlsLive: "TRỰC TIẾP",
        playlistLoadingNextVideo: "Đang tải video tiếp theo",
        controlsNextVideoIn: "Video tiếp theo",
        overflowMenuPlaybackSpeed: "Tốc độ",
        overflowMenuSubtitles: "Phụ đề",
        overflowMenuQuality: "Chất lượng",
        overflowMenuAudioTracks: "Âm thanh",
        qualityAuto: "Tự động",
        playlistTitle: "Danh sách phát",
        playlistUnavailable: "Danh sách phát không khả dụng",
        videoItem: "Video {index}",
        audioItem: "Track {index}",
        trackItem: "Bài hát {index}",
      );

  /// 西班牙语
  factory IAppPlayerTranslations.spanish() => IAppPlayerTranslations(
        languageCode: "es",
        generalDefaultError: "No se puede reproducir el video",
        generalNone: "Ninguno",
        generalDefault: "Por defecto",
        generalRetry: "Reintentar",
        controlsLive: "EN VIVO",
        playlistLoadingNextVideo: "Cargando siguiente video",
        controlsNextVideoIn: "Siguiente video en",
        overflowMenuPlaybackSpeed: "Velocidad",
        overflowMenuSubtitles: "Subtítulos",
        overflowMenuQuality: "Calidad",
        overflowMenuAudioTracks: "Audio",
        qualityAuto: "Auto",
        playlistTitle: "Lista de reproducción",
        playlistUnavailable: "Lista no disponible",
        videoItem: "Video {index}",
        audioItem: "Pista {index}",
        trackItem: "Canción {index}",
      );
}
