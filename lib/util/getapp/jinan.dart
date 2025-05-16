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

  /// 解析济南电视台直播流地址，添加 cancelToken 参数
  static Future<String> parse(String url, {CancelToken? cancelToken}) async {
    // 添加取消检查
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('任务已取消，跳过济南电视台解析');
      return 'ERROR';
    }
    
    try {
      final uri = Uri.parse(url);
      final clickIndex = int.tryParse(uri.queryParameters['clickIndex'] ?? '0') ?? 0;

      // 获取频道列表，传递 cancelToken
      final channels = await _getChannelList(cancelToken: cancelToken);
      
      // 添加取消检查
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('获取频道列表后任务被取消');
        return 'ERROR';
      }
      
      if (channels.isEmpty) {
        LogUtil.i('获取频道列表失败');
        return 'ERROR';
      }

      // 如果 clickIndex 超出范围，使用第一个频道
      final channel = (clickIndex >= channels.length) ? channels[0] : channels[clickIndex];
      
      final playUrls = channel['push_play_urls'] as List<dynamic>?;

      if (playUrls == null || playUrls.isEmpty) {
        LogUtil.i('播放地址列表为空');
        return 'ERROR';
      }

      // 添加日志，打印 playUrls 内容
      LogUtil.i('push_play_urls: $playUrls');

      // 直接取第三个地址（索引 2），因为它是 m3u8
      if (playUrls.length < 3) {
        LogUtil.i('播放地址列表长度不足，无法获取 m3u8');
        return 'ERROR';
      }

      final m3u8Url = playUrls[2] as String;
      LogUtil.i('原始 m3u8Url: "$m3u8Url"'); // 打印原始内容
      final trimmedM3u8Url = m3u8Url.trim(); // 修剪字符串
      LogUtil.i('修剪后的 m3u8Url: "$trimmedM3u8Url"'); // 打印修剪后内容

      // 修改检查逻辑，使用 contains 替代 endsWith
      if (trimmedM3u8Url.isEmpty || !trimmedM3u8Url.contains('.m3u8')) {
        LogUtil.i('地址不包含 m3u8: $trimmedM3u8Url');
        return 'ERROR';
      }

      LogUtil.i('成功获取 m3u8 播放地址: $trimmedM3u8Url');
      return trimmedM3u8Url;
    } catch (e) {
      // 添加取消检查
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('解析过程中任务被取消');
      } else {
        LogUtil.i('解析济南电视台直播流失败: $e');
      }
      return 'ERROR';
    }
  }

  /// 获取频道列表，添加 cancelToken 参数
  static Future<List<dynamic>> _getChannelList({CancelToken? cancelToken}) async {
    // 添加取消检查
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('任务已取消，跳过获取频道列表');
      return [];
    }
    
    final path = '/api/public/third/channel/tv/page';
    final params = {
      'size': '10',
      'page': '1'
    };

    // 传递 cancelToken
    final result = await _sendRequest(path, params, cancelToken: cancelToken);
    
    // 添加取消检查
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('请求完成后任务被取消');
      return [];
    }
    
    if (result == null) return [];

    try {
      final data = result['data'];
      if (data == null || data is! List) return [];
      
      return data; // 直接返回 data，而不是 data['records']
    } catch (e) {
      // 添加取消检查
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('解析频道列表数据过程中任务被取消');
      } else {
        LogUtil.i('解析频道列表失败: $e');
      }
      return [];
    }
  }

  /// 获取节目列表，添加 cancelToken 参数
  static Future<List<dynamic>> _getProgramList(String channelId, {CancelToken? cancelToken}) async {
    // 添加取消检查
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('任务已取消，跳过获取节目列表');
      return [];
    }
    
    // 获取当前日期
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    final path = '/api/public/third/channel/tv/$channelId/program/list';
    final params = {
      'start': date,
      'limit': '1',
      'channelId': channelId
    };

    // 传递 cancelToken
    final result = await _sendRequest(path, params, cancelToken: cancelToken);
    
    // 添加取消检查
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('请求完成后任务被取消');
      return [];
    }
    
    if (result == null) return [];

    try {
      final data = result['data'];
      if (data is! List) return [];
      
      return data;
    } catch (e) {
      // 添加取消检查
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('解析节目列表数据过程中任务被取消');
      } else {
        LogUtil.i('解析节目列表失败: $e');
      }
      return [];
    }
  }

  /// 发送请求，添加 cancelToken 参数
  static Future<Map<String, dynamic>?> _sendRequest(
    String path, 
    Map<String, String> params, 
    {CancelToken? cancelToken}
  ) async {
    // 添加取消检查
    if (cancelToken?.isCancelled ?? false) {
      LogUtil.i('任务已取消，跳过发送请求');
      return null;
    }
    
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

      // 使用 HttpUtil 发送请求，添加 cancelToken
      final response = await HttpUtil().getRequest<String>(
        fullUrl,
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 6),
        ),
        cancelToken: cancelToken,
      );

      // 添加取消检查
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('请求完成后任务被取消');
        return null;
      }

      if (response != null) {
        LogUtil.i('API 响应内容: $response'); // 添加日志记录响应内容
        return json.decode(response);
      }
    } catch (e) {
      // 添加取消检查
      if (cancelToken?.isCancelled ?? false) {
        LogUtil.i('请求过程中任务被取消');
      } else {
        LogUtil.i('请求失败: $e');
      }
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
