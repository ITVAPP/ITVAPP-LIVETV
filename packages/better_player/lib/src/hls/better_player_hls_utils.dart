import 'package:better_player/src/asms/better_player_asms_audio_track.dart';
import 'package:better_player/src/asms/better_player_asms_data_holder.dart';
import 'package:better_player/src/asms/better_player_asms_subtitle.dart';
import 'package:better_player/src/asms/better_player_asms_subtitle_segment.dart';
import 'package:better_player/src/asms/better_player_asms_track.dart';
import 'package:better_player/src/asms/better_player_asms_utils.dart';
import 'package:better_player/src/core/better_player_utils.dart';
import 'package:better_player/src/hls/hls_parser/hls_master_playlist.dart';
import 'package:better_player/src/hls/hls_parser/hls_media_playlist.dart';
import 'package:better_player/src/hls/hls_parser/hls_playlist_parser.dart';
import 'package:better_player/src/hls/hls_parser/rendition.dart';
import 'package:better_player/src/hls/hls_parser/segment.dart';
import 'package:better_player/src/hls/hls_parser/util.dart';

/// HLS 辅助类，解析 HLS 播放列表以提取轨道、字幕和音频信息
class BetterPlayerHlsUtils {
  /// 解析 HLS 播放列表，提取轨道、字幕和音频信息，返回数据持有者对象
  static Future<BetterPlayerAsmsDataHolder> parse(
      String data, String masterPlaylistUrl) async {
    List<BetterPlayerAsmsTrack> tracks = [];
    List<BetterPlayerAsmsSubtitle> subtitles = [];
    List<BetterPlayerAsmsAudioTrack> audios = [];
    try {
      /// 单次解析播放列表，复用结果以提升性能
      final parsedPlaylist = await HlsPlaylistParser.create()
          .parseString(Uri.parse(masterPlaylistUrl), data);
      
      final List<List<dynamic>> list = await Future.wait([
        _parseTracksFromPlaylist(parsedPlaylist),
        _parseSubtitlesFromPlaylist(parsedPlaylist),
        _parseLanguagesFromPlaylist(parsedPlaylist)
      ]);
      tracks = list[0] as List<BetterPlayerAsmsTrack>;
      subtitles = list[1] as List<BetterPlayerAsmsSubtitle>;
      audios = list[2] as List<BetterPlayerAsmsAudioTrack>;
    } catch (exception) {
      BetterPlayerUtils.log("解析 HLS 播放列表失败: $exception");
    }
    return BetterPlayerAsmsDataHolder(
        tracks: tracks, audios: audios, subtitles: subtitles);
  }

  /// 从已解析的播放列表提取视频轨道信息
  static Future<List<BetterPlayerAsmsTrack>> _parseTracksFromPlaylist(
      dynamic parsedPlaylist) async {
    final List<BetterPlayerAsmsTrack> tracks = [];
    try {
      if (parsedPlaylist is HlsMasterPlaylist) {
        parsedPlaylist.variants.forEach(
          (variant) {
            tracks.add(BetterPlayerAsmsTrack('', variant.format.width,
                variant.format.height, variant.format.bitrate, 0, '', ''));
          },
        );
      }

      if (tracks.isNotEmpty) {
        tracks.insert(0, BetterPlayerAsmsTrack.defaultTrack());
      }
    } catch (exception) {
      BetterPlayerUtils.log("解析视频轨道失败: $exception");
    }
    return tracks;
  }

  /// 从已解析的播放列表提取字幕信息
  static Future<List<BetterPlayerAsmsSubtitle>> _parseSubtitlesFromPlaylist(
      dynamic parsedPlaylist) async {
    final List<BetterPlayerAsmsSubtitle> subtitles = [];
    try {
      if (parsedPlaylist is HlsMasterPlaylist) {
        for (final Rendition element in parsedPlaylist.subtitles) {
          final hlsSubtitle = await _parseSubtitlesPlaylist(element);
          if (hlsSubtitle != null) {
            subtitles.add(hlsSubtitle);
          }
        }
      }
    } catch (exception) {
      BetterPlayerUtils.log("解析字幕失败: $exception");
    }

    return subtitles;
  }

  /// 从已解析的播放列表提取音频轨道信息
  static Future<List<BetterPlayerAsmsAudioTrack>> _parseLanguagesFromPlaylist(
      dynamic parsedPlaylist) async {
    final List<BetterPlayerAsmsAudioTrack> audios = [];
    if (parsedPlaylist is HlsMasterPlaylist) {
      for (int index = 0; index < parsedPlaylist.audios.length; index++) {
        final Rendition audio = parsedPlaylist.audios[index];
        audios.add(BetterPlayerAsmsAudioTrack(
          id: index,
          label: audio.name,
          language: audio.format.language,
          url: audio.url.toString(),
        ));
      }
    }

    return audios;
  }

  /// 解析 HLS 播放列表以提取视频轨道信息
  static Future<List<BetterPlayerAsmsTrack>> parseTracks(
      String data, String masterPlaylistUrl) async {
    final List<BetterPlayerAsmsTrack> tracks = [];
    try {
      final parsedPlaylist = await HlsPlaylistParser.create()
          .parseString(Uri.parse(masterPlaylistUrl), data);
      return await _parseTracksFromPlaylist(parsedPlaylist);
    } catch (exception) {
      BetterPlayerUtils.log("解析视频轨道失败: $exception");
    }
    return tracks;
  }

  /// 从指定 m3u8 地址解析字幕信息
  static Future<List<BetterPlayerAsmsSubtitle>> parseSubtitles(
      String data, String masterPlaylistUrl) async {
    final List<BetterPlayerAsmsSubtitle> subtitles = [];
    try {
      final parsedPlaylist = await HlsPlaylistParser.create()
          .parseString(Uri.parse(masterPlaylistUrl), data);
      return await _parseSubtitlesFromPlaylist(parsedPlaylist);
    } catch (exception) {
      BetterPlayerUtils.log("解析字幕失败: $exception");
    }

    return subtitles;
  }

  /// 解析 HLS 字幕播放列表，支持分段字幕处理，按需加载以优化性能
  static Future<BetterPlayerAsmsSubtitle?> _parseSubtitlesPlaylist(
      Rendition rendition) async {
    try {
      final HlsPlaylistParser _hlsPlaylistParser = HlsPlaylistParser.create();
      final subtitleData =
          await BetterPlayerAsmsUtils.getDataFromUrl(rendition.url.toString());
      if (subtitleData == null) {
        return null;
      }

      final parsedSubtitle =
          await _hlsPlaylistParser.parseString(rendition.url, subtitleData);
      final hlsMediaPlaylist = parsedSubtitle as HlsMediaPlaylist;
      final hlsSubtitlesUrls = <String>[];

      final List<BetterPlayerAsmsSubtitleSegment> asmsSegments = [];
      final bool isSegmented = hlsMediaPlaylist.segments.length > 1;
      int microSecondsFromStart = 0;
      for (final Segment segment in hlsMediaPlaylist.segments) {
        final split = rendition.url.toString().split("/");
        /// 使用 join() 拼接 URL，提升性能
        var realUrl = split.take(split.length - 1).join("/") + "/";
        
        if (segment.url?.startsWith("http") == true) {
          realUrl = segment.url!;
        } else {
          realUrl += segment.url!;
        }
        hlsSubtitlesUrls.add(realUrl);

        if (isSegmented) {
          final int nextMicroSecondsFromStart =
              microSecondsFromStart + segment.durationUs!;
          microSecondsFromStart = nextMicroSecondsFromStart;
          asmsSegments.add(
            BetterPlayerAsmsSubtitleSegment(
              Duration(microseconds: microSecondsFromStart),
              Duration(microseconds: nextMicroSecondsFromStart),
              realUrl,
            ),
          );
        }
      }

      int targetDuration = 0;
      if (parsedSubtitle.targetDurationUs != null) {
        targetDuration = parsedSubtitle.targetDurationUs! ~/ 1000;
      }

      bool isDefault = false;

      if (rendition.format.selectionFlags != null) {
        isDefault =
            Util.checkBitPositionIsSet(rendition.format.selectionFlags!, 1);
      }

      return BetterPlayerAsmsSubtitle(
          name: rendition.format.label,
          language: rendition.format.language,
          url: rendition.url.toString(),
          realUrls: hlsSubtitlesUrls,
          isSegmented: isSegmented,
          segmentsTime: targetDuration,
          segments: asmsSegments,
          isDefault: isDefault);
    } catch (exception) {
      BetterPlayerUtils.log("解析字幕播放列表失败: $exception");
      return null;
    }
  }

  /// 解析 HLS 播放列表以提取音频轨道信息
  static Future<List<BetterPlayerAsmsAudioTrack>> parseLanguages(
      String data, String masterPlaylistUrl) async {
    final List<BetterPlayerAsmsAudioTrack> audios = [];
    try {
      final parsedPlaylist = await HlsPlaylistParser.create()
          .parseString(Uri.parse(masterPlaylistUrl), data);
      return await _parseLanguagesFromPlaylist(parsedPlaylist);
    } catch (exception) {
      BetterPlayerUtils.log("解析音频轨道失败: $exception");
    }
    return audios;
  }
}
