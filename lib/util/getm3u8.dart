import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:itvapp_live_tv/util/log_util.dart';

/// M3U8地址获取类
/// 用于从网页中提取M3U8视频流地址
class GetM3U8 {
  /// 目标URL
  final String url;
  
  /// 超时时间(秒)
  final int timeoutSeconds;
  
  /// WebView控制器
  late WebViewController _controller;
  
  /// 是否已找到M3U8
  bool _m3u8Found = false;
  
  /// 已发现的URL集合
  final Set<String> _foundUrls = {};
  
  /// 定期检查定时器
  Timer? _periodicCheckTimer;
  
  /// 重试计数器
  int _retryCount = 0;
  
  /// 最大重试次数
  static const int MAX_RETRIES = 3;
  
  /// 检查间隔(秒)
  static const int CHECK_INTERVAL = 3;
  
  /// 是否已释放资源
  bool _isDisposed = false;

  /// 构造函数
  GetM3U8({
    required this.url,
    this.timeoutSeconds = 30,
  });

  /// 获取M3U8地址
  /// 返回找到的第一个有效M3U8地址，如果未找到返回空字符串
  Future<String> getUrl() async {
    final completer = Completer<String>();
    
    LogUtil.i('GetM3U8初始化开始，目标URL: $url');
    try {
      await _initController(completer);
      _startTimeout(completer);
    } catch (e, stackTrace) {
      LogUtil.logError('初始化过程发生错误', e, stackTrace);
      completer.complete('');
    }
    
    return completer.future;
  }

  /// 初始化WebViewController
  Future<void> _initController(Completer<String> completer) async {
    LogUtil.i('开始初始化WebViewController');
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
        ..addJavaScriptChannel(
          'M3U8Detector',
          onMessageReceived: (JavaScriptMessage message) {
            LogUtil.i('JS检测器发现新的URL: ${message.message}');
            _handleM3U8Found(message.message, completer);
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
              _setupPeriodicCheck();
              _injectM3U8Detector();
            },
            onWebResourceError: (WebResourceError error) {
              LogUtil.e('WebView加载错误: ${error.description}, 错误码: ${error.errorCode}');
              _handleLoadError(completer);
            },
          ),
        );

      await _loadUrlWithHeaders();
      LogUtil.i('WebViewController初始化完成');
    } catch (e, stackTrace) {
      LogUtil.logError('初始化WebViewController时发生错误', e, stackTrace);
      _handleLoadError(completer);
    }
  }

  /// 处理加载错误
  void _handleLoadError(Completer<String> completer) {
    if (_retryCount < MAX_RETRIES && !_isDisposed) {
      _retryCount++;
      LogUtil.i('尝试重试 ($_retryCount/$MAX_RETRIES)');
      Future.delayed(Duration(seconds: 1), () {
        _initController(completer);
      });
    } else if (!completer.isCompleted) {
      LogUtil.e('达到最大重试次数或已释放资源');
      completer.complete('');
      disposeResources();
    }
  }

  /// 加载URL并设置headers
  Future<void> _loadUrlWithHeaders() async {
    LogUtil.i('准备加载URL，添加自定义headers');
    try {
      final Map<String, String> headers = {
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Referer': Uri.parse(url).origin,
        'Pragma': 'no-cache',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
      };
      
      LogUtil.i('设置的headers: $headers');
      await _controller.loadRequest(Uri.parse(url), headers: headers);
      LogUtil.i('URL加载请求已发送');
    } catch (e, stackTrace) {
      LogUtil.logError('加载URL时发生错误', e, stackTrace);
      rethrow;
    }
  }
  
  /// 设置定期检查
  void _setupPeriodicCheck() {
    LogUtil.i('设置定期检查任务');
    // 取消现有定时器
    _periodicCheckTimer?.cancel();

    // 创建新的定期检查定时器
    _periodicCheckTimer = Timer.periodic(
      Duration(seconds: CHECK_INTERVAL),
      (timer) {
        if (!_m3u8Found && !_isDisposed) {
          LogUtil.i('执行定期检查');
          _injectM3U8Detector();
        } else {
          LogUtil.i('停止定期检查，原因: ${_m3u8Found ? 'M3U8已找到' : '已释放资源'}');
          timer.cancel();
        }
      },
    );
  }

  /// 启动超时计时器
  void _startTimeout(Completer<String> completer) {
    LogUtil.i('开始超时计时: ${timeoutSeconds}秒');
    Future.delayed(Duration(seconds: timeoutSeconds), () {
      if (!_isDisposed && !_m3u8Found) {
        LogUtil.i('GetM3U8提取超时，未找到有效的m3u8地址');
        if (!completer.isCompleted) {
          completer.complete('');
        }
        disposeResources();
      }
    });
  }

  /// 处理发现的M3U8 URL
  void _handleM3U8Found(String url, Completer<String> completer) {
    LogUtil.i('处理发现的URL: $url');
    if (!_m3u8Found && url.isNotEmpty && !_foundUrls.contains(url)) {
      LogUtil.i('发现新的未处理URL');
      _foundUrls.add(url);
      
      if (_isValidM3U8Url(url)) {
        LogUtil.i('URL验证通过，标记为有效的m3u8地址');
        _m3u8Found = true;
        if (!completer.isCompleted) {
          completer.complete(url);
        }
        disposeResources();
      } else {
        LogUtil.i('URL验证失败，不是有效的m3u8地址');
      }
    }
  }

  /// 验证M3U8 URL是否有效
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

  /// 释放资源
  void disposeResources() {
    LogUtil.i('开始释放资源');
    _isDisposed = true;
    _periodicCheckTimer?.cancel();
    
    // 清理JavaScript检测器
    try {
      _controller.runJavaScript('if(window._cleanupM3U8Detector) window._cleanupM3U8Detector();');
    } catch (e) {
      LogUtil.e('清理JavaScript检测器时发生错误: $e');
    }
    
    LogUtil.i('资源释放完成');
  }
  
  /// 注入M3U8检测器的JavaScript代码
  void _injectM3U8Detector() {
    LogUtil.i('开始注入m3u8检测器JS代码');
    const jsCode = '''
      (function() {
        // 避免重复初始化
        if (window._m3u8DetectorInitialized) {
          console.log('M3U8检测器已初始化，跳过');
          return;
        }
        console.log('M3U8检测器开始初始化');
        window._m3u8DetectorInitialized = true;
        
        // 已处理的URL缓存
        const processedUrls = new Set();
        
        // 全局变量
        let observer = null;
        const MAX_RECURSION_DEPTH = 3;
        
        // URL处理函数
        function processM3U8Url(url, depth = 0) {
          console.log('处理URL:', url, '当前深度:', depth);
          
          if (!url || typeof url !== 'string') {
            console.log('无效URL，跳过处理');
            return;
          }
          
          if (depth > MAX_RECURSION_DEPTH) {
            console.log('达到最大递归深度，停止处理');
            return;
          }
          
          if (processedUrls.has(url)) {
            console.log('URL已处理过，跳过');
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
              processM3U8Url(decodedUrl, depth + 1);
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
                processM3U8Url(decodedContent, depth + 1);
              }
            }
          } catch(e) {
            console.error('Base64解码失败:', e);
          }
          
          if (url.includes('.m3u8')) {
            console.log('发现m3u8 URL，添加到已处理集合');
            processedUrls.add(url);
            console.log('向Flutter发送m3u8 URL');
            window.M3U8Detector.postMessage(url);
          }
        }

        // 监控MediaSource
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
        XHR.open = function() {
          this._url = arguments[1];
          console.log('XHR打开连接:', this._url);
          return originalOpen.apply(this, arguments);
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
        
        // 检查媒体元素
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
            const elementObserver = new MutationObserver((mutations) => {
              mutations.forEach((mutation) => {
                if (mutation.type === 'attributes') {
                  console.log('媒体元素属性变化:', mutation.attributeName);
                  processM3U8Url(element[mutation.attributeName]);
                }
              });
            });
            
            elementObserver.observe(element, {
              attributes: true,
              attributeFilter: ['src', 'currentSrc']
            });
          });
        }
        
        // 高效的DOM扫描
        function efficientDOMScan() {
          console.log('开始高效DOM扫描');
          // 使用选择器直接查找可能包含m3u8的元素
          const elements = document.querySelectorAll([
            'a[href*="m3u8"]',
            'source[src*="m3u8"]',
            'video[src*="m3u8"]',
            'div[data-src*="m3u8"]',
            'iframe[src*="m3u8"]'
          ].join(','));
          
          elements.forEach(element => {
            const url = element.href || element.src || element.dataset.src;
            if (url) {
              console.log('从元素中发现可能的m3u8 URL:', url);
              processM3U8Url(url);
            }
          });
        }
        
        // 处理iframe
        function handleIframe(iframe) {
          try {
            console.log('处理iframe:', iframe.src);
            const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document;
            if (iframeDoc) {
              checkMediaElements(iframeDoc);
              efficientDOMScan();
            }
          } catch (e) {
            console.error('无法访问iframe内容:', e);
          }
        }
        
        // 设置DOM观察器
        observer = new MutationObserver((mutations) => {
          mutations.forEach((mutation) => {
            // 处理新添加的节点
            mutation.addedNodes.forEach((node) => {
              if (node.nodeType === 1) { // ELEMENT_NODE
                console.log('新增DOM元素:', node.tagName);
                
                // 处理iframe
                if (node.tagName === 'IFRAME') {
                  handleIframe(node);
                }
                
                // 检查新添加元素的所有属性
                if (node instanceof Element) {
                  Array.from(node.attributes).forEach(attr => {
                    processM3U8Url(attr.value);
                  });
                }
              }
            });

            // 处理属性变化
            if (mutation.type === 'attributes') {
              processM3U8Url(mutation.target.getAttribute(mutation.attributeName));
            }
          });
        });
        
        // 启动观察器
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src', 'href', 'data-src']
        });
        
        // 处理现有iframe
        document.querySelectorAll('iframe').forEach(handleIframe);
        
        // 初始检查
        console.log('执行初始检查');
        checkMediaElements();
        efficientDOMScan();
        
        // 监听URL变化
        window.addEventListener('popstate', function() {
          console.log('检测到popstate事件');
          setTimeout(() => {
            checkMediaElements();
            efficientDOMScan();
          }, 100);
        });
        
        // 监听hash变化
        window.addEventListener('hashchange', function() {
          console.log('检测到hashchange事件');
          setTimeout(() => {
            checkMediaElements();
            efficientDOMScan();
          }, 100);
        });
        
        // 清理函数
        window._cleanupM3U8Detector = function() {
          console.log('执行M3U8检测器清理');
          if (observer) {
            observer.disconnect();
          }
          
          // 恢复原始的fetch函数
          if (originalFetch) {
            window.fetch = originalFetch;
          }
          
          // 清理事件监听器
          window.removeEventListener('popstate', checkMediaElements);
          window.removeEventListener('hashchange', checkMediaElements);
          
          // 移除初始化标记
          delete window._m3u8DetectorInitialized;
          
          console.log('M3U8检测器清理完成');
        };
        
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
