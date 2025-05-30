// 流媒体探测器：检测页面中的 m3u8 等流媒体文件
(function() {
  // 防止重复初始化
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

  // LRU缓存类：管理URL缓存，优化查询与访问性能
  class LRUCache {
    constructor(capacity) {
      this.capacity = capacity;
      this.cache = new Map();
    }
    
    // 检查键是否存在，不更新LRU顺序
    has(key) {
      return this.cache.has(key);
    }
    
    // 访问键，更新LRU顺序
    access(key) {
      const hasKey = this.cache.has(key);
      if (hasKey) {
        const value = this.cache.get(key);
        this.cache.delete(key);
        this.cache.set(key, value);
      }
      return hasKey;
    }
    
    // 添加键，超出容量时移除最旧项
    add(key) {
      if (this.has(key)) {
        this.cache.delete(key);
      } else if (this.cache.size >= this.capacity) {
        const oldestKey = this.cache.keys().next().value;
        this.cache.delete(oldestKey);
      }
      this.cache.set(key, true);
    }
    
    // 清空缓存
    clear() {
      this.cache.clear();
    }
    
    // 获取缓存大小
    get size() {
      return this.cache.size;
    }
  }

  // 初始化变量：URL缓存、递归深度、观察器等
  const processedUrls = new LRUCache(1000);
  const MAX_RECURSION_DEPTH = 3;
  let observer = null;
  const filePattern = "m3u8";
  
  const CONFIG = {
    fullScanInterval: 3000
  };

  // 预编译正则：URL清理和绝对路径检测
  const COMPILED_REGEX = {
    CLEAN_URL: /\\(\/|\\|"|')|([^:])\/\/+|[\s'"]+/g,
    ABSOLUTE_URL: /^https?:\/\//i
  };

  // 正则缓存：文件和URL正则表达式
  const fileRegexCache = new Map();
  const urlRegexCache = new Map();

  // 获取文件正则，缓存以提升性能
  const getFileRegex = (pattern) => {
    if (!fileRegexCache.has(pattern)) {
      fileRegexCache.set(pattern, new RegExp(`\\.${pattern}([?#]|$)`, 'i'));
    }
    return fileRegexCache.get(pattern);
  };

  // 获取URL正则，缓存以提升性能
  const getUrlRegex = (pattern) => {
    if (!urlRegexCache.has(pattern)) {
      urlRegexCache.set(pattern, new RegExp(`[^\\s'"()<>{}\\[\\]]*?\\.${pattern}[^\\s'"()<>{}\\[\\]]*`, 'g'));
    }
    return urlRegexCache.get(pattern);
  };
  
  // 支持的媒体类型列表
  const SUPPORTED_MEDIA_TYPES = [
    'application/x-mpegURL', 
    'application/vnd.apple.mpegURL', 
    'video/x-flv', 
    'application/x-flv', 
    'flv-application/octet-stream',
    'video/mp4', 
    'application/mp4'
  ];

  // DOM选择器缓存：优化选择器性能
  let cachedMediaSelector = null;
  let lastPatternForSelector = null;

  // 获取媒体选择器，按性能排序
  function getMediaSelector() {
    const currentPattern = window.filePattern || filePattern;
    if (currentPattern !== lastPatternForSelector || !cachedMediaSelector) {
      lastPatternForSelector = currentPattern;
      cachedMediaSelector = [
        'video', // 最高效
        'source', // 高效
        `a[href*="${currentPattern}"]`, // 中等效率
        `[data-src*="${currentPattern}"]`, // 中等效率
        `[data-${currentPattern}]`, // 中等效率
        '[class*="video"]', // 低效率
        '[class*="player"]', // 低效率
        `[class*="${currentPattern}"]` // 最低效率
      ].join(',');
    }
    return cachedMediaSelector;
  }

  // 更新文件模式，清除相关缓存
  window.updateFilePattern = function(newPattern) {
    if (newPattern && typeof newPattern === 'string' && newPattern !== filePattern) {
      window.filePattern = newPattern;
      fileRegexCache.clear();
      urlRegexCache.clear();
      cachedMediaSelector = null;
      lastPatternForSelector = null;
    }
  };

  // URL处理队列
  let pendingProcessQueue = new Set();
  let processingQueueTimer = null;

  // 防抖函数：延迟执行以减少频繁调用
  const debounce = (func, wait) => {
    let timeout;
    return (...args) => {
      clearTimeout(timeout);
      timeout = setTimeout(() => func(...args), wait);
    };
  };

  // 检测是否为直接媒体URL
  function isDirectMediaUrl(url) {
    if (!url || typeof url !== 'string') return false;
    
    try {
      const parsedUrl = new URL(url, window.location.href);
      const pathname = parsedUrl.pathname.toLowerCase();
      const currentPattern = window.filePattern || filePattern;
      
      // 🔥 关键逻辑：只有当filePattern是m3u8时，m3u8文件才不拦截
      if (pathname.endsWith('.m3u8')) {
        return currentPattern !== 'm3u8'; // filePattern=m3u8时返回false（不拦截），其他返回true（拦截）
      }
      
      return pathname.endsWith(`.${currentPattern}`);
    } catch (e) {
      const lowerUrl = url.toLowerCase();
      const currentPattern = window.filePattern || filePattern;
      const urlWithoutParams = lowerUrl.split('?')[0].split('#')[0];
      
      // 🔥 同样的逻辑
      if (urlWithoutParams.endsWith('.m3u8')) {
        return currentPattern !== 'm3u8';
      }
      
      const extensionPattern = new RegExp(`\\.(${currentPattern})$`);
      return extensionPattern.test(urlWithoutParams);
    }
  }

  // 提取并处理文本中的URL
  function extractAndProcessUrls(text, source, baseUrl) {
    if (!text || typeof text !== 'string') return;
    const currentPattern = window.filePattern || filePattern;
    
    if (text.length > 10000) {
      if (text.indexOf('.' + currentPattern) === -1) return;
    } else {
      if (!text.includes('.' + currentPattern)) return;
    }
    
    const urlRegex = getUrlRegex(currentPattern);
    const matches = text.match(urlRegex) || [];
    for (const match of matches) {
      const cleanUrl = match.replace(/^["'\s]+/, '');
      VideoUrlProcessor.processUrl(cleanUrl, 0, source, baseUrl);
    }
  }

  // URL处理工具：规范化与检测
  const VideoUrlProcessor = {
    processUrl(url, depth = 0, source = 'unknown', baseUrl) {
      if (!url || typeof url !== 'string' || depth > MAX_RECURSION_DEPTH || processedUrls.has(url)) return;
      
      url = this.normalizeUrl(url, baseUrl);
      if (!url || processedUrls.has(url)) return;
      
      const currentPattern = window.filePattern || filePattern;
      const fileRegex = getFileRegex(currentPattern);
      if (fileRegex.test(url)) {
        processedUrls.add(url);
        
        if (window.M3U8Detector && typeof window.M3U8Detector.postMessage === 'function') {
          try {
            window.M3U8Detector.postMessage(JSON.stringify({
              type: 'url',
              url,
              source
            }));
          } catch (msgError) {
            console.warn(`消息发送失败: ${source}`, msgError);
          }
        }
      }
    },

    // 规范化URL，清理冗余字符
    normalizeUrl(url, baseUrl = window.location.href) {
      if (!url || typeof url !== 'string') return '';
      try {
        url = url.replace(COMPILED_REGEX.CLEAN_URL, '$2');
        let parsedUrl;
        if (COMPILED_REGEX.ABSOLUTE_URL.test(url)) {
          parsedUrl = new URL(url);
        } else {
          parsedUrl = new URL(url, baseUrl);
        }
        parsedUrl.hostname = parsedUrl.hostname.toLowerCase();
        if ((parsedUrl.protocol === 'http:' && parsedUrl.port === '80') || 
            (parsedUrl.protocol === 'https:' && parsedUrl.port === '443')) {
          parsedUrl.port = '';
        }
        parsedUrl.hash = '';
        return parsedUrl.toString();
      } catch (e) {
        return url;
      }
    }
  };

  // 处理JSON中的URL
  function processJsonContent(jsonText, source, baseUrl) {
    try {
      const data = JSON.parse(jsonText);
      const currentPattern = window.filePattern || filePattern;
      const queue = [{obj: data, path: ''}];
      
      while (queue.length > 0 && queue.length < 1000) {
        const {obj, path} = queue.shift();
        if (typeof obj === 'string' && obj.includes('.' + currentPattern)) {
          VideoUrlProcessor.processUrl(obj, 0, `${source}:json:${path}`, baseUrl);
        } else if (obj && typeof obj === 'object') {
          const keys = Object.keys(obj).slice(0, 100);
          for (const key of keys) {
            const newPath = path ? `${path}.${key}` : key;
            queue.push({obj: obj[key], path: newPath});
          }
        }
      }
    } catch (e) {
      // JSON解析失败，忽略
    }
  }

  // 处理网络URL
  function handleNetworkUrl(url, source, content, contentType, baseUrl) {
    if (url) VideoUrlProcessor.processUrl(url, 0, source, baseUrl);
    if (content && typeof content === 'string') {
      extractAndProcessUrls(content, `${source}:content`, baseUrl);
      if (contentType?.includes('application/json')) {
        processJsonContent(content, source, baseUrl);
      }
    }
  }

  // 网络拦截器：拦截XHR、Fetch和MediaSource请求
  const NetworkInterceptor = {
    setupXHRInterceptor() {
      try {
        const XHR = XMLHttpRequest.prototype;
        const originalOpen = XHR.open;
        const originalSend = XHR.send;

        XHR.open = function() {
          this._url = arguments[1];
          this._isDirectMedia = isDirectMediaUrl(this._url);
          if (this._isDirectMedia) {
            VideoUrlProcessor.processUrl(this._url, 0, 'xhr:direct_media_intercepted');
          }
          if (this._url) {
            VideoUrlProcessor.processUrl(this._url, 0, 'xhr:request');
          }
          return originalOpen.apply(this, arguments);
        };

        XHR.send = function() {
          if (!this._url) {
            return originalSend.apply(this, arguments);
          }
          if (this._isDirectMedia) {
            setTimeout(() => {
              Object.defineProperties(this, {
                status: { value: 200, writable: false },
                readyState: { value: 4, writable: false },
                response: { value: '', writable: false },
                responseText: { value: '', writable: false }
              });
              this.dispatchEvent(new Event('load'));
            }, 0);
            return;
          }
          handleNetworkUrl(this._url, 'xhr');
          const handleLoad = () => {
            if (this.responseURL) handleNetworkUrl(this.responseURL, 'xhr:response');
            if (this.responseType === '' || this.responseType === 'text') {
              handleNetworkUrl(null, 'xhr:responseContent', this.responseText, null, this.responseURL);
            }
          };
          this.addEventListener('load', handleLoad);
          return originalSend.apply(this, arguments);
        };
      } catch (e) {
        console.error('XHR拦截器初始化失败', e);
      }
    },

    setupFetchInterceptor() {
      try {
        const originalFetch = window.fetch;
        window.fetch = function(input, init) {
          const url = (input instanceof Request) ? input.url : input;
          const isDirectMedia = isDirectMediaUrl(url);
          if (isDirectMedia && url) {
            VideoUrlProcessor.processUrl(url, 0, 'fetch:direct_media_intercepted');
            return Promise.resolve(new Response('', {
              status: 200,
              headers: {'content-type': 'text/plain'},
              url: url
            }));
          }
          handleNetworkUrl(url, 'fetch');
          
          const fetchPromise = originalFetch.apply(this, arguments);
          fetchPromise.then(response => {
            const contentType = response.headers.get('content-type')?.toLowerCase();
            if (contentType && (
                contentType.includes('application/json') ||
                contentType.includes('application/x-mpegURL') ||
                contentType.includes('text/plain')
            )) {
              response.clone().text().then(text => {
                handleNetworkUrl(response.url, 'fetch:response', text, contentType, response.url);
              }).catch(() => {
                // 响应读取失败，忽略
              });
            } else {
              handleNetworkUrl(response.url, 'fetch:response');
            }
            return response;
          }).catch(err => {
            throw err;
          });
          return fetchPromise;
        };
      } catch (e) {
        console.error('Fetch拦截器初始化失败', e);
      }
    },

    setupMediaSourceInterceptor() {
      if (!window.MediaSource) return;
      
      try {
        const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
        MediaSource.prototype.addSourceBuffer = function(mimeType) {
          if (SUPPORTED_MEDIA_TYPES.some(type => mimeType.includes(type))) {
            if (this.url) {
              VideoUrlProcessor.processUrl(this.url, 0, 'mediaSource');
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
              });
            }
            return url;
          };
        }
      } catch (e) {
        console.error('MediaSource拦截器初始化失败', e);
      }
    }
  };

  // DOM扫描器：扫描页面元素，提取媒体URL
  const DOMScanner = {
    processedElements: new WeakSet(),
    lastFullScanTime: 0,
    cachedElements: null,
    lastSelectorTime: 0,
    SELECTOR_CACHE_TTL: 3000,
    isScanning: false, // 防止并发扫描
    
    // 获取媒体元素，优先使用缓存
    getMediaElements(root = document) {
      if (root !== document) {
        return this.querySelectorMedia(root);
      }
      const now = Date.now();
      if (!this.cachedElements || (now - this.lastSelectorTime > this.SELECTOR_CACHE_TTL)) {
        this.cachedElements = this.querySelectorMedia(document);
        this.lastSelectorTime = now;
      }
      return this.cachedElements;
    },
    
    // 查询媒体元素选择器
    querySelectorMedia(root) {
      const selector = getMediaSelector() + ',[data-src],[data-url]';
      return root.querySelectorAll(selector);
    },

    // 扫描元素属性
    scanAttributes(element) {
      if (!element || !element.attributes) return;
      for (const attr of element.attributes) {
        if (attr.value && typeof attr.value === 'string') {
          VideoUrlProcessor.processUrl(attr.value, 0, `attribute:${attr.name}`);
        }
      }
    },

    // 扫描视频元素
    scanMediaElement(element) {
      if (!element || element.tagName !== 'VIDEO') return;
      
      if (element.src) {
        VideoUrlProcessor.processUrl(element.src, 0, 'video:src');
      }
      if (element.currentSrc) {
        VideoUrlProcessor.processUrl(element.currentSrc, 0, 'video:currentSrc');
      }
      
      const sources = element.querySelectorAll('source');
      for (const source of sources) {
        const src = source.src || source.getAttribute('src');
        if (src) {
          VideoUrlProcessor.processUrl(src, 0, 'video:source');
        }
      }
      
      if (!element._srcObserved) {
        element._srcObserved = true;
        const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (descriptor && descriptor.set) {
          const originalSrcSetter = descriptor.set;
          Object.defineProperty(element, 'src', {
            set(value) {
              if (value && typeof value === 'string') {
                VideoUrlProcessor.processUrl(value, 0, 'video:src:setter');
              }
              return originalSrcSetter.call(this, value);
            },
            get() {
              return element.getAttribute('src');
            },
            configurable: true
          });
        }
      }
    },

    // 扫描页面元素
    scanPage(root = document) {
      if (this.isScanning && root === document) {
        return;
      }
      if (root === document) {
        this.isScanning = true;
      }

      try {
        const now = Date.now();
        const isFullScan = now - this.lastFullScanTime > CONFIG.fullScanInterval;
        if (isFullScan) {
          this.lastFullScanTime = now;
          this.cachedElements = null;
        }
        
        const elements = this.getMediaElements(root);
        for (const element of elements) {
          if (!element || this.processedElements.has(element)) continue;
          
          this.processedElements.add(element);
          this.scanAttributes(element);
          this.scanMediaElement(element);
          
          if (element.tagName === 'A' && element.href) {
            VideoUrlProcessor.processUrl(element.href, 0, 'anchor');
          }
          if (isFullScan && element.attributes) {
            for (const attr of element.attributes) {
              if (attr.name.startsWith('data-') && attr.value) {
                VideoUrlProcessor.processUrl(attr.value, 0, 'data-attribute');
              }
            }
          }
        }
        
        if (isFullScan) {
          if (window.requestIdleCallback) {
            requestIdleCallback(() => this.scanScripts(), { timeout: 2000 });
          } else {
            setTimeout(() => this.scanScripts(), 200);
          }
        }
      } finally {
        if (root === document) {
          this.isScanning = false;
        }
      }
    },

    // 扫描脚本内容
    scanScripts() {
      const scripts = document.querySelectorAll('script:not([src])');
      for (const script of scripts) {
        const content = script.textContent;
        if (content && typeof content === 'string') {
          extractAndProcessUrls(content, 'script:regex');
        }
      }
    }
  };

  // 处理URL变化，防抖执行
  const handleUrlChange = debounce(() => {
    DOMScanner.scanPage(document);
  }, 300);

  // 处理队列中的URL和节点
  function processPendingQueue() {
    if (processingQueueTimer || pendingProcessQueue.size === 0) return;
    processingQueueTimer = setTimeout(() => {
      const currentQueue = new Set(pendingProcessQueue);
      pendingProcessQueue.clear();
      processingQueueTimer = null;
      
      const urlsToProcess = [];
      const nodesToScan = new Set();
      currentQueue.forEach(item => {
        if (typeof item === 'string') {
          urlsToProcess.push(item);
        } else if (item && item.parentNode) {
          nodesToScan.add(item.parentNode);
        }
      });
      
      urlsToProcess.forEach(url => {
        VideoUrlProcessor.processUrl(url, 0, 'mutation:string');
      });
      nodesToScan.forEach(node => {
        DOMScanner.scanPage(node);
      });
    }, 100);
  }

  // 初始化探测器
  function initializeDetector() {
    NetworkInterceptor.setupXHRInterceptor();
    NetworkInterceptor.setupFetchInterceptor();
    NetworkInterceptor.setupMediaSourceInterceptor();
    
    try {
      observer = new MutationObserver(mutations => {
        const newVideos = new Set();
        for (const mutation of mutations) {
          if (mutation.addedNodes.length > 0) {
            for (const node of mutation.addedNodes) {
              if (!node || node.nodeType !== 1) continue;
              if (node.tagName === 'VIDEO') {
                newVideos.add(node);
              }
              if (node instanceof Element && node.attributes) {
                for (const attr of node.attributes) {
                  if (attr.value && typeof attr.value === 'string') {
                    pendingProcessQueue.add(attr.value);
                  }
                }
              }
            }
          }
          if (mutation.type === 'attributes' && mutation.target) {
            const newValue = mutation.target.getAttribute(mutation.attributeName);
            if (newValue && typeof newValue === 'string') {
              pendingProcessQueue.add(newValue);
              const pattern = window.filePattern || filePattern;
              if (['src', 'data-src', 'href'].includes(mutation.attributeName) && 
                  newValue.includes('.' + pattern)) {
                VideoUrlProcessor.processUrl(newValue, 0, 'attribute:change');
              }
            }
          }
        }
        newVideos.forEach(video => {
          DOMScanner.scanMediaElement(video);
        });
        processPendingQueue();
      });
      
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true
      });
    } catch (e) {
      console.error('MutationObserver初始化失败', e);
    }
    
    window.addEventListener('popstate', handleUrlChange);
    window.addEventListener('hashchange', handleUrlChange);
    
    if (window.location.href) {
      VideoUrlProcessor.processUrl(window.location.href, 0, 'immediate:page_url');
    }
    // 执行初始扫描
    DOMScanner.scanPage(document);
  }

  // 立即执行初始化
  initializeDetector();

  // 清理探测器资源
  window._cleanupM3U8Detector = () => {
    if (observer) {
      observer.disconnect();
      observer = null;
    }
    window.removeEventListener('popstate', handleUrlChange);
    window.removeEventListener('hashchange', handleUrlChange);
    if (processingQueueTimer) {
      clearTimeout(processingQueueTimer);
      processingQueueTimer = null;
    }
    delete window._m3u8DetectorInitialized;
    processedUrls.clear();
    pendingProcessQueue.clear();
    DOMScanner.cachedElements = null;
    cachedMediaSelector = null;
    lastPatternForSelector = null;
    fileRegexCache.clear();
    urlRegexCache.clear();
  };

  // 外部接口：扫描指定根节点（供Dart调用）
  window.checkMediaElements = function(root) {
    if (root) DOMScanner.scanPage(root);
  };
  
  // 外部接口：高效扫描整个页面（供Dart调用）
  window.efficientDOMScan = function() {
    DOMScanner.scanPage(document);
  };
  
  // 发送初始化消息
  if (window.M3U8Detector) {
    try {
      window.M3U8Detector.postMessage(JSON.stringify({
        type: 'init',
        message: 'M3U8Detector initialized'
      }));
    } catch (e) {
      console.warn('初始化消息发送失败', e);
    }
  }
})();
