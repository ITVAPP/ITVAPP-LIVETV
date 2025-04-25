import 'dart:collection';
import 'package:flutter/services.dart' show rootBundle;
import 'package:itvapp_live_tv/util/log_util.dart';

/// 中文转换工具类
class ZhConverter {
  final String conversionType; // 转换类型：'s2t' 简体到繁体, 't2s' 繁体到简体
  Map<String, String> conversionMap = {}; // 存储字符转换映射
  bool _isInitialized = false; // 标记是否完成初始化
  
  // Trie树结构，用于高效字符串前缀匹配
  _ConverterTrie? _trie;
  
  ZhConverter(this.conversionType); // 构造函数，指定转换类型

  /// 初始化转换表，加载并解析字符映射
  Future<void> initialize() async {
    // 已初始化则直接返回
    if (_isInitialized) return;
    
    try {
      // 加载 assets 中的 Characters.js 文件
      final String content = await rootBundle.loadString('assets/js/Characters.js');
      final List<String> lines = content.split('\n'); // 按行分割文件内容
      
      // 预分配映射表和Trie树以优化性能
      final Map<String, String> newMap = {};
      final _ConverterTrie newTrie = _ConverterTrie();
      
      for (var line in lines) {
        line = line.trim(); // 去除首尾空白
        if (line.isEmpty) continue; // 跳过空行
        
        // 查找分隔符位置，避免创建数组
        final separatorIndex = line.indexOf('|');
        if (separatorIndex <= 0 || separatorIndex == line.length - 1) continue; // 跳过无效行
        
        final traditional = line.substring(0, separatorIndex); // 提取繁体字符
        final simplified = line.substring(separatorIndex + 1); // 提取简体字符
        
        // 验证映射有效性
        if (traditional.isEmpty || simplified.isEmpty) continue;
        
        // 根据转换类型添加映射
        if (conversionType == 's2t') {
          newMap[simplified] = traditional; // 简体到繁体映射
          newTrie.insert(simplified, traditional); // 插入Trie树
        } else if (conversionType == 't2s') {
          newMap[traditional] = simplified; // 繁体到简体映射
          newTrie.insert(traditional, simplified); // 插入Trie树
        }
      }
      
      // 成功后更新属性
      conversionMap = newMap;
      _trie = newTrie;
      _isInitialized = true;
      LogUtil.i('中文转换器初始化完成: $conversionType, 映射数量: ${conversionMap.length}');
    } catch (e, stackTrace) {
      LogUtil.logError('中文转换器初始化失败: $e', e, stackTrace); // 记录错误
      conversionMap = {}; // 初始化失败时置空映射表
      _trie = null; // 清空Trie树
    }
  }

  /// 异步转换文本
  Future<String> convert(String text) async {
    if (text.isEmpty) return text; // 空文本直接返回
    
    if (!_isInitialized) await initialize(); // 未初始化则执行初始化
    
    if (conversionMap.isEmpty || _trie == null) {
      LogUtil.i('转换映射表为空，返回原文本');
      return text; // 映射表为空返回原文本
    }
    
    return _performConversion(text); // 执行转换
  }

  /// 同步转换文本，兼容原有接口
  String convertSync(String text) {
    if (text.isEmpty) return text; // 空文本直接返回
    
    if (!_isInitialized || conversionMap.isEmpty || _trie == null) {
      LogUtil.i('同步转换：转换器未初始化或映射表为空，返回原文本');
      return text; // 未初始化或映射表为空返回原文本
    }
    
    return _performConversion(text); // 执行转换
  }
  
  /// 执行文本转换，使用Trie树最大匹配算法
  String _performConversion(String text) {
    if (_trie == null) return text; // Trie树未初始化返回原文本
    
    // 使用StringBuffer优化字符串拼接
    StringBuffer resultBuffer = StringBuffer();
    
    // 预转换文本为代码单元列表以提高效率
    final List<int> codeUnits = text.codeUnits;
    
    // 逐字符遍历文本
    int i = 0;
    while (i < codeUnits.length) {
      // 使用Trie树查找最长匹配
      final match = _trie!.findLongestMatch(text, codeUnits, i);
      
      if (match != null) {
        resultBuffer.write(match.value); // 添加转换后的字符串
        i += match.keyLength; // 跳过已匹配字符
      } else {
        resultBuffer.writeCharCode(codeUnits[i]); // 保留原字符
        i++; // 移动到下一字符
      }
    }
    
    return resultBuffer.toString(); // 返回转换结果
  }
}

/// Trie树实现，用于高效字符串匹配
class _ConverterTrie {
  final _TrieNode _root = _TrieNode(); // Trie树根节点
  
  /// 插入键值对到Trie树
  void insert(String key, String value) {
    if (key.isEmpty) return; // 空键直接返回
    
    // 转换键为代码单元以提高效率
    final List<int> codeUnits = key.codeUnits;
    
    _TrieNode node = _root;
    for (int i = 0; i < codeUnits.length; i++) {
      final codeUnit = codeUnits[i];
      node.children.putIfAbsent(codeUnit, () => _TrieNode()); // 创建子节点
      node = node.children[codeUnit]!; // 移动到子节点
    }
    
    node.isEndOfWord = true; // 标记单词结束
    node.value = value; // 存储转换值
  }
  
  /// 查找文本中最长匹配项
  _TrieMatch? findLongestMatch(String text, List<int> codeUnits, int startPos) {
    _TrieNode? node = _root;
    _TrieMatch? longestMatch; // 记录最长匹配
    int matchLength = 0;
    
    for (int i = startPos; i < codeUnits.length && node != null; i++) {
      final codeUnit = codeUnits[i];
      node = node.children[codeUnit]; // 查找子节点
      
      if (node == null) break; // 无匹配节点，退出
      
      matchLength++; // 增加匹配长度
      
      if (node.isEndOfWord) {
        longestMatch = _TrieMatch(node.value!, matchLength); // 记录当前匹配
      }
    }
    
    return longestMatch; // 返回最长匹配结果
  }
}

/// Trie树节点，存储子节点和转换值
class _TrieNode {
  Map<int, _TrieNode> children = {}; // 子节点映射，键为代码单元
  bool isEndOfWord = false; // 标记是否为单词结束
  String? value; // 存储转换后的值
}

/// 表示Trie树匹配结果
class _TrieMatch {
  final String value; // 匹配到的转换值
  final int keyLength; // 匹配的键长度
  
  _TrieMatch(this.value, this.keyLength); // 构造函数
}
