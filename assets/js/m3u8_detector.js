// 流媒体地址检测注入
(function() {
  // 避免重复初始化，确保脚本只执行一次
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

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
        window.M3U8Detector && window.M3U8Detector.postMessage(url); // 增加安全检查
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
      const XHR = XMLHttpRequest.prototype;
      const originalOpen = XHR.open;
      const originalSend = XHR.send;

      XHR.open = function() { // 重写open方法，捕获请求URL
        this._url = arguments[1];
        return originalOpen.apply(this, arguments);
      };

      XHR.send = function() { // 重写send方法，处理捕获的URL
        if (this._url) VideoUrlProcessor.processUrl(this._url, 0);
        return originalSend.apply(this, arguments);
      };
    },

    setupFetchInterceptor() { // 拦截fetch请求
      const originalFetch = window.fetch;
      window.fetch = function(input) { // 重写fetch，捕获请求URL
        const url = (input instanceof Request) ? input.url : input;
        VideoUrlProcessor.processUrl(url, 0);
        return originalFetch.apply(this, arguments);
      };
    },

    setupMediaSourceInterceptor() { // 拦截MediaSource流媒体
      if (!window.MediaSource) return; // 浏览器不支持MediaSource则跳过

      const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
      MediaSource.prototype.addSourceBuffer = function(mimeType) { // 重写addSourceBuffer
        const supportedTypes = { // 支持的流媒体MIME类型
          'm3u8': ['application/x-mpegURL', 'application/vnd.apple.mpegURL'],
          'flv': ['video/x-flv', 'application/x-flv', 'flv-application/octet-stream'],
          'mp4': ['video/mp4', 'application/mp4']
        };

        const currentTypes = supportedTypes[filePattern] || []; // 获取当前检测类型
        const url = this.url || window.location.href; // 使用当前页面URL作为回退
        if (currentTypes.some(type => mimeType.includes(type))) { // 检查MIME类型
          VideoUrlProcessor.processUrl(url, 0);
        }
        return originalAddSourceBuffer.call(this, mimeType); // 调用原始方法
      };
    }
  };

  // DOM扫描器：扫描页面元素中的流媒体URL
  const DOMScanner = {
    // 使用WeakSet存储已处理元素，避免内存泄漏
    processedElements: new WeakSet(), 

    scanAttributes(element) { // 扫描元素属性中的URL
      for (const attr of element.attributes) {
        if (attr.value) VideoUrlProcessor.processUrl(attr.value, 0);
      }
    },

    scanMediaElement(element) { // 扫描视频相关元素的URL
      if (element.tagName === 'VIDEO') {
        // 使用短路运算符和可选链简化逻辑
        element.src && VideoUrlProcessor.processUrl(element.src, 0);
        element.currentSrc && VideoUrlProcessor.processUrl(element.currentSrc, 0);

        element.querySelectorAll('source').forEach(source => { // 检查source标签
          const src = source.src || source.getAttribute('src');
          if (src) VideoUrlProcessor.processUrl(src, 0);
        });
      }
    },

    scanPage(root = document) { // 扫描整个页面中的流媒体元素
      const selector = [ // 定义目标元素的选择器
        'video', 'source', '[class*="video"]', '[class*="player"]',
        `[class*="${filePattern}"]`, `[data-${filePattern}]`,
        `a[href*="${filePattern}"]`, `[data-src*="${filePattern}"]`
      ].join(',');

      try {
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
      document.querySelectorAll('script:not([src])').forEach(script => {
        if (!script.textContent) return; // 跳过空脚本
        
        try {
          const pattern = '\\.' + filePattern; // 定义检测模式
          // 使用更稳定的正则表达式
          const regex = new RegExp(`https?://[^\\s'"]*${pattern}[^\\s'"]*`, 'g'); // URL匹配正则
          let match;
          
          // 使用字符串匹配提取URL
          const content = script.textContent;
          while ((match = regex.exec(content)) !== null) { // 提取匹配的URL
            VideoUrlProcessor.processUrl(match[0], 0);
          }
        } catch (e) {
          // 防止正则表达式错误导致脚本扫描失败
          console.error('脚本扫描失败:', e);
        }
      });
    }
    // extractUrlFromScript函数未被使用，已移除
  };

  // 初始化检测器：设置拦截和观察机制
  function initializeDetector() {
    // 设置网络拦截器
    NetworkInterceptor.setupXHRInterceptor(); // 拦截XHR请求
    NetworkInterceptor.setupFetchInterceptor(); // 拦截fetch请求
    NetworkInterceptor.setupMediaSourceInterceptor(); // 拦截MediaSource

    // 设置DOM变化观察器
    let debounceTimer = null; // 防抖定时器

    // 存储事件处理函数引用，确保清理时可正确移除
    const urlChangeHandler = () => { DOMScanner.scanPage(document); };

    observer = new MutationObserver(mutations => { // 监听DOM变化
      const processQueue = new Set(); // 待处理队列

      mutations.forEach(mutation => { // 处理每个变化
        mutation.addedNodes.forEach(node => { // 检查新增节点
          if (node.nodeType === 1) { // 元素节点
            if (node.matches && node.matches('video,source,[class*="video"],[class*="player"]')) {
              processQueue.add(node);
            }
            if (node instanceof Element) {
              for (const attr of node.attributes) { // 检查属性值
                if (attr.value) processQueue.add(attr.value);
              }
            }
          }
        });

        if (mutation.type === 'attributes') { // 处理属性变化
          const newValue = mutation.target.getAttribute(mutation.attributeName);
          if (newValue) processQueue.add(newValue);
        }
      });

      // 使用防抖优化性能
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        // 兼容性处理：检查requestIdleCallback是否可用
        if (typeof requestIdleCallback === 'function') {
          requestIdleCallback(() => { // 在空闲时处理队列
            processQueueItems(processQueue);
          }, { timeout: 1000 });
        } else {
          // 降级处理：直接使用setTimeout
          setTimeout(() => {
            processQueueItems(processQueue);
          }, 0);
        }
      }, 100); // 100ms防抖间隔
    });

    // 抽取队列处理逻辑为独立函数
    function processQueueItems(queue) {
      queue.forEach(item => {
        if (typeof item === 'string') {
          VideoUrlProcessor.processUrl(item, 0);
        } else if (item && item.parentNode) {
          DOMScanner.scanPage(item.parentNode || document);
        }
      });
    }

    observer.observe(document.documentElement, { // 开始观察DOM
      childList: true, subtree: true, attributes: true
    });

    // 处理URL变化事件
    window.addEventListener('popstate', urlChangeHandler); // 监听历史记录变化
    window.addEventListener('hashchange', urlChangeHandler); // 监听hash变化

    // 初始页面扫描
    if (typeof requestIdleCallback === 'function') {
      requestIdleCallback(() => { DOMScanner.scanPage(document); }, { timeout: 1000 });
    } else {
      // 降级处理
      setTimeout(() => { DOMScanner.scanPage(document); }, 0);
    }
    
    // 存储事件处理器引用，确保正确清理
    window._m3u8DetectorHandlers = {
      urlChangeHandler
    };
  }

  // 执行初始化
  initializeDetector();

  // 清理函数：移除监听器并释放资源
  window._cleanupM3U8Detector = () => {
    if (observer) { observer.disconnect(); } // 停止DOM观察
    
    // 使用存储的引用移除事件监听器
    const handlers = window._m3u8DetectorHandlers || {};
    if (handlers.urlChangeHandler) {
      window.removeEventListener('popstate', handlers.urlChangeHandler); 
      window.removeEventListener('hashchange', handlers.urlChangeHandler);
    }
    
    // 清除引用和标记
    delete window._m3u8DetectorHandlers;
    delete window._m3u8DetectorInitialized;
  };
})();
