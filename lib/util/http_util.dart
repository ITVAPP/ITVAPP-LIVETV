import 'dart:io';
import 'package:dio/dio.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:flutter/cupertino.dart';
import '../generated/l10n.dart';

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._();
  late Dio _dio;
  
  // 设置基本选项
  BaseOptions options = BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  );

  CancelToken cancelToken = CancelToken();

  // 工厂构造函数，确保 HttpUtil 是单例
  factory HttpUtil() {
    return _instance;
  }

  // 私有构造函数，初始化 Dio 实例并添加日志拦截器
  HttpUtil._() {
    _dio = Dio(options)
      ..interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
      ));
  }

  // GET 请求方法，添加了重试机制
  Future<T?> getRequest<T>(String path,
      {Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onReceiveProgress,
      int retryCount = 3,  // 默认重试次数为 3
      Duration retryDelay = const Duration(seconds: 2)  // 重试前的延迟
      }) async {
    Response? response;
    int currentAttempt = 0;

    while (currentAttempt < retryCount) {
      try {
        // 执行 GET 请求
        response = await _dio.get<T>(path,
            queryParameters: queryParameters,
            options: options,
            cancelToken: cancelToken,
            onReceiveProgress: onReceiveProgress);
        return response?.data; // 请求成功，返回数据
      } on DioException catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError('第 $currentAttempt 次 GET 请求失败: $path', e, stackTrace);

        // 当达到最大重试次数时，处理错误并终止请求
        if (currentAttempt >= retryCount) {
          formatError(e);
          return null; // 返回 null 表示失败
        } else {
          // 在每次失败后等待一段时间再重试
          await Future.delayed(retryDelay);
          LogUtil.i('等待 $retryDelay 后重试第 $currentAttempt 次');
        }
      }
    }
    return null; // 万一出现意外，返回 null
  }

  // 文件下载方法，包含进度回调
  Future<int?> downloadFile(String url, String savePath,
      {ValueChanged<double>? progressCallback}) async {
    Response? response;
    try {
      // 执行下载操作
      response = await _dio.download(
        url,
        savePath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          headers: {
            HttpHeaders.acceptEncodingHeader: '*',
            HttpHeaders.userAgentHeader:
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
          },
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          progressCallback?.call((received / total)); // 回调下载进度
        },
      );

      // 下载成功状态码应为 200，否则抛出异常
      if (response.statusCode != 200) {
        throw DioException(
            requestOptions: response.requestOptions,
            error: '状态码: ${response.statusCode}');
      }
      LogUtil.i('文件下载成功: $url, 保存路径: $savePath');
    } on DioException catch (e, stackTrace) {
      LogUtil.logError('文件下载失败: $url', e, stackTrace);
    }
    return response?.statusCode ?? 500; // 如果失败返回 500
  }
}

// 错误处理方法，记录日志并显示不同的提示
void formatError(DioException e) {
  LogUtil.safeExecute(() {
    if (e.type == DioExceptionType.connectionTimeout) {
      // 连接超时
      LogUtil.v(S.current.netTimeOut);
    } else if (e.type == DioExceptionType.sendTimeout) {
      // 发送超时
      LogUtil.v(S.current.netSendTimeout);
    } else if (e.type == DioExceptionType.receiveTimeout) {
      // 接收超时
      LogUtil.v(S.current.netReceiveTimeout);
    } else if (e.type == DioExceptionType.badResponse) {
      // 错误响应
      LogUtil.v(S.current.netBadResponse(e.response?.statusCode ?? ''));
    } else if (e.type == DioExceptionType.cancel) {
      // 请求取消
      LogUtil.v(S.current.netCancel);
    } else {
      // 其他错误类型
      LogUtil.v(e.message.toString());
    }
  }, '处理 DioException 错误时发生异常');
}
