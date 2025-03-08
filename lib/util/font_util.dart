import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

class FontUtil {
  FontUtil._();

  static final FontUtil _instance = FontUtil._();

  factory FontUtil() {
    return _instance;
  }

  /// 获取字体文件的存储路径
  Future<String> getFontPath() async {
    final path = (await getApplicationSupportDirectory()).path;
    return '$path/fonts';
  }

  /// 下载字体文件
  /// [url] 字体文件的下载地址
  /// [overwrite] 是否覆盖已存在的字体文件，默认为 false
  /// [progressCallback] 下载进度回调
  Future<Uint8List?> downloadFont(String url, {bool overwrite = false, ValueChanged<double>? progressCallback}) async {
    final uri = Uri.parse(url);
    final filename = uri.pathSegments.last;
    final dir = await getFontPath();
    final fontPath = '$dir/$filename';
    final file = File(fontPath);

    // 如果文件已存在且不覆盖，则直接读取文件内容
    if (await file.exists() && !overwrite) {
      LogUtil.v('字体文件已存在，直接读取: $fontPath');
      return file.readAsBytes();
    }

    // 创建字体目录（如果不存在）
    final fontDir = Directory(dir);
    if (!await fontDir.exists()) {
      await fontDir.create(recursive: true);
      LogUtil.v('创建字体目录: $dir');
    }

    // 下载字体文件
    final bytes = await downloadBytes(url, filename, fontPath, progressCallback: progressCallback);
    return bytes;
  }

  /// 下载字体文件并保存为字节数据
  /// [url] 字体文件的下载地址
  /// [filename] 文件名
  /// [savePath] 文件保存路径
  /// [progressCallback] 下载进度回调
  Future<Uint8List?> downloadBytes(String url, String filename, String savePath, {ValueChanged<double>? progressCallback}) async {
    try {
      final code = await HttpUtil().downloadFile(
        url: url,
        savePath: savePath,
        progressCallback: progressCallback,
        timeout: const Duration(minutes: 2), // 设置合理的超时时间
      );

      // 根据状态码处理下载结果
      switch (code) {
        case 200:
          LogUtil.v('字体文件下载成功: $savePath');
          return File(savePath).readAsBytes();
        case 408:
          LogUtil.e('字体文件下载超时: $url');
          return null;
        case 499:
          LogUtil.v('字体文件下载已取消: $url');
          return null;
        default:
          LogUtil.e('字体文件下载失败，状态码: $code, URL: $url');
          return null;
      }
    } catch (e, stackTrace) {
      LogUtil.logError('下载字体文件时发生错误: $url', e, stackTrace);
      return null;
    }
  }

  /// 删除指定 URL 对应的字体文件
  /// [url] 字体文件的下载地址
  Future<void> deleteFont(String url) async {
    final uri = Uri.parse(url);
    final filename = uri.pathSegments.last;
    final dir = (await getApplicationSupportDirectory()).path;
    final file = File('$dir/$filename');
    if (await file.exists()) {
      await file.delete();
      LogUtil.v('字体文件已删除: ${file.path}');
    } else {
      LogUtil.v('字体文件不存在，无需删除: ${file.path}');
    }
  }

  /// 加载字体文件到 Flutter 引擎
  /// [url] 字体文件的下载地址
  /// [fontFamily] 字体家族名称
  /// [progressCallback] 下载进度回调
  Future<bool> loadFont(String url, String fontFamily, {ValueChanged<double>? progressCallback}) async {
    final fontByte = await downloadFont(url, progressCallback: progressCallback);
    if (fontByte == null) {
      LogUtil.e('字体文件下载失败，无法加载: $url');
      return false;
    }
    try {
      await loadFontFromList(fontByte, fontFamily: fontFamily);
      LogUtil.v('字体加载成功: $fontFamily from $url');
      return true;
    } catch (e, stackTrace) {
      LogUtil.logError('加载字体失败: $fontFamily from $url', e, stackTrace);
      return false;
    }
  }
}
