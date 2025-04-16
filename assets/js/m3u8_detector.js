// 流媒体探测器：检测页面中的 m3u8 等流媒体文件
(function() {
  // 防止重复初始化
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

  // 已处理 URL 集合，用于去重
  const processedUrls = new Set();
  // 最大递归深度，防止无限循环
  const MAX_RECURSION_DEPTH = 3;
  // MutationObserver 实例，用于监控 DOM 变化
  let observer = null;
  
  // 文件扩展名模式，动态替换为 m3u8
  const filePattern = "m3u8";
  
  // 全局配置，统一管理扫描和清理参数
  const CONFIG = {
    fullScanInterval: 5000, // 全面扫描间隔（毫秒）
    cleanupInterval: 30000, // 定期清理间隔（毫秒）
    maxProcessedElements: 500 // 最大处理元素数量
  };

  // 预编译常用正则表达式
  const FILE_REGEX = new RegExp('\\.(' + filePattern + ')([?#]|$)', 'i');
  const UNIFIED_URL_REGEX = new RegExp(`(?:https?://|//|/)[^\\s'"()<>{}\\[\\]]*?\\.${filePattern}[^\\s'"()<>{}\\[\\]]*`, 'g');
  
  // 支持的媒体类型
  const SUPPORTED_MEDIA_TYPES = [
    'application/x-mpegURL', 
    'application/vnd.apple.mpegURL', 
    'video/x-flv', 
    'application/x-flv', 
    'flv-application/octet-stream',
    'video/mp4', 
    'application/mp4'
  ];
  
  // 预编译 DOM 选择器
  const MEDIA_SELECTOR = [
    'video',
    'source',
    '[class*="video"]',
    '[class*="player"]',
    `[class*="${filePattern}"]`,
    `[data-${filePattern}]`,
    `a[href*="${filePattern}"]`,
    `[data-src*="${filePattern}"]`
  ].join(',');

  // 处理队列，用于批量处理 DOM 变更
  let pendingProcessQueue = new Set();
  let processingQueueTimer = null;

  // 防抖函数，用于减少频繁操作
  function debounce(func, wait) {
    let timeout;
    return function() {
      const context = this;
      const args = arguments;
      clearTimeout(timeout);
      timeout = setTimeout(() => func.apply(context, args), wait);
    };
  }

  // URL 处理工具，负责标准化和检测 URL
  const VideoUrlProcessor = {
    // 处理 URL，检查是否为目标文件类型
    processUrl(url, depth = 0, source = 'unknown') {
      if (!url || typeof url !== 'string' || 
          depth > MAX_RECURSION_DEPTH || 
          processedUrls.has(url)) return;

      try {
        // 先进行标准化处理
        url = this.normalizeUrl(url); 
        if (!url) return;
        
        // 对于已经标准化的 URL 再次检查是否已处理
        if (processedUrls.has(url)) return;
        
        if (FILE_REGEX.test(url)) {
          processedUrls.add(url); // 记录已处理 URL
          if (window.M3U8Detector) {
            try {
              // 发送检测到的 URL 信息
              window.M3U8Detector.postMessage(JSON.stringify({
                type: 'url',
                url: url,
                source: source
              }));
            } catch (e) {}
          }
        }
      } catch (e) {}
    },

    // 标准化 URL，处理相对路径和协议
    normalizeUrl(url) {
      try {
        if (!url) return '';
        
        // 处理 JSON 中的转义字符
        url = url.replace(/\\(\/|\\|"|')/g, '$1');
        
        // 处理重复斜杠 (但保留协议中的双斜杠)
        url = url.replace(/([^:])\/\/+/g, '$1/');
        
        // 去除 URL 开头和结尾的引号和空白
        url = url.replace(/^[\s'"]+|[\s'"]+$/g, '');
        
        if (url.startsWith('/')) {
          const baseUrl = new URL(window.location.href);
          return baseUrl.protocol + '//' + baseUrl.host + url;
        }
        if (!url.startsWith('http')) {
          return new URL(url, window.location.href).toString();
        }
        return url;
      } catch (e) {
        return url; // 格式错误时返回原 URL
      }
    },
  };

  // 网络请求拦截器，捕获 XHR 和 Fetch 请求
  const NetworkInterceptor = {
    // 拦截 XMLHttpRequest 请求
    setupXHRInterceptor() {
      const XHR = XMLHttpRequest.prototype;
      const originalOpen = XHR.open;
      const originalSend = XHR.send;

      // 重写 open 方法，记录请求 URL
      XHR.open = function() {
        this._url = arguments[1];
        return originalOpen.apply(this, arguments);
      };

      // 重写 send 方法，处理请求和响应 URL
      XHR.send = function() {
        if (this._url) VideoUrlProcessor.processUrl(this._url, 0, 'xhr');
        
        this.addEventListener('load', function() {
          if (this.responseURL) {
            VideoUrlProcessor.processUrl(this.responseURL, 0, 'xhr:response');
          }
          
          if (this.responseType === '' || this.responseType === 'text') {
            const responseText = this.responseText;
            if (responseText && responseText.includes('.' + filePattern)) {
              // 提取响应内容中的 URL - 使用统一的正则表达式
              UNIFIED_URL_REGEX.lastIndex = 0; // 重置正则表达式状态
              const matches = responseText.match(UNIFIED_URL_REGEX);
              if (matches) {
                matches.forEach(url => {
                  // 清理 URL 开头可能的引号或空格
                  const cleanUrl = url.replace(/^["'\s]+/, '');
                  VideoUrlProcessor.processUrl(cleanUrl, 0, 'xhr:responseContent');
                });
              }
            }
          }
        });
        
        return originalSend.apply(this, arguments);
      };
    },

    // 拦截 Fetch 请求
    setupFetchInterceptor() {
      const originalFetch = window.fetch;
      window.fetch = function(input) {
        try {
          const url = (input instanceof Request) ? input.url : input;
          VideoUrlProcessor.processUrl(url, 0, 'fetch'); // 处理请求 URL
        } catch (e) {}
        
        const fetchPromise = originalFetch.apply(this, arguments);
        
        fetchPromise.then(response => {
          try {
            VideoUrlProcessor.processUrl(response.url, 0, 'fetch:response'); // 处理响应 URL
            
            if (response.headers.get('content-type')?.includes('application/json')) {
              response.clone().text().then(text => {
                if (!text || !text.includes('.' + filePattern)) return;
                
                try {
                  const data = JSON.parse(text);
                  // 递归搜索 JSON 中的 URL
                  function searchJsonForUrls(obj, path = '') {
                    if (!obj) return;
                    if (typeof obj === 'string' && obj.includes('.' + filePattern)) {
                      VideoUrlProcessor.processUrl(obj, 0, 'fetch:json:' + path);
                    } else if (typeof obj === 'object') {
                      for (const key in obj) {
                        if (Object.prototype.hasOwnProperty.call(obj, key)) {
                          searchJsonForUrls(obj[key], path ? path + '.' + key : key);
                        }
                      }
                    }
                  }
                  searchJsonForUrls(data);
                } catch (e) {}
              }).catch(() => {});
            }
          } catch (e) {}
          
          return response;
        });
        
        return fetchPromise;
      };
    },

    // 拦截 MediaSource API，检测流媒体
    setupMediaSourceInterceptor() {
      if (!window.MediaSource) return;

      try {
        const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
        MediaSource.prototype.addSourceBuffer = function(mimeType) {
          try {
            if (SUPPORTED_MEDIA_TYPES.some(type => mimeType.includes(type))) {
              if (this.url) {
                VideoUrlProcessor.processUrl(this.url, 0, 'mediaSource'); // 处理 MediaSource URL
              }
            }
          } catch (e) {}
          
          return originalAddSourceBuffer.call(this, mimeType);
        };
        
        const originalURL = window.URL || window.webkitURL;
        if (originalURL && originalURL.createObjectURL) {
          const originalCreateObjectURL = originalURL.createObjectURL;
          originalURL.createObjectURL = function(obj) {
            const url = originalCreateObjectURL.call(this, obj);
            
            if (obj instanceof MediaSource) {
              // 使用 requestAnimationFrame 延迟检查视频元素
              requestAnimationFrame(() => {
                try {
                  const videoElements = document.querySelectorAll('video');
                  videoElements.forEach(video => {
                    if (video && video.src === url) {
                      const handleMetadata = () => {
                        if (video.duration > 0 && video.src) {
                          VideoUrlProcessor.processUrl(video.src, 0, 'mediaSource:video');
                        }
                        video.removeEventListener('loadedmetadata', handleMetadata);
                      };
                      
                      video.addEventListener('loadedmetadata', handleMetadata);
                    }
                  });
                } catch (e) {}
              });
            }
            
            return url;
          };
        }
      } catch (e) {}
    }
  };

  // DOM 扫描器，检测页面中的媒体元素和属性
  const DOMScanner = {
    // 使用 WeakSet 存储已处理元素，避免内存泄漏
    processedElements: new WeakSet(), 
    lastFullScanTime: 0, // 上次全面扫描时间
    processedCount: 0, // 已处理元素计数

    // 扫描元素属性中的 URL
    scanAttributes(element) {
      if (!element || !element.attributes) return;
      
      for (let i = 0; i < element.attributes.length; i++) {
        const attr = element.attributes[i];
        if (attr && attr.value) {
          VideoUrlProcessor.processUrl(attr.value, 0, 'attribute:' + attr.name);
        }
      }
    },

    // 扫描视频元素及其子节点
    scanMediaElement(element) {
      if (!element || element.tagName !== 'VIDEO') return;
      
      if (element.src) {
        VideoUrlProcessor.processUrl(element.src, 0, 'video:src'); // 处理 src 属性
      }
      if (element.currentSrc) {
        VideoUrlProcessor.processUrl(element.currentSrc, 0, 'video:currentSrc'); // 处理当前播放 URL
      }
      
      // 使用一次性查询，避免多次 DOM 操作
      const sources = element.querySelectorAll('source');
      for (let i = 0; i < sources.length; i++) {
        const source = sources[i];
        const src = source.src || source.getAttribute('src');
        if (src) {
          VideoUrlProcessor.processUrl(src, 0, 'video:source'); // 处理 source 标签
        }
      }
      
      // 监控 src 属性变化
      if (!element._srcObserved) {
        element._srcObserved = true;
        try {
          const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
          if (descriptor && descriptor.set) {
            const originalSrcSetter = descriptor.set;
            Object.defineProperty(element, 'src', {
              set: function(value) {
                if (value) {
                  VideoUrlProcessor.processUrl(value, 0, 'video:src:setter');
                }
                return originalSrcSetter.call(this, value);
              },
              get: function() {
                return element.getAttribute('src');
              },
              configurable: true
            });
          }
        } catch (e) {}
      }
    },

    // 扫描页面中的媒体相关元素
    scanPage(root = document) {
      const now = Date.now();
      const isFullScan = now - this.lastFullScanTime > CONFIG.fullScanInterval;
      
      if (isFullScan) {
        this.lastFullScanTime = now;
        this.processedCount = 0; // 重置计数，不再需要复杂的清理逻辑
      }
      
      try {
        // 使用一次性查询所有元素
        const elements = root.querySelectorAll(MEDIA_SELECTOR);
        
        for (let i = 0; i < elements.length; i++) {
          const element = elements[i];
          // WeakSet 不需要检查元素是否存在
          if (!element || this.processedElements.has(element)) continue;
          
          this.processedElements.add(element);
          this.processedCount++;
          this.scanAttributes(element);
          this.scanMediaElement(element);
        }
        
        // 全面扫描时执行额外操作
        if (isFullScan) {
          // 扫描链接
          const anchorElements = root.querySelectorAll('a[href]');
          for (let i = 0; i < anchorElements.length; i++) {
            const a = anchorElements[i];
            if (a && a.href && !this.processedElements.has(a)) {
              this.processedElements.add(a);
              this.processedCount++;
              VideoUrlProcessor.processUrl(a.href, 0, 'anchor');
            }
          }
          
          // 使用 requestIdleCallback 延迟执行较耗时的操作
          if (window.requestIdleCallback) {
            requestIdleCallback(() => {
              this.scanAllDataAttributes(root);
              this.scanScripts();
            }, { timeout: 2000 });
          } else {
            setTimeout(() => {
              this.scanAllDataAttributes(root);
              this.scanScripts();
            }, 200);
          }
        }
      } catch (e) {}
    },
    
    // 扫描所有 data 属性
    scanAllDataAttributes(root) {
      try {
        const allElements = root.querySelectorAll('[data-*]');
        for (let i = 0; i < allElements.length; i++) {
          const el = allElements[i];
          if (!el || this.processedElements.has(el)) continue;
          
          this.processedElements.add(el);
          this.processedCount++;
          
          const attributes = el.attributes;
          for (let j = 0; j < attributes.length; j++) {
            const attr = attributes[j];
            if (attr && attr.name && attr.name.startsWith('data-') && attr.value) {
              VideoUrlProcessor.processUrl(attr.value, 0, 'data-attribute');
            }
          }
        }
      } catch (e) {}
    },

    // 扫描脚本内容中的 URL
    scanScripts() {
      try {
        const scripts = document.querySelectorAll('script:not([src])');
        for (let i = 0; i < scripts.length; i++) {
          const script = scripts[i];
          const content = script.textContent;
          if (!content) continue;
          
          let match;
          UNIFIED_URL_REGEX.lastIndex = 0; // 重置正则表达式状态
          while ((match = UNIFIED_URL_REGEX.exec(content)) !== null) {
            const url = match[0].replace(/^["'\s]+/, ''); // 清理 URL 开头可能的引号或空格
            if (url) {
              VideoUrlProcessor.processUrl(url, 0, 'script:regex');
            }
          }
        }
      } catch (e) {}
    }
  };

  // 处理页面 URL 变化（使用防抖优化）
  const handleUrlChange = debounce(function() {
    DOMScanner.scanPage(document);
  }, 300);

  // 处理批量队列处理
  function processPendingQueue() {
    if (processingQueueTimer || pendingProcessQueue.size === 0) return;
    
    processingQueueTimer = setTimeout(() => {
      const currentQueue = new Set(pendingProcessQueue);
      pendingProcessQueue.clear();
      processingQueueTimer = null;
      
      // 处理队列项
      currentQueue.forEach(item => {
        if (typeof item === 'string') {
          VideoUrlProcessor.processUrl(item, 0, 'mutation:string');
        } else if (item && item.parentNode) {
          DOMScanner.scanPage(item.parentNode || document);
        }
      });
    }, 100);
  }

  // 初始化流媒体检测器
  function initializeDetector() {
    try {
      // 设置网络拦截器
      NetworkInterceptor.setupXHRInterceptor();
      NetworkInterceptor.setupFetchInterceptor();
      NetworkInterceptor.setupMediaSourceInterceptor();
      
      // 设置 MutationObserver
      observer = new MutationObserver(mutations => {
        const newVideos = new Set();
        
        for (let i = 0; i < mutations.length; i++) {
          const mutation = mutations[i];
          
          // 处理新增节点
          if (mutation.addedNodes.length > 0) {
            for (let j = 0; j < mutation.addedNodes.length; j++) {
              const node = mutation.addedNodes[j];
              if (!node || node.nodeType !== 1) continue;
              
              if (node.tagName === 'VIDEO') {
                newVideos.add(node);
              }
              
              if (node instanceof Element && node.attributes) {
                for (let k = 0; k < node.attributes.length; k++) {
                  const attr = node.attributes[k];
                  if (attr && attr.value) {
                    pendingProcessQueue.add(attr.value);
                  }
                }
              }
            }
          }
          
          // 处理属性变化
          if (mutation.type === 'attributes' && mutation.target) {
            const newValue = mutation.target.getAttribute(mutation.attributeName);
            if (newValue) {
              pendingProcessQueue.add(newValue);
              if (['src', 'data-src', 'href'].includes(mutation.attributeName) && 
                  newValue.includes('.' + filePattern)) {
                VideoUrlProcessor.processUrl(newValue, 0, 'attribute:change');
              }
            }
          }
        }
        
        // 处理新增视频元素
        newVideos.forEach(video => {
          DOMScanner.scanMediaElement(video);
        });
        
        // 触发队列处理
        processPendingQueue();
      });
      
      // 开始观察 DOM 变化
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true
      });
      
      // 监听 URL 变化
      window.addEventListener('popstate', handleUrlChange);
      window.addEventListener('hashchange', handleUrlChange);
      
      // 初始页面扫描
      if (window.requestIdleCallback) {
        requestIdleCallback(() => DOMScanner.scanPage(document), { timeout: 1000 });
      } else {
        setTimeout(() => DOMScanner.scanPage(document), 100);
      }
      
      // 定期扫描页面（只在页面可见时执行）
      const intervalId = setInterval(() => {
        if (!document.hidden) {
          DOMScanner.scanPage(document);
        }
      }, 1000);
      
      window._m3u8DetectorIntervalId = intervalId;
    } catch (e) {}
  }

  // 执行初始化
  initializeDetector();

  // 清理检测器资源
  window._cleanupM3U8Detector = () => {
    try {
      if (observer) {
        observer.disconnect();
        observer = null;
      }
      
      window.removeEventListener('popstate', handleUrlChange);
      window.removeEventListener('hashchange', handleUrlChange);
      
      if (window._m3u8DetectorIntervalId) {
        clearInterval(window._m3u8DetectorIntervalId);
        delete window._m3u8DetectorIntervalId;
      }
      
      if (processingQueueTimer) {
        clearTimeout(processingQueueTimer);
        processingQueueTimer = null;
      }
      
      delete window._m3u8DetectorInitialized;
      processedUrls.clear();
      pendingProcessQueue.clear();
      DOMScanner.processedCount = 0;
      // WeakSet 不需要手动清理，会被垃圾回收
    } catch (e) {}
  };

  // 提供外部接口：扫描指定节点
  window.checkMediaElements = function(root) {
    try {
      if (root) DOMScanner.scanPage(root);
    } catch (e) {
      console.error("检查媒体元素时出错:", e);
    }
  };
  
  // 提供外部接口：高效扫描整个页面
  window.efficientDOMScan = function() {
    try {
      DOMScanner.scanPage(document);
    } catch (e) {
      console.error("高效DOM扫描时出错:", e);
    }
  };
  
  // 通知外部初始化完成
  if (window.M3U8Detector) {
    try {
      window.M3U8Detector.postMessage(JSON.stringify({
        type: 'init',
        message: 'M3U8Detector initialized'
      }));
    } catch (e) {}
  }
})();
