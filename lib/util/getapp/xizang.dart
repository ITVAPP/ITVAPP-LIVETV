import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 西藏电视台解析器
class xizangParser {
  static const String _baseUrl = 'https://api.vtibet.cn/xizangmobileinf/rest/xz/cardgroups';
  
  /// 解析西藏电视台直播流地址，添加 cancelToken 参数
  static Future<String> parse(String url, {CancelToken? cancelToken}) async {
    try {
      final uri = Uri.parse(url);
      final clickIndex = int.tryParse(uri.queryParameters['clickIndex'] ?? '0') ?? 0;
      
      // 传递 cancelToken
      final cards = await _getCardList(cancelToken: cancelToken);
      if (cards.isEmpty) {
        LogUtil.i('获取频道列表失败');
        return 'ERROR';
      }
      
      // 优化：处理负数情况，使用取模运算确保索引有效（原代码未处理负数）
      final cardIndex = clickIndex < 0 ? 0 : clickIndex % cards.length;
      final card = cards[cardIndex];
      
      final video = card['video'] as Map<String, dynamic>?;
      if (video == null) {
        LogUtil.i('频道列表缺少 video 数据');
        return 'ERROR';
      }
      
      final m3u8Url = video['url'] as String?;
      
      // 优化：合并空值检查、trim和m3u8验证
      if (m3u8Url == null || m3u8Url.isEmpty) {
        LogUtil.i('m3u8 地址为空');
        return 'ERROR';
      }
      
      final trimmedUrl = m3u8Url.trim();
      if (!trimmedUrl.contains('.m3u8')) {
        LogUtil.i('地址不包含 m3u8: $trimmedUrl');
        return 'ERROR';
      }
      
      LogUtil.i('成功获取 m3u8 播放地址: $trimmedUrl');
      return trimmedUrl;
    } catch (e) {
      LogUtil.i('解析西藏电视台直播流失败: $e');
      return 'ERROR';
    }
  }
  
  /// 获取卡片列表，添加 cancelToken 参数
  static Future<List<dynamic>> _getCardList({CancelToken? cancelToken}) async {
    final appcommon = {
      "adid": "5a78345cba65245f",
      "cctvId": "",
      "av": "2.2.3",
      "selfSetRecommend": "1",
      "an": "珠峰云",
      "userId": "",
      "ap": "android_phone"
    };
    final json = {
      "cardgroups": "LIVECAST",
      "paging": {"page_no": "1", "page_size": "10"},
      "version": "2.2.3"
    };
    final postData = {
      'appcommon': jsonEncode(appcommon),
      'json': jsonEncode(json),
    };
    
    try {
      // 传递 cancelToken 参数
      final response = await HttpUtil().postRequest<Map<String, dynamic>>(
        _baseUrl,
        data: postData,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; U; Android 12; zh-cn; SM-G9750 Build/SP1A.210812.016) AppleWebKit/533.1 (KHTML, like Gecko) Version/5.0 Mobile Safari/533.1',
            'Connection': 'Keep-Alive',
            'Accept-Encoding': 'gzip',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept-Language': 'zh-CN,zh;q=0.8',
            'Cache-Control': 'no-cache',
          },
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 6),
        ),
        cancelToken: cancelToken,
      );
      
      if (response == null) {
        LogUtil.i('POST 请求返回空响应');
        return [];
      }
      
      if (response['succeed'] != 1 || response['error_code'] != 0) {
        LogUtil.i('API 返回错误: ${response['error_desc']}');
        return [];
      }
      
      final cardgroups = response['cardgroups'] as List<dynamic>?;
      if (cardgroups == null || cardgroups.isEmpty) {
        LogUtil.i('cardgroups 为空');
        return [];
      }
      
      // 优化：使用更高效的方式收集cards
      final cards = <dynamic>[];
      for (var group in cardgroups) {
        final groupCards = group['cards'] as List<dynamic>?;
        if (groupCards != null && groupCards.isNotEmpty) {
          cards.addAll(groupCards);
        }
      }
      
      LogUtil.i('成功获取频道列表，数量: ${cards.length}');
      return cards;
    } catch (e) {
      LogUtil.i('获取频道列表失败: $e');
      return [];
    }
  }
}
