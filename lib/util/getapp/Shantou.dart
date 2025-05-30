import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';

/// 汕头电视台解析器
class ShantouParser {
  // 频道列表映射表，键为 clickIndex，值为 [频道ID, 频道名称]
  static const Map<int, List<String>> _channelList = {
    0: ['lKGXIQa', '汕头综合'],
    1: ['7xjJK9d', '汕头经济'], 
    2: ['G7Kql7a', '汕头文旅'],
    3: ['L3y6rt8', 'FM102.0'],
    4: ['s7k681h', 'FM102.5'],
    5: ['Li7mg21', 'FM107.2'],
  };

  static const String _baseUrl = 'https://sttv-hls.strtv.cn';
  static const String _signKey = 'bf9b2cab35a9c38857b82aabf99874aa96b9ffbb';

  /// 解析汕头电视台直播流地址
  static Future<String> parse(String url, {CancelToken? cancelToken}) async {
    try {
      final uri = Uri.parse(url);
      final clickIndex = int.tryParse(uri.queryParameters['clickIndex'] ?? '0') ?? 0;

      // 获取频道信息
      final channelInfo = _channelList[clickIndex];
      if (channelInfo == null) {
        LogUtil.i('无效的 clickIndex: $clickIndex，支持范围: 0-${_channelList.length - 1}，使用默认频道');
        final defaultChannelInfo = _channelList[0]!;
        final channelId = defaultChannelInfo[0];
        final channelName = defaultChannelInfo[1];
        LogUtil.i('使用默认频道: $channelName (ID: $channelId)');
        
        // 构建默认频道的M3U8地址
        final m3u8Url = _buildM3u8Url(channelId, cancelToken: cancelToken);
        return m3u8Url.isEmpty ? 'ERROR' : m3u8Url.trim();
      }
      
      final channelId = channelInfo[0];
      final channelName = channelInfo[1];
      
      LogUtil.i('选择的频道: $channelName (ID: $channelId, clickIndex: $clickIndex)');

      // 构建 m3u8 播放地址
      final m3u8Url = _buildM3u8Url(channelId, cancelToken: cancelToken);
      if (m3u8Url.isEmpty) {
        LogUtil.i('构建 m3u8 地址失败');
        return 'ERROR';
      }

      final trimmedM3u8Url = m3u8Url.trim();
      LogUtil.i('构建的 m3u8Url: "$trimmedM3u8Url"');

      // 验证地址格式
      if (trimmedM3u8Url.isEmpty || !trimmedM3u8Url.contains('.m3u8')) {
        LogUtil.i('地址格式无效: $trimmedM3u8Url');
        return 'ERROR';
      }

      LogUtil.i('成功获取 m3u8 播放地址: $trimmedM3u8Url');
      return trimmedM3u8Url;
    } catch (e) {
      LogUtil.i('解析汕头电视台直播流失败: $e');
      return 'ERROR';
    }
  }

  /// 构建 m3u8 播放地址，严格按照PHP逻辑实现
  static String _buildM3u8Url(String channelId, {CancelToken? cancelToken}) {
    try {
      // 计算时间戳（当前时间+2小时，转16进制）
      final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final dectime = (currentTime + 7200).toRadixString(16);
      
      // 确定码率：电视频道用500，广播频道用64（与PHP逻辑一致）
      final tvChannels = ['lKGXIQa', '7xjJK9d', 'G7Kql7a'];
      final rate = tvChannels.contains(channelId) ? '500' : '64';
      
      // 生成路径名（严格按照PHP pathname函数实现）
      final pathName = _pathname(channelId);
      final path = '/$channelId/$rate/$pathName.m3u8';
      
      // 生成MD5签名（与PHP逻辑一致）
      final signString = '$_signKey$path$dectime';
      final sign = md5.convert(utf8.encode(signString)).toString();
      
      // 构建完整URL
      final m3u8Url = '$_baseUrl$path?sign=$sign&t=$dectime';
      
      LogUtil.i('URL构建详情:');
      LogUtil.i('  channelId: $channelId');
      LogUtil.i('  rate: $rate');
      LogUtil.i('  pathName: $pathName');
      LogUtil.i('  path: $path');
      LogUtil.i('  timestamp: $dectime');
      LogUtil.i('  sign: $sign');
      LogUtil.i('  finalUrl: $m3u8Url');
      
      return m3u8Url;
    } catch (e) {
      LogUtil.i('构建 m3u8 地址失败: $e');
      return '';
    }
  }

  /// 精确移植PHP pathname函数的逻辑
  static String _pathname(String e) {
    try {
      // PHP: strtotime('today') * 1000 - 获取今天0点的毫秒时间戳
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final o = todayStart.millisecondsSinceEpoch;
      
      int a = 0;
      int r = 0;
      int d = -1;
      int p = 0;
      int l = 0;

      // 第一个循环：计算字符ASCII码和相邻字符差值
      for (a = 0; a < e.length; a++) {
        p = e.codeUnitAt(a); // PHP ord()等价
        r = r + p;
        if (d != -1) {
          l = l + (d - p);
        }
        d = p;
      }

      r = r + l;
      final s = r.toRadixString(36); // PHP base_convert($r, 10, 36)
      final c_original = o.toRadixString(36); // PHP base_convert($o, 10, 36)
      
      int u = 0;
      for (a = 0; a < c_original.length; a++) {
        u = u + c_original.codeUnitAt(a); // PHP ord()
      }

      // PHP: substr($c, 5) . substr($c, 0, 5)
      String c;
      if (c_original.length > 5) {
        c = c_original.substring(5) + c_original.substring(0, 5);
      } else {
        c = c_original;
      }
      
      final f = (u - r).abs(); // PHP abs()
      c = _reverseString(s) + c; // PHP strrev($s) . $c
      
      final g = c.length >= 4 ? c.substring(0, 4) : c; // PHP substr($c, 0, 4)
      final w = c.length > 4 ? c.substring(4) : ''; // PHP substr($c, 4)
      
      // PHP: date('w') % 2 - 获取星期几模2
      // PHP的date('w'): 0=Sunday, 1=Monday, ..., 6=Saturday
      // Dart的weekday: 1=Monday, 2=Tuesday, ..., 7=Sunday
      final dartWeekday = DateTime.now().weekday;
      final phpWeekday = dartWeekday == 7 ? 0 : dartWeekday; // 转换为PHP格式
      final b = phpWeekday % 2;

      final m = <String>[];
      for (a = 0; a < e.length; a++) {
        if (a % 2 == b) {
          final index = a % c.length;
          m.add(c[index]);
        } else {
          final hIndex = a - 1;
          if (hIndex >= 0) {
            final h = e[hIndex];
            final v = g.indexOf(h); // PHP strpos()
            if (v == -1) { // PHP strpos返回false时
              m.add(h);
            } else {
              if (v < w.length) {
                m.add(w[v]);
              } else {
                m.add(h); // 安全fallback
              }
            }
          } else {
            final gIndex = a % g.length;
            m.add(g[gIndex]);
          }
        }
      }
      
      final reversedF = _reverseString(f.toRadixString(36)); // PHP strrev(base_convert($f, 10, 36))
      final joined = m.join(''); // PHP implode('', $m)
      final result = reversedF + joined;
      
      // PHP: substr($result, 0, strlen($e))
      final finalResult = result.length > e.length ? result.substring(0, e.length) : result;
      
      LogUtil.i('pathname生成详情:');
      LogUtil.i('  输入: $e');
      LogUtil.i('  今天0点时间戳: $o');
      LogUtil.i('  字符总和r: $r');
      LogUtil.i('  时间戳字符总和u: $u');
      LogUtil.i('  差值f: $f');
      LogUtil.i('  星期几b: $b');
      LogUtil.i('  最终结果: $finalResult');
      
      return finalResult;
    } catch (e) {
      LogUtil.i('pathname生成失败: $e');
      // 发生错误时返回原始channelId作为fallback
      return e.toString();
    }
  }

  /// 字符串反转工具函数（对应PHP strrev）
  static String _reverseString(String input) {
    return input.split('').reversed.join('');
  }
}
