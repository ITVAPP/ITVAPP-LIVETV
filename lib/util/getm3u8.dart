import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

class GetM3U8 extends StatefulWidget {
  final String url;
  final Function(String) onM3U8Found;
  final int timeoutSeconds;
  
  const GetM3U8({
    Key? key,
    required this.url,
    required this.onM3U8Found,
    this.timeoutSeconds = 30,  // 默认30秒超时
  }) : super(key: key);

  @override
  State<GetM3U8> createState() => _GetM3U8State();
}

class _GetM3U8State extends State<GetM3U8> {
  late WebViewController _controller;
  bool _m3u8Found = false;
  Set<String> _foundUrls = {}; // 用于去重
  
  @override
  void initState() {
    super.initState();
    LogUtil.i('GetM3U8初始化，目标URL: ${widget.url}');
    _startTimeout();
  }

  void _startTimeout() {
    LogUtil.i('开始超时计时: ${widget.timeoutSeconds}秒');
    Future.delayed(Duration(seconds: widget.timeoutSeconds), () {
      if (mounted && !_m3u8Found) {
        LogUtil.w('GetM3U8提取超时，未找到有效的m3u8地址');
        widget.onM3U8Found(''); // 超时返回空字符串
        _disposeWebView();
      }
    });
  }

  void _handleM3U8Found(String url) {
    if (!_m3u8Found && url.isNotEmpty && !_foundUrls.contains(url)) {
      LogUtil.i('发现新的URL: $url');
      _foundUrls.add(url);
      
      // 验证URL格式
      if (_isValidM3U8Url(url)) {
        _m3u8Found = true;
        LogUtil.i('找到有效的m3u8地址: $url');
        widget.onM3U8Found(url);
        _disposeWebView();
      } else {
        LogUtil.w('URL格式验证失败: $url');
      }
    }
  }

  bool _isValidM3U8Url(String url) {
    // 验证URL是否为有效的m3u8地址
    final validUrl = Uri.tryParse(url);
    if (validUrl == null) {
      LogUtil.w('无效的URL格式');
      return false;
    }
    
    // 检查文件扩展名
    if (!url.toLowerCase().contains('.m3u8')) {
      LogUtil.w('URL不包含.m3u8扩展名');
      return false;
    }
    
    // 检查是否为完整URL
    if (!url.startsWith('http')) {
      LogUtil.w('URL不是以http开头的完整地址');
      return false;
    }
    
    return true;
  }

  void _disposeWebView() {
    LogUtil.i('释放WebView资源');
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_m3u8Found) {
      return const SizedBox.shrink();
    }

    LogUtil.i('创建WebView实例');
    return WebView(
      javascriptMode: JavascriptMode.unrestricted,
      onWebViewCreated: (controller) {
        _controller = controller;
        LogUtil.i('WebView控制器创建完成');
      },
      onPageFinished: (_) {
        LogUtil.i('页面加载完成，注入JS代码');
        _injectM3U8Detector();
      },
      javascriptChannels: {
        JavascriptChannel(
          name: 'm3u8Detector',
          onMessageReceived: (message) {
            LogUtil.i('JS检测器发现新的URL: ${message.message}');
            _handleM3U8Found(message.message);
          },
        ),
      },
      userAgent: 'Mozilla/5.0 (Linux; Android 12; Pixel 6 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      initialUrl: widget.url,
      onWebResourceError: (error) {
        LogUtil.e('WebView加载错误: ${error.description}，错误码: ${error.errorCode}');
      },
    );
  }

  void _injectM3U8Detector() {
    LogUtil.i('开始注入m3u8检测器JS代码');
    const jsCode = '''
      (function() {
        // 已处理的URL缓存
        const processedUrls = new Set();
        
        // URL处理函数
        function processM3U8Url(url) {
          if (!url || typeof url !== 'string') return;
          
          // 标准化URL
          try {
            url = new URL(url, window.location.href).href;
          } catch(e) {
            console.error('URL标准化失败:', e);
            return;
          }
          
          // 处理加密的URL
          try {
            const decodedUrl = decodeURIComponent(url);
            if (decodedUrl !== url) {
              processM3U8Url(decodedUrl);
            }
          } catch(e) {
            console.error('URL解码失败:', e);
          }
          
          // 处理base64编码的URL
          try {
            if (url.includes('base64,')) {
              const base64Content = url.split('base64,')[1];
              const decodedContent = atob(base64Content);
              if (decodedContent.includes('.m3u8')) {
                processM3U8Url(decodedContent);
              }
            }
          } catch(e) {
            console.error('Base64解码失败:', e);
          }
          
          if (url.includes('.m3u8') && !processedUrls.has(url)) {
            processedUrls.add(url);
            console.log('发现m3u8 URL:', url);
            window.m3u8Detector.postMessage(url);
          }
        }
        
        // 拦截XHR
        const XHR = XMLHttpRequest.prototype;
        const originalOpen = XHR.open;
        const originalSend = XHR.send;
        
        XHR.open = function() {
          this._url = arguments[1];
          return originalOpen.apply(this, arguments);
        };
        
        XHR.send = function() {
          const xhr = this;
          xhr.addEventListener('load', function() {
            processM3U8Url(xhr._url);
            
            // 检查响应内容
            try {
              const contentType = xhr.getResponseHeader('content-type');
              if (contentType && contentType.includes('application/json')) {
                const response = JSON.parse(xhr.responseText);
                JSON.stringify(response).split('"').forEach(processM3U8Url);
              }
            } catch(e) {
              console.error('处理XHR响应时出错:', e);
            }
          });
          return originalSend.apply(this, arguments);
        };
        
        // 拦截Fetch
        const originalFetch = window.fetch;
        window.fetch = function(input) {
          const url = (input instanceof Request) ? input.url : input;
          processM3U8Url(url);
          return originalFetch.apply(this, arguments)
            .then(response => {
              if (response.headers.get('content-type')?.includes('application/json')) {
                response.clone().json()
                  .then(data => {
                    JSON.stringify(data).split('"').forEach(processM3U8Url);
                  })
                  .catch(e => console.error('解析Fetch响应JSON失败:', e));
              }
              return response;
            });
        };
        
        // 拦截WebSocket
        const originalWebSocket = window.WebSocket;
        window.WebSocket = function(url, protocols) {
          processM3U8Url(url);
          const ws = new originalWebSocket(url, protocols);
          
          // 监听WebSocket消息
          const originalOnMessage = ws.onmessage;
          ws.onmessage = function(event) {
            try {
              if (typeof event.data === 'string') {
                // 尝试解析JSON
                try {
                  const jsonData = JSON.parse(event.data);
                  JSON.stringify(jsonData).split('"').forEach(processM3U8Url);
                } catch(e) {
                  // 如果不是JSON，直接检查字符串
                  processM3U8Url(event.data);
                }
              }
            } catch(e) {
              console.error('处理WebSocket消息时出错:', e);
            }
            
            // 调用原始的onmessage处理器
            if (originalOnMessage) {
              originalOnMessage.apply(this, arguments);
            }
          };
          
          return ws;
        };
        
        // 监听视频元素
        function checkVideoSources() {
          document.querySelectorAll('video,source').forEach(element => {
            processM3U8Url(element.src);
            processM3U8Url(element.dataset.src);
          });
        }
        
        // DOM监视器
        new MutationObserver(() => {
          checkVideoSources();
        }).observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src', 'data-src']
        });
        
        // 定期检查
        const checkInterval = setInterval(() => {
          checkVideoSources();
          if (processedUrls.size > 0) {
            console.log('找到m3u8地址，停止定期检查');
            clearInterval(checkInterval);
          }
        }, 1000);
        
        console.log('m3u8检测器初始化完成');
        // 初始检查
        checkVideoSources();
      })();
    ''';
    
    try {
      _controller.evaluateJavascript(jsCode).then((_) {
        LogUtil.i('JS代码注入成功');
      }).catchError((error) {
        LogUtil.e('JS代码注入失败: $error');
      });
    } catch (e, stackTrace) {
      LogUtil.logError('执行JS代码时发生错误', e, stackTrace);
    }
  }
}
