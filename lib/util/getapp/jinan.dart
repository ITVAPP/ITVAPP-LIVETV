import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 济南电视台解析器
class JinanParser {
  static const String _mainUsername = 'jntv';
  static const String _baseUrl = 'https://dlive.guangbocloud.com';
  static const String _secret = '401b38e85b0640b9a6d8f13ad4e1bcc4';
  static const String _authentication = '1681c47ebfb2861ea9ea2d35224b67ad';

  /// 解析济南电视台直播流地址
  static Future<String> parse(String url) async {
    try {
      final uri = Uri.parse(url);
      final clickIndex = int.tryParse(uri.queryParameters['clickIndex'] ?? '0') ?? 0;

      // 获取频道列表
      final channels = await _getChannelList();
      if (channels.isEmpty) {
        LogUtil.i('获取频道列表失败');
        return 'ERROR';
      }

      // 检查是否有足够的频道
      if (clickIndex >= channels.length) {
        LogUtil.i('点击索引超出范围: $clickIndex >= ${channels.length}');
        return 'ERROR';
      }

      // 获取指定频道的节目列表
      final channelId = channels[clickIndex]['id'];
      final programs = await _getProgramList(channelId);
      
      if (programs.isEmpty) {
        LogUtil.i('获取节目列表失败');
        return 'ERROR';
      }

      // 返回直播流地址
      final playUrl = programs[0]['playUrl'];
      if (playUrl == null || playUrl.isEmpty) {
        LogUtil.i('播放地址为空');
        return 'ERROR';
      }

      LogUtil.i('成功获取播放地址: $playUrl');
      return playUrl;
    } catch (e) {
      LogUtil.i('解析济南电视台直播流失败: $e');
      return 'ERROR';
    }
  }

  /// 获取频道列表
  static Future<List<dynamic>> _getChannelList() async {
    final path = '/api/public/third/channel/tv/page';
    final params = {
      'size': '10',
      'page': '1'
    };

    final result = await _sendRequest(path, params);
    if (result == null) return [];

    try {
      final data = result['data'];
      if (data == null) return [];
      
      final records = data['records'];
      if (records is! List) return [];

      return records;
    } catch (e) {
      LogUtil.i('解析频道列表失败: $e');
      return [];
    }
  }

  /// 获取节目列表
  static Future<List<dynamic>> _getProgramList(String channelId) async {
    // 获取当前日期
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    final path = '/api/public/third/channel/tv/$channelId/program/list';
    final params = {
      'start': date,
      'limit': '1',
      'channelId': channelId
    };

    final result = await _sendRequest(path, params);
    if (result == null) return [];

    try {
      final data = result['data'];
      if (data is! List) return [];
      
      return data;
    } catch (e) {
      LogUtil.i('解析节目列表失败: $e');
      return [];
    }
  }

  /// 发送请求
  static Future<Map<String, dynamic>?> _sendRequest(String path, Map<String, String> params) async {
    try {
      // 生成时间戳
      final msTimestamp = DateTime.now().millisecondsSinceEpoch;
      final timestamp = msTimestamp ~/ 1000;

      // 生成签名
      final signature = _generateSignature(params, timestamp);

      // 构建请求头
      final headers = {
        'Authentication': _authentication,
        'X-DFSX-Signature': signature,
        'X-DFSX-mainUsername': _mainUsername,
        'X-DFSX-Timestamp': timestamp.toString(),
        'YS-Timestamp': msTimestamp.toString(),
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Redmi K30 5G Speed Build/SKQ1.211006.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/96.0.4664.104 Mobile Safari/537.36',
        'Cache-Control': 'max-age=60, max-stale=0',
        'Host': 'dlive.guangbocloud.com',
        'Connection': 'Keep-Alive',
        'Accept-Encoding': 'gzip'
      };

      // 构建完整URL
      final queryString = Uri(queryParameters: params).query;
      final fullUrl = '$_baseUrl$path?$queryString';

      LogUtil.i('发送请求: $fullUrl');
      LogUtil.i('请求头: $headers');

      // 使用 HttpUtil 发送请求，移除重试相关参数，使用 HttpUtil 默认的重试逻辑
      final response = await HttpUtil().getRequest<String>(
        fullUrl,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );

      if (response != null) {
        return json.decode(response);
      }
    } catch (e) {
      LogUtil.i('请求失败: $e');
    }
    return null;
  }

  /// 生成签名
  static String _generateSignature(Map<String, String> params, int timestamp) {
    // 添加时间戳参数
    final signParams = Map<String, String>.from(params)
      ..['timestamp'] = timestamp.toString();

    // 按键名排序
    final sortedParams = Map.fromEntries(
      signParams.entries.toList()..sort((a, b) => a.key.compareTo(b.key))
    );

    // 构建签名字符串
    final pairs = sortedParams.entries.map((e) => '${e.key}=${e.value}').toList();
    final signStr = '${pairs.join('&')}&secret=$_secret';

    LogUtil.i('签名字符串: $signStr');

    // 生成MD5签名
    final signature = md5.convert(utf8.encode(signStr)).toString();
    LogUtil.i('生成的签名: $signature');

    return signature;
  }
}
