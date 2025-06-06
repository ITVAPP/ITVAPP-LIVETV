import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'parser_helper.dart';

/// 西藏电视台解析器
class XizangParser {  // 修正类名首字母大写
  static const String _baseUrl = 'https://api.vtibet.cn/xizangmobileinf/rest/xz/cardgroups';
  static const String _parserName = '西藏电视台';
  
  // 提取常量配置
  static const Map<String, dynamic> _appCommon = {
    "adid": "5a78345cba65245f",
    "cctvId": "",
    "av": "2.2.3",
    "selfSetRecommend": "1",
    "an": "珠峰云",
    "userId": "",
    "ap": "android_phone"
  };
  
  static const Map<String, dynamic> _requestJson = {
    "cardgroups": "LIVECAST",
    "paging": {"page_no": "1", "page_size": "10"},
    "version": "2.2.3"
  };
  
  /// 解析西藏电视台直播流地址，添加 cancelToken 参数
  static Future<String> parse(String url, {CancelToken? cancelToken}) async {
    try {
      final uri = Uri.parse(url);
      final clickIndex = ParserHelper.parseClickIndex(uri);
      
      // 传递 cancelToken
      final cards = await _getCardList(cancelToken: cancelToken);
      if (cards.isEmpty) {
        LogUtil.i('[$_parserName] 获取频道列表失败');
        return ParserHelper.errorResult;
      }
      
      LogUtil.i('[$_parserName] cards 列表: $cards'); // 添加调试日志
      
      // 使用工具方法获取安全索引
      final safeIndex = ParserHelper.getSafeIndex(clickIndex, cards.length);
      final card = cards[safeIndex];
      LogUtil.i('[$_parserName] 选择的 card: $card'); // 添加调试日志
      
      final video = card['video'] as Map<String, dynamic>?;
      if (video == null) {
        LogUtil.i('[$_parserName] 频道列表缺少 video 数据');
        return ParserHelper.errorResult;
      }
      
      final m3u8Url = video['url'] as String?;
      LogUtil.i('[$_parserName] 原始 m3u8Url: "$m3u8Url"');
      
      // 使用工具方法验证 m3u8 地址
      final validatedUrl = ParserHelper.validateM3u8Url(m3u8Url, _parserName);
      return validatedUrl ?? ParserHelper.errorResult;
    } catch (e) {
      LogUtil.i('[$_parserName] 解析直播流失败: $e');
      return ParserHelper.errorResult;
    }
  }
  
  /// 获取卡片列表，添加 cancelToken 参数
  static Future<List<dynamic>> _getCardList({CancelToken? cancelToken}) async {
    final postData = {
      'appcommon': jsonEncode(_appCommon),
      'json': jsonEncode(_requestJson),
    };
    
    try {
      // 构建请求头
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Linux; U; Android 12; zh-cn; SM-G9750 Build/SP1A.210812.016) AppleWebKit/533.1 (KHTML, like Gecko) Version/5.0 Mobile Safari/533.1',
        'Connection': 'Keep-Alive',
        'Accept-Encoding': 'gzip',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept-Language': 'zh-CN,zh;q=0.8',
        'Cache-Control': 'no-cache',
      };
      
      // 使用工具方法创建请求选项
      final options = ParserHelper.createRequestOptions(headers: headers);
      
      // 传递 cancelToken 参数
      final response = await HttpUtil().postRequest<Map<String, dynamic>>(
        _baseUrl,
        data: postData,
        options: options,
        cancelToken: cancelToken,
      );
      
      if (response == null) {
        LogUtil.i('[$_parserName] POST 请求返回空响应');
        return [];
      }
      
      LogUtil.i('[$_parserName] API 响应内容: $response'); // 添加调试日志
      
      if (response['succeed'] != 1 || response['error_code'] != 0) {
        LogUtil.i('[$_parserName] API 返回错误: ${response['error_desc']}');
        return [];
      }
      
      final cardgroups = response['cardgroups'] as List<dynamic>?;
      if (cardgroups == null || cardgroups.isEmpty) {
        LogUtil.i('[$_parserName] cardgroups 为空');
        return [];
      }
      
      // 优化：使用 expand 替代循环
      final cards = cardgroups
          .where((group) => group['cards'] != null)
          .expand((group) => group['cards'] as List<dynamic>)
          .toList();
      
      LogUtil.i('[$_parserName] 成功获取频道列表，数量: ${cards.length}');
      return cards;
    } catch (e) {
      LogUtil.i('[$_parserName] 获取频道列表失败: $e');
      return [];
    }
  }
}
