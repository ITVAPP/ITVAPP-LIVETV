import 'dart:async'; // 导入异步支持库
import 'package:flutter/foundation.dart'; // 导入Flutter基础库
import 'package:intl/intl.dart'; // 导入国际化库
import 'package:intl/message_lookup_by_library.dart'; // 导入消息查找库
import 'package:intl/src/intl_helpers.dart'; // 导入Intl帮助库

// 导入各语言的消息文件
import 'messages_en.dart' as messages_en;
import 'messages_zh_CN.dart' as messages_zh_cn;
import 'messages_zh_TW.dart' as messages_zh_tw;

// 定义一个typedef，表示一个返回Future的函数类型
typedef Future<dynamic> LibraryLoader();

// 延迟加载库的映射
Map<String, LibraryLoader> _deferredLibraries = {
  'en': () => new SynchronousFuture(null), // 英语（美国）
  'zh_CN': () => new SynchronousFuture(null), // 中文（中国）
  'zh_TW': () => new SynchronousFuture(null), // 中文（台湾）
};

// 查找并返回特定语言环境的消息库
MessageLookupByLibrary? _findExact(String localeName) {
  switch (localeName) {
    case 'en':
      return messages_en.messages; // 返回英语消息库
    case 'zh_CN':
      return messages_zh_cn.messages; // 返回中文（简体）消息库
    case 'zh_TW':
      return messages_zh_tw.messages; // 返回中文（繁体）消息库
    default:
      return null; // 默认返回null
  }
}

/// 用户程序应在使用[localeName]查找消息之前调用此函数。
Future<bool> initializeMessages(String localeName) {
  var availableLocale = Intl.verifiedLocale(
      localeName, (locale) => _deferredLibraries[locale] != null,
      onFailure: (_) => null); // 验证是否有可用的语言环境
  if (availableLocale == null) {
    return new SynchronousFuture(false); // 如果没有可用的语言环境，返回false
  }
  var lib = _deferredLibraries[availableLocale]; // 获取对应的库加载器
  lib == null ? new SynchronousFuture(false) : lib(); // 如果库加载器为空，返回false，否则执行加载器
  initializeInternalMessageLookup(() => new CompositeMessageLookup()); // 初始化内部消息查找机制
  messageLookup.addLocale(availableLocale, _findGeneratedMessagesFor); // 添加语言环境及其对应的消息库
  return new SynchronousFuture(true); // 返回true，表示初始化成功
}

// 检查是否存在指定语言环境的消息
bool _messagesExistFor(String locale) {
  try {
    return _findExact(locale) != null; // 尝试查找指定语言环境的消息库
  } catch (e) {
    return false; // 如果查找失败，返回false
  }
}

// 查找并返回生成的消息库
MessageLookupByLibrary? _findGeneratedMessagesFor(String locale) {
  var actualLocale =
      Intl.verifiedLocale(locale, _messagesExistFor, onFailure: (_) => null); // 验证实际语言环境
  if (actualLocale == null) return null; // 如果实际语言环境为null，返回null
  return _findExact(actualLocale); // 返回对应的消息库
}
