import 'dart:convert';
import 'dart:io';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'iapp_player_subtitle.dart';

/// 字幕解析工厂，处理多种字幕源
class IAppPlayerSubtitlesFactory {
  /// 解析字幕源为字幕列表
  static Future<List<IAppPlayerSubtitle>> parseSubtitles(
      IAppPlayerSubtitlesSource source) async {
    switch (source.type) {
      case IAppPlayerSubtitlesSourceType.file:
        return _parseSubtitlesFromFile(source);
      case IAppPlayerSubtitlesSourceType.network:
        return _parseSubtitlesFromNetwork(source);
      case IAppPlayerSubtitlesSourceType.memory:
        return _parseSubtitlesFromMemory(source);
      default:
        return [];
    }
  }

  /// 从文件解析字幕
  static Future<List<IAppPlayerSubtitle>> _parseSubtitlesFromFile(
      IAppPlayerSubtitlesSource source) async {
    try {
      final List<IAppPlayerSubtitle> subtitles = [];
      // 并行读取多个文件
      final futures = <Future<List<IAppPlayerSubtitle>>>[];
      
      for (final String? url in source.urls!) {
        if (url != null) {
          futures.add(_readSingleFile(url));
        }
      }
      
      final results = await Future.wait(futures);
      for (final result in results) {
        subtitles.addAll(result);
      }
      
      return subtitles;
    } catch (exception) {
    }
    return [];
  }
  
  /// 读取单个字幕文件
  static Future<List<IAppPlayerSubtitle>> _readSingleFile(String url) async {
    try {
      final file = File(url);
      if (file.existsSync()) {
        final String fileContent = await file.readAsString();
        return _parseString(fileContent);
      }
    } catch (e) {
    }
    return [];
  }

  /// 从网络解析字幕
  static Future<List<IAppPlayerSubtitle>> _parseSubtitlesFromNetwork(
      IAppPlayerSubtitlesSource source) async {
    try {
      // 每个请求使用独立的HttpClient
      final List<IAppPlayerSubtitle> subtitles = [];
      final futures = <Future<List<IAppPlayerSubtitle>>>[];
      
      for (final String? url in source.urls!) {
        if (url != null) {
          futures.add(_fetchSingleUrl(url, source.headers));
        }
      }
      
      final results = await Future.wait(futures);
      for (final result in results) {
        subtitles.addAll(result);
      }

      return subtitles;
    } catch (exception) {
    }
    return [];
  }
  
  /// 获取单个网络字幕
  static Future<List<IAppPlayerSubtitle>> _fetchSingleUrl(
      String url, Map<String, String>? headers) async {
    // 每个请求创建独立的client并正确关闭
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      headers?.forEach((key, value) {
        request.headers.add(key, value);
      });
      final response = await request.close();
      final data = await response.transform(const Utf8Decoder()).join();
      return _parseString(data);
    } catch (e) {
      return [];
    } finally {
      client.close();
    }
  }

  /// 从内存解析字幕
  static List<IAppPlayerSubtitle> _parseSubtitlesFromMemory(
      IAppPlayerSubtitlesSource source) {
    try {
      return _parseString(source.content!);
    } catch (exception) {
    }
    return [];
  }

  /// 解析字幕字符串
  static List<IAppPlayerSubtitle> _parseString(String value) {
    // 换行符处理逻辑
    List<String> components = value.split('\r\n\r\n');
    if (components.length == 1) {
      components = value.split('\n\n');
    }

    // Skip parsing files with no cues
    if (components.length == 1) {
      return [];
    }

    final List<IAppPlayerSubtitle> subtitlesObj = [];

    final bool isWebVTT = components.any((c) => c.contains("WEBVTT"));
    for (final component in components) {
      if (component.isEmpty) {
        continue;
      }
      final subtitle = IAppPlayerSubtitle(component, isWebVTT);
      if (subtitle.start != null &&
          subtitle.end != null &&
          subtitle.texts != null) {
        subtitlesObj.add(subtitle);
      }
    }

    return subtitlesObj;
  }
}
