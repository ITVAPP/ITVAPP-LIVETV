import 'package:flutter/services.dart' show rootBundle;
import 'package:itvapp_live_tv/util/log_util.dart';

/// 中文转换工具类，支持单字符和词组的简繁体转换
class ZhConverter {
  final String conversionType; // 转换类型：'s2t' 简体到繁体，'t2s' 繁体到简体
  OptimizedCharMap conversionMap = OptimizedCharMap(); // 优化的字符转换映射
  Map<String, String> phrasesMap = {}; // 词组转换映射
  bool _isInitialized = false; // 标记初始化状态
  
  /// 词组匹配前缀树，优化匹配效率
  late _PhraseTrie _phraseTrie;
  
  /// 转换结果缓存，优化重复转换性能
  final Map<String, String> _conversionCache = {};
  final int _maxCacheSize = 588; // 缓存最大容量，防止内存溢出
  
  /// 初始化锁，防止并发初始化
  bool _isInitializing = false;
  
  /// 单例实例，优化多次创建
  static final Map<String, ZhConverter> _instances = {};
  
  /// 获取转换器实例，实现单例模式
  /// @param conversionType 转换类型：'s2t' 简体到繁体，'t2s' 繁体到简体
  static ZhConverter getInstance(String conversionType) {
    if (!_instances.containsKey(conversionType)) {
      _instances[conversionType] = ZhConverter._internal(conversionType);
    }
    return _instances[conversionType]!;
  }
  
  /// 私有构造函数，初始化转换类型和前缀树
  ZhConverter._internal(this.conversionType) {
    _phraseTrie = _PhraseTrie();
  }
  
  /// 公开构造函数，保持向后兼容
  ZhConverter(this.conversionType) {
    _phraseTrie = _PhraseTrie();
  }

  /// 初始化转换表，加载字符和词组映射
  Future<void> initialize() async {
    // 已初始化则直接返回
    if (_isInitialized) return;
    // 避免并发初始化
    if (_isInitializing) {
      // 等待初始化完成
      while (_isInitializing) {
        await Future.delayed(Duration(milliseconds: 50));
      }
      return;
    }
    
    _isInitializing = true;
    
    try {
      // 并发加载字符和词组映射
      final results = await Future.wait([
        _loadCharacterMappings(), // 加载字符映射
        _loadPhrasesMappings().catchError((e) { // 加载词组映射，失败时返回空映射
          LogUtil.i('词组映射加载失败，使用基本转换: $e');
          return <String, String>{};
        })
      ]);
      
      // 将结果转换为优化的字符映射结构
      final Map<int, String> charMap = results[0] as Map<int, String>;
      conversionMap.clear();
      for (final entry in charMap.entries) {
        conversionMap.set(entry.key, entry.value);
      }
      
      phrasesMap = results[1] as Map<String, String>; // 设置词组映射
      
      _buildPhraseTrie(); // 构建词组前缀树
      _isInitialized = true; // 标记初始化完成
      LogUtil.i('转换器初始化完成: $conversionType, 字符映射: ${conversionMap.length}, 词组: ${phrasesMap.length}');
    } catch (e, stackTrace) {
      LogUtil.logError('转换器初始化失败: $e', e, stackTrace); // 记录初始化错误
      _resetState(); // 重置状态
    } finally {
      _isInitializing = false; // 释放初始化锁
    }
  }
  
  /// 重置内部状态，保持一致性
  void _resetState() {
    conversionMap.clear();
    phrasesMap = {};
    _conversionCache.clear(); // 清除缓存
    _phraseTrie = _PhraseTrie(); // 重置前缀树
    _isInitialized = false;
  }
  
  /// 构建词组前缀树，加速词组匹配
  void _buildPhraseTrie() {
    _phraseTrie = _PhraseTrie();
    for (final entry in phrasesMap.entries) {
      _phraseTrie.addPhrase(entry.key, entry.value); // 添加词组到前缀树
    }
  }
  
  /// 加载字符映射，解析单字符转换规则
  Future<Map<int, String>> _loadCharacterMappings() async {
    final String content = await rootBundle.loadString('assets/js/Characters.js'); // 读取字符映射文件
    final List<String> lines = content.split('\n'); // 按行分割
    final Map<int, String> newMap = {}; // 新建字符映射表
    
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue; // 跳过空行
      final separatorIndex = line.indexOf('|'); // 查找分隔符
      if (separatorIndex <= 0 || separatorIndex == line.length - 1) continue; // 跳过无效行
      
      final traditional = line.substring(0, separatorIndex); // 提取繁体字符
      final simplified = line.substring(separatorIndex + 1); // 提取简体字符
      if (traditional.isEmpty || simplified.isEmpty || traditional.length != 1 || simplified.length != 1) {
        continue;
      }
      
      // 根据转换类型添加映射
      if (conversionType == 's2t') {
        final key = simplified.codeUnitAt(0);
        newMap.putIfAbsent(key, () => traditional); // 简体到繁体
      } else if (conversionType == 't2s') {
        final key = traditional.codeUnitAt(0);
        newMap.putIfAbsent(key, () => simplified); // 繁体到简体
      }
    }
    
    return newMap;
  }
  
  /// 加载词组映射，解析词组转换规则
  Future<Map<String, String>> _loadPhrasesMappings() async {
    const String fileName = 'STPhrases.js';
    final String content = await rootBundle.loadString('assets/js/$fileName'); // 读取词组映射文件
    final List<String> lines = content.split('\n'); // 按行分割
    final Map<String, String> newPhrasesMap = {}; // 新建词组映射表
    
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue; // 跳过空行
      final separatorIndex = line.indexOf('|'); // 查找分隔符
      if (separatorIndex <= 0 || separatorIndex == line.length - 1) continue; // 跳过无效行
      
      final simplified = line.substring(0, separatorIndex); // 提取简体词组（STPhrases.js前面是简体）
      final traditional = line.substring(separatorIndex + 1); // 提取繁体词组（STPhrases.js后面是繁体）
      if (simplified.isEmpty || traditional.isEmpty) continue; // 跳过空映射
      
      // 根据转换类型决定如何添加到映射表中
      if (conversionType == 's2t') {
        newPhrasesMap[simplified] = traditional; // 简体->繁体
      } else if (conversionType == 't2s') {
        newPhrasesMap[traditional] = simplified; // 繁体->简体
      }
    }
    
    return newPhrasesMap;
  }

  /// 异步转换文本，执行简繁体转换
  Future<String> convert(String text) async {
    if (text.isEmpty) return text;
    
    // 确保初始化
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized || conversionMap.isEmpty) {
        LogUtil.i('转换器未初始化或映射为空，返回原文本');
        return text;
      }
    }
    
    // 执行实际转换
    return _processTextConversion(text);
  }

  /// 同步转换文本，兼容原有接口
  String convertSync(String text) {
    if (text.isEmpty) return text;
    
    if (!_isInitialized || conversionMap.isEmpty) {
      LogUtil.i('同步转换未初始化或映射为空，返回原文本');
      return text;
    }
    
    // 复用处理逻辑
    return _processTextConversion(text);
  }
  
  /// 处理文本转换，抽取共用逻辑
  String _processTextConversion(String text) {
    // 检查缓存
    final String? cachedResult = _getCachedConversion(text);
    if (cachedResult != null) return cachedResult;
    
    // 执行转换
    final result = _performCombinedConversion(text);
    
    // 缓存结果
    _cacheConversionResult(text, result);
    
    return result;
  }
  
  /// 获取缓存的转换结果，优化性能
  String? _getCachedConversion(String text) {
    if (text.length <= 100 && _conversionCache.containsKey(text)) {
      return _conversionCache[text]; // 返回缓存结果
    }
    return null;
  }
  
  /// 缓存转换结果，控制内存占用
  void _cacheConversionResult(String text, String result) {
    if (text.length <= 100) {
      if (_conversionCache.length >= _maxCacheSize) {
        final keysToRemove = (_conversionCache.keys.toList()..shuffle()).take(_maxCacheSize ~/ 3).toList();
        for (final key in keysToRemove) {
          _conversionCache.remove(key); // 清除部分缓存
        }
      }
      _conversionCache[text] = result; // 添加新缓存
    }
  }
  
  /// 合并词组和单字转换，优化遍历效率
  String _performCombinedConversion(String text) {
    try {
      if (text.isEmpty || (conversionMap.isEmpty && phrasesMap.isEmpty)) return text;
      final StringBuffer resultBuffer = StringBuffer(); // 使用StringBuffer优化拼接
      int position = 0; // 当前处理位置
      
      while (position < text.length) {
        bool phraseMatched = false;
        if (phrasesMap.isNotEmpty) {
          final matchResult = _phraseTrie.findLongestMatch(text, position); // 查找最长词组匹配
          if (matchResult.isMatch) {
            resultBuffer.write(matchResult.replacement); // 添加转换后词组
            position = matchResult.endPos; // 跳到词组末尾
            phraseMatched = true;
          }
        }
        
        if (!phraseMatched) {
          final int codeUnit = text.codeUnitAt(position); // 获取当前字符codeUnit
          final String? convertedChar = conversionMap.get(codeUnit); // 查找字符映射
          resultBuffer.write(convertedChar ?? text[position]); // 添加转换字符或原字符
          position++; // 前进到下一字符
        }
      }
      
      return resultBuffer.toString();
    } catch (e, stackTrace) {
      LogUtil.logError('转换过程异常: $e', e, stackTrace); // 记录转换错误
      return text;
    }
  }
}

/// 优化的字符映射，使用数组提高查找速度
class OptimizedCharMap {
  final List<String?> _fastMap = List.filled(65536, null);
  final Map<int, String> _overflowMap = {};
  
  /// 设置字符映射
  void set(int codeUnit, String value) {
    if (codeUnit < 65536) {
      _fastMap[codeUnit] = value;
    } else {
      _overflowMap[codeUnit] = value;
    }
  }
  
  /// 获取字符映射
  String? get(int codeUnit) {
    if (codeUnit < 65536) {
      return _fastMap[codeUnit];
    } else {
      return _overflowMap[codeUnit];
    }
  }
  
  /// 清空映射
  void clear() {
    for (int i = 0; i < _fastMap.length; i++) {
      _fastMap[i] = null;
    }
    _overflowMap.clear();
  }
  
  /// 检查是否为空
  bool get isEmpty {
    return _fastMap.every((element) => element == null) && _overflowMap.isEmpty;
  }
  
  /// 获取映射数量
  int get length {
    int count = 0;
    for (String? char in _fastMap) {
      if (char != null) count++;
    }
    return count + _overflowMap.length;
  }
}

/// 前缀树结构，优化词组匹配效率
class _PhraseTrie {
  final _TrieNode root = _TrieNode(); // 根节点
  
  /// 添加词组到前缀树
  void addPhrase(String phrase, String replacement) {
    _TrieNode node = root;
    for (int i = 0; i < phrase.length; i++) {
      final String char = phrase[i];
      node.children.putIfAbsent(char, () => _TrieNode()); // 添加子节点
      node = node.children[char]!;
    }
    node.isEndOfPhrase = true; // 标记词组结束
    node.phrase = phrase; // 存储词组
    node.replacement = replacement; // 存储转换结果
  }
  
  /// 查找最长匹配词组
  _MatchResult findLongestMatch(String text, int startPos) {
    _TrieNode node = root;
    _TrieNode? lastMatchNode;
    int matchEndPos = startPos;
    
    for (int i = startPos; i < text.length; i++) {
      final String char = text[i];
      if (!node.children.containsKey(char)) break; // 无匹配子节点
      node = node.children[char]!;
      if (node.isEndOfPhrase) {
        lastMatchNode = node; // 记录最近匹配节点
        matchEndPos = i + 1; // 更新匹配结束位置
      }
    }
    
    if (lastMatchNode != null) {
      return _MatchResult(lastMatchNode.phrase!, lastMatchNode.replacement!, startPos, matchEndPos); // 返回匹配结果
    }
    return _MatchResult.noMatch(); // 无匹配
  }
}

/// 前缀树节点，存储词组和转换信息
class _TrieNode {
  Map<String, _TrieNode> children = {}; // 子节点映射
  bool isEndOfPhrase = false; // 标记词组结束
  String? phrase; // 词组内容
  String? replacement; // 转换结果
}

/// 词组匹配结果，封装匹配信息
class _MatchResult {
  final String phrase; // 匹配的词组
  final String replacement; // 转换结果
  final int startPos; // 匹配起始位置
  final int endPos; // 匹配结束位置
  final bool isMatch; // 是否匹配成功
  
  /// 构造匹配结果
  _MatchResult(this.phrase, this.replacement, this.startPos, this.endPos) : isMatch = true;
  
  /// 构造无匹配结果
  _MatchResult.noMatch() : phrase = '', replacement = '', startPos = -1, endPos = -1, isMatch = false;
}
