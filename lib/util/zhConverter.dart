import 'package:flutter/services.dart' show rootBundle;
import 'package:itvapp_live_tv/util/log_util.dart';

/// 自定义中文转换工具类，替代原有的 opencc ZhConverter
class ZhConverter {
  final String conversionType; // 's2t' 简体到繁体, 't2s' 繁体到简体
  Map<String, String> conversionMap = {};
  bool _isInitialized = false;

  ZhConverter(this.conversionType);

  /// 初始化转换表
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // 从 assets 加载 Characters.js 文件
      final String content = await rootBundle.loadString('assets/js/Characters.js');
      final List<String> lines = content.split('\n');
      
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;
        
        // 每行格式为: 繁体|简体
        final parts = line.split('|');
        if (parts.length != 2) continue;
        
        final traditional = parts[0];
        final simplified = parts[1];
        
        // 根据转换方向添加到映射表
        if (conversionType == 's2t') {
          // 简体 -> 繁体
          conversionMap[simplified] = traditional;
        } else if (conversionType == 't2s') {
          // 繁体 -> 简体
          conversionMap[traditional] = simplified;
        }
      }
      
      _isInitialized = true;
      LogUtil.i('中文转换器初始化完成: ${conversionType}, 映射数量: ${conversionMap.length}');
    } catch (e, stackTrace) {
      LogUtil.logError('中文转换器初始化失败', e, stackTrace);
    }
  }

  /// 转换文本
  Future<String> convert(String text) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (conversionMap.isEmpty) {
      LogUtil.i('转换映射表为空，返回原文本');
      return text;
    }
    
    String result = text;
    // 对每个字符进行转换
    conversionMap.forEach((source, target) {
      result = result.replaceAll(source, target);
    });
    
    return result;
  }

  /// 兼容原有 ZhConverter 的同步转换方法
  String convertSync(String text) {
    if (!_isInitialized || conversionMap.isEmpty) {
      LogUtil.i('同步转换：转换器未初始化或映射表为空，返回原文本');
      return text;
    }
    
    String result = text;
    conversionMap.forEach((source, target) {
      result = result.replaceAll(source, target);
    });
    
    return result;
  }
}
