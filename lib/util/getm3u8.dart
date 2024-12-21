import 'dart:async';
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
    this.timeoutSeconds = 30,
  }) : super(key: key);

  @override
  State<GetM3U8> createState() => _GetM3U8State();
}

class _GetM3U8State extends State<GetM3U8> {
  late WebViewController _controller;
  bool _m3u8Found = false;
  Set<String> _foundUrls = {};
  Timer? _periodicInjectionTimer;
  Timer? _periodicCheckTimer;
  
  @override
  void initState() {
    super.initState();
    LogUtil.i('GetM3U8初始化开始，目标URL: ${widget.url}');
    _initController();
    _startTimeout();
  }

  void _initController() {
    LogUtil.i('开始初始化WebViewController');
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
        ..addJavaScriptChannel(
          'M3U8Detector',
          onMessageReceived: (message) {
            LogUtil.i('JS检测器发现新的URL: ${message.message}');
            _handleM3U8Found(message.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              LogUtil.i('页面导航请求: ${request.url}');
              return NavigationDecision.navigate;
            },
            onPageStarted: (String url) {
              LogUtil.i('页面开始加载: $url');
            },
            onProgress: (int progress) {
              LogUtil.i('页面加载进度: $progress%');
            },
            onPageFinished: (String url) {
              LogUtil.i('页面加载完成: $url');
              _setupPeriodicTasks();
              _injectM3U8Detector();
            },
            onWebResourceError: (WebResourceError error) {
              LogUtil.e('WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
            },
          ),
        );

      _loadUrlWithHeaders();
      LogUtil.i('WebViewController初始化完成');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化WebViewController时发生错误', e, stackTrace);
    }
  }

  void _loadUrlWithHeaders() {
    LogUtil.i('准备加载URL，添加自定义headers');
    try {
      final Map<String, String> headers = {
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Referer': Uri.parse(widget.url).origin,
        'Pragma': 'no-cache',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
      };
      
      LogUtil.i('设置的headers: $headers');
      _controller.loadRequest(Uri.parse(widget.url), headers: headers);
      LogUtil.i('URL加载请求已发送');
    } catch (e, stackTrace) {
      LogUtil.logError('加载URL时发生错误', e, stackTrace);
    }
  }

  void _setupPeriodicTasks() {
    LogUtil.i('设置定期任务');
    // 取消现有的定时器
    _periodicInjectionTimer?.cancel();
    _periodicCheckTimer?.cancel();

    // 定期重新注入检测器
    _periodicInjectionTimer = Timer.periodic(
      const Duration(seconds: 2),
      (timer) {
        if (!_m3u8Found && mounted) {
          LogUtil.i('定期重新注入M3U8检测器');
          _injectM3U8Detector();
        } else {
          LogUtil.i('停止定期注入，原因: ${_m3u8Found ? 'M3U8已找到' : '组件已卸载'}');
          timer.cancel();
        }
      },
    );

    // 定期检查页面状态
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!_m3u8Found && mounted) {
          _checkPageStatus();
        } else {
          timer.cancel();
        }
      },
    );
  }

  void _checkPageStatus() async {
    LogUtil.i('开始检查页面状态');
    try {
      final videoCount = await _controller.runJavaScriptReturningResult(
        'document.querySelectorAll("video").length'
      );
      LogUtil.i('页面中发现 $videoCount 个视频元素');

      final iframeCount = await _controller.runJavaScriptReturningResult(
        'document.querySelectorAll("iframe").length'
      );
      LogUtil.i('页面中发现 $iframeCount 个iframe元素');
    } catch (e, stackTrace) {
      LogUtil.logError('检查页面状态时发生错误', e, stackTrace);
    }
  }

  void _startTimeout() {
    LogUtil.i('开始超时计时: ${widget.timeoutSeconds}秒');
    Future.delayed(Duration(seconds: widget.timeoutSeconds), () {
      if (mounted && !_m3u8Found) {
        LogUtil.i('GetM3U8提取超时，未找到有效的m3u8地址');
        widget.onM3U8Found('');
        _disposeResources();
      }
    });
  }

  void _handleM3U8Found(String url) {
    LogUtil.i('处理发现的URL: $url');
    if (!_m3u8Found && url.isNotEmpty && !_foundUrls.contains(url)) {
      LogUtil.i('发现新的未处理URL');
      _foundUrls.add(url);
      
      if (_isValidM3U8Url(url)) {
        LogUtil.i('URL验证通过，标记为有效的m3u8地址');
        _m3u8Found = true;
        widget.onM3U8Found(url);
        _disposeResources();
      } else {
        LogUtil.i('URL验证失败，不是有效的m3u8地址');
      }
    }
  }

  bool _isValidM3U8Url(String url) {
    LogUtil.i('开始验证URL: $url');
    
    // 验证URL是否为有效格式
    final validUrl = Uri.tryParse(url);
    if (validUrl == null) {
      LogUtil.i('无效的URL格式');
      return false;
    }
    
    // 检查文件扩展名
    if (!url.toLowerCase().contains('.m3u8')) {
      LogUtil.i('URL不包含.m3u8扩展名');
      return false;
    }
    
    // 检查是否为完整URL
    if (!url.startsWith('http')) {
      LogUtil.i('URL不是以http开头的完整地址');
      return false;
    }
    
    LogUtil.i('URL验证通过');
    return true;
  }

  void _disposeResources() {
    LogUtil.i('开始释放资源');
    _periodicInjectionTimer?.cancel();
    _periodicCheckTimer?.cancel();
    if (mounted) {
      setState(() {});
    }
    LogUtil.i('资源释放完成');
  }

  @override
  void dispose() {
    LogUtil.i('GetM3U8组件开始销毁');
    _disposeResources();
    super.dispose();
    LogUtil.i('GetM3U8组件销毁完成');
  }

  @override
  Widget build(BuildContext context) {
    if (_m3u8Found) {
      LogUtil.i('已找到m3u8，返回空组件');
      return const SizedBox.shrink();
    }

    LogUtil.i('构建WebView组件');
    return WebViewWidget(controller: _controller);
  }

  void _injectM3U8Detector() {
    LogUtil.i('开始注入m3u8检测器JS代码');
    const jsCode = '''
      (function() {
        console.log('M3U8检测器开始初始化');
        
        // 已处理的URL缓存
        const processedUrls = new Set();
        
        // URL处理函数
        function processM3U8Url(url) {
          console.log('处理URL:', url);
          
          if (!url || typeof url !== 'string') {
            console.log('无效URL，跳过处理');
            return;
          }
          
          // 标准化URL
          try {
            url = new URL(url, window.location.href).href;
            console.log('标准化后的URL:', url);
          } catch(e) {
            console.error('URL标准化失败:', e);
            return;
          }
          
          // 处理加密的URL
          try {
            const decodedUrl = decodeURIComponent(url);
            if (decodedUrl !== url) {
              console.log('发现编码的URL，解码后:', decodedUrl);
              processM3U8Url(decodedUrl);
            }
          } catch(e) {
            console.error('URL解码失败:', e);
          }
          
          // 处理base64编码的URL
          try {
            if (url.includes('base64,')) {
              console.log('发现Base64编码的内容');
              const base64Content = url.split('base64,')[1];
              const decodedContent = atob(base64Content);
              if (decodedContent.includes('.m3u8')) {
                console.log('Base64解码后发现m3u8 URL');
                processM3U8Url(decodedContent);
              }
            }
          } catch(e) {
            console.error('Base64解码失败:', e);
          }
          
          if (url.includes('.m3u8') && !processedUrls.has(url)) {
            console.log('发现新的m3u8 URL，添加到已处理集合');
            processedUrls.add(url);
            console.log('向Flutter发送m3u8 URL');
            window.M3U8Detector.postMessage(url);
          }
        }

        // 监控媒体源扩展
        if (window.MediaSource) {
          console.log('设置MediaSource监控');
          const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
          MediaSource.prototype.addSourceBuffer = function(mimeType) {
            console.log('MediaSource添加源缓冲区:', mimeType);
            return originalAddSourceBuffer.call(this, mimeType);
          };
        }
        
        // 拦截XHR请求
        console.log('设置XHR请求拦截');
        const XHR = XMLHttpRequest.prototype;
        const originalOpen = XHR.open;
        const originalSend = XHR.send;
        
        XHR.open = function() {
          this._url = arguments[1];
          console.log('XHR打开连接:', this._url);
          return originalOpen.apply(this, arguments);
        };
        
        XHR.send = function() {
          console.log('XHR发送请求');
          const xhr = this;
          xhr.addEventListener('load', function() {
            console.log('XHR请求完成');
            processM3U8Url(xhr._url);
            
            if (xhr.responseType === '' || xhr.responseType === 'text') {
              console.log('检查XHR响应内容');
              processM3U8Url(xhr.responseText);
            }
            
            try {
              const contentType = xhr.getResponseHeader('content-type');
              if (contentType && contentType.includes('application/json')) {
                console.log('处理JSON响应');
                const response = JSON.parse(xhr.responseText);
                JSON.stringify(response).split('"').forEach(processM3U8Url);
              }
            } catch(e) {
              console.error('处理XHR响应时出错:', e);
            }
          });
          return originalSend.apply(this, arguments);
        };
        
        // 拦截Fetch请求
        console.log('设置Fetch请求拦截');
        const originalFetch = window.fetch;
        window.fetch = function(input) {
          const url = (input instanceof Request) ? input.url : input;
          console.log('拦截到Fetch请求:', url);
          processM3U8Url(url);
          return originalFetch.apply(this, arguments)
            .then(response => {
              console.log('Fetch请求完成');
              if (response.headers.get('content-type')?.includes('application/json')) {
                console.log('处理Fetch JSON响应');
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
        console.log('设置WebSocket拦截');
        const originalWebSocket = window.WebSocket;
        window.WebSocket = function(url, protocols) {
          console.log('创建WebSocket连接:', url);
          processM3U8Url(url);
          const ws = new originalWebSocket(url, protocols);
          
          const originalOnMessage = ws.onmessage;
          ws.onmessage = function(event) {
            console.log('接收到WebSocket消息');
            try {
              if (typeof event.data === 'string') {
                console.log('处理WebSocket文本消息');
                try {
                  const jsonData = JSON.parse(event.data);
                  console.log('解析WebSocket JSON数据');
                  JSON.stringify(jsonData).split('"').forEach(processM3U8Url);
                } catch(e) {
                  console.log('WebSocket消息不是JSON格式,直接处理文本');
                  processM3U8Url(event.data);
                }
              }
            } catch(e) {
              console.error('处理WebSocket消息时出错:', e);
            }
            
            if (originalOnMessage) {
              originalOnMessage.apply(this, arguments);
            }
          };
          
          return ws;
        };
        
        // 监视视频元素
        function checkMediaElements(doc = document) {
          console.log('开始检查媒体元素');
          doc.querySelectorAll('video,audio,source').forEach(element => {
            console.log('检查媒体元素:', element.tagName);
            const sources = [
              element.src,
              element.currentSrc,
              element.dataset.src,
              element.getAttribute('src'),
              element.querySelector('source')?.src
            ];
            
            sources.forEach(src => {
              if (src) {
                console.log('处理媒体元素源:', src);
                processM3U8Url(src);
              }
            });
            
            // 监控源变化
            const observer = new MutationObserver((mutations) => {
              mutations.forEach((mutation) => {
                if (mutation.type === 'attributes') {
                  console.log('媒体元素属性变化:', mutation.attributeName);
                  processM3U8Url(element[mutation.attributeName]);
                }
              });
            });
            
            observer.observe(element, {
              attributes: true,
              attributeFilter: ['src', 'currentSrc']
            });
          });
        }
        
        // 深度扫描DOM
        function deepScanDOM() {
          console.log('开始深度扫描DOM');
          document.querySelectorAll('*').forEach(element => {
            Array.from(element.attributes).forEach(attr => {
              if (attr.value && typeof attr.value === 'string') {
                processM3U8Url(attr.value);
              }
            });
          });
        }
        
        // 监控DOM变化
        console.log('设置DOM变化监视器');
        new MutationObserver((mutations) => {
          mutations.forEach((mutation) => {
            mutation.addedNodes.forEach((node) => {
              if (node.nodeType === 1) { // ELEMENT_NODE
                console.log('新增DOM元素:', node.tagName);
                if (node.tagName === 'IFRAME') {
                  try {
                    console.log('处理iframe内容');
                    const iframeDoc = node.contentDocument || node.contentWindow?.document;
                    if (iframeDoc) {
                      checkMediaElements(iframeDoc);
                    }
                  } catch (e) {
                    console.error('无法访问iframe内容:', e);
                  }
                }
                // 检查新添加元素的所有属性
                if (node instanceof Element) {
                  Array.from(node.attributes).forEach(attr => {
                    processM3U8Url(attr.value);
                  });
                }
              }
            });
          });
        }).observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true
        });
        
        // 设置定期检查
        console.log('设置定期检查任务');
        const checkInterval = setInterval(() => {
          console.log('执行定期检查');
          checkMediaElements();
          deepScanDOM();
          
          if (processedUrls.size > 0) {
            console.log('找到m3u8地址，停止定期检查');
            clearInterval(checkInterval);
          }
        }, 1000);
        
        // 初始检查
        console.log('执行初始检查');
        checkMediaElements();
        deepScanDOM();
        
        // 监听数据层变化
        console.log('设置数据层监听');
        let lastPush = window.history.pushState;
        let lastReplace = window.history.replaceState;
        
        window.history.pushState = function() {
          console.log('检测到pushState事件');
          setTimeout(checkMediaElements, 100);
          return lastPush.apply(this, arguments);
        };
        
        window.history.replaceState = function() {
          console.log('检测到replaceState事件');
          setTimeout(checkMediaElements, 100);
          return lastReplace.apply(this, arguments);
        };
        
        // 监听URL变化
        window.addEventListener('popstate', function() {
          console.log('检测到popstate事件');
          setTimeout(checkMediaElements, 100);
        });
        
        // 监听hash变化
        window.addEventListener('hashchange', function() {
          console.log('检测到hashchange事件');
          setTimeout(checkMediaElements, 100);
        });
        
        console.log('M3U8检测器初始化完成');
      })();
    ''';
    
    try {
      LogUtil.i('执行JS代码注入');
      _controller.runJavaScript(jsCode).then((_) {
        LogUtil.i('JS代码注入成功');
      }).catchError((error) {
        LogUtil.e('JS代码注入失败: $error');
      });
    } catch (e, stackTrace) {
      LogUtil.logError('执行JS代码时发生错误', e, stackTrace);
    }
  }
}
