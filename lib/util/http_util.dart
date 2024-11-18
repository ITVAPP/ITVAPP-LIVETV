import 'dart:io';
import 'package:dio/io.dart';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/cupertino.dart';
import '../generated/l10n.dart';

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._(); // 单例模式的静态实例
  late final Dio _dio;

  // 配置 Dio 的基本选项，包括超时时间和默认请求头
  BaseOptions options = BaseOptions(
    connectTimeout: const Duration(seconds: 8), // 连接超时时间
    receiveTimeout: const Duration(seconds: 8), // 接收超时时间
    headers: {
      HttpHeaders.acceptEncodingHeader: '*', // 支持所有的内容编码
      HttpHeaders.connectionHeader: 'keep-alive', // 保持长连接
    },
  );

  CancelToken cancelToken = CancelToken(); // 默认的取消令牌，用于取消请求

  // 工厂构造函数，确保 HttpUtil 是单例模式
  factory HttpUtil() {
    return _instance;
  }

  // 私有构造函数，初始化 Dio 实例，并添加日志拦截器
  HttpUtil._() {
    _dio = Dio(options)
      ..interceptors.add(LogInterceptor(
        requestBody: true, // 打印请求体
        responseBody: true, // 打印响应体
        requestHeader: false, // 不打印请求头
        responseHeader: false, // 不打印响应头
      ));

    // 配置连接池管理，限制每个主机的最大连接数
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.maxConnectionsPerHost = 5; // 每个主机的最大连接数
      return client;
    };
  }

  // 通用的 GET 请求方法，支持重试机制和重试延迟
  Future<T?> getRequest<T>(String path,
      {Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onReceiveProgress,
      int retryCount = 2, // 默认重试次数
      Duration retryDelay = const Duration(seconds: 2)}) async {
    Response? response; // 请求响应
    int currentAttempt = 0; // 当前重试次数
    Duration currentDelay = retryDelay; // 当前延迟时间（初始值为默认重试延迟）

    // 尝试请求，并在失败时重试
    while (currentAttempt < retryCount) {
      try {
        // 发起 GET 请求
        response = await _dio.get<T>(
          path,
          queryParameters: queryParameters, // 查询参数
          options: options?.copyWith(extra: {'attempt': currentAttempt}) ??
              Options(extra: {'attempt': currentAttempt}), // 添加当前重试次数到请求选项中
          cancelToken: cancelToken, // 用于取消请求
          onReceiveProgress: onReceiveProgress, // 接收进度回调
        );

        // 如果请求返回的数据不为空，直接返回
        if (response.data != null) {
          return response.data;
        }
        return null; // 返回空表示请求成功但无数据
      } on DioException catch (e, stackTrace) {
        currentAttempt++; // 增加重试次数
        LogUtil.logError('第 $currentAttempt 次 GET 请求失败: $path', e, stackTrace); // 记录错误日志

        // 如果达到最大重试次数或请求被取消，则停止重试并处理错误
        if (currentAttempt >= retryCount || e.type == DioExceptionType.cancel) {
          formatError(e); // 格式化并记录错误
          return null; // 返回空，表示失败
        }

        // 使用指数退避策略，延迟后再重试
        await Future.delayed(currentDelay); // 延迟当前的重试时间
        currentDelay *= 2; // 下次重试延迟时间加倍
        LogUtil.i('等待 ${currentDelay.inSeconds} 秒后重试第 $currentAttempt 次'); // 记录重试延迟信息
      }
    }
    return null; // 返回空，表示所有重试失败
  }

  // 文件下载方法，支持进度回调
  Future<int?> downloadFile(String url, String savePath,
      {ValueChanged<double>? progressCallback}) async {
    try {
      // 使用 Dio 的 download 方法进行文件下载
      final response = await _dio.download(
        url,
        savePath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60), // 设置接收超时时间
          headers: {
            HttpHeaders.acceptEncodingHeader: '*', // 支持内容压缩
            HttpHeaders.userAgentHeader:
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36', // 模拟浏览器 UA
          },
        ),
        // 下载进度回调，计算已下载的百分比
        onReceiveProgress: (received, total) {
          if (total <= 0) return; // 如果总大小为 0，忽略回调
          progressCallback?.call(received / total); // 回调下载进度
        },
      );

      // 检查下载是否成功，状态码为 200 时成功
      if (response.statusCode != 200) {
        throw DioException(
            requestOptions: response.requestOptions,
            error: '状态码: ${response.statusCode}'); // 抛出异常
      }

      LogUtil.i('文件下载成功: $url, 保存路径: $savePath');
      return response.statusCode; // 返回状态码表示成功
    } on DioException catch (e, stackTrace) {
      // 记录下载失败的错误日志
      LogUtil.logError('文件下载失败: $url', e, stackTrace);
      return 500; // 返回错误码表示失败
    }
  }
}

// 格式化并处理 DioException 错误
void formatError(DioException e) {
  LogUtil.safeExecute(() {
    // 使用 switch 表达式，根据异常类型生成对应的错误信息
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => S.current.netTimeOut, // 连接超时
      DioExceptionType.sendTimeout => S.current.netSendTimeout, // 发送超时
      DioExceptionType.receiveTimeout => S.current.netReceiveTimeout, // 接收超时
      DioExceptionType.badResponse => S.current.netBadResponse(
          e.response?.statusCode ?? ''), // 错误响应（带状态码）
      DioExceptionType.cancel => S.current.netCancel, // 请求被取消
      _ => e.message.toString() // 其他未知错误
    };

    // 记录错误信息到日志
    LogUtil.v(message);
  }, '处理 DioException 错误时发生异常'); 
}
