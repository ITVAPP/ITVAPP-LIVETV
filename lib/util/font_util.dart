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

  Future<String> getFontPath() async {
    final path = (await getApplicationSupportDirectory()).path;
    return '$path/fonts';
  }

  Future<Uint8List?> downloadFont(String url, {bool overwrite = false, ValueChanged<double>? progressCallback, CancelToken? cancelToken}) async {
    final uri = Uri.parse(url);
    final filename = uri.pathSegments.last;
    final dir = await getFontPath();
    final fontPath = '$dir/$filename';
    final file = File(fontPath);
    if (await file.exists() && !overwrite) {
      return file.readAsBytes();
    }

    // 传递 cancelToken，用于取消下载任务
    final bytes = await downloadBytes(url, filename, fontPath, progressCallback: progressCallback, cancelToken: cancelToken);
    return bytes;
  }

  Future<Uint8List?> downloadBytes(String url, String filename, String savePath, {ValueChanged<double>? progressCallback, CancelToken? cancelToken}) async {
    if (cancelToken?.isCancelled == true) {
      LogUtil.i('下载请求已取消');
      return null;  // 如果请求被取消，直接返回
    }

    final code = await HttpUtil().downloadFile(url, savePath, progressCallback: progressCallback);
    if (code == 200) {
      return File(savePath).readAsBytes();
    } else {
      return null;
    }
  }

  Future<void> deleteFont(String url) async {
    final uri = Uri.parse(url);
    final filename = uri.pathSegments.last;
    final dir = (await getApplicationSupportDirectory()).path;
    final file = File('$dir/$filename');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> loadFont(String url, String fontFamily, {ValueChanged<double>? progressCallback, CancelToken? cancelToken}) async {
    final fontByte = await downloadFont(url, progressCallback: progressCallback, cancelToken: cancelToken);
    if (fontByte == null) return false;
    try {
      await loadFontFromList(fontByte, fontFamily: fontFamily);
      return true;
    } catch (e, s) {
      debugPrint(e.toString());
      debugPrint(s.toString());
      return false;
    }
  }
}
