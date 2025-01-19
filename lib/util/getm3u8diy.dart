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

 /// 获取秒级时间戳
 static int getSecondTimestamp() {
   return DateTime.now().millisecondsSinceEpoch ~/ 1000;
 }

 /// 获取毫秒级时间戳(秒*1000)
 static int getMillisTimestamp() {
   return getSecondTimestamp() * 1000;
 }

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

     // 使用秒级时间戳并转16进制
     final timestamp = getSecondTimestamp();
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
   // 使用秒级时间戳
   final timestamp = getSecondTimestamp().toString();
   LogUtil.i('LiveKey使用的时间戳: $timestamp');
   
   final tokenString = timestamp + liveId + 'cutvLiveStream|Dream2017';
   LogUtil.i('直播密钥token原始字符串: $tokenString');
   final token = md5.convert(utf8.encode(tokenString)).toString();
   LogUtil.i('生成的token: $token');

   try {
     final uri = Uri.parse('https://hls-api.sztv.com.cn/getCutvHlsLiveKey').replace(
       queryParameters: {
         't': timestamp,
         'id': liveId,
         'token': token,
         'at': '1',
       },
     );

     LogUtil.i('正在请求深圳卫视直播密钥: ${uri.toString()}');
     LogUtil.i('请求参数: ${uri.queryParameters}');

     // 定义需要的headers
     final headers = {
       'Accept': '*/*',
       'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
       'Referer': 'https://www.sztv.com.cn/'
     };

     // 记录headers日志
     final headerLog = StringBuffer('LiveKey请求headers:\n');
     headers.forEach((key, value) => headerLog.write('$key:$value\n'));
     LogUtil.i(headerLog.toString().trim());

     final httpClient = ParserUtils.createHttpClient();
     final request = await httpClient.getUrl(uri);
     
     // 添加headers
     headers.forEach((key, value) {
       request.headers.add(key, value);
     });

     final response = await request.close();
     final responseBody = await response.transform(utf8.decoder).join();

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
     // 使用毫秒级时间戳(秒*1000)
     final timestamp = getMillisTimestamp();
     LogUtil.i('CDN密钥使用的时间戳: $timestamp');
     
     // 生成token
     final tokenString = 'iYKkRHlmUanQGaNMIJziWOkNsztv-live.sztv.com.cn$timestamp';
     LogUtil.i('CDN密钥token原始字符串: $tokenString');
     final token = md5.convert(utf8.encode(tokenString)).toString();
     LogUtil.i('生成的token: $token');
     
     final uri = Uri.parse('https://sttv2-api.sztv.com.cn/api/getCDNkey.php').replace(
       queryParameters: {
         'domain': 'sztv-live.sztv.com.cn',
         'page': 'https://www.sztv.com.cn/pindao/index.html?id=$cdnId',
         'token': token,
         't': timestamp.toString(),
       },
     );

     LogUtil.i('请求参数: ${uri.queryParameters}');
     LogUtil.i('正在请求CDN密钥: ${uri.toString()}');

     // 定义需要的headers
     final headers = {
       'Accept': '*/*',
       'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
       'Referer': 'https://www.sztv.com.cn/'
     };

     // 记录headers日志
     final headerLog = StringBuffer('CDN密钥请求headers:\n');
     headers.forEach((key, value) => headerLog.write('$key:$value\n'));
     LogUtil.i(headerLog.toString().trim());

     final httpClient = ParserUtils.createHttpClient();
     final request = await httpClient.getUrl(uri);
     
     // 添加headers
     headers.forEach((key, value) {
       request.headers.add(key, value);
     });

     final response = await request.close();
     final responseBody = await response.transform(utf8.decoder).join();

     LogUtil.i('CDN密钥响应状态码: ${response.statusCode}');
     LogUtil.i('CDN密钥响应体: $responseBody');

     if (response.statusCode == 200) {
       final data = json.decode(responseBody);
       if (data != null && data['status'] == 'ok') {
         return data['key'] ?? 'ERROR';
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
 
 // 修改为与PHP完全相同的数据结构
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
   final id = uri.queryParameters['id']; // 提取频道 ID
   if (!TV_LIST.containsKey(id)) {
     LogUtil.i('无效的频道 ID: $id');
     return 'ERROR';
   }

   final channelInfo = TV_LIST[id]!;
   final channelId = channelInfo['id'].toString(); // 修改channel ID获取方式
   
   // 使用秒级时间戳（与PHP的time()保持一致）
   final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
   
   // 使用与PHP完全相同的签名生成方式
   final signString = API_KEY + timestamp;  // 使用 + 操作符而不是字符串插值
   LogUtil.i('签名原始字符串: $signString');
   final sign = sha256.convert(utf8.encode(signString)).toString();
   LogUtil.i('生成的sign: $sign');
   
   final requestUrl = 'https://pubmod.hntv.tv/program/getAuth/live/class/program/11';
   LogUtil.i('正在请求河南电视台直播流: $requestUrl');

   // 构造与PHP相同格式的headers
   final headers = [
     'timestamp:$timestamp',
     'sign:$sign'
   ];

   final headerLog = StringBuffer('请求headers:\n');
   headers.forEach((header) => headerLog.write('$header\n'));
   LogUtil.i(headerLog.toString().trim());

   try {
     final httpClient = ParserUtils.createHttpClient();
     final request = await httpClient.getUrl(Uri.parse(requestUrl));
     
     // 添加通用头信息
     request.headers.set('Accept', '*/*');
     request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36');
     
     // 使用与PHP相同的header格式添加认证头信息
     for (var header in headers) {
       final parts = header.split(':');
       if (parts.length == 2) {
         request.headers.set(parts[0].trim(), parts[1].trim());
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
