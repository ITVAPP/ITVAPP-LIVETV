import 'dart:async';
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
  
  // LRU缓存实现
  final _LRUCache<String, String> _conversionCache = _LRUCache(588);
  
  // 初始化控制
  Completer<void>? _initCompleter;
  
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
  
  // 工厂构造，返回单例
  factory ZhConverter(String conversionType) {
    return getInstance(conversionType);
  }

  // 加载字符和词组映射，初始化转换表
  Future<void> initialize() async {
    if (_isInitialized) return; // 已初始化则返回
    
    // 使用Completer避免重复初始化
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    
    _initCompleter = Completer<void>();
    
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
      
      _initCompleter!.complete();
    } catch (e, stackTrace) {
      LogUtil.logError('[ZhConverter] 初始化失败: $e', e, stackTrace);
      _resetState(); // 重置状态
      _initCompleter!.completeError(e);
    } finally {
      _initCompleter = null;
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
    // 预分配容量，避免扩容
    final Map<int, String> newMap = HashMap<int, String>(
      equals: (a, b) => a == b,
      hashCode: (e) => e.hashCode,
      isValidKey: (e) => e is int,
    );
    
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
    // 只缓存短文本
    if (text.length <= 100) {
      final String? cachedResult = _conversionCache.get(text);
      if (cachedResult != null) return cachedResult;
    }
    
    final result = _performCombinedConversion(text);
    
    if (text.length <= 100) {
      _conversionCache.put(text, result);
    }
    
    return result;
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

// 简单的LRU缓存实现
class _LRUCache<K, V> {
  final int maxSize;
  final Map<K, _LRUNode<K, V>> _map = {};
  _LRUNode<K, V>? _head;
  _LRUNode<K, V>? _tail;
  
  _LRUCache(this.maxSize);
  
  V? get(K key) {
    final node = _map[key];
    if (node == null) return null;
    
    // 移到头部
    _removeNode(node);
    _addToHead(node);
    
    return node.value;
  }
  
  void put(K key, V value) {
    final existingNode = _map[key];
    
    if (existingNode != null) {
      // 更新现有节点
      existingNode.value = value;
      _removeNode(existingNode);
      _addToHead(existingNode);
    } else {
      // 添加新节点
      final newNode = _LRUNode(key, value);
      _map[key] = newNode;
      _addToHead(newNode);
      
      // 检查容量
      if (_map.length > maxSize) {
        final tailNode = _tail;
        if (tailNode != null) {
          _removeNode(tailNode);
          _map.remove(tailNode.key);
        }
      }
    }
  }
  
  void clear() {
    _map.clear();
    _head = null;
    _tail = null;
  }
  
  void _addToHead(_LRUNode<K, V> node) {
    node.prev = null;
    node.next = _head;
    
    if (_head != null) {
      _head!.prev = node;
    }
    
    _head = node;
    
    if (_tail == null) {
      _tail = node;
    }
  }
  
  void _removeNode(_LRUNode<K, V> node) {
    final prev = node.prev;
    final next = node.next;
    
    if (prev != null) {
      prev.next = next;
    } else {
      _head = next;
    }
    
    if (next != null) {
      next.prev = prev;
    } else {
      _tail = prev;
    }
  }
}

class _LRUNode<K, V> {
  final K key;
  V value;
  _LRUNode<K, V>? prev;
  _LRUNode<K, V>? next;
  
  _LRUNode(this.key, this.value);
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
