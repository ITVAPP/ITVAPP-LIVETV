import 'package:flutter/services.dart' show rootBundle;
import 'package:itvapp_live_tv/util/log_util.dart';

// 中文简繁体转换工具类
class ZhConverter {
  final String conversionType; // 简繁体转换类型
  OptimizedCharMap conversionMap = OptimizedCharMap(); // 字符转换映射
  Map<String, String> phrasesMap = {}; // 词组转换映射
  bool _isInitialized = false; // 初始化状态
  
  // 词组前缀树
  late _PhraseTrie _phraseTrie;
  
  // 转换结果缓存
  final Map<String, _CacheEntry> _conversionCache = {};
  final int _maxCacheSize = 588; // 缓存最大容量
  
  // 初始化锁
  bool _isInitializing = false;
  
  // 单例实例
  static final Map<String, ZhConverter> _instances = {};
  
  // 获取指定转换类型的单例实例
  static ZhConverter getInstance(String conversionType) {
    if (!_instances.containsKey(conversionType)) {
      _instances[conversionType] = ZhConverter._internal(conversionType);
    }
    return _instances[conversionType]!;
  }
  
  // 私有构造，初始化转换类型和前缀树
  ZhConverter._internal(this.conversionType) {
    _phraseTrie = _PhraseTrie();
  }
  
  // 公开构造，保持兼容
  ZhConverter(this.conversionType) {
    _phraseTrie = _PhraseTrie();
  }

  // 加载字符和词组映射，初始化转换表
  Future<void> initialize() async {
    if (_isInitialized) return; // 已初始化则返回
    if (_isInitializing) { // 防止并发初始化
      while (_isInitializing) {
        await Future.delayed(Duration(milliseconds: 50));
      }
      return;
    }
    
    _isInitializing = true;
    
    try {
      final results = await Future.wait([
        _loadCharacterMappings(), // 加载单字符映射
        _loadPhrasesMappings().catchError((e) { // 加载词组映射
          LogUtil.i('[ZhConverter] 词组映射加载失败: $e');
          return <String, String>{};
        })
      ]);
      
      final Map<int, String> charMap = results[0] as Map<int, String>;
      conversionMap.clear();
      for (final entry in charMap.entries) {
        conversionMap.set(entry.key, entry.value);
      }
      
      phrasesMap = results[1] as Map<String, String>;
      
      _buildPhraseTrie(); // 构建词组前缀树
      _isInitialized = true;
      LogUtil.i('[ZhConverter] 初始化完成: $conversionType, 字符数: ${conversionMap.length}, 词组数: ${phrasesMap.length}');
    } catch (e, stackTrace) {
      LogUtil.logError('[ZhConverter] 初始化失败: $e', e, stackTrace);
      _resetState(); // 重置状态
    } finally {
      _isInitializing = false; // 释放初始化锁
    }
  }
  
  // 重置内部状态
  void _resetState() {
    conversionMap.clear();
    phrasesMap = {};
    _conversionCache.clear();
    _phraseTrie = _PhraseTrie();
    _isInitialized = false;
  }
  
  // 构建词组前缀树
  void _buildPhraseTrie() {
    _phraseTrie = _PhraseTrie();
    for (final entry in phrasesMap.entries) {
      _phraseTrie.addPhrase(entry.key, entry.value);
    }
  }
  
  // 加载单字符简繁体映射
  Future<Map<int, String>> _loadCharacterMappings() async {
    final String content = await rootBundle.loadString('assets/js/Characters.js');
    final List<String> lines = content.split('\n');
    final Map<int, String> newMap = {};
    
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      final separatorIndex = line.indexOf('|');
      if (separatorIndex <= 0 || separatorIndex == line.length - 1) continue;
      
      final traditional = line.substring(0, separatorIndex);
      final simplified = line.substring(separatorIndex + 1);
      if (traditional.isEmpty || simplified.isEmpty || traditional.length != 1 || simplified.length != 1) {
        continue;
      }
      
      if (conversionType == 's2t') {
        final key = simplified.codeUnitAt(0);
        newMap.putIfAbsent(key, () => traditional);
      } else if (conversionType == 't2s') {
        final key = traditional.codeUnitAt(0);
        newMap.putIfAbsent(key, () => simplified);
      }
    }
    
    return newMap;
  }
  
  // 加载词组简繁体映射
  Future<Map<String, String>> _loadPhrasesMappings() async {
    const String fileName = 'STPhrases.js';
    final String content = await rootBundle.loadString('assets/js/$fileName');
    final List<String> lines = content.split('\n');
    final Map<String, String> newPhrasesMap = {};
    
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      final separatorIndex = line.indexOf('|');
      if (separatorIndex <= 0 || separatorIndex == line.length - 1) continue;
      
      final simplified = line.substring(0, separatorIndex);
      final traditional = line.substring(separatorIndex + 1);
      if (simplified.isEmpty || traditional.isEmpty) continue;
      
      if (conversionType == 's2t') {
        newPhrasesMap[simplified] = traditional;
      } else if (conversionType == 't2s') {
        newPhrasesMap[traditional] = simplified;
      }
    }
    
    return newPhrasesMap;
  }

  // 执行文本简繁体转换（异步）
  Future<String> convert(String text) async {
    if (text.isEmpty) return text;
    
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized || conversionMap.isEmpty) {
        LogUtil.i('[ZhConverter] 未初始化或映射为空，返回原文本');
        return text;
      }
    }
    
    return _processTextConversion(text); // 处理文本转换
  }

  // 执行文本简繁体转换（同步）
  String convertSync(String text) {
    if (text.isEmpty) return text;
    
    if (!_isInitialized || conversionMap.isEmpty) {
      LogUtil.i('[ZhConverter] 同步转换未初始化或映射为空，返回原文本');
      return text;
    }
    
    return _processTextConversion(text); // 处理文本转换
  }
  
  // 处理文本转换，优先查缓存
  String _processTextConversion(String text) {
    final String? cachedResult = _getCachedConversion(text);
    if (cachedResult != null) return cachedResult;
    
    final result = _performCombinedConversion(text);
    _cacheConversionResult(text, result); // 缓存转换结果
    
    return result;
  }
  
  // 获取缓存的转换结果
  String? _getCachedConversion(String text) {
    if (text.length <= 100 && _conversionCache.containsKey(text)) {
      final entry = _conversionCache[text]!;
      entry.accessCount++;
      return entry.result;
    }
    return null;
  }
  
  // 缓存转换结果，控制内存占用
  void _cacheConversionResult(String text, String result) {
    if (text.length <= 100) {
      if (_conversionCache.length >= _maxCacheSize) {
        // 清理低频缓存，控制内存占用
        final entries = _conversionCache.entries.toList()
          ..sort((a, b) => a.value.accessCount.compareTo(b.value.accessCount));
        
        final removeCount = _maxCacheSize ~/ 3;
        for (int i = 0; i < removeCount && i < entries.length; i++) {
          _conversionCache.remove(entries[i].key);
        }
      }
      _conversionCache[text] = _CacheEntry(result, 1);
    }
  }
  
  // 合并词组和单字转换
  String _performCombinedConversion(String text) {
    try {
      if (text.isEmpty || (conversionMap.isEmpty && phrasesMap.isEmpty)) return text;
      final StringBuffer resultBuffer = StringBuffer();
      int position = 0;
      
      while (position < text.length) {
        bool phraseMatched = false;
        if (phrasesMap.isNotEmpty) {
          final matchResult = _phraseTrie.findLongestMatch(text, position);
          if (matchResult.isMatch) {
            resultBuffer.write(matchResult.replacement);
            position = matchResult.endPos;
            phraseMatched = true;
          }
        }
        
        if (!phraseMatched) {
          final int codeUnit = text.codeUnitAt(position);
          final String? convertedChar = conversionMap.get(codeUnit);
          resultBuffer.write(convertedChar ?? text[position]);
          position++;
        }
      }
      
      return resultBuffer.toString();
    } catch (e, stackTrace) {
      LogUtil.logError('[ZhConverter] 转换异常: $e', e, stackTrace);
      return text;
    }
  }
}

// 优化字符映射，降低内存占用
class OptimizedCharMap {
  static const int _cjkStart = 0x4E00;
  static const int _cjkEnd = 0x9FFF;
  static const int _cjkExtAStart = 0x3400;
  static const int _cjkExtAEnd = 0x4DBF;
  
  final List<String?> _cjkMap = List.filled(_cjkEnd - _cjkStart + 1, null);
  final List<String?> _cjkExtAMap = List.filled(_cjkExtAEnd - _cjkExtAStart + 1, null);
  final Map<int, String> _otherMap = {};
  
  // 设置字符映射
  void set(int codeUnit, String value) {
    if (codeUnit >= _cjkStart && codeUnit <= _cjkEnd) {
      _cjkMap[codeUnit - _cjkStart] = value;
    } else if (codeUnit >= _cjkExtAStart && codeUnit <= _cjkExtAEnd) {
      _cjkExtAMap[codeUnit - _cjkExtAStart] = value;
    } else {
      _otherMap[codeUnit] = value;
    }
  }
  
  // 获取字符映射
  String? get(int codeUnit) {
    if (codeUnit >= _cjkStart && codeUnit <= _cjkEnd) {
      return _cjkMap[codeUnit - _cjkStart];
    } else if (codeUnit >= _cjkExtAStart && codeUnit <= _cjkExtAEnd) {
      return _cjkExtAMap[codeUnit - _cjkExtAStart];
    } else {
      return _otherMap[codeUnit];
    }
  }
  
  // 清空映射
  void clear() {
    for (int i = 0; i < _cjkMap.length; i++) {
      _cjkMap[i] = null;
    }
    for (int i = 0; i < _cjkExtAMap.length; i++) {
      _cjkExtAMap[i] = null;
    }
    _otherMap.clear();
  }
  
  // 检查是否为空
  bool get isEmpty {
    return _cjkMap.every((element) => element == null) && 
           _cjkExtAMap.every((element) => element == null) && 
           _otherMap.isEmpty;
  }
  
  // 获取映射数量
  int get length {
    int count = 0;
    for (String? char in _cjkMap) {
      if (char != null) count++;
    }
    for (String? char in _cjkExtAMap) {
      if (char != null) count++;
    }
    return count + _otherMap.length;
  }
}

// 缓存条目，记录转换结果和访问次数
class _CacheEntry {
  final String result;
  int accessCount;
  
  _CacheEntry(this.result, this.accessCount);
}

// 前缀树，加速词组匹配
class _PhraseTrie {
  final _TrieNode root = _TrieNode();
  
  // 添加词组到前缀树
  void addPhrase(String phrase, String replacement) {
    _TrieNode node = root;
    for (int i = 0; i < phrase.length; i++) {
      final String char = phrase[i];
      node.children.putIfAbsent(char, () => _TrieNode());
      node = node.children[char]!;
    }
    node.isEndOfPhrase = true;
    node.phrase = phrase;
    node.replacement = replacement;
  }
  
  // 查找最长匹配词组
  _MatchResult findLongestMatch(String text, int startPos) {
    _TrieNode node = root;
    _TrieNode? lastMatchNode;
    int matchEndPos = startPos;
    
    for (int i = startPos; i < text.length; i++) {
      final String char = text[i];
      if (!node.children.containsKey(char)) break;
      node = node.children[char]!;
      if (node.isEndOfPhrase) {
        lastMatchNode = node;
        matchEndPos = i + 1;
      }
    }
    
    if (lastMatchNode != null) {
      return _MatchResult(lastMatchNode.phrase!, lastMatchNode.replacement!, startPos, matchEndPos);
    }
    return _MatchResult.noMatch();
  }
}

// 前缀树节点，存储词组和转换信息
class _TrieNode {
  Map<String, _TrieNode> children = {};
  bool isEndOfPhrase = false;
  String? phrase;
  String? replacement;
}

// 词组匹配结果，封装匹配信息
class _MatchResult {
  final String phrase;
  final String replacement;
  final int startPos;
  final int endPos;
  final bool isMatch;
  
  _MatchResult(this.phrase, this.replacement, this.startPos, this.endPos) : isMatch = true;
  
  _MatchResult.noMatch() : phrase = '', replacement = '', startPos = -1, endPos = -1, isMatch = false;
}
