import 'dart:convert';
import 'dart:io';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/core/iapp_player_utils.dart';
import 'iapp_player_subtitle.dart';

class IAppPlayerSubtitlesFactory {
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

  static Future<List<IAppPlayerSubtitle>> _parseSubtitlesFromFile(
      IAppPlayerSubtitlesSource source) async {
    try {
      final List<IAppPlayerSubtitle> subtitles = [];
      // 优化：并行读取多个文件
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
      IAppPlayerUtils.log("Failed to read subtitles from file: $exception");
    }
    return [];
  }
  
  static Future<List<IAppPlayerSubtitle>> _readSingleFile(String url) async {
    try {
      final file = File(url);
      if (file.existsSync()) {
        final String fileContent = await file.readAsString();
        return _parseString(fileContent);
      } else {
        IAppPlayerUtils.log("$url doesn't exist!");
      }
    } catch (e) {
      IAppPlayerUtils.log("Failed to read file $url: $e");
    }
    return [];
  }

  static Future<List<IAppPlayerSubtitle>> _parseSubtitlesFromNetwork(
      IAppPlayerSubtitlesSource source) async {
    try {
      // 修复：每个请求使用独立的HttpClient
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

      IAppPlayerUtils.log("Parsed total subtitles: ${subtitles.length}");
      return subtitles;
    } catch (exception) {
      IAppPlayerUtils.log(
          "Failed to read subtitles from network: $exception");
    }
    return [];
  }
  
  static Future<List<IAppPlayerSubtitle>> _fetchSingleUrl(
      String url, Map<String, String>? headers) async {
    // 修复：每个请求创建独立的client并正确关闭
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
      IAppPlayerUtils.log("Failed to fetch URL $url: $e");
      return [];
    } finally {
      client.close();
    }
  }

  static List<IAppPlayerSubtitle> _parseSubtitlesFromMemory(
      IAppPlayerSubtitlesSource source) {
    try {
      return _parseString(source.content!);
    } catch (exception) {
      IAppPlayerUtils.log("Failed to read subtitles from memory: $exception");
    }
    return [];
  }

  static List<IAppPlayerSubtitle> _parseString(String value) {
    // 修复：保持原始的换行符处理逻辑
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
