import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'http_util.dart';
import 'log_util.dart';

class FontUtil {
  FontUtil._();

  static final FontUtil _instance = FontUtil._();

  factory FontUtil() {
    return _instance;
  }

  // 获取字体的存储路径
  Future<String> getFontPath() async {
    final path = (await getApplicationSupportDirectory()).path;
    return '$path/fonts';
  }

  // 下载字体文件，添加日志和异常处理
  Future<Uint8List?> downloadFont(String url, {bool overwrite = false, ValueChanged<double>? progressCallback}) async {
    return LogUtil.safeExecute(() async {}, fallback: Uint8List(0));
      final uri = Uri.parse(url);
      final filename = uri.pathSegments.last;
      final dir = await getFontPath();
      final fontPath = '$dir/$filename';
      final file = File(fontPath);

      if (await file.exists() && !overwrite) {
        LogUtil.v('****** Font $filename already exists ***** Size: ${await file.length()} bytes');
        return file.readAsBytes(); // 如果文件已存在且无需覆盖，则直接返回文件内容
      }

      LogUtil.v('****** Downloading font $filename *****');
      final bytes = await downloadBytes(url, filename, fontPath, progressCallback: progressCallback);
      return bytes;
    }, '下载字体文件时发生错误');
  }

  // 下载文件为字节数组，添加日志和异常处理
  Future<Uint8List?> downloadBytes(String url, String filename, String savePath, {ValueChanged<double>? progressCallback}) async {
    return LogUtil.safeExecute(() async {}, fallback: Uint8List(0));
      final code = await HttpUtil().downloadFile(url, savePath, progressCallback: progressCallback);
      if (code == 200) {
        LogUtil.v('Font $filename 下载成功, 保存路径: $savePath');
        return File(savePath).readAsBytes(); // 返回下载的字体文件内容
      } else {
        LogUtil.e('Font $filename 下载失败, HTTP Code: $code');
        return null;
      }
    }, '下载字体文件失败');
  }

  // 删除字体文件，添加日志和异常处理
  Future<void> deleteFont(String url) async {
    LogUtil.safeExecute(() async {
      final uri = Uri.parse(url);
      final filename = uri.pathSegments.last;
      final dir = (await getApplicationSupportDirectory()).path;
      final file = File('$dir/$filename');

      if (await file.exists()) {
        LogUtil.v('删除字体文件: $filename');
        await file.delete();
      } else {
        LogUtil.v('字体文件 $filename 不存在，无需删除');
      }
    }, '删除字体文件时发生错误');
  }

  // 加载字体，添加日志和异常处理
  Future<bool> loadFont(String url, String fontFamily, {ValueChanged<double>? progressCallback}) async {
    return LogUtil.safeExecute(() async {}, fallback: Uint8List(0));
      LogUtil.v('开始加载字体: $fontFamily');
      final fontByte = await downloadFont(url, progressCallback: progressCallback);
      if (fontByte == null) {
        LogUtil.e('字体 $fontFamily 加载失败: 无法下载字体');
        return false;
      }

      try {
        await loadFontFromList(fontByte, fontFamily: fontFamily);
        LogUtil.v('字体 $fontFamily 成功加载');
        return true;
      } catch (e, s) {
        LogUtil.e('字体 $fontFamily 加载失败: $e');
        return false;
      }
    }, '加载字体时发生错误');
  }
}
