import 'package:flutter/services.dart' show rootBundle;
import 'package:itvapp_live_tv/util/log_util.dart';

/// 中文转换工具类 - 支持单字符映射、一简多繁汉字和词组转换
class ZhConverter {
  final String conversionType; // 转换类型：'s2t' 简体到繁体, 't2s' 繁体到简体
  Map<int, String> conversionMap = {}; // 存储字符转换映射，使用codeUnit作为键
  Set<int> multiChars = {}; // 存储需要特殊处理的"一简多繁汉字"的codeUnit
  Map<String, String> phrasesMap = {}; // 存储词组转换映射
  List<String> phraseKeys = []; // 存储排序后的词组键，用于优先匹配长词组
  bool _isInitialized = false; // 标记是否完成初始化
  
  // 优化: 添加词组匹配的前缀树结构
  late _PhraseTrie _phraseTrie;
  
  // 优化: 添加常用短句的转换缓存
  final Map<String, String> _conversionCache = {};
  final int _maxCacheSize = 1000; // 限制最大缓存数量，防止内存溢出
  
  ZhConverter(this.conversionType) {
    _phraseTrie = _PhraseTrie(); // 初始化前缀树
  } // 构造函数，指定转换类型

  /// 初始化转换表，加载并解析字符映射
  Future<void> initialize() async {
    // 已初始化则直接返回
    if (_isInitialized) return;
    
    try {
      // 优化: 使用Future.wait并发加载所有必要文件
      final results = await Future.wait([
        // 1. 加载并解析基本字符映射 - 这是核心功能，必须成功
        _loadCharacterMappings(),
        
        // 2. 尝试加载并解析"一简多繁汉字" - 即使失败也不影响基本功能
        _loadMultiCharacters().catchError((e) {
          LogUtil.i('加载一简多繁汉字文件失败，将使用基本转换: $e');
          // 失败时返回空集合
          return <int>{}; 
        }),
        
        // 3. 尝试加载并解析词组映射 - 即使失败也不影响基本功能
        _loadPhrasesMappings().catchError((e) {
          LogUtil.i('加载词组映射文件失败，将使用基本转换: $e');
          // 失败时返回空映射
          return <String, String>{}; 
        })
      ]);
      
      // 处理并发加载的结果
      conversionMap = results[0] as Map<int, String>;
      multiChars = results[1] as Set<int>;
      phrasesMap = results[2] as Map<String, String>;
      
      // 对词组键按长度降序排序，确保优先匹配长词组
      phraseKeys = phrasesMap.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      
      // 优化: 构建词组前缀树
      _buildPhraseTrie();
      
      _isInitialized = true;
      LogUtil.i('中文转换器初始化完成: $conversionType, ' 
          '映射数量: ${conversionMap.length}, '
          '特殊字符: ${multiChars.length}, '
          '词组映射: ${phrasesMap.length}');
    } catch (e, stackTrace) {
      LogUtil.logError('中文转换器初始化失败: $e', e, stackTrace); // 记录错误
      _resetState(); // 重置状态确保一致性
      // 不抛出异常，让调用者可以通过检查_isInitialized来判断初始化状态
    }
  }
  
  /// 重置内部状态 - 用于初始化失败时保持一致性
  void _resetState() {
    conversionMap = {}; 
    multiChars = {};
    phrasesMap = {};
    phraseKeys = [];
    _conversionCache.clear(); // 优化: 清除缓存
    _phraseTrie = _PhraseTrie(); // 优化: 重置前缀树
    _isInitialized = false;
  }
  
  /// 优化: 构建词组前缀树，用于加速词组匹配
  void _buildPhraseTrie() {
    _phraseTrie = _PhraseTrie();
    for (final entry in phrasesMap.entries) {
      _phraseTrie.addPhrase(entry.key, entry.value);
    }
  }
  
  /// 加载基本字符映射
  Future<Map<int, String>> _loadCharacterMappings() async {
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
    
    return newMap;
  }
  
  /// 加载一简多繁汉字列表
  Future<Set<int>> _loadMultiCharacters() async {
    final String content = await rootBundle.loadString('assets/js/STMulti.js');
    final List<String> lines = content.split('\n'); // 按行分割文件内容
    
    // 创建特殊字符集合
    final Set<int> newMultiChars = {};
    
    for (var line in lines) {
      line = line.trim(); // 去除首尾空白
      if (line.isEmpty) continue; // 跳过空行
      
      // 一简多繁汉字文件每行只包含一个字符
      if (line.length != 1) {
        LogUtil.i('跳过非单字符的一简多繁行: $line');
        continue;
      }
      
      // 添加到特殊字符集合
      newMultiChars.add(line.codeUnitAt(0));
    }
    
    return newMultiChars;
  }
  
  /// 加载词组映射
  Future<Map<String, String>> _loadPhrasesMappings() async {
    final String fileName = conversionType == 's2t' ? 'STPhrases.js' : 'TSPhrases.js';
    final String content = await rootBundle.loadString('assets/js/$fileName');
    final List<String> lines = content.split('\n'); // 按行分割文件内容
    
    // 创建词组映射表
    final Map<String, String> newPhrasesMap = {};
    
    for (var line in lines) {
      line = line.trim(); // 去除首尾空白
      if (line.isEmpty) continue; // 跳过空行
      
      // 查找分隔符位置
      final separatorIndex = line.indexOf('|');
      if (separatorIndex <= 0 || separatorIndex == line.length - 1) continue; // 跳过无效行
      
      final source = line.substring(0, separatorIndex); // 提取源词组
      final target = line.substring(separatorIndex + 1); // 提取目标词组
      
      // 验证映射有效性
      if (source.isEmpty || target.isEmpty) continue;
      
      // 添加到词组映射表
      newPhrasesMap[source] = target;
    }
    
    return newPhrasesMap;
  }

  /// 异步转换文本
  Future<String> convert(String text) async {
    if (text.isEmpty) return text; // 空文本直接返回
    
    // 优化: 检查缓存
    final String? cachedResult = _getCachedConversion(text);
    if (cachedResult != null) {
      return cachedResult;
    }
    
    // 确保转换器已初始化
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized || conversionMap.isEmpty) {
        LogUtil.i('转换器初始化失败或映射表为空，返回原文本');
        return text;
      }
    }
    
    final result = _performConversion(text); // 执行转换
    
    // 优化: 缓存结果(仅缓存合理长度的文本)
    _cacheConversionResult(text, result);
    
    return result;
  }

  /// 同步转换文本，兼容原有接口
  String convertSync(String text) {
    if (text.isEmpty) return text; // 空文本直接返回
    
    // 优化: 检查缓存
    final String? cachedResult = _getCachedConversion(text);
    if (cachedResult != null) {
      return cachedResult;
    }
    
    if (!_isInitialized || conversionMap.isEmpty) {
      LogUtil.i('同步转换：转换器未初始化或映射表为空，返回原文本');
      return text; // 未初始化或映射表为空返回原文本
    }
    
    final result = _performConversion(text); // 执行转换
    
    // 优化: 缓存结果(仅缓存合理长度的文本)
    _cacheConversionResult(text, result);
    
    return result;
  }
  
  /// 优化: 从缓存获取转换结果
  String? _getCachedConversion(String text) {
    // 仅对短文本使用缓存，避免缓存大量长文本
    if (text.length <= 100 && _conversionCache.containsKey(text)) {
      return _conversionCache[text];
    }
    return null;
  }
  
  /// 优化: 缓存转换结果
  void _cacheConversionResult(String text, String result) {
    // 仅缓存短文本，避免内存占用过大
    if (text.length <= 100) {
      // 如果缓存已满，清除30%的缓存
      if (_conversionCache.length >= _maxCacheSize) {
        final keysToRemove = (_conversionCache.keys.toList()..shuffle()).take(_maxCacheSize ~/ 3).toList();
        for (final key in keysToRemove) {
          _conversionCache.remove(key);
        }
      }
      _conversionCache[text] = result;
    }
  }
  
  /// 执行文本转换，先处理词组，再处理单字符
  String _performConversion(String text) {
    try {
      if (text.isEmpty) return text;
      
      // 首先处理词组转换 - 优化: 使用前缀树加速词组匹配
      if (phrasesMap.isNotEmpty) {
        text = _processPhrasesConversionOptimized(text);
      }
      
      // 如果文本为空或映射表为空，直接返回
      if (text.isEmpty || conversionMap.isEmpty) {
        return text;
      }
      
      // 使用StringBuffer优化字符串拼接
      final StringBuffer resultBuffer = StringBuffer();
      
      // 获取代码单元以加速处理
      final List<int> codeUnits = text.codeUnits;
      
      // 优化: 简化处理逻辑，移除冗余条件分支
      for (int codeUnit in codeUnits) {
        final String? convertedChar = conversionMap[codeUnit];
        if (convertedChar != null) {
          resultBuffer.write(convertedChar);
        } else {
          resultBuffer.writeCharCode(codeUnit);
        }
      }
      
      return resultBuffer.toString(); // 返回转换结果
    } catch (e, stackTrace) {
      // 防止任何异常导致转换失败，出现异常时返回原文本并记录详细错误
      LogUtil.logError('字符转换过程中出现异常: $e', e, stackTrace);
      return text;
    }
  }
  
  /// 优化: 使用前缀树加速词组转换
  String _processPhrasesConversionOptimized(String text) {
    if (text.isEmpty || phrasesMap.isEmpty) return text;
    
    try {
      final StringBuffer resultBuffer = StringBuffer();
      int i = 0;
      
      while (i < text.length) {
        // 使用前缀树查找最长匹配词组
        final matchResult = _phraseTrie.findLongestMatch(text, i);
        
        if (matchResult.isMatch) {
          // 找到匹配的词组，添加替换文本
          resultBuffer.write(matchResult.replacement);
          i = matchResult.endPos; // 跳过已匹配部分
        } else {
          // 没有匹配的词组，保留原字符
          resultBuffer.write(text[i]);
          i++;
        }
      }
      
      return resultBuffer.toString();
    } catch (e, stackTrace) {
      // 发生异常时返回原文本并记录错误
      LogUtil.logError('词组转换过程中出现异常: $e', e, stackTrace);
      return text;
    }
  }
  
  /// 原有词组转换方法 - 保留以备回退
  String _processPhrasesConversion(String text) {
    if (text.isEmpty || phraseKeys.isEmpty) return text;
    
    try {
      // 为提高效率，使用一个缓冲区保存结果
      final StringBuffer resultBuffer = StringBuffer();
      int i = 0;
      final int textLength = text.length;
      
      // 预先计算每个词组的长度，避免多次计算
      final Map<String, int> phraseLengths = 
          {for (var key in phraseKeys) key: key.length};
      
      // 遍历文本
      while (i < textLength) {
        bool matched = false;
        
        // 尝试匹配所有词组，长词组优先
        for (String phrase in phraseKeys) {
          final int phraseLength = phraseLengths[phrase]!;
          final int endIndex = i + phraseLength;
          
          // 优化：先检查长度再进行子字符串比较
          if (endIndex <= textLength) {
            // 使用更高效的子字符串比较
            bool isMatch = true;
            for (int j = 0; j < phraseLength; j++) {
              if (text[i + j] != phrase[j]) {
                isMatch = false;
                break;
              }
            }
            
            if (isMatch) {
              // 找到匹配的词组
              resultBuffer.write(phrasesMap[phrase]);
              i += phraseLength; // 跳过已匹配的部分
              matched = true;
              break;
            }
          }
        }
        
        // 如果没有匹配的词组，保留原字符
        if (!matched) {
          resultBuffer.write(text[i]);
          i++;
        }
      }
      
      return resultBuffer.toString();
    } catch (e, stackTrace) {
      // 防止任何异常导致转换失败，出现异常时返回原文本并记录详细错误
      LogUtil.logError('词组转换过程中出现异常: $e', e, stackTrace);
      return text;
    }
  }
}

/// 优化: 词组匹配的前缀树结构
class _PhraseTrie {
  final _TrieNode root = _TrieNode();
  
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
  
  _MatchResult findLongestMatch(String text, int startPos) {
    _TrieNode node = root;
    _TrieNode? lastMatchNode;
    int matchEndPos = startPos;
    
    for (int i = startPos; i < text.length; i++) {
      final String char = text[i];
      if (!node.children.containsKey(char)) {
        break;
      }
      node = node.children[char]!;
      if (node.isEndOfPhrase) {
        lastMatchNode = node;
        matchEndPos = i + 1;
      }
    }
    
    if (lastMatchNode != null) {
      return _MatchResult(
        lastMatchNode.phrase!, 
        lastMatchNode.replacement!,
        startPos,
        matchEndPos
      );
    }
    return _MatchResult.noMatch();
  }
}

/// 优化: 前缀树节点类
class _TrieNode {
  Map<String, _TrieNode> children = {};
  bool isEndOfPhrase = false;
  String? phrase;
  String? replacement;
}

/// 优化: 词组匹配结果类
class _MatchResult {
  final String phrase;
  final String replacement;
  final int startPos;
  final int endPos;
  final bool isMatch;
  
  _MatchResult(this.phrase, this.replacement, this.startPos, this.endPos) : isMatch = true;
  _MatchResult.noMatch() : phrase = '', replacement = '', startPos = -1, endPos = -1, isMatch = false;
}
