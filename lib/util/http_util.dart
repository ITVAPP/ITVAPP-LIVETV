import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/io.dart';
import 'package:dio/dio.dart';
import 'package:brotli/brotli.dart';
import 'package:flutter/cupertino.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/widget/headers.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

class HttpUtil {
  static final HttpUtil _instance = HttpUtil._(); // 单例模式的静态实例，确保 HttpUtil 全局唯一
  late final Dio _dio; // 使用 Dio 进行 HTTP 请求

  // 初始化 Dio 的基础配置，headers在具体请求时动态生成
  BaseOptions options = BaseOptions(
    connectTimeout: const Duration(seconds: 3), // 设置默认连接超时时间
    receiveTimeout: const Duration(seconds: 8), // 设置默认接收超时时间
  );

  CancelToken cancelToken = CancelToken(); // 用于取消请求的全局令牌

  factory HttpUtil() => _instance;

  // 构造函数
  HttpUtil._() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3), // 默认连接超时
      receiveTimeout: const Duration(seconds: 8), // 默认接收超时
      responseType: ResponseType.bytes, // 统一使用字节响应类型，避免重复设置
    ));

    // 自定义 HttpClient 适配器，限制每个主机的最大连接数，允许不安全的证书
    if (_dio.httpClientAdapter is IOHttpClientAdapter) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient()
          ..maxConnectionsPerHost = 5
          ..autoUncompress = true
          ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }
  }

  // 超时设置的工具函数
  Duration _getTimeout(Duration? customTimeout, Duration? defaultTimeout) {
    return customTimeout != null && customTimeout.inMilliseconds > 0
        ? customTimeout
        : defaultTimeout ?? const Duration(seconds: 3); // 提供最终默认值
  }

  Response _processResponse(Response response) {
    // 如果响应数据不是字节数组，说明已经处理过，直接返回
    if (!(response.data is List<int>)) {
      return response;
    }

    final bytes = response.data as List<int>;
    
    // 添加空内容判断逻辑
    if (bytes.isEmpty) {
      LogUtil.v('响应内容为空字节数组，跳过解码处理');
      // 对于空内容，将其设置为空字符串，避免后续处理
      response.data = '';
      return response;
    }

    final contentEncoding = response.headers.value('content-encoding')?.toLowerCase() ?? '';
    final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';

    // 处理 Brotli 压缩的内容
    if (contentEncoding.contains('br')) {
      try {
        final decodedBytes = brotliDecode(Uint8List.fromList(bytes));
        response.data = _decodeContent(decodedBytes, contentType); // 提取解码逻辑
        LogUtil.i('成功解码 Brotli 压缩内容');
      } catch (e, stackTrace) {
        LogUtil.logError('Brotli 解压缩失败', e, stackTrace);
        response.data = _decodeFallback(bytes, contentType); // 回退解码
      }
    } else {
      response.data = _decodeFallback(bytes, contentType); // 非 Brotli 内容解码
    }

    // 统一处理字符串 trim，避免重复代码
    if (response.data is String) {
      response.data = (response.data as String).trim();
    }
    return response;
  }

  // 内容解码逻辑
  dynamic _decodeContent(List<int> bytes, String contentType) {
    // 添加空内容判断
    if (bytes.isEmpty) {
      LogUtil.v('_decodeContent: 内容为空，返回空字符串');
      return '';
    }
    
    final text = utf8.decode(bytes, allowMalformed: true);
    if (contentType.contains('json')) {
      try {
        // 添加空字符串判断
        if (text.isEmpty) {
          LogUtil.v('JSON内容为空字符串，返回空对象');
          return contentType.contains('array') ? [] : {};
        }
        return jsonDecode(text);
      } catch (e) {
        LogUtil.e('JSON 解析失败: $e');
        return text;
      }
    }
    return text;
  }

  // 回退解码逻辑，处理非 Brotli 或解压失败的情况
  dynamic _decodeFallback(List<int> bytes, String contentType) {
    // 添加空内容判断
    if (bytes.isEmpty) {
      LogUtil.v('_decodeFallback: 内容为空，返回空字符串');
      return '';
    }
    
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      if (contentType.contains('json')) {
        try {
          // 添加空字符串判断
          if (text.isEmpty) {
            LogUtil.v('JSON内容为空字符串，返回空对象');
            return contentType.contains('array') ? [] : {};
          }
          return jsonDecode(text);
        } catch (e) {
          LogUtil.e('JSON 解析失败: $e');
          return text;
        }
      }
      return text;
    } catch (e) {
      LogUtil.e('UTF-8 解码失败，尝试其他编码: $e');
      try {
        return latin1.decode(bytes);
      } catch (e) {
        LogUtil.e('所有解码尝试均失败: $e');
        return bytes; // 保留原始字节数据
      }
    }
  }

  // 提取类型处理的公共函数，减少重复逻辑
  T? _parseResponseData<T>(dynamic data, {T? Function(dynamic)? parseData}) {
    // 添加null检查
    if (data == null) return null;
    
    // 添加空数组和空字符串检查
    if (data is List && data.isEmpty) {
      LogUtil.v('_parseResponseData: 数据为空数组');
      return null;
    }
    
    // 如果数据是字符串，去除前后的空格和换行符
    if (data is String) {
      data = data.trim();
      // 检查空字符串
      if (data.isEmpty) {
        LogUtil.v('_parseResponseData: 数据为空字符串');
        return null;
      }
    }

    // 如果提供了自定义解析函数，优先使用
    if (parseData != null) {
      try {
        return parseData(data);
      } catch (e, stackTrace) {
        LogUtil.logError('自定义解析失败: $data', e, stackTrace);
        return null;
      }
    }

    // 处理 String 类型
    if (T == String) {
      if (data is String) return data as T;
      if (data is Map || data is List) return jsonEncode(data) as T;
      if (data is int || data is double || data is bool) return data.toString() as T;
      LogUtil.e('无法将数据转换为 String: $data (类型: ${data.runtimeType})');
      return null;
    }

    // 其他类型直接尝试转换
    try {
      return data is T ? data as T : null;
    } catch (e) {
      LogUtil.e('类型转换失败: $data无法转换为 $T');
      return null;
    }
  }

  // 合并 GET 和 POST 请求逻辑，使用布尔值区分请求类型
  Future<R?> _performRequest<R>({
    required bool isPost, // 使用布尔值替代 method 字符串，简化逻辑
    required String path,
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    required R? Function(Response response) onSuccess,
  }) async {
    Response? response;
    int currentAttempt = 0;

    // 确保所有请求使用 ResponseType.bytes，避免重复设置
    options = options ?? Options();

    while (currentAttempt < retryCount) {
      try {
        // 如果 options.headers 存在且不为空，则使用它；否则使用 HeadersConfig.generateHeaders
        final headers = options.headers != null && options.headers!.isNotEmpty
            ? options.headers!
            : HeadersConfig.generateHeaders(url: path);

        // 提取超时设置，使用局部配置副本，避免修改全局 _dio.options
        final connectTimeout = _getTimeout(
          options.extra?['connectTimeout'] as Duration?,
          _dio.options.connectTimeout,
        );
        final receiveTimeout = _getTimeout(
          options.extra?['receiveTimeout'] as Duration?,
          _dio.options.receiveTimeout,
        );

        // 临时修改 BaseOptions 的超时设置
        final originalBaseOptions = _dio.options; // 保存原始 BaseOptions
        _dio.options = _dio.options.copyWith(
          connectTimeout: connectTimeout, // 设置动态连接超时
          receiveTimeout: receiveTimeout, // 设置动态接收超时
        );

        // 使用局部选项配置，避免影响全局 _dio，仅处理 headers 等每请求设置
        final requestOptions = options.copyWith(
          headers: headers,
        );

        // 执行请求，使用全局 cancelToken 或传入的 cancelToken
        response = await (isPost
            ? _dio.post(
                path,
                data: data,
                queryParameters: queryParameters,
                options: requestOptions,
                cancelToken: cancelToken ?? this.cancelToken,
                onSendProgress: onSendProgress,
                onReceiveProgress: onReceiveProgress,
              )
            : _dio.get(
                path,
                queryParameters: queryParameters,
                options: requestOptions,
                cancelToken: cancelToken ?? this.cancelToken,
                onReceiveProgress: onReceiveProgress,
              ));

        // 恢复原始的 BaseOptions 设置
        _dio.options = originalBaseOptions;

        // 处理响应内容，包括 Brotli 解压缩和类型转换
        response = _processResponse(response);
        return onSuccess(response);
      } on DioException catch (e, stackTrace) {
        currentAttempt++;
        LogUtil.logError(
          '第 $currentAttempt 次${isPost ? 'POST' : 'GET'} 请求失败: $path\n'
          '响应状态码: ${e.response?.statusCode}\n'
          '响应数据: ${e.response?.data}\n'
          '响应头: ${e.response?.headers}',
          e,
          stackTrace,
        );

        if (currentAttempt >= retryCount || e.type == DioExceptionType.cancel) {
          formatError(e);
          return null;
        }

        await Future.delayed(retryDelay);
        LogUtil.i('等待 ${retryDelay.inSeconds} 秒后重试第 $currentAttempt 次');
      }
    }
    return null;
  }

  // GET 请求方法
  Future<T?> getRequest<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    T? Function(dynamic data)? parseData,
  }) async {
    return _performRequest<T>(
      isPost: false,
      path: path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => _parseResponseData<T>(response.data, parseData: parseData),
    );
  }

  // GET 请求方法，返回完整 Response
  Future<Response?> getRequestWithResponse(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    return _performRequest<Response>(
      isPost: false,
      path: path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => response,
    );
  }

  // POST 请求方法
  Future<T?> postRequest<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
    T? Function(dynamic data)? parseData,
  }) async {
    // 调用合并后的 _performRequest 方法，传入 isPost: true
    return _performRequest<T>(
      isPost: true,
      path: path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => _parseResponseData<T>(response.data, parseData: parseData),
    );
  }

  // POST 请求方法，返回完整 Response
  Future<Response?> postRequestWithResponse(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    int retryCount = 2,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    return _performRequest<Response>(
      isPost: true,
      path: path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      retryCount: retryCount,
      retryDelay: retryDelay,
      onSuccess: (response) => response,
    );
  }

  // 文件下载方法
  Future<int?> downloadFile(
    String url,
    String savePath, {
    ValueChanged<double>? progressCallback,
  }) async {
    try {
      final headers = HeadersConfig.generateHeaders(url: url);
      final response = await _dio.download(
        url,
        savePath,
        options: Options(
          receiveTimeout: const Duration(seconds: 298),
          headers: headers,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) progressCallback?.call(received / total);
        },
      );

      if (response.statusCode != 200) {
        throw DioException(
          requestOptions: response.requestOptions,
          error: '状态码: ${response.statusCode}',
        );
      }

      LogUtil.i('文件下载成功: $url,保存路径: $savePath');
      return response.statusCode;
    } on DioException catch (e, stackTrace) {
      LogUtil.logError('文件下载失败: $url', e, stackTrace);
      return 500;
    }
  }
}

// 统一处理 Dio 请求的异常
void formatError(DioException e) {
  LogUtil.safeExecute(() {
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => S.current.netTimeOut,
      DioExceptionType.sendTimeout => S.current.netSendTimeout,
      DioExceptionType.receiveTimeout => S.current.netReceiveTimeout,
      DioExceptionType.badResponse => S.current.netBadResponse(e.response?.statusCode ?? ''),
      DioExceptionType.cancel => S.current.netCancel,
      _ => e.message.toString()
    };
    LogUtil.v(message);
  }, '处理 DioException 错误时发生异常');
}
