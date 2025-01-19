import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';

/// 通用工具类
class ParserUtils {
  /// 常用请求头
  static const Map<String, String> commonHeaders = {
    'Accept': '*/*',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
  };

  /// 创建禁用SSL验证的HttpClient
  static HttpClient createHttpClient() {
    LogUtil.i('创建禁用SSL验证的HttpClient');
    return HttpClient()
      ..badCertificateCallback = ((X509Certificate cert, String host, int port) {
        LogUtil.i('SSL证书验证已禁用: $host:$port');
        return true;
      });
  }

  /// 记录请求头的辅助方法
  static void logHeaders(String prefix, Map<String, String> headers) {
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

      // 生成签名和完整的直播流地址
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timeHex = timestamp.toRadixString(16); // 转换为16进制
      
      // 调整sign计算方式
      final signString = '$cdnKey$liveId/500/$liveKey$timestamp';
      LogUtil.i('签名原始字符串: $signString');
      final sign = md5.convert(utf8.encode(signString)).toString();
      LogUtil.i('生成的sign: $sign');

      // 返回正确格式的URL
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
    // 生成时间戳(保持秒级)
    final int ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timestamp = ts.toString();
  
    // 修改: 使用正确的token生成方式 
    final tokenString = timestamp + liveId + 'cutvLiveStream|Dream2017';
    LogUtil.i('直播密钥token原始字符串: $tokenString');
    final token = md5.convert(utf8.encode(tokenString)).toString();
    LogUtil.i('生成的token: $token');

    try {
      // 创建 HttpClient 并禁用证书验证
      final httpClient = ParserUtils.createHttpClient();

      final uri = Uri.parse('https://hls-api.sztv.com.cn/getCutvHlsLiveKey').replace(
        queryParameters: {
          't': timestamp,
          'id': liveId,
          'token': token,
          'at': '1',
        },
      );

      // 添加请求日志记录
      LogUtil.i('正在请求深圳卫视直播密钥: ${uri.toString()}');

      // 创建完整的headers Map
      final Map<String, String> headers = {
        ...ParserUtils.commonHeaders,
        'Referer': 'https://www.sztv.com.cn/',
        ...HeadersConfig.generateHeaders(
          url: 'https://hls-api.sztv.com.cn/getCutvHlsLiveKey',
        ),
      };

      // 使用改进的日志方法
      ParserUtils.logHeaders('LiveKey', headers);

      final request = await httpClient.getUrl(uri);
      
      // 添加headers
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      // 添加响应日志
      LogUtil.i('LiveKey响应状态码: ${response.statusCode}');
      LogUtil.i('LiveKey响应体: $responseBody');

      if (response.statusCode == 200) {
        return ParserUtils.decodeBase64(responseBody);
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
      // 修改:使用毫秒时间戳
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // 修改:调整token生成方式
      final tokenString = timestamp.toString() + 'cutvLiveStream|Dream2017';
      LogUtil.i('CDN密钥token原始字符串: $tokenString');
      final token = md5.convert(utf8.encode(tokenString)).toString();
      LogUtil.i('生成的token: $token');
      
      // 构建新的请求URL
      final uri = Uri.parse('https://sttv2-api.sztv.com.cn/api/getCDNkey.php').replace(
        queryParameters: {
          'domain': 'sztv-live.sztv.com.cn',
          'page': 'https://www.sztv.com.cn/pindao/index.html?id=$cdnId',
          'token': token,
          't': timestamp.toString(),
        },
      );

      // 添加请求日志记录
      LogUtil.i('正在请求CDN密钥: ${uri.toString()}');

      // 创建完整的headers Map
      final Map<String, String> headers = {
        ...ParserUtils.commonHeaders,
        'Referer': 'https://www.sztv.com.cn/',
      };

      // 使用改进的日志方法
      ParserUtils.logHeaders('CDN密钥', headers);

      // 创建 HttpClient 并禁用证书验证
      final httpClient = ParserUtils.createHttpClient();
      final request = await httpClient.getUrl(uri);
      
      // 添加headers
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      LogUtil.i('CDN密钥响应状态码: ${response.statusCode}');
      LogUtil.i('CDN密钥响应体: $responseBody');

      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        if (data != null && data['status'] == 'ok') {  //修改:调整判断条件
          return data['key'] ?? 'ERROR';  //修改:返回key字段
        }
        LogUtil.i('响应格式不符合预期: $responseBody');
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
  
  static const Map<String, List<String>> TV_LIST = {
    'hnws': ['145', '河南卫视'],
    'hnds': ['141', '河南都市'],
    'hnms': ['146', '河南民生'],
    'hmfz': ['147', '河南法治'],
    'hndsj': ['148', '河南电视剧'],
    'hnxw': ['149', '河南新闻'],
    'htgw': ['150', '欢腾购物'],
    'hngg': ['151', '河南公共'],
    'hnxc': ['152', '河南乡村'],
    'hngj': ['153', '河南国际'],
    'hnly': ['154', '河南梨园'],
  };
  
  static Future<String> parse(String url) async {
    final uri = Uri.parse(url);
    final id = uri.queryParameters['id']; // 提取频道 ID

    if (!TV_LIST.containsKey(id)) {
      LogUtil.i('无效的频道 ID: $id');
      return 'ERROR';
    }

    final channelInfo = TV_LIST[id]!;
    final channelId = channelInfo[0];

    // 使用秒级时间戳（与PHP的time()保持一致）
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    
    // 使用与PHP完全相同的签名生成方式
    final signString = '$API_KEY$timestamp';
    LogUtil.i('签名原始字符串: $signString');
    final sign = sha256.convert(utf8.encode(signString)).toString();
    LogUtil.i('生成的sign: $sign');
    
    final requestUrl = 'https://pubmod.hntv.tv/program/getAuth/live/class/program/11';
    LogUtil.i('正在请求河南电视台直播流: $requestUrl');
    
    // 修改：使用与PHP相同的header格式
    final List<String> headers = [
      'timestamp:$timestamp',
      'sign:$sign'
    ];

    // 记录headers
    LogUtil.i('请求headers:');
    for (var header in headers) {
      LogUtil.i('  $header');
    }

    try {
      final httpClient = ParserUtils.createHttpClient();
      final request = await httpClient.getUrl(Uri.parse(requestUrl));
      
      // 使用PHP相同的方式设置headers
      for (var header in headers) {
        final parts = header.split(':');
        if (parts.length >= 2) {
          request.headers.set(parts[0], header.substring(parts[0].length + 1));
        }
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      LogUtil.i('HTTP 状态码: ${response.statusCode}');
      LogUtil.i('响应 Body: $responseBody');

      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        
        // 改进错误处理：检查是否是错误响应
        if (data is Map && data['success'] == false) {
          LogUtil.i('API返回错误: ${data['msg']}');
          return 'ERROR';
        }
        
        // 确保数据是List类型
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

            // 修改：与PHP版本保持一致的视频流检查逻辑
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
