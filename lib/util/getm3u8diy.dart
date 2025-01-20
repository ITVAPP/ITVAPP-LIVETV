import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 通用工具类
class ParserUtils {
  /// 常用请求头
  static const Map<String, String> commonHeaders = {
    'Accept': '*/*',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
  };

  /// 创建Dio实例并配置
  static final dio = Dio()
    ..options.headers = commonHeaders
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        LogUtil.i('SSL证书验证已禁用');
        return handler.next(options);
      }
    ));

  /// 记录请求头的辅助方法
  static void logHeaders(String prefix, Map<String, dynamic> headers) {
    LogUtil.i('$prefix 请求头:');
    headers.forEach((key, value) {
      LogUtil.i('  $key: $value');
    });
  }

  /// Base64 解码函数
  static String decodeBase64(String input) {
    try {
      // 去除无效字符，确保输入字符串合法
      String cleanInput = input.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      // 补齐 Base64 长度，避免解码异常
      while (cleanInput.length % 4 != 0) {
        cleanInput += '=';
      }

      // 对输入字符串进行反转和重组
      final halfLength = cleanInput.length ~/ 2;
      final firstHalf = cleanInput.substring(0, halfLength);
      final secondHalf = cleanInput.substring(halfLength);
      final reversed = (secondHalf + firstHalf).split('').reversed.join();

      try {
        // 优先尝试解码反转后的字符串
        return utf8.decode(base64.decode(reversed));
      } on FormatException {
        // 如果反转解码失败，尝试直接解码原始字符串
        return utf8.decode(base64.decode(cleanInput));
      }
    } catch (e) {
      // 解码失败时记录日志并返回空字符串
      LogUtil.i('Base64 解码失败: $e');
      return 'ERROR';
    }
  }
}

/// m3u8地址解析器
class GetM3u8Diy {
  /// 根据 URL 获取直播流地址
  static Future<String> getStreamUrl(String url) async {
    try {
      // 如果 URL 包含 `sztv.com.cn`，调用深圳卫视解析器
      if (url.contains('sztv.com.cn')) {
        return await SztvParser.parse(url);
      }
      // 如果 URL 包含 `hntv`，调用河南卫视解析器
      else if (url.contains('hntv')) {
        return await HntvParser.parse(url);
      }
      // 如果不符合任何解析规则，记录日志并返回空字符串
      LogUtil.i('未找到匹配的解析规则: $url');
      return 'ERROR';
    } catch (e) {
      // 捕获解析异常并记录日志
      LogUtil.i('解析直播流地址失败: $e');
      return 'ERROR';
    }
  }
}

/// 深圳卫视解析器
class SztvParser {
  /// 频道列表映射表：频道 ID -> [频道编号, CDN ID, 频道名称]
  static const Map<String, List<String>> TV_LIST = {
    'szws': ['AxeFRth', '7867', '深圳卫视'],
    'szds': ['ZwxzUXr', '7868', '都市频道'],
    'szdsj': ['4azbkoY', '7880', '电视剧频道'],
    'szcj': ['3vlcoxP', '7871', '财经频道'],
    'szse': ['1SIQj6s', '7881', '少儿频道'],
    'szyd': ['wDF6KJ3', '7869', '移动电视'],
    'szyh': ['BJ5u5k2', '7878', '宜和购物频道'],
    'szgj': ['sztvgjpd', '7944', '国际频道'],
  };

  /// 解析深圳卫视直播流地址
  static Future<String> parse(String url) async {
    final uri = Uri.parse(url);
    final id = uri.queryParameters['id']; // 提取频道 ID

    // 检查频道 ID 是否在映射表中
    if (!TV_LIST.containsKey(id)) {
      LogUtil.i('无效的频道 ID');
      return 'ERROR';
    }

    final channelInfo = TV_LIST[id]!; // 获取频道信息
    final liveId = channelInfo[0];
    final cdnId = channelInfo[1];

    try {
      // 获取直播密钥和 CDN 密钥
      final liveKey = await _getLiveKey(liveId);
      if (liveKey.isEmpty) return 'ERROR';
      final cdnKey = await _getCdnKey(cdnId);
      if (cdnKey.isEmpty) return 'ERROR';

      // 生成时间戳的16进制表示
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      LogUtil.i('生成最终URL使用的时间戳: $timestamp');
      final timeHex = timestamp.toRadixString(16);
      LogUtil.i('转换为16进制: $timeHex');
      
      // 生成sign
      final signString = '$cdnKey/$liveId/500/$liveKey.m3u8$timeHex';
      LogUtil.i('签名原始字符串: $signString');
      final sign = md5.convert(utf8.encode(signString)).toString();
      LogUtil.i('生成的sign: $sign');

      // 生成最终URL
      final streamUrl = 'https://sztv-live.sztv.com.cn/$liveId/500/$liveKey.m3u8?sign=$sign&t=$timeHex';
      LogUtil.i('生成的直播流地址: $streamUrl');
      return streamUrl;
    } catch (e) {
      LogUtil.i('生成深圳卫视直播流地址失败: $e');
      return 'ERROR';
    }
  }
  
  /// 获取直播密钥
  static Future<String> _getLiveKey(String liveId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    LogUtil.i('LiveKey使用的时间戳: $timestamp');
    
    final tokenString = '$timestamp$liveId' + 'cutvLiveStream|Dream2017';
    LogUtil.i('直播密钥token原始字符串: $tokenString');
    final token = md5.convert(utf8.encode(tokenString)).toString();
    LogUtil.i('生成的token: $token');

    try {
      final response = await ParserUtils.dio.get(
        'https://hls-api.sztv.com.cn/getCutvHlsLiveKey',
        queryParameters: {
          't': timestamp.toString(),
          'id': liveId,
          'token': token,
          'at': '1',
        },
        options: Options(
          headers: {
            'Accept': '*/*',
            'Referer': 'https://www.sztv.com.cn/'
          }
        ),
      );

      LogUtil.i('响应状态码: ${response.statusCode}');
      LogUtil.i('响应头: ${response.headers}');
      LogUtil.i('响应体: ${response.data}');

      if (response.statusCode == 200) {
        return ParserUtils.decodeBase64(response.data.toString());
      }
      LogUtil.i('获取直播密钥失败: HTTP ${response.statusCode}');
    } catch (e) {
      LogUtil.i('获取直播密钥时发生错误: $e');
    }
    return 'ERROR';
  }
  
  /// 获取 CDN 密钥
  static Future<String> _getCdnKey(String cdnId) async {
    try {
      final millisTimestamp = DateTime.now().millisecondsSinceEpoch;
      LogUtil.i('毫秒时间戳: $millisTimestamp');
      
      final tokenString = 'iYKkRHlmUanQGaNMIJziWOkNsztv-live.sztv.com.cn$millisTimestamp';
      LogUtil.i('CDN密钥token原始字符串: $tokenString');
      final token = md5.convert(utf8.encode(tokenString)).toString();
      LogUtil.i('生成的token: $token');

      final response = await ParserUtils.dio.get(
        'https://sttv2-api.sztv.com.cn/api/getCDNkey.php',
        queryParameters: {
          'domain': 'sztv-live.sztv.com.cn',
          'page': 'https://www.sztv.com.cn/pindao/index.html?id=$cdnId',
          'token': token,
          't': millisTimestamp.toString(),
        },
        options: Options(
          headers: {
            'Accept': '*/*',
            'Referer': 'https://www.sztv.com.cn/'
          }
        ),
      );

      LogUtil.i('响应状态码: ${response.statusCode}');
      LogUtil.i('响应头: ${response.headers}');
      LogUtil.i('响应体: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null && data['status'] == 'ok' && data['key'] != null) {
          return data['key'];
        }
        LogUtil.i('响应格式不符合预期: ${data}');
      } else {
        LogUtil.i('获取 CDN 密钥失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      LogUtil.i('获取 CDN 密钥时发生错误: $e');
    }
    return 'ERROR';
  }
}

/// 河南卫视解析器
class HntvParser {
  static const String API_KEY = '6ca114a836ac7d73';
  
  static const Map<String, Map<String, dynamic>> TV_LIST = {
    'hnws': {'id': 145, 'name': '河南卫视'},
    'hnds': {'id': 141, 'name': '河南都市'},
    'hnms': {'id': 146, 'name': '河南民生'}, 
    'hmfz': {'id': 147, 'name': '河南法治'},
    'hndsj': {'id': 148, 'name': '河南电视剧'},
    'hnxw': {'id': 149, 'name': '河南新闻'},
    'htgw': {'id': 150, 'name': '欢腾购物'},
    'hngg': {'id': 151, 'name': '河南公共'},
    'hnxc': {'id': 152, 'name': '河南乡村'},
    'hngj': {'id': 153, 'name': '河南国际'},
    'hnly': {'id': 154, 'name': '河南梨园'},
    'wwbk': {'id': 155, 'name': '文物宝库'},
    'wspd': {'id': 156, 'name': '武术世界'},
    'jczy': {'id': 157, 'name': '睛彩中原'},
    'ydxj': {'id': 163, 'name': '移动戏曲'},
    'xsj': {'id': 183, 'name': '象视界'}
  };
  
  static Future<String> parse(String url) async {
    final uri = Uri.parse(url);
    final id = uri.queryParameters['id'];
    if (!TV_LIST.containsKey(id)) {
      LogUtil.i('无效的频道 ID: $id');
      return 'ERROR';
    }

    final channelInfo = TV_LIST[id]!;
    final channelId = channelInfo['id'].toString();
    
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    
    final signString = "${API_KEY}${timestamp}";
    LogUtil.i('签名原始字符串: $signString');
    final sign = sha256.convert(utf8.encode(signString)).toString();
    LogUtil.i('生成的sign: $sign');
    
    const requestUrl = 'https://pubmod.hntv.tv/program/getAuth/live/class/program/11';
    LogUtil.i('正在请求河南电视台直播流: $requestUrl');

    try {
      final response = await ParserUtils.dio.get(
        requestUrl,
        options: Options(
          headers: {
            'Accept': '*/*',
            'timestamp': timestamp,
            'sign': sign,
          }
        ),
      );

      LogUtil.i('HTTP 状态码: ${response.statusCode}');
      LogUtil.i('响应 Body: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;
        
        if (data is Map && data['success'] == false) {
          LogUtil.i('API返回错误: ${data['msg']}');
          return 'ERROR';
        }
        
        if (data is! List) {
          LogUtil.i('响应数据格式错误：预期是List，实际是${data.runtimeType}');
          return 'ERROR';
        }

        final List<dynamic> channels = data;
        LogUtil.i('返回的频道数量: ${channels.length}');

        for (var item in channels) {
          LogUtil.i('频道 ID: ${item['cid']}, 频道名称: ${item['title']}');
          if (item['cid'].toString() == channelId) {
            LogUtil.i('匹配的频道 ID 找到: $channelId');
            if (item['video_streams'] is List && (item['video_streams'] as List).isNotEmpty) {
              final url = item['video_streams'][0].toString();
              LogUtil.i('找到video_streams地址: $url');
              return url;
            } else if (item['streams'] is List && (item['streams'] as List).isNotEmpty) {
              final url = item['streams'][0].toString();
             LogUtil.i('找到streams地址: $url');
             return url;
           } else {
             LogUtil.i('频道 $channelId 没有可用的视频流');
           }
         }
       }
       LogUtil.i('未找到匹配的频道信息: 可能频道 ID 发生变化');
     } else {
       LogUtil.i('获取河南电视台数据失败: HTTP ${response.statusCode}');
     }
   } catch (e) {
     LogUtil.i('获取河南电视台直播地址失败: $e');
   }

   return 'ERROR';
 }
}
