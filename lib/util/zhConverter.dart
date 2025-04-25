import 'package:flutter/services.dart' show rootBundle;
import 'package:itvapp_live_tv/util/log_util.dart';

/// 中文转换工具类 - 针对单字符映射优化的版本
class ZhConverter {
  final String conversionType; // 转换类型：'s2t' 简体到繁体, 't2s' 繁体到简体
  Map<int, String> conversionMap = {}; // 存储字符转换映射，使用codeUnit作为键
  bool _isInitialized = false; // 标记是否完成初始化
  
  ZhConverter(this.conversionType); // 构造函数，指定转换类型

  /// 初始化转换表，加载并解析字符映射
  Future<void> initialize() async {
    // 已初始化则直接返回
    if (_isInitialized) return;
    
    try {
      // 加载 assets 中的 Characters.js 文件
      final String content = await rootBundle.loadString('assets/js/Characters.js');
      final List<String> lines = content.split('\n'); // 按行分割文件内容
      
      // 创建映射表
      final Map<int, String> newMap = {};
      
      for (var line in lines) {
        line = line.trim(); // 去除首尾空白
        if (line.isEmpty) continue; // 跳过空行
        
        // 查找分隔符位置
        final separatorIndex = line.indexOf('|');
        if (separatorIndex <= 0 || separatorIndex == line.length - 1) continue; // 跳过无效行
        
        final traditional = line.substring(0, separatorIndex); // 提取繁体字符
        final simplified = line.substring(separatorIndex + 1); // 提取简体字符
        
        // 验证映射有效性
        if (traditional.isEmpty || simplified.isEmpty) continue;
        
        // 在确信所有映射都是单字符的情况下，可以直接处理
        // 但仍保留验证以确保数据完整性
        if (traditional.length != 1 || simplified.length != 1) {
          LogUtil.i('跳过非单字符映射: $traditional|$simplified');
          continue;
        }
        
        // 根据转换类型添加映射 - 使用codeUnit作为键以加速查找
        // 仅在映射不存在时添加，确保前面的映射优先
        if (conversionType == 's2t') {
          final key = simplified.codeUnitAt(0);
          if (!newMap.containsKey(key)) {
            newMap[key] = traditional; // 简体到繁体映射
          }
        } else if (conversionType == 't2s') {
          final key = traditional.codeUnitAt(0);
          if (!newMap.containsKey(key)) {
            newMap[key] = simplified; // 繁体到简体映射
          }
        }
      }
      
      // 成功后更新属性
      conversionMap = newMap;
      _isInitialized = true;
      LogUtil.i('中文转换器初始化完成: $conversionType, 映射数量: ${conversionMap.length}');
    } catch (e, stackTrace) {
      LogUtil.logError('中文转换器初始化失败: $e', e, stackTrace); // 记录错误
      conversionMap = {}; // 初始化失败时置空映射表
      _isInitialized = false; // 确保初始化状态一致
    }
  }

  /// 异步转换文本
  Future<String> convert(String text) async {
    if (text.isEmpty) return text; // 空文本直接返回
    
    if (!_isInitialized) await initialize(); // 未初始化则执行初始化
    
    if (conversionMap.isEmpty) {
      LogUtil.i('转换映射表为空，返回原文本');
      return text; // 映射表为空返回原文本
    }
    
    return _performConversion(text); // 执行转换
  }

  /// 同步转换文本，兼容原有接口
  String convertSync(String text) {
    if (text.isEmpty) return text; // 空文本直接返回
    
    if (!_isInitialized || conversionMap.isEmpty) {
      LogUtil.i('同步转换：转换器未初始化或映射表为空，返回原文本');
      return text; // 未初始化或映射表为空返回原文本
    }
    
    return _performConversion(text); // 执行转换
  }
  
  /// 执行文本转换，使用O(1)查找的字符映射方法
  String _performConversion(String text) {
    // 使用StringBuffer优化字符串拼接
    StringBuffer resultBuffer = StringBuffer();
    
    // 获取代码单元以加速处理
    final List<int> codeUnits = text.codeUnits;
    
    // 逐字符遍历并转换
    for (int i = 0; i < codeUnits.length; i++) {
      final codeUnit = codeUnits[i];
      final convertedChar = conversionMap[codeUnit];
      
      if (convertedChar != null) {
        resultBuffer.write(convertedChar); // 添加转换后的字符
      } else {
        resultBuffer.writeCharCode(codeUnit); // 保留原字符
      }
    }
    
    return resultBuffer.toString(); // 返回转换结果
  }
}
