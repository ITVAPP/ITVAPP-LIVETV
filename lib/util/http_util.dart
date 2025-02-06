import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import '../generated/l10n.dart';

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._(); // 单例模式的静态实例，确保 HttpUtil 全局唯一
  final Duration connectTimeout;
  final Duration receiveTimeout;
  late final http.Client _client;
  bool _isCancelled = false;

  // 初始化基础配置，这里主要设置超时时间，headers 在具体请求时动态生成
  HttpUtil._()
      : connectTimeout = const Duration(seconds: 3),
        receiveTimeout = const Duration(seconds: 6) {
    _client = http.Client();
    HttpOverrides.global = _CustomHttpOverrides();
    LogUtil.i('HttpUtil initialized'); // 保持日志记录
  }

  factory HttpUtil() {
    return _instance;
  }

  void cancelRequests() {
    _isCancelled = true;
    LogUtil.i('所有请求已取消');
  }

  // GET 请求方法，确保返回 String? 时不会出错
  Future<T?> getRequest<T>(String path,
      {Map<String, dynamic>? queryParameters,
      Map<String, String>? headers,
      void Function(int, int)? onReceiveProgress,
      int retryCount = 2,
      Duration retryDelay = const Duration(seconds: 2)}) async {
    Uri uri = Uri.parse(path);
    if (queryParameters != null) {
      uri = uri.replace(queryParameters: queryParameters);
    }
    
    int currentAttempt = 0;
    Duration currentDelay = retryDelay;

    while (currentAttempt < retryCount) {
      try {
        // 检查是否需要取消请求
        if (_isCancelled) {
          _handleError(HttpRequestError.cancelled);
          return null;
        }

        LogUtil.i('发起请求: $uri'); // 请求日志
        LogUtil.i('Headers: ${HeadersConfig.generateHeaders(url: path)}'); // 请求头日志

        final response = await _client
            .get(
              uri,
              headers: {...?headers, ...HeadersConfig.generateHeaders(url: path)},
            )
            .timeout(connectTimeout);

        LogUtil.i('响应状态码: ${response.statusCode}'); // 响应状态码日志
        LogUtil.i('响应体: ${response.body}'); // 响应体日志

        if (response.statusCode == 200) {
          return response.body as T;
        }
        _handleError(HttpRequestError.badResponse(response.statusCode));
        return null;
      } catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError('第 $currentAttempt 次 GET 请求失败: $path', e, stackTrace);

        if (currentAttempt >= retryCount) {
          _handleError(_mapError(e));
          return null;
        }

        await Future.delayed(currentDelay);
        currentDelay *= 2;
        LogUtil.i('等待 ${currentDelay.inSeconds} 秒后重试第 $currentAttempt 次');
      }
    }
    return null;
  }

  // 文件下载方法，支持显示下载进度
  Future<int?> downloadFile(String url, String savePath,
      {ValueChanged<double>? progressCallback}) async {
    try {
      final headers = HeadersConfig.generateHeaders(url: url);
      
      LogUtil.i('开始下载文件: $url'); // 下载开始日志
      
      final response = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final file = File(savePath);
        final bytes = response.bodyBytes;
        final totalBytes = bytes.length;
        
        // 分块写入并更新进度
        final chunkSize = 1024 * 1024; // 1MB chunks
        var written = 0;
        
        final sink = file.openWrite();
        for (var i = 0; i < totalBytes; i += chunkSize) {
          if (_isCancelled) {
            await sink.close();
            return null;
          }
          
          final end = (i + chunkSize < totalBytes) ? i + chunkSize : totalBytes;
          sink.add(bytes.sublist(i, end));
          written += end - i;
          
          progressCallback?.call(written / totalBytes);
        }
        await sink.close();
        
        LogUtil.i('文件下载成功: $url, 保存路径: $savePath');
        return response.statusCode;
      }

      LogUtil.logError('文件下载失败: $url', 'Status code: ${response.statusCode}', StackTrace.current);
      return 500;
    } catch (e, stackTrace) {
      LogUtil.logError('文件下载失败: $url', e, stackTrace);
      return 500;
    }
  }

  void dispose() {
    _isCancelled = true;
    _client.close();
    LogUtil.i('HttpUtil disposed');
  }
}

class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..maxConnectionsPerHost = 5
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

// 错误处理相关
enum HttpRequestError {
  connectionTimeout,
  sendTimeout,
  receiveTimeout,
  cancelled,
  badResponse(int? statusCode);

  final int? statusCode;
  const HttpRequestError([this.statusCode]);
}

HttpRequestError _mapError(dynamic error) {
  if (error is TimeoutException) {
    return HttpRequestError.connectionTimeout;
  }
  return HttpRequestError.connectionTimeout; // 默认超时错误
}

void _handleError(HttpRequestError error) {
  LogUtil.safeExecute(() {
    final message = switch (error) {
      HttpRequestError.connectionTimeout => S.current.netTimeOut,
      HttpRequestError.sendTimeout => S.current.netSendTimeout,
      HttpRequestError.receiveTimeout => S.current.netReceiveTimeout,
      HttpRequestError.cancelled => S.current.netCancel,
      HttpRequestError.badResponse(final code?) => 
          S.current.netBadResponse(code?.toString() ?? ''),
    };

    LogUtil.v(message);
  }, '处理 HTTP 错误时发生异常');
}
