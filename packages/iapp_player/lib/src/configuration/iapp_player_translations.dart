///Class used to hold translations for all features within IApp Player
class IAppPlayerTranslations {
  final String languageCode;
  final String generalDefaultError;
  final String generalNone;
  final String generalDefault;
  final String generalRetry;
  final String playlistLoadingNextVideo;
  final String controlsLive;
  final String controlsNextVideoIn;
  final String overflowMenuPlaybackSpeed;
  final String overflowMenuSubtitles;
  final String overflowMenuQuality;
  final String overflowMenuAudioTracks;
  final String qualityAuto;

  IAppPlayerTranslations(
      {this.languageCode = "en",
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
      this.qualityAuto = "Auto"});

  factory IAppPlayerTranslations.polish() => IAppPlayerTranslations(
        languageCode: "pl",
        generalDefaultError: "Video nie mo