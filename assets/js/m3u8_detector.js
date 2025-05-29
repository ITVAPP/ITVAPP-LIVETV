// 流媒体探测器：检测页面中的 m3u8 等流媒体文件
(function() {
  // 防止重复初始化m3u8探测器
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true; // 标记探测器已初始化

  // LRU缓存管理已处理URL
  class LRUCache {
    constructor(capacity) {
      this.capacity = capacity; // 设置缓存容量
      this.cache = new Map(); // 初始化缓存映射
    }
    
    // 检查并更新URL的最近使用状态
    has(key) {
      const hasKey = this.cache.has(key);
      if (hasKey) {
        const value = this.cache.get(key);
        this.cache.delete(key);
        this.cache.set(key, value);
      }
      return hasKey;
    }
    
    // 添加新URL，必要时移除最旧URL
    add(key) {
      if (this.cache.has(key)) {
        this.cache.delete(key);
      } else if (this.cache.size >= this.capacity) {
        const oldestKey = this.cache.keys().next().value;
        this.cache.delete(oldestKey);
      }
      this.cache.set(key, true);
    }
    
    // 清空URL缓存
    clear() {
      this.cache.clear();
    }
    
    // 获取当前缓存大小
    get size() {
      return this.cache.size;
    }
  }

  const processedUrls = new LRUCache(1000); // 初始化URL缓存，容量1000
  const MAX_RECURSION_DEPTH = 3; // 设置最大递归深度
  let observer = null; // DOM变化观察器
  const filePattern = "m3u8"; // 目标文件扩展名
  
  // 全局探测器配置
  const CONFIG = {
    fullScanInterval: 5000, // 全面扫描间隔（毫秒）
    maxProcessedElements: 500, // 最大处理元素数
    enableErrorLogging: false // 启用错误日志
  };

  // 统一处理错误并记录日志
  const handleError = (error, context = '', isCritical = false) => {
    if (CONFIG.enableErrorLogging) {
      console.warn(`[M3U8Detector${context ? ':' + context : ''}] 错误: ${error.message || error}`);
    }
    
    // 关键错误通知主程序
    if (isCritical && window.M3U8Detector) {
      window.M3U8Detector.postMessage(JSON.stringify({
        type: 'error',
        message: `${context || '未知'}: ${error.message || error}`,
        details: { context, error: error.message }
      }));
    }
  };

  // 预编译正则表达式以优化URL处理
  const COMPILED_REGEX = {
    CLEAN_URL: /\\(\/|\\|"|')|([^:])\/\/+|[\s'"]+/g, // 清理URL中的冗余字符
    ABSOLUTE_URL: /^https?:\/\//i, // 匹配HTTP/HTTPS协议
    URL_PARAMS_HASH: /[?#].*$/g, // 移除URL参数和锚点
    MULTIPLE_SLASHES: /\/+/g, // 合并多个斜杠
    URL_WHITESPACE: /^\s+|\s+$/g // 清除URL首尾空白
  };

  const fileRegexCache = new Map(); // 缓存文件正则表达式
  const urlRegexCache = new Map(); // 缓存URL正则表达式

  // 获取匹配文件扩展名的正则表达式
  const getFileRegex = (pattern) => {
    if (!fileRegexCache.has(pattern)) {
      fileRegexCache.set(pattern, new RegExp(`\\.${pattern}([?#]|$)`, 'i'));
    }
    return fileRegexCache.get(pattern);
  };

  // 获取匹配URL的正则表达式
  const getUrlRegex = (pattern) => {
    if (!urlRegexCache.has(pattern)) {
      urlRegexCache.set(pattern, new RegExp(`[^\\s'"()<>{}\\[\\]]*?\\.${pattern}[^\\s'"()<>{}\\[\\]]*`, 'g'));
    }
    return urlRegexCache.get(pattern);
  };
  
  const SUPPORTED_MEDIA_TYPES = [
    'application/x-mpegURL', 
    'application/vnd.apple.mpegURL', 
    'video/x-flv', 
    'application/x-flv', 
    'flv-application/octet-stream',
    'video/mp4', 
    'application/mp4'
  ]; // 支持的媒体MIME类型

  let cachedMediaSelector = null; // 缓存媒体元素选择器
  let lastPatternForSelector = null; // 缓存上次使用的文件模式

  // 生成媒体元素选择器
  function getMediaSelector() {
    const currentPattern = window.filePattern || filePattern;
    if (currentPattern !== lastPatternForSelector || !cachedMediaSelector) {
      lastPatternForSelector = currentPattern;
      cachedMediaSelector = [
        'video',
        'source',
        '[class*="video"]',
        '[class*="player"]',
        `[class*="${currentPattern}"]`,
        `[data-${currentPattern}]`,
        `a[href*="${currentPattern}"]`,
        `[data-src*="${currentPattern}"]`
      ].join(',');
    }
    return cachedMediaSelector;
  }

  // 更新文件扩展名模式并清空相关缓存
  window.updateFilePattern = function(newPattern) {
    if (newPattern && typeof newPattern === 'string' && newPattern !== filePattern) {
      window.filePattern = newPattern;
      fileRegexCache.clear();
      urlRegexCache.clear();
      cachedMediaSelector = null;
      lastPatternForSelector = null;
    }
  };

  let pendingProcessQueue = new Set(); // 待处理URL队列
  let processingQueueTimer = null; // 队列处理定时器
  const processedAttributes = new WeakMap(); // 缓存已处理属性

  // 防抖函数，延迟执行以优化性能
  const debounce = (func, wait) => {
    let timeout;
    return (...args) => {
      clearTimeout(timeout);
      timeout = setTimeout(() => func(...args), wait);
    };
  };

  // 检查是否为直接媒体URL
  function isDirectMediaUrl(url) {
    if (!url || typeof url !== 'string') return false;
    
    const lowerUrl = url.toLowerCase();
    const currentPattern = window.filePattern || filePattern;
    const hasTargetExtension = lowerUrl.includes(`.${currentPattern}`);
    
    if (!hasTargetExtension) return false;
    
    try {
      const parsedUrl = new URL(url, window.location.href);
      const pathname = parsedUrl.pathname.toLowerCase();
      return pathname.endsWith(`.${currentPattern}`);
    } catch (e) {
      const urlWithoutParams = lowerUrl.replace(COMPILED_REGEX.URL_PARAMS_HASH, '');
      const extensionPattern = new RegExp(`\\.(${currentPattern})$`);
      return extensionPattern.test(urlWithoutParams);
    }
  }

  // 提取并处理文本中的URL
  function extractAndProcessUrls(text, source, baseUrl) {
    if (!text || typeof text !== 'string') return;
    const currentPattern = window.filePattern || filePattern;
    if (!text.includes('.' + currentPattern)) return;
    
    const urlRegex = getUrlRegex(currentPattern);
    const matches = text.match(urlRegex);
    if (!matches) return;
    
    for (let i = 0; i < matches.length; i++) {
      const cleanUrl = matches[i].replace(COMPILED_REGEX.URL_WHITESPACE, '');
      VideoUrlProcessor.processUrl(cleanUrl, 0, source, baseUrl);
    }
  }

  // URL处理工具，规范化并发送媒体URL
  const VideoUrlProcessor = {
    processUrl(url, depth = 0, source = 'unknown', baseUrl) {
      try {
        if (!url || typeof url !== 'string' || depth > MAX_RECURSION_DEPTH || processedUrls.has(url)) return;
        url = this.normalizeUrl(url, baseUrl);
        if (!url || processedUrls.has(url)) return;
        const currentPattern = window.filePattern || filePattern;
        const fileRegex = getFileRegex(currentPattern);
        if (fileRegex.test(url)) {
          processedUrls.add(url);
          if (window.M3U8Detector && typeof window.M3U8Detector.postMessage === 'function') {
            window.M3U8Detector.postMessage(JSON.stringify({
              type: 'url',
              message: `检测到媒体URL: ${url}`,
              details: { url, source }
            }));
          }
        }
      } catch (e) {
        handleError(e, `processUrl:${source}`, true);
      }
    },

    // 规范化URL，清理冗余字符并解析相对路径
    normalizeUrl(url, baseUrl = window.location.href) {
      if (!url || typeof url !== 'string') return '';
      try {
        url = url.replace(COMPILED_REGEX.URL_WHITESPACE, '');
        if (url.includes('\\')) {
          url = url.replace(/\\/g, '/');
        }
        if (url.includes('//') && !COMPILED_REGEX.ABSOLUTE_URL.test(url)) {
          url = url.replace(COMPILED_REGEX.MULTIPLE_SLASHES, '/');
        }
        
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
        handleError(e, 'normalizeUrl', false);
        return url;
      }
    }
  };

  // 处理JSON内容中的URL，限制递归深度
  function processJsonContent(jsonText, source, baseUrl) {
    try {
      const data = JSON.parse(jsonText);
      const currentPattern = window.filePattern || filePattern;
      const queue = [{obj: data, path: '', depth: 0}];
      const MAX_QUEUE_SIZE = 1000;
      const MAX_DEPTH = 10;
      
      while (queue.length > 0 && queue.length < MAX_QUEUE_SIZE) {
        const {obj, path, depth} = queue.shift();
        if (depth > MAX_DEPTH) continue;
        
        if (typeof obj === 'string' && obj.includes('.' + currentPattern)) {
          VideoUrlProcessor.processUrl(obj, 0, `${source}:json:${path}`, baseUrl);
        } else if (obj && typeof obj === 'object') {
          const keys = Object.keys(obj).slice(0, 100);
          for (const key of keys) {
            const newPath = path ? `${path}.${key}` : key;
            queue.push({obj: obj[key], path: newPath, depth: depth + 1});
          }
        }
      }
    } catch (e) {
      handleError(e, `processJsonContent:${source}`, false);
    }
  }

  // 处理网络请求中的URL和内容
  function handleNetworkUrl(url, source, content, contentType, baseUrl) {
    try {
      if (url) VideoUrlProcessor.processUrl(url, 0, source, baseUrl);
      if (content && typeof content === 'string') {
        extractAndProcessUrls(content, `${source}:content`, baseUrl);
        if (contentType?.includes('application/json')) {
          processJsonContent(content, source, baseUrl);
        }
      }
    } catch (e) {
      handleError(e, `handleNetworkUrl:${source}`, false);
    }
  }

  // 网络请求拦截器
  const NetworkInterceptor = {
    // 拦截并处理XHR请求
    setupXHRInterceptor() {
      try {
        const XHR = XMLHttpRequest.prototype;
        const originalOpen = XHR.open;
        const originalSend = XHR.send;

        XHR.open = function() {
          try {
            this._url = arguments[1];
            this._isDirectMedia = isDirectMediaUrl(this._url);
            if (this._isDirectMedia) {
              VideoUrlProcessor.processUrl(this._url, 0, 'xhr:direct_media');
            }
            if (this._url) {
              VideoUrlProcessor.processUrl(this._url, 0, 'xhr:request');
            }
          } catch (e) {
            handleError(e, 'XHR.open', false);
          }
          return originalOpen.apply(this, arguments);
        };

        XHR.send = function() {
          try {
            if (!this._url) return originalSend.apply(this, arguments);
            if (this._isDirectMedia) {
              setTimeout(() => {
                try {
                  Object.defineProperties(this, {
                    status: { value: 200, writable: false },
                    readyState: { value: 4, writable: false },
                    response: { value: '', writable: false },
                    responseText: { value: '', writable: false }
                  });
                  this.dispatchEvent(new Event('load'));
                } catch (e) {
                  handleError(e, 'XHR.send:direct_media', false);
                }
              }, 0);
              return;
            }
            handleNetworkUrl(this._url, 'xhr');
            const handleLoad = () => {
              try {
                if (this.responseURL) handleNetworkUrl(this.responseURL, 'xhr:response');
                if (this.responseType === '' || this.responseType === 'text') {
                  handleNetworkUrl(null, 'xhr:responseContent', this.responseText, null, this.responseURL);
                }
              } catch (e) {
                handleError(e, 'XHR.load', false);
              }
            };
            this.addEventListener('load', handleLoad);
          } catch (e) {
            handleError(e, 'XHR.send', false);
          }
          return originalSend.apply(this, arguments);
        };
      } catch (e) {
        handleError(e, 'setupXHRInterceptor', true);
      }
    },

    // 拦截并处理Fetch请求
    setupFetchInterceptor() {
      try {
        const originalFetch = window.fetch;
        window.fetch = function(input, init) {
          try {
            const url = (input instanceof Request) ? input.url : input;
            const isDirectMedia = isDirectMediaUrl(url);
            if (isDirectMedia && url) {
              VideoUrlProcessor.processUrl(url, 0, 'fetch:direct_media');
              return Promise.resolve(new Response('', {
                status: 200,
                headers: {'content-type': 'text/plain'},
                url: url
              }));
            }
            handleNetworkUrl(url, 'fetch');
          } catch (e) {
            handleError(e, 'fetch:request', false);
          }
          
          const fetchPromise = originalFetch.apply(this, arguments);
          fetchPromise.then(response => {
            try {
              const contentType = response.headers.get('content-type')?.toLowerCase();
              if (contentType && (
                  contentType.includes('application/json') ||
                  contentType.includes('application/x-mpegURL') ||
                  contentType.includes('text/plain')
              )) {
                response.clone().text().then(text => {
                  handleNetworkUrl(response.url, 'fetch:response', text, contentType, response.url);
                }).catch(err => {
                  handleError(err, 'fetch:responseText', false);
                });
              } else {
                handleNetworkUrl(response.url, 'fetch:response');
              }
            } catch (e) {
              handleError(e, 'fetch:response', false);
            }
            return response;
          }).catch(err => { 
            handleError(err, 'fetch:promise', true);
            throw err; 
          });
          return fetchPromise;
        };
      } catch (e) {
        handleError(e, 'setupFetchInterceptor', true);
      }
    },

    // 拦截MediaSource相关操作
    setupMediaSourceInterceptor() {
      try {
        if (!window.MediaSource) return;
        const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
        MediaSource.prototype.addSourceBuffer = function(mimeType) {
          try {
            if (SUPPORTED_MEDIA_TYPES.some(type => mimeType.includes(type))) {
              if (this.url) {
                VideoUrlProcessor.processUrl(this.url, 0, 'mediaSource');
              }
            }
          } catch (e) {
            handleError(e, 'addSourceBuffer', false);
          }
          return originalAddSourceBuffer.call(this, mimeType);
        };
        
        const originalURL = window.URL || window.webkitURL;
        if (originalURL && originalURL.createObjectURL) {
          const originalCreateObjectURL = originalURL.createObjectURL;
          originalURL.createObjectURL = function(obj) {
            const url = originalCreateObjectURL.call(this, obj);
            try {
              if (obj instanceof MediaSource) {
                requestAnimationFrame(() => {
                  try {
                    const videoElements = document.querySelectorAll('video');
                    videoElements.forEach(video => {
                      if (video && video.src === url) {
                        const handleMetadata = () => {
                          try {
                            if (video.duration > 0 && video.src) {
                              VideoUrlProcessor.processUrl(video.src, 0, 'mediaSource:video');
                            }
                          } catch (e) {
                            handleError(e, 'mediaSource:video', false);
                          }
                          video.removeEventListener('loadedmetadata', handleMetadata);
                        };
                        video.addEventListener('loadedmetadata', handleMetadata);
                      }
                    });
                  } catch (e) {
                    handleError(e, 'createObjectURL', false);
                  }
                });
              }
            } catch (e) {
              handleError(e, 'createObjectURL', false);
            }
            return url;
          };
        }
      } catch (e) {
        handleError(e, 'setupMediaSourceInterceptor', true);
      }
    }
  };

  // DOM扫描器，检测页面中的媒体元素
  const DOMScanner = {
    processedElements: new WeakSet(), // 缓存已处理元素
    lastFullScanTime: 0, // 上次全面扫描时间
    processedCount: 0, // 已处理元素计数
    cachedElements: null, // DOM元素缓存
    lastSelectorTime: 0, // 上次选择器查询时间
    SELECTOR_CACHE_TTL: 2000, // 选择器缓存有效期（毫秒）
    elementAttributeCache: new WeakMap(), // 元素属性缓存
    
    // 获取媒体元素，优化缓存策略
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
    
    // 查询包含媒体相关属性的DOM元素
    querySelectorMedia(root) {
      const selector = getMediaSelector() + ',[data-src],[data-url]';
      return root.querySelectorAll(selector);
    },

    // 扫描元素属性，检测潜在媒体URL
    scanAttributes(element) {
      try {
        if (!element || !element.attributes) return;
        
        const lastProcessedTime = this.elementAttributeCache.get(element);
        const now = Date.now();
        if (lastProcessedTime && (now - lastProcessedTime < 1000)) return;
        
        for (const attr of element.attributes) {
          if (attr.value && typeof attr.value === 'string') {
            VideoUrlProcessor.processUrl(attr.value, 0, `attribute:${attr.name}`);
          }
        }
        
        this.elementAttributeCache.set(element, now);
      } catch (e) {
        handleError(e, 'scanAttributes', false);
      }
    },

    // 扫描视频元素及其source子节点
    scanMediaElement(element) {
      try {
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
          try {
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
          } catch (e) {
            handleError(e, 'scanMediaElement:srcSetter', false);
          }
        }
      } catch (e) {
        handleError(e, 'scanMediaElement', false);
      }
    },

    // 扫描页面中的媒体元素
    scanPage(root = document) {
      try {
        const now = Date.now();
        const isFullScan = now - this.lastFullScanTime > CONFIG.fullScanInterval;
        if (isFullScan) {
          this.lastFullScanTime = now;
          this.processedCount = 0;
          this.cachedElements = null;
        }
        
        const elements = this.getMediaElements(root);
        const elementsToProcess = [];
        
        for (const element of elements) {
          if (!element || this.processedElements.has(element)) continue;
          elementsToProcess.push(element);
        }
        
        for (const element of elementsToProcess) {
          try {
            this.processedElements.add(element);
            this.processedCount++;
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
          } catch (e) {
            handleError(e, 'scanElement', false);
          }
        }
        
        if (isFullScan) {
          if (window.requestIdleCallback) {
            requestIdleCallback(() => this.scanScripts(), { timeout: 2000 });
          } else {
            setTimeout(() => this.scanScripts(), 200);
          }
        }
      } catch (e) {
        handleError(e, 'scanPage', true);
      }
    },

    // 扫描内联脚本中的URL
    scanScripts() {
      try {
        const scripts = document.querySelectorAll('script:not([src])');
        for (const script of scripts) {
          try {
            const content = script.textContent;
            if (content && typeof content === 'string') {
              extractAndProcessUrls(content, 'script:regex');
            }
          } catch (e) {
            handleError(e, 'scanScripts:script', false);
          }
        }
      } catch (e) {
        handleError(e, 'scanScripts', false);
      }
    }
  };

  // 处理URL变化，防抖执行扫描
  const handleUrlChange = debounce(() => {
    try {
      DOMScanner.scanPage(document);
    } catch (e) {
      handleError(e, 'handleUrlChange', false);
    }
  }, 300);

  // 批量处理待处理队列
  function processPendingQueue() {
    try {
      if (processingQueueTimer || pendingProcessQueue.size === 0) return;
      processingQueueTimer = setTimeout(() => {
        try {
          const currentQueue = Array.from(pendingProcessQueue);
          pendingProcessQueue.clear();
          processingQueueTimer = null;
          const urlsToProcess = [];
          const nodesToScan = new Set();
          
          for (let i = 0; i < currentQueue.length; i++) {
            const item = currentQueue[i];
            if (typeof item === 'string') {
              urlsToProcess.push(item);
            } else if (item && item.parentNode) {
              nodesToScan.add(item.parentNode);
            }
          }
          
          for (let i = 0; i < urlsToProcess.length; i++) {
            VideoUrlProcessor.processUrl(urlsToProcess[i], 0, 'mutation:string');
          }
          
          nodesToScan.forEach(node => {
            DOMScanner.scanPage(node);
          });
        } catch (e) {
          processingQueueTimer = null;
          handleError(e, 'processPendingQueue', false);
        }
      }, 100);
    } catch (e) {
      handleError(e, 'processPendingQueue', false);
    }
  }

  // 定期扫描页面
  let lastScanTime = 0;
  const SCAN_INTERVAL = 1000;

  function scheduleNextScan() {
    try {
      if (document.hidden) {
        setTimeout(scheduleNextScan, SCAN_INTERVAL * 2);
        return;
      }
      const now = Date.now();
      const timeSinceLastScan = now - lastScanTime;
      if (timeSinceLastScan >= SCAN_INTERVAL) {
        lastScanTime = now;
        DOMScanner.scanPage(document);
        setTimeout(scheduleNextScan, SCAN_INTERVAL);
      } else {
        const remainingTime = SCAN_INTERVAL - timeSinceLastScan;
        setTimeout(scheduleNextScan, remainingTime);
      }
    } catch (e) {
      handleError(e, 'scheduleNextScan', false);
      setTimeout(scheduleNextScan, SCAN_INTERVAL);
    }
  }

  // 初始化m3u8探测器
  function initializeDetector() {
    try {
      NetworkInterceptor.setupXHRInterceptor();
      NetworkInterceptor.setupFetchInterceptor();
      NetworkInterceptor.setupMediaSourceInterceptor();
      
      observer = new MutationObserver(mutations => {
        try {
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
          
          if (newVideos.size > 0) {
            newVideos.forEach(video => {
              DOMScanner.scanMediaElement(video);
            });
          }
          
          processPendingQueue();
        } catch (e) {
          handleError(e, 'mutationObserver', false);
        }
      });
      
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['src', 'data-src', 'href', 'data-url']
      });

      if (window.location.href) {
        VideoUrlProcessor.processUrl(window.location.href, 0, 'page_url');
      }
      
      DOMScanner.scanPage(document);
      scheduleNextScan();
    } catch (e) {
      handleError(e, 'initializeDetector', true);
    }
  }

  // 立即执行探测器初始化
  initializeDetector();

  // 清理探测器，释放资源
  window._cleanupM3U8Detector = () => {
    try {
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
      DOMScanner.processedCount = 0;
      DOMScanner.cachedElements = null;
      DOMScanner.elementAttributeCache = new WeakMap();
      cachedMediaSelector = null;
      lastPatternForSelector = null;
      fileRegexCache.clear();
      urlRegexCache.clear();
    } catch (e) {
      handleError(e, 'cleanup', true);
    }
  };

  // 扫描指定根节点的媒体元素
  window.checkMediaElements = function(root) {
    try {
      DOMScanner.scanPage(root);
    } catch (e) {
      handleError(e, 'checkMediaElements', false);
    }
  };
  
  // 执行高效DOM扫描
  window.efficientDOMScan = function() {
    try {
      DOMScanner.scanPage(document);
    } catch (e) {
      handleError(e, 'efficientDOMScan', false);
    }
  };
})();
