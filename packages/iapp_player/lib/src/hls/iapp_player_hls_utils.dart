import 'package:iapp_player/src/asms/iapp_player_asms_audio_track.dart';
import 'package:iapp_player/src/asms/iapp_player_asms_data_holder.dart';
import 'package:iapp_player/src/asms/iapp_player_asms_subtitle.dart';
import 'package:iapp_player/src/asms/iapp_player_asms_subtitle_segment.dart';
import 'package:iapp_player/src/asms/iapp_player_asms_track.dart';
import 'package:iapp_player/src/asms/iapp_player_asms_utils.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'package:iapp_player/src/hls/hls_parser/hls_master_playlist.dart';
import 'package:iapp_player/src/hls/hls_parser/hls_media_playlist.dart';
import 'package:iapp_player/src/hls/hls_parser/hls_playlist_parser.dart';
import 'package:iapp_player/src/hls/hls_parser/rendition.dart';
import 'package:iapp_player/src/hls/hls_parser/segment.dart';
import 'package:iapp_player/src/hls/hls_parser/util.dart';

/// HLS 辅助类，解析 HLS 播放列表以提取轨道、字幕和音频信息
class IAppPlayerHlsUtils {
  static Future<IAppPlayerAsmsDataHolder> parse(
      String data, String masterPlaylistUrl) async {
    List<IAppPlayerAsmsTrack> tracks = [];
    List<IAppPlayerAsmsSubtitle> subtitles = [];
    List<IAppPlayerAsmsAudioTrack> audios = [];
    try {
      /// 单次解析播放列表，复用结果以提升性能
      final parsedPlaylist = await HlsPlaylistParser.create()
          .parseString(Uri.parse(masterPlaylistUrl), data);
      
      final List<List<dynamic>> list = await Future.wait([
        _parseTracksFromPlaylist(parsedPlaylist),
        _parseSubtitlesFromPlaylist(parsedPlaylist),
        _parseLanguagesFromPlaylist(parsedPlaylist)
      ]);
      tracks = list[0] as List<IAppPlayerAsmsTrack>;
      subtitles = list[1] as List<IAppPlayerAsmsSubtitle>;
      audios = list[2] as List<IAppPlayerAsmsAudioTrack>;
    } catch (exception) {
      IAppPlayerUtils.log("解析 HLS 播放列表失败: $exception");
    }
    return IAppPlayerAsmsDataHolder(
        tracks: tracks, audios: audios, subtitles: subtitles);
  }

  /// 从已解析的播放列表提取视频轨道信息
  static Future<List<IAppPlayerAsmsTrack>> _parseTracksFromPlaylist(
      dynamic parsedPlaylist) async {
    final List<IAppPlayerAsmsTrack> tracks = [];
    try {
      if (parsedPlaylist is HlsMasterPlaylist) {
        parsedPlaylist.variants.forEach(
          (variant) {
            tracks.add(IAppPlayerAsmsTrack('', variant.format.width,
                variant.format.height, variant.format.bitrate, 0, '', ''));
          },
        );
      }

      if (tracks.isNotEmpty) {
        tracks.insert(0, IAppPlayerAsmsTrack.defaultTrack());
      }
    } catch (exception) {
      IAppPlayerUtils.log("解析视频轨道失败: $exception");
    }
    return tracks;
  }

  /// 从已解析的播放列表提取字幕信息
  static Future<List<IAppPlayerAsmsSubtitle>> _parseSubtitlesFromPlaylist(
      dynamic parsedPlaylist) async {
    final List<IAppPlayerAsmsSubtitle> subtitles = [];
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
      IAppPlayerUtils.log("解析字幕失败: $exception");
    }

    return subtitles;
  }

  /// 从已解析的播放列表提取音频轨道信息
  static Future<List<IAppPlayerAsmsAudioTrack>> _parseLanguagesFromPlaylist(
      dynamic parsedPlaylist) async {
    final List<IAppPlayerAsmsAudioTrack> audios = [];
    if (parsedPlaylist is HlsMasterPlaylist) {
      for (int index = 0; index < parsedPlaylist.audios.length; index++) {
        final Rendition audio = parsedPlaylist.audios[index];
        audios.add(IAppPlayerAsmsAudioTrack(
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
  static Future<List<IAppPlayerAsmsTrack>> parseTracks(
      String data, String masterPlaylistUrl) async {
    final List<IAppPlayerAsmsTrack> tracks = [];
    try {
      final parsedPlaylist = await HlsPlaylistParser.create()
          .parseString(Uri.parse(masterPlaylistUrl), data);
      return await _parseTracksFromPlaylist(parsedPlaylist);
    } catch (exception) {
      IAppPlayerUtils.log("解析视频轨道失败: $exception");
    }
    return tracks;
  }

  /// 从指定 m3u8 地址解析字幕信息
  static Future<List<IAppPlayerAsmsSubtitle>> parseSubtitles(
      String data, String masterPlaylistUrl) async {
    final List<IAppPlayerAsmsSubtitle> subtitles = [];
    try {
      final parsedPlaylist = await HlsPlaylistParser.create()
          .parseString(Uri.parse(masterPlaylistUrl), data);
      return await _parseSubtitlesFromPlaylist(parsedPlaylist);
    } catch (exception) {
      IAppPlayerUtils.log("解析字幕失败: $exception");
    }

    return subtitles;
  }

  /// 解析 HLS 字幕播放列表，支持分段字幕处理，按需加载
  static Future<IAppPlayerAsmsSubtitle?> _parseSubtitlesPlaylist(
      Rendition rendition) async {
    try {
      final HlsPlaylistParser _hlsPlaylistParser = HlsPlaylistParser.create();
      final subtitleData =
          await IAppPlayerAsmsUtils.getDataFromUrl(rendition.url.toString());
      if (subtitleData == null) {
        return null;
      }

      final parsedSubtitle =
          await _hlsPlaylistParser.parseString(rendition.url, subtitleData);
      final hlsMediaPlaylist = parsedSubtitle as HlsMediaPlaylist;
      final hlsSubtitlesUrls = <String>[];

      final List<IAppPlayerAsmsSubtitleSegment> asmsSegments = [];
      final bool isSegmented = hlsMediaPlaylist.segments.length > 1;
      int microSecondsFromStart = 0;
      final baseUrlString = rendition.url.toString();
      final lastSlashIndex = baseUrlString.lastIndexOf('/');
      final baseUrl = lastSlashIndex != -1 
          ? baseUrlString.substring(0, lastSlashIndex + 1)
          : '$baseUrlString/';
      
      for (final Segment segment in hlsMediaPlaylist.segments) {
        String realUrl;
        if (segment.url?.startsWith("http") == true) {
          realUrl = segment.url!;
        } else {
          realUrl = baseUrl + segment.url!;
        }
        hlsSubtitlesUrls.add(realUrl);

        if (isSegmented) {
          final int nextMicroSecondsFromStart =
              microSecondsFromStart + segment.durationUs!;
          microSecondsFromStart = nextMicroSecondsFromStart;
          asmsSegments.add(
            IAppPlayerAsmsSubtitleSegment(
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

      return IAppPlayerAsmsSubtitle(
          name: rendition.format.label,
          language: rendition.format.language,
          url: rendition.url.toString(),
          realUrls: hlsSubtitlesUrls,
          isSegmented: isSegmented,
          segmentsTime: targetDuration,
          segments: asmsSegments,
          isDefault: isDefault);
    } catch (exception) {
      IAppPlayerUtils.log("解析字幕播放列表失败: $exception");
      return null;
    }
  }

  /// 解析 HLS 播放列表以提取音频轨道信息
  static Future<List<IAppPlayerAsmsAudioTrack>> parseLanguages(
      String data, String masterPlaylistUrl) async {
    final List<IAppPlayerAsmsAudioTrack> audios = [];
    try {
      final parsedPlaylist = await HlsPlaylistParser.create()
          .parseString(Uri.parse(masterPlaylistUrl), data);
      return await _parseLanguagesFromPlaylist(parsedPlaylist);
    } catch (exception) {
      IAppPlayerUtils.log("解析音频轨道失败: $exception");
    }
    return audios;
  }
}
