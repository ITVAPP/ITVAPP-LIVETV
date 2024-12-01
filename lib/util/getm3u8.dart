import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';

// 常量配置类
class GetM3U8Config {
  static const Duration defaultTimeout = Duration(seconds: 10);
  static const Duration retryDelay = Duration(seconds: 1);
  static const int maxRetries = 2;
  static const String emptyPlaylist = '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-ENDLIST';
  
  static const Map<String, String> defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
  };
}

class GetM3U8 {
  final http.Client _client;
  final Duration timeoutDuration;
  bool _isDisposed = false;
  
  // 从源码中提取 m3u8 地址的正则表达式
  static final RegExp m3u8Regex = RegExp(r'''https?://[^\s<>"']+?\.m3u8[^\s<>"']*''');
  
  GetM3U8({this.timeoutDuration = GetM3U8Config.defaultTimeout}) : _client = http.Client();

  // 检查实例是否已释放
  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('GetM3U8实例已被释放');
    }
  }

  // 作为工具类使用：解析源码并返回 m3u8 URL
  Future<String> extractM3U8Url(String sourceUrl) async {
    _checkDisposed();
    try {
      final response = await _client.get(
        Uri.parse(sourceUrl),
        headers: _getRequestHeaders(),
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final match = m3u8Regex.firstMatch(response.body);
        if (match != null) {
          final m3u8Url = match.group(0) ?? 'ERROR';
          LogUtil.i('成功提取 M3U8 URL: $m3u8Url');
          return m3u8Url;
        }
      }
      LogUtil.e('未能从源码中提取 M3U8 URL');
      return 'ERROR';
    } catch (e, stackTrace) {
      LogUtil.logError('提取 M3U8 URL 时发生错误', e, stackTrace);
      return 'ERROR';
    }
  }

  // 作为播放列表文件使用：获取完整的播放列表内容（带重试机制）
  Future<String> getPlaylist(String sourceUrl) async {
    _checkDisposed();
    for (int i = 0; i <= GetM3U8Config.maxRetries; i++) {
      try {
        // 先获取 m3u8 地址
        LogUtil.i('开始第 ${i + 1} 次尝试获取播放列表，源URL: $sourceUrl');
        final m3u8Url = await extractM3U8Url(sourceUrl);
        if (m3u8Url == 'ERROR') {
          LogUtil.e('第 ${i + 1} 次尝试获取 M3U8 URL 失败');
          if (i < GetM3U8Config.maxRetries) {
            await Future.delayed(GetM3U8Config.retryDelay);
            continue;
          }
          return GetM3U8Config.emptyPlaylist;
        }

        // 获取 m3u8 内容
        final response = await _client.get(
          Uri.parse(m3u8Url),
          headers: _getRequestHeaders(),
        ).timeout(timeoutDuration);

        if (response.statusCode == 200) {
          final content = response.body;
          // 如果内容看起来是有效的 m3u8
          if (content.contains('#EXTM3U')) {
            LogUtil.i('成功获取播放列表内容');
            return content;
          }
        }
        
        LogUtil.e('第 ${i + 1} 次尝试获取播放列表内容失败');
        if (i < GetM3U8Config.maxRetries) {
          await Future.delayed(GetM3U8Config.retryDelay);
          continue;
        }
        
      } catch (e, stackTrace) {
        LogUtil.logError('第 ${i + 1} 次尝试时发生错误', e, stackTrace);
        if (i < GetM3U8Config.maxRetries) {
          await Future.delayed(GetM3U8Config.retryDelay);
          continue;
        }
      }
    }
    
    LogUtil.e('所有重试都失败，返回空播放列表');
    return GetM3U8Config.emptyPlaylist;
  }

  // 获取请求头
  Map<String, String> _getRequestHeaders() {
    return Map<String, String>.from(GetM3U8Config.defaultHeaders);
  }

  // 释放资源
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _client.close();
  }

  // 静态方法：解析 URL 中的参数
  static String? getUrlParameter(String filePath) {
    try {
      final uri = Uri.parse(filePath);
      return uri.queryParameters['url'];
    } catch (e, stackTrace) {
      LogUtil.logError('解析 URL 参数时发生错误', e, stackTrace);
      return null;
    }
  }
}

// 入口函数：当文件被直接访问时调用
void main(List<String> args) async {
  // 获取文件路径（即访问时的完整 URL）
  final filePath = Platform.script.toString();
  final sourceUrl = GetM3U8.getUrlParameter(filePath);
  
  if (sourceUrl != null) {
    final handler = GetM3U8();
    try {
      LogUtil.i('开始处理请求，源URL: $sourceUrl');
      // 获取并输出播放列表内容
      final playlist = await handler.getPlaylist(sourceUrl);
      stdout.write(playlist);  // 直接写入标准输出，不使用print
    } catch (e, stackTrace) {
      LogUtil.logError('处理请求时发生错误', e, stackTrace);
      stdout.write(GetM3U8Config.emptyPlaylist);
    } finally {
      handler.dispose();
    }
  } else {
    LogUtil.e('未提供源URL参数');
    stdout.write(GetM3U8Config.emptyPlaylist);
  }
}
