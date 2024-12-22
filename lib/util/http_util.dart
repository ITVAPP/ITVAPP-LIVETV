import 'dart:io';
import 'package:dio/io.dart';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/cupertino.dart';
import 'package:itvapp_live_tv/widget/headers.dart';  // 引入动态生成 headers 的工具类
import '../generated/l10n.dart';

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._(); // 单例模式的静态实例，确保 HttpUtil 全局唯一
  late final Dio _dio; // 使用 Dio 进行 HTTP 请求

  // 初始化 Dio 的基础配置，这里主要设置超时时间，headers 在具体请求时动态生成
  BaseOptions options = BaseOptions(
    connectTimeout: const Duration(seconds: 8), // 设置连接超时时间
    receiveTimeout: const Duration(seconds: 8), // 设置接收超时时间
  );

  CancelToken cancelToken = CancelToken(); // 用于取消请求的令牌

  factory HttpUtil() {
    return _instance;
  }

  HttpUtil._() {
    // 初始化 Dio 实例并配置日志拦截器
    _dio = Dio(options)
      ..interceptors.add(LogInterceptor(
        requestBody: true, // 日志中打印请求体
        responseBody: true, // 日志中打印响应体
        requestHeader: false, // 不打印请求头
        responseHeader: false, // 不打印响应头
      ));

    // 自定义 HttpClient 适配器，限制每个主机的最大连接数
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.maxConnectionsPerHost = 5; // 设置最大连接数为 5
      return client;
    };
  }

  // GET 请求方法，支持自动重试机制
  Future<T?> getRequest<T>(String path,
      {Map<String, dynamic>? queryParameters, // 查询参数
      Options? options, // 可选的请求配置
      CancelToken? cancelToken, // 请求取消令牌
      ProgressCallback? onReceiveProgress, // 接收进度回调
      int retryCount = 2, // 重试次数
      Duration retryDelay = const Duration(seconds: 2)}) async {
    Response? response;
    int currentAttempt = 0; // 当前重试次数
    Duration currentDelay = retryDelay; // 当前重试延迟

    while (currentAttempt < retryCount) {
      try {
        // 动态生成请求头
        final headers = HeadersConfig.generateHeaders(url: path);
        
        response = await _dio.get<T>(
          path,
          queryParameters: queryParameters,
          options: (options?.copyWith(
            extra: {'attempt': currentAttempt}, // 记录当前尝试次数
            headers: headers, // 添加动态生成的 headers
          ) ?? Options(
            extra: {'attempt': currentAttempt}, // 记录当前尝试次数
            headers: headers, // 添加动态生成的 headers
          )),
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
        );

        if (response.data != null) {
          return response.data; // 成功返回数据
        }
        return null;
      } on DioException catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError('第 $currentAttempt 次 GET 请求失败: $path', e, stackTrace); // 记录失败日志

        // 如果达到最大重试次数或请求被取消，则不再重试
        if (currentAttempt >= retryCount || e.type == DioExceptionType.cancel) {
          formatError(e); // 处理错误信息
          return null;
        }

        // 等待一定时间后重试，并加倍延迟时间
        await Future.delayed(currentDelay);
        currentDelay *= 2;
        LogUtil.i('等待 ${currentDelay.inSeconds} 秒后重试第 $currentAttempt 次');
      }
    }
    return null; // 重试后依然失败则返回 null
  }

  // 文件下载方法，支持显示下载进度
  Future<int?> downloadFile(String url, String savePath,
      {ValueChanged<double>? progressCallback}) async {
    try {
      // 动态生成请求头
      final headers = HeadersConfig.generateHeaders(url: url);

      final response = await _dio.download(
        url,
        savePath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60), // 下载超时时间设置为 60 秒
          headers: headers, // 使用动态生成的 headers
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) return; // 避免除以零的错误
          progressCallback?.call(received / total); // 回调下载进度
        },
      );

      if (response.statusCode != 200) {
        throw DioException(
            requestOptions: response.requestOptions,
            error: '状态码: ${response.statusCode}');
      }

      LogUtil.i('文件下载成功: $url, 保存路径: $savePath'); // 下载成功日志
      return response.statusCode;
    } on DioException catch (e, stackTrace) {
      LogUtil.logError('文件下载失败: $url', e, stackTrace); // 下载失败日志
      return 500; // 返回错误状态码
    }
  }
}

// 统一处理 Dio 请求的异常
void formatError(DioException e) {
  LogUtil.safeExecute(() {
    // 根据异常类型返回对应的本地化错误信息
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => S.current.netTimeOut,
      DioExceptionType.sendTimeout => S.current.netSendTimeout,
      DioExceptionType.receiveTimeout => S.current.netReceiveTimeout,
      DioExceptionType.badResponse => S.current.netBadResponse(
          e.response?.statusCode ?? ''),
      DioExceptionType.cancel => S.current.netCancel,
      _ => e.message.toString()
    };

    LogUtil.v(message); // 打印详细的错误信息
  }, '处理 DioException 错误时发生异常'); // 捕获处理异常中的异常
}
