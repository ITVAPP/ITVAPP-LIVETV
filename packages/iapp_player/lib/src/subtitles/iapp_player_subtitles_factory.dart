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
      for (final String? url in source.urls!) {
        final file = File(url!);
        if (file.existsSync()) {
          final String fileContent = await file.readAsString();
          final subtitlesCache = _parseString(fileContent);
          subtitles.addAll(subtitlesCache);
        } else {
          IAppPlayerUtils.log("$url doesn't exist!");
        }
      }
      return subtitles;
    } catch (exception) {
      IAppPlayerUtils.log("Failed to read subtitles from file: $exception");
    }
    return [];
  }

  static Future<List<IAppPlayerSubtitle>> _parseSubtitlesFromNetwork(
      IAppPlayerSubtitlesSource source) async {
    try {
      final client = HttpClient();
      final List<IAppPlayerSubtitle> subtitles = [];
      for (final String? url in source.urls!) {
        final request = await client.getUrl(Uri.parse(url!));
        source.headers?.keys.forEach((key) {
          final value = source.headers![key];
          if (value != null) {
            request.headers.add(key, value);
          }
        });
        final response = await request.close();
        final data = await response.transform(const Utf8Decoder()).join();
        final cacheList = _parseString(data);
        subtitles.addAll(cacheList);
      }
      client.close();

      IAppPlayerUtils.log("Parsed total subtitles: ${subtitles.length}");
      return subtitles;
    } catch (exception) {
      IAppPlayerUtils.log(
          "Failed to read subtitles from network: $exception");
    }
    return [];
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
    List<String> components = value.split('\r\n\r\n');
    if (components.length == 1) {
      components = value.split('\n\n');
    }

    // Skip parsing files with no cues
    if (components.length == 1) {
      return [];
    }

    final List<IAppPlayerSubtitle> subtitlesObj = [];

    final bool isWebVTT = components.contains("WEBVTT");
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
