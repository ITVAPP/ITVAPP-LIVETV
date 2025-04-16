// 流媒体地址检测器
(function() {
  // 防止重复初始化
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

  // 使用LRU缓存存储已处理URL
  class LRUCache {
    constructor(capacity) {
      this.capacity = capacity; // 设置缓存容量
      this.cache = new Map(); // 初始化缓存映射
    }
    
    has(key) {
      return this.cache.has(key); // 检查URL是否已缓存
    }
    
    add(key) {
      if (this.cache.size >= this.capacity) {
        const firstKey = this.cache.keys().next().value;
        this.cache.delete(firstKey); // 移除最老的缓存项
      }
      this.cache.set(key, true); // 添加新URL到缓存
    }
    
    clear() {
      this.cache.clear(); // 清空缓存
    }
    
    get size() {
      return this.cache.size; // 获取当前缓存大小
    }
  }

  // 已处理URL集合，使用LRU缓存
  const processedUrls = new LRUCache(1000); // 初始化URL缓存，容量1000
  const MAX_RECURSION_DEPTH = 3; // 最大递归深度
  let observer = null; // DOM变化观察器
  const filePattern = "m3u8"; // 目标文件扩展名
  
  // 全局配置
  const CONFIG = {
    fullScanInterval: 5000, // 全面扫描间隔（毫秒）
    maxProcessedElements: 500 // 最大处理元素数量
  };

  // 预编译正则表达式
  const FILE_REGEX = new RegExp(`\\.${filePattern}([?#]|$)`, 'i'); // 匹配m3u8文件URL
  const URL_REGEX = new RegExp(`[^\\s'"()<>{}\\[\\]]*?\\.${filePattern}[^\\s'"()<>{}\\[\\]]*`, 'g'); // 提取m3u8 URL
  const SUPPORTED_MEDIA_TYPES = [
    'application/x-mpegURL', 
    'application/vnd.apple.mpegURL', 
    'video/x-flv', 
    'application/x-flv', 
    'flv-application/octet-stream',
    'video/mp4', 
    'application/mp4'
  ]; // 支持的媒体类型
  const MEDIA_SELECTOR = [
    'video',
    'source',
    '[class*="video"]',
    '[class*="player"]',
    `[class*="${filePattern}"]`,
    `[data-${filePattern}]`,
    `a[href*="${filePattern}"]`,
    `[data-src*="${filePattern}"]`
  ].join(','); // 媒体元素选择器

  // 处理队列
  let pendingProcessQueue = new Set(); // 待处理URL队列
  let processingQueueTimer = null; // 队列处理定时器

  // 简化防抖函数
  const debounce = (func, wait) => {
    let timeout;
    return (...args) => {
      clearTimeout(timeout);
      timeout = setTimeout(() => func(...args), wait); // 延迟执行函数
    };
  };

  // 提取并处理URL
  function extractAndProcessUrls(text, source, baseUrl) {
    if (!text || !text.includes('.' + filePattern)) return;
    const matches = text.match(URL_REGEX) || [];
    for (const match of matches) {
      const cleanUrl = match.replace(/^["'\s]+/, ''); // 清理URL前缀
      VideoUrlProcessor.processUrl(cleanUrl, 0, source, baseUrl); // 处理URL
    }
  }

  // URL处理工具
  const VideoUrlProcessor = {
    processUrl(url, depth = 0, source = 'unknown', baseUrl) {
      if (!url || depth > MAX_RECURSION_DEPTH || processedUrls.has(url)) return;
      try {
        url = this.normalizeUrl(url, baseUrl); // 规范化URL
        if (!url || processedUrls.has(url)) return;
        if (FILE_REGEX.test(url)) {
          processedUrls.add(url); // 缓存已处理的URL
          if (window.M3U8Detector) {
            window.M3U8Detector.postMessage(JSON.stringify({
              type: 'url',
              url,
              source
            })); // 发送URL消息
          }
        }
      } catch (e) {}
    },

    normalizeUrl(url, baseUrl = window.location.href) {
      if (!url) return '';
      try {
        url = url.replace(/\\(\/|\\|"|')|([^:])\/\/+|[\s'"]+/g, '$2'); // 清理URL格式
        let parsedUrl;
        if (url.startsWith('/')) {
          parsedUrl = new URL(url, baseUrl); // 相对路径转绝对
        } else if (!url.startsWith('http')) {
          parsedUrl = new URL(url, baseUrl); // 非http开头转绝对
        } else {
          parsedUrl = new URL(url); // 直接解析
        }
        parsedUrl.hostname = parsedUrl.hostname.toLowerCase(); // 主机名转小写
        if ((parsedUrl.protocol === 'http:' && parsedUrl.port === '80') || 
            (parsedUrl.protocol === 'https:' && parsedUrl.port === '443')) {
          parsedUrl.port = ''; // 移除默认端口
        }
        parsedUrl.hash = ''; // 移除URL锚点
        return parsedUrl.toString();
      } catch (e) {
        return url; // 解析失败返回原URL
      }
    }
  };

  // 共用网络URL处理函数
  function handleNetworkUrl(url, source, content, contentType, baseUrl) {
    if (url) VideoUrlProcessor.processUrl(url, 0, source, baseUrl); // 处理网络URL
    if (content) {
      extractAndProcessUrls(content, `${source}:content`, baseUrl); // 提取内容中的URL
      if (contentType?.includes('application/json')) {
        try {
          const data = JSON.parse(content); // 解析JSON内容
          function searchJsonForUrls(obj, path = '') {
            if (!obj) return;
            if (typeof obj === 'string' && obj.includes('.' + filePattern)) {
              VideoUrlProcessor.processUrl(obj, 0, `${source}:json:${path}`, baseUrl); // 处理JSON中的URL
            } else if (typeof obj === 'object') {
              for (const key in obj) {
                if (Object.prototype.hasOwnProperty.call(obj, key)) {
                  searchJsonForUrls(obj[key], path ? `${path}.${key}` : key); // 递归搜索
                }
              }
            }
          }
          searchJsonForUrls(data);
        } catch (e) {}
      }
    }
  }

  // 网络拦截器
  const NetworkInterceptor = {
    setupXHRInterceptor() {
      const XHR = XMLHttpRequest.prototype;
      const originalOpen = XHR.open;
      const originalSend = XHR.send;

      XHR.open = function() {
        this._url = arguments[1]; // 记录请求URL
        return originalOpen.apply(this, arguments);
      };

      XHR.send = function() {
        if (this._url) handleNetworkUrl(this._url, 'xhr'); // 处理XHR请求URL
        this.addEventListener('load', () => {
          if (this.responseURL) handleNetworkUrl(this.responseURL, 'xhr:response'); // 处理响应URL
          if (this.responseType === '' || this.responseType === 'text') {
            handleNetworkUrl(null, 'xhr:responseContent', this.responseText, null, this.responseURL); // 处理响应内容
          }
        });
        return originalSend.apply(this, arguments);
      };
    },

    setupFetchInterceptor() {
      const originalFetch = window.fetch;
      window.fetch = function(input) {
        const url = (input instanceof Request) ? input.url : input;
        handleNetworkUrl(url, 'fetch'); // 处理fetch请求URL
        const fetchPromise = originalFetch.apply(this, arguments);
        fetchPromise.then(response => {
          const contentType = response.headers.get('content-type')?.toLowerCase();
          if (contentType && (
              contentType.includes('application/json') ||
              contentType.includes('application/x-mpegURL') ||
              contentType.includes('text/plain')
          )) {
            response.clone().text().then(text => {
              handleNetworkUrl(response.url, 'fetch:response', text, contentType, response.url); // 处理响应内容
            }).catch(() => {});
          } else {
            handleNetworkUrl(response.url, 'fetch:response'); // 处理响应URL
          }
          return response;
        });
        return fetchPromise;
      };
    },

    setupMediaSourceInterceptor() {
      if (!window.MediaSource) return;
      const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
      MediaSource.prototype.addSourceBuffer = function(mimeType) {
        if (SUPPORTED_MEDIA_TYPES.some(type => mimeType.includes(type))) {
          if (this.url) {
            VideoUrlProcessor.processUrl(this.url, 0, 'mediaSource'); // 处理MediaSource URL
          }
        }
        return originalAddSourceBuffer.call(this, mimeType);
      };
      
      const originalURL = window.URL || window.webkitURL;
      if (originalURL && originalURL.createObjectURL) {
        const originalCreateObjectURL = originalURL.createObjectURL;
        originalURL.createObjectURL = function(obj) {
          const url = originalCreateObjectURL.call(this, obj);
          if (obj instanceof MediaSource) {
            requestAnimationFrame(() => {
              try {
                const videoElements = document.querySelectorAll('video');
                videoElements.forEach(video => {
                  if (video && video.src === url) {
                    const handleMetadata = () => {
                      if (video.duration > 0 && video.src) {
                        VideoUrlProcessor.processUrl(video.src, 0, 'mediaSource:video'); // 处理视频URL
                      }
                      video.removeEventListener('loadedmetadata', handleMetadata);
                    };
                    video.addEventListener('loadedmetadata', handleMetadata); // 监听视频元数据加载
                  }
                });
              } catch (e) {}
            });
          }
          return url;
        };
      }
    }
  };

  // DOM扫描器
  const DOMScanner = {
    processedElements: new WeakSet(), // 存储已处理元素
    lastFullScanTime: 0, // 上次全面扫描时间
    processedCount: 0, // 已处理元素计数
    cachedElements: null, // 缓存的DOM元素
    lastSelectorTime: 0, // 上次选择器查询时间
    SELECTOR_CACHE_TTL: 2000, // 选择器缓存有效期
    
    getMediaElements(root = document) {
      const now = Date.now();
      if (!this.cachedElements || (now - this.lastSelectorTime > this.SELECTOR_CACHE_TTL)) {
        this.cachedElements = root.querySelectorAll(MEDIA_SELECTOR + ',[data-*],a[href]'); // 查询媒体元素
        this.lastSelectorTime = now;
      }
      return this.cachedElements;
    },

    scanAttributes(element) {
      if (!element || !element.attributes) return;
      for (const attr of element.attributes) {
        if (attr.value) {
          VideoUrlProcessor.processUrl(attr.value, 0, `attribute:${attr.name}`); // 处理元素属性URL
        }
      }
    },

    scanMediaElement(element) {
      if (!element || element.tagName !== 'VIDEO') return;
      if (element.src) {
        VideoUrlProcessor.processUrl(element.src, 0, 'video:src'); // 处理video元素的src
      }
      if (element.currentSrc) {
        VideoUrlProcessor.processUrl(element.currentSrc, 0, 'video:currentSrc'); // 处理video当前播放src
      }
      const sources = element.querySelectorAll('source');
      for (const source of sources) {
        const src = source.src || source.getAttribute('src');
        if (src) {
          VideoUrlProcessor.processUrl(src, 0, 'video:source'); // 处理source元素的src
        }
      }
      if (!element._srcObserved) {
        element._srcObserved = true;
        try {
          const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
          if (descriptor && descriptor.set) {
            const originalSrcSetter = descriptor.set;
            Object.defineProperty(element, 'src', {
              set(value) {
                if (value) {
                  VideoUrlProcessor.processUrl(value, 0, 'video:src:setter'); // 处理动态设置的src
                }
                return originalSrcSetter.call(this, value);
              },
              get() {
                return element.getAttribute('src');
              },
              configurable: true
            });
          }
        } catch (e) {}
      }
    },

    scanPage(root = document) {
      const now = Date.now();
      const isFullScan = now - this.lastFullScanTime > CONFIG.fullScanInterval;
      if (isFullScan) {
        this.lastFullScanTime = now;
        this.processedCount = 0; // 重置计数
        this.cachedElements = null; // 清除缓存
      }
      
      try {
        const elements = this.getMediaElements(root);
        for (const element of elements) {
          if (!element || this.processedElements.has(element)) continue;
          this.processedElements.add(element); // 标记已处理
          this.processedCount++;
          this.scanAttributes(element); // 扫描元素属性
          this.scanMediaElement(element); // 扫描媒体元素
          if (element.tagName === 'A' && element.href) {
            VideoUrlProcessor.processUrl(element.href, 0, 'anchor'); // 处理锚点URL
          }
          if (isFullScan && element.attributes) {
            for (const attr of element.attributes) {
              if (attr.name.startsWith('data-') && attr.value) {
                VideoUrlProcessor.processUrl(attr.value, 0, 'data-attribute'); // 处理data属性URL
              }
            }
          }
        }
        if (isFullScan) {
          if (window.requestIdleCallback) {
            requestIdleCallback(() => this.scanScripts(), { timeout: 2000 }); // 异步扫描脚本
          } else {
            setTimeout(() => this.scanScripts(), 200);
          }
        }
      } catch (e) {}
    },

    scanScripts() {
      try {
        const scripts = document.querySelectorAll('script:not([src])');
        for (const script of scripts) {
          const content = script.textContent;
          if (content) {
            extractAndProcessUrls(content, 'script:regex'); // 提取脚本中的URL
          }
        }
      } catch (e) {}
    }
  };

  // 处理URL变化
  const handleUrlChange = debounce(() => {
    DOMScanner.scanPage(document); // 页面URL变化时重新扫描
  }, 300);

  // 批量队列处理
  function processPendingQueue() {
    if (processingQueueTimer || pendingProcessQueue.size === 0) return;
    processingQueueTimer = setTimeout(() => {
      const currentQueue = new Set(pendingProcessQueue);
      pendingProcessQueue.clear(); // 清空待处理队列
      processingQueueTimer = null;
      currentQueue.forEach(item => {
        if (typeof item === 'string') {
          VideoUrlProcessor.processUrl(item, 0, 'mutation:string'); // 处理字符串URL
        } else if (item && item.parentNode) {
          DOMScanner.scanPage(item.parentNode || document); // 扫描节点
        }
      });
    }, 100);
  }

  // 定期扫描
  let lastScanTime = 0;
  const SCAN_INTERVAL = 1000; // 扫描间隔

  function scheduleNextScan() {
    if (document.hidden) {
      setTimeout(scheduleNextScan, SCAN_INTERVAL * 2); // 页面不可见时降低频率
      return;
    }
    const now = Date.now();
    if (now - lastScanTime >= SCAN_INTERVAL) {
      lastScanTime = now;
      DOMScanner.scanPage(document); // 执行定期扫描
    }
    requestAnimationFrame(scheduleNextScan); // 下一帧继续调度
  }

  // 初始化
  function initializeDetector() {
    try {
      NetworkInterceptor.setupXHRInterceptor(); // 初始化XHR拦截
      NetworkInterceptor.setupFetchInterceptor(); // 初始化fetch拦截
      NetworkInterceptor.setupMediaSourceInterceptor(); // 初始化MediaSource拦截
      observer = new MutationObserver(mutations => {
        const newVideos = new Set();
        for (const mutation of mutations) {
          if (mutation.addedNodes.length > 0) {
            for (const node of mutation.addedNodes) {
              if (!node || node.nodeType !== 1) continue;
              if (node.tagName === 'VIDEO') {
                newVideos.add(node); // 收集新增视频元素
              }
              if (node instanceof Element && node.attributes) {
                for (const attr of node.attributes) {
                  if (attr.value) {
                    pendingProcessQueue.add(attr.value); // 添加属性值到队列
                  }
                }
              }
            }
          }
          if (mutation.type === 'attributes' && mutation.target) {
            const newValue = mutation.target.getAttribute(mutation.attributeName);
            if (newValue) {
              pendingProcessQueue.add(newValue); // 添加变化的属性值
              if (['src', 'data-src', 'href'].includes(mutation.attributeName) && 
                  newValue.includes('.' + filePattern)) {
                VideoUrlProcessor.processUrl(newValue, 0, 'attribute:change'); // 处理特定属性变化
              }
            }
          }
        }
        newVideos.forEach(video => {
          DOMScanner.scanMediaElement(video); // 扫描新增视频元素
        });
        processPendingQueue(); // 处理队列
      });
      
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true
      }); // 启动DOM变化观察
      
      window.addEventListener('popstate', handleUrlChange); // 监听页面历史变化
      window.addEventListener('hashchange', handleUrlChange); // 监听hash变化
      
      if (window.requestIdleCallback) {
        requestIdleCallback(() => DOMScanner.scanPage(document), { timeout: 1000 }); // 空闲时扫描
      } else {
        setTimeout(() => DOMScanner.scanPage(document), 100);
      }
      
      requestAnimationFrame(scheduleNextScan); // 启动定期扫描
    } catch (e) {}
  }

  // 执行初始化
  initializeDetector();

  // 清理
  window._cleanupM3U8Detector = () => {
    if (observer) {
      observer.disconnect(); // 停止DOM观察
      observer = null;
    }
    window.removeEventListener('popstate', handleUrlChange); // 移除历史变化监听
    window.removeEventListener('hashchange', handleUrlChange); // 移除hash变化监听
    if (processingQueueTimer) {
      clearTimeout(processingQueueTimer); // 清除队列定时器
      processingQueueTimer = null;
    }
    delete window._m3u8DetectorInitialized; // 移除初始化标记
    processedUrls.clear(); // 清空URL缓存
    pendingProcessQueue.clear(); // 清空待处理队列
    DOMScanner.processedCount = 0; // 重置计数
    DOMScanner.cachedElements = null; // 清除元素缓存
  };

  // 外部接口
  window.checkMediaElements = function(root) {
    try {
      if (root) DOMScanner.scanPage(root); // 扫描指定根节点的媒体元素
    } catch (e) {
      console.error("检查媒体元素时出错:", e);
    }
  };
  
  window.efficientDOMScan = function() {
    try {
      DOMScanner.scanPage(document); // 执行高效DOM扫描
    } catch (e) {
      console.error("高效DOM扫描时出错:", e);
    }
  };
  
  if (window.M3U8Detector) {
    try {
      window.M3U8Detector.postMessage(JSON.stringify({
        type: 'init',
        message: 'M3U8Detector initialized'
      })); // 发送初始化消息
    } catch (e) {}
  }
})();
