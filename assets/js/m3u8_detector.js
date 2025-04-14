// 流媒体地址检测注入
(function() {
  // 避免重复初始化，确保脚本只执行一次
  if (window._itvapp_m3u8_detector_initialized) return;
  window._itvapp_m3u8_detector_initialized = true;

  // 保存原始函数引用
  const _original = {
    XHR: {
      open: XMLHttpRequest.prototype.open,
      send: XMLHttpRequest.prototype.send
    },
    fetch: window.fetch,
    MediaSourceAddBuffer: window.MediaSource ? 
      MediaSource.prototype.addSourceBuffer : null,
    addEventListener: window.addEventListener,
    removeEventListener: window.removeEventListener
  };

  // 初始化状态：跟踪已处理URL和最大递归深度
  const processedUrls = new Set(); // 存储已处理的URL，避免重复
  const MAX_RECURSION_DEPTH = 3; // 限制递归深度，防止无限循环
  let observer = null; // DOM变化观察器实例
  const filePattern = 'FILE_PATTERN'; // 统一处理文件模式替换，增强安全性
  
  // URL处理工具：负责URL标准化和检测
  const VideoUrlProcessor = {
    processUrl(url, depth = 0) { // 处理URL并检测流媒体格式
      if (!url || typeof url !== 'string' || 
          depth > MAX_RECURSION_DEPTH || 
          processedUrls.has(url)) return; // 跳过无效或重复URL

      // URL标准化，确保格式一致
      url = this.normalizeUrl(url);
      
      processedUrls.add(url); // 标记为已处理，提前添加避免在回调前重复处理
      
      // 检查是否包含特定文件模式（由Dart动态替换）
      if (url.includes('.' + filePattern)) {
        // 使用异步方式发送消息，避免阻塞主流程
        setTimeout(() => {
          if (window.M3U8Detector) {
            window.M3U8Detector.postMessage(url);
          }
        }, 0);
      }
    },

    normalizeUrl(url) { // 将相对URL转换为绝对URL
      try {
        if (url.startsWith('/')) { // 处理根路径URL
          const baseUrl = new URL(window.location.href);
          return baseUrl.protocol + '//' + baseUrl.host + url;
        }
        if (!url.startsWith('http')) { // 处理相对路径URL
          return new URL(url, window.location.href).toString();
        }
        return url; // 返回原始URL（已是绝对路径）
      } catch (e) {
        // 处理无效URL
        return url;
      }
    }
  };

  // 网络请求拦截器：捕获网络请求中的流媒体URL
  const NetworkInterceptor = {
    setupXHRInterceptor() { // 拦截XMLHttpRequest请求
      // 安全地修改XHR.open方法，保留原始功能
      XMLHttpRequest.prototype.open = function() {
        // 存储URL以供后续检查
        this._itvapp_url = arguments[1];
        // 调用原始方法，保持原有行为不变
        return _original.XHR.open.apply(this, arguments);
      };

      XMLHttpRequest.prototype.send = function() {
        // 异步处理URL检测，不干扰原始请求
        if (this._itvapp_url) {
          setTimeout(() => {
            VideoUrlProcessor.processUrl(this._itvapp_url, 0);
          }, 0);
        }
        // 调用原始方法，保持原有行为不变
        return _original.XHR.send.apply(this, arguments);
      };
    },

    setupFetchInterceptor() { // 拦截fetch请求
      window.fetch = function(input) {
        // 异步处理URL检测，不干扰原始请求
        setTimeout(() => {
          try {
            const url = (input instanceof Request) ? input.url : input;
            VideoUrlProcessor.processUrl(url, 0);
          } catch (e) {
            // 忽略错误，确保不影响原始fetch功能
          }
        }, 0);
        
        // 调用原始方法，保持原有行为不变
        return _original.fetch.apply(this, arguments);
      };
    },

    setupMediaSourceInterceptor() { // 拦截MediaSource流媒体
      if (!window.MediaSource || !_original.MediaSourceAddBuffer) return; // 浏览器不支持MediaSource则跳过

      MediaSource.prototype.addSourceBuffer = function(mimeType) {
        // 异步处理MIME类型检测，不干扰原始功能
        setTimeout(() => {
          try {
            const supportedTypes = { // 支持的流媒体MIME类型
              'm3u8': ['application/x-mpegURL', 'application/vnd.apple.mpegURL'],
              'flv': ['video/x-flv', 'application/x-flv', 'flv-application/octet-stream'],
              'mp4': ['video/mp4', 'application/mp4']
            };
    
            const currentTypes = supportedTypes[filePattern] || []; // 获取当前检测类型
            if (currentTypes.some(type => mimeType.includes(type))) { // 检查MIME类型
              const url = this.url || window.location.href; // 使用当前页面URL作为回退
              VideoUrlProcessor.processUrl(url, 0);
            }
          } catch (e) {
            // 忽略错误，确保不影响原始功能
          }
        }, 0);
        
        // 调用原始方法，保持原有行为不变
        return _original.MediaSourceAddBuffer.call(this, mimeType);
      };
    }
  };

  // DOM扫描器：扫描页面元素中的流媒体URL
  const DOMScanner = {
    // 使用WeakSet存储已处理元素，避免内存泄漏
    processedElements: new WeakSet(), 

    scanAttributes(element) { // 扫描元素属性中的URL
      try {
        for (const attr of element.attributes) {
          if (attr.value) VideoUrlProcessor.processUrl(attr.value, 0);
        }
      } catch (e) {
        // 忽略错误，确保不影响页面
      }
    },

    scanMediaElement(element) { // 扫描视频相关元素的URL
      try {
        if (element.tagName === 'VIDEO') {
          // 使用短路运算符和可选链简化逻辑
          element.src && VideoUrlProcessor.processUrl(element.src, 0);
          element.currentSrc && VideoUrlProcessor.processUrl(element.currentSrc, 0);

          element.querySelectorAll('source').forEach(source => { // 检查source标签
            const src = source.src || source.getAttribute('src');
            if (src) VideoUrlProcessor.processUrl(src, 0);
          });
        }
      } catch (e) {
        // 忽略错误，确保不影响页面
      }
    },

    scanPage(root = document) { // 扫描整个页面中的流媒体元素
      try {
        const selector = [ // 定义目标元素的选择器
          'video', 'source', '[class*="video"]', '[class*="player"]',
          `[class*="${filePattern}"]`, `[data-${filePattern}]`,
          `a[href*="${filePattern}"]`, `[data-src*="${filePattern}"]`
        ].join(',');

        root.querySelectorAll(selector).forEach(element => {
          if (this.processedElements.has(element)) return; // 跳过已处理元素
          this.processedElements.add(element);

          this.scanAttributes(element); // 检查属性
          this.scanMediaElement(element); // 检查媒体元素
        });

        this.scanScripts(); // 扫描脚本中的URL
      } catch (e) {
        // 防止选择器错误导致整个扫描失败
        console.error('DOM扫描失败:', e);
      }
    },

    scanScripts() { // 扫描内联脚本中的流媒体URL
      try {
        document.querySelectorAll('script:not([src])').forEach(script => {
          if (!script.textContent) return; // 跳过空脚本
          
          const pattern = '\\.' + filePattern; // 定义检测模式
          // 使用更稳定的正则表达式
          try {
            const regex = new RegExp(`https?://[^\\s'"]*${pattern}[^\\s'"]*`, 'g'); // URL匹配正则
            let match;
            
            // 使用字符串匹配提取URL
            const content = script.textContent;
            while ((match = regex.exec(content)) !== null) { // 提取匹配的URL
              VideoUrlProcessor.processUrl(match[0], 0);
            }
          } catch (regexError) {
            // 正则表达式可能在某些浏览器中不支持，使用简单字符串搜索作为备选
            const content = script.textContent;
            const index = content.indexOf('.' + filePattern);
            if (index > 0) {
              // 简单提取可能的URL
              const start = content.lastIndexOf('http', index);
              if (start >= 0) {
                const end = content.indexOf('"', index);
                const end2 = content.indexOf("'", index);
                const validEnd = end > 0 ? (end2 > 0 ? Math.min(end, end2) : end) : (end2 > 0 ? end2 : content.length);
                if (validEnd > start) {
                  const possibleUrl = content.substring(start, validEnd);
                  VideoUrlProcessor.processUrl(possibleUrl, 0);
                }
              }
            }
          }
        });
      } catch (e) {
        // 防止脚本扫描失败
        console.error('脚本扫描失败:', e);
      }
    }
  };

  // 初始化检测器：设置拦截和观察机制
  function initializeDetector() {
    // 设置网络拦截器 - 使用异步方式安全地设置
    setTimeout(() => {
      try {
        NetworkInterceptor.setupXHRInterceptor(); // 拦截XHR请求
        NetworkInterceptor.setupFetchInterceptor(); // 拦截fetch请求
        NetworkInterceptor.setupMediaSourceInterceptor(); // 拦截MediaSource
      } catch (e) {
        console.error('设置网络拦截器失败:', e);
      }
    }, 0);

    // 设置DOM变化观察器
    let debounceTimer = null; // 防抖定时器

    // 存储事件处理函数引用，确保清理时可正确移除
    const urlChangeHandler = () => { 
      // 使用防抖优化性能
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        DOMScanner.scanPage(document);
      }, 150);
    };
    
    // 存储处理器引用
    window._itvapp_detector_handlers = {
      urlChange: urlChangeHandler
    };

    // 使用原始addEventListener方法添加监听器
    _original.addEventListener.call(window, 'popstate', urlChangeHandler);
    _original.addEventListener.call(window, 'hashchange', urlChangeHandler);

    // 安全地设置MutationObserver
    try {
      observer = new MutationObserver(mutations => { // 监听DOM变化
        // 使用防抖优化性能
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => {
          const processQueue = new Set(); // 待处理队列
  
          mutations.forEach(mutation => { // 处理每个变化
            if (mutation.type === 'childList') {
              mutation.addedNodes.forEach(node => { // 检查新增节点
                if (node.nodeType === 1) { // 元素节点
                  if (node.matches && node.matches('video,source,[class*="video"],[class*="player"]')) {
                    processQueue.add(node);
                  }
                  if (node instanceof Element) {
                    for (const attr of node.attributes) { // 检查属性值
                      if (attr.value && typeof attr.value === 'string' && attr.value.includes('.' + filePattern)) {
                        processQueue.add(attr.value);
                      }
                    }
                  }
                }
              });
            }
  
            if (mutation.type === 'attributes') { // 处理属性变化
              const newValue = mutation.target.getAttribute(mutation.attributeName);
              if (newValue && typeof newValue === 'string' && newValue.includes('.' + filePattern)) {
                processQueue.add(newValue);
              }
            }
          });
  
          // 使用requestIdleCallback或setTimeout处理队列
          if (typeof requestIdleCallback === 'function') {
            requestIdleCallback(() => {
              processQueueItems(processQueue);
            }, { timeout: 1000 });
          } else {
            setTimeout(() => {
              processQueueItems(processQueue);
            }, 50);
          }
        }, 150); // 150ms防抖间隔
      });
  
      // 抽取队列处理逻辑为独立函数
      function processQueueItems(queue) {
        queue.forEach(item => {
          try {
            if (typeof item === 'string') {
              VideoUrlProcessor.processUrl(item, 0);
            } else if (item && item.parentNode) {
              // 局部扫描而不是整个文档
              const parent = item.parentNode instanceof Element ? item.parentNode : document.body;
              DOMScanner.scanPage(parent || document.body);
            }
          } catch (e) {
            // 忽略错误，确保处理继续
          }
        });
      }
  
      // 仅观察文档主体，减少不必要的通知
      if (document.body) {
        observer.observe(document.body, {
          childList: true, subtree: true, attributes: true
        });
      } else {
        // 文档尚未加载完成，等待body可用
        document.addEventListener('DOMContentLoaded', () => {
          if (document.body) {
            observer.observe(document.body, {
              childList: true, subtree: true, attributes: true
            });
          }
        });
      }
    } catch (e) {
      console.error('设置MutationObserver失败:', e);
    }

    // 初始页面扫描 - 使用异步方式避免阻塞页面加载
    setTimeout(() => {
      try {
        DOMScanner.scanPage(document);
      } catch (e) {
        console.error('初始页面扫描失败:', e);
      }
    }, 100);
  }

  // 执行初始化
  initializeDetector();

  // 清理函数：移除监听器并释放资源
  window._cleanupITVAppDetector = () => {
    // 恢复原始函数
    XMLHttpRequest.prototype.open = _original.XHR.open;
    XMLHttpRequest.prototype.send = _original.XHR.send;
    window.fetch = _original.fetch;
    
    if (_original.MediaSourceAddBuffer && window.MediaSource) {
      MediaSource.prototype.addSourceBuffer = _original.MediaSourceAddBuffer;
    }
    
    // 停止DOM观察
    if (observer) { 
      observer.disconnect(); 
    }
    
    // 使用原始removeEventListener方法移除事件监听器
    const handlers = window._itvapp_detector_handlers || {};
    if (handlers.urlChange) {
      _original.removeEventListener.call(window, 'popstate', handlers.urlChange);
      _original.removeEventListener.call(window, 'hashchange', handlers.urlChange);
    }
    
    // 清除引用和标记
    delete window._itvapp_detector_handlers;
    delete window._itvapp_m3u8_detector_initialized;
    delete window._cleanupITVAppDetector;
  };
})();
