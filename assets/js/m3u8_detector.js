// 流媒体探测器：检测页面中的 m3u8 等流媒体文件
(function() {
  // 防止重复初始化
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

  // 使用 Set 替代 LRUCache，因为只需要去重功能
  const processedUrls = new Set(); // 已处理 URL 缓存
  let observer = null; // DOM 变化观察器
  const filePattern = "m3u8"; // 默认文件模式
  
  const CONFIG = {
    fullScanInterval: 60000 // 完整扫描间隔（毫秒）- 增加到60秒
  };

  const COMPILED_REGEX = {
    CLEAN_URL: /\\(\/|\\|"|')|([^:])\/\/+|[\s'"]+/g, // URL 清理正则
    ABSOLUTE_URL: /^https?:\/\//i // 绝对 URL 检测正则
  };

  const fileRegexCache = new Map(); // 文件正则缓存
  const urlRegexCache = new Map(); // URL 正则缓存
  const patternPrefixCache = new Map(); // 模式前缀缓存

  // 获取模式前缀（缓存优化）
  const getPatternPrefix = (pattern) => {
    if (!patternPrefixCache.has(pattern)) {
      patternPrefixCache.set(pattern, '.' + pattern);
    }
    return patternPrefixCache.get(pattern);
  };

  // 获取文件正则，缓存优化
  const getFileRegex = (pattern) => {
    if (!fileRegexCache.has(pattern)) {
      fileRegexCache.set(pattern, new RegExp(`\\.${pattern}([?#]|$)`, 'i'));
    }
    return fileRegexCache.get(pattern);
  };

  // 获取 URL 正则，缓存优化
  const getUrlRegex = (pattern) => {
    if (!urlRegexCache.has(pattern)) {
      urlRegexCache.set(pattern, new RegExp(`[^\\s'"()<>{}\\[\\]]*?\\.${pattern}[^\\s'"()<>{}\\[\\]]*`, 'g'));
    }
    return urlRegexCache.get(pattern);
  };
  
  const SUPPORTED_MEDIA_TYPES = [ // 支持的媒体类型
    'application/x-mpegURL', 
    'application/vnd.apple.mpegURL', 
    'video/x-flv', 
    'application/x-flv', 
    'flv-application/octet-stream',
    'video/mp4', 
    'application/mp4'
  ];

  let cachedMediaSelector = null; // 媒体选择器缓存
  let lastPatternForSelector = null; // 最后使用的文件模式

  // 获取媒体选择器
  function getMediaSelector() {
    const currentPattern = window.filePattern || filePattern;
    if (currentPattern !== lastPatternForSelector || !cachedMediaSelector) {
      lastPatternForSelector = currentPattern;
      cachedMediaSelector = [
        'video',
        'source',
        `a[href*="${currentPattern}"]`,
        `[data-src*="${currentPattern}"]`,
        `[data-${currentPattern}]`,
        '[class*="video"]',
        '[class*="player"]',
        `[class*="${currentPattern}"]`
      ].join(',');
    }
    return cachedMediaSelector;
  }

  // 更新文件模式并清理缓存
  window.updateFilePattern = function(newPattern) {
    if (newPattern && typeof newPattern === 'string' && newPattern !== filePattern) {
      window.filePattern = newPattern;
      fileRegexCache.clear();
      urlRegexCache.clear();
      patternPrefixCache.clear();
      cachedMediaSelector = null;
      lastPatternForSelector = null;
    }
  };

  let pendingProcessQueue = new Set(); // URL 处理队列
  let processingQueueTimer = null; // 队列处理定时器

  // 防抖函数，延迟执行
  const debounce = (func, wait) => {
    let timeout;
    return (...args) => {
      clearTimeout(timeout);
      timeout = setTimeout(() => func(...args), wait);
    };
  };

  // 检查是否为直接媒体 URL
  function isDirectMediaUrl(url) {
    if (!url || typeof url !== 'string') return false;
    
    const currentPattern = window.filePattern || filePattern;
    
    try {
      const parsedUrl = new URL(url, window.location.href);
      const pathname = parsedUrl.pathname.toLowerCase();
      
      if (pathname.endsWith('.m3u8')) {
        return currentPattern !== 'm3u8';
      }
      
      return pathname.endsWith(`.${currentPattern}`);
    } catch (e) {
      const lowerUrl = url.toLowerCase();
      const urlWithoutParams = lowerUrl.split('?')[0].split('#')[0];
      
      if (urlWithoutParams.endsWith('.m3u8')) {
        return currentPattern !== 'm3u8';
      }
      
      return urlWithoutParams.endsWith(`.${currentPattern}`);
    }
  }

  // 提取并处理文本中的 URL
  function extractAndProcessUrls(text, source, baseUrl) {
    if (!text || typeof text !== 'string') return;
    const currentPattern = window.filePattern || filePattern;
    const patternPrefix = getPatternPrefix(currentPattern);
    
    // 使用 indexOf 进行快速检查
    if (text.indexOf(patternPrefix) === -1) return;
    
    const urlRegex = getUrlRegex(currentPattern);
    const matches = text.match(urlRegex) || [];
    for (const match of matches) {
      const cleanUrl = match.replace(/^["'\s]+/, '');
      VideoUrlProcessor.processUrl(cleanUrl, source, baseUrl);
    }
  }

  // 处理媒体 URL
  const VideoUrlProcessor = {
    processUrl(url, source = 'unknown', baseUrl) {
      if (!url || typeof url !== 'string' || processedUrls.has(url)) return;
      
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

    // 规范化 URL
    normalizeUrl(url, baseUrl = window.location.href) {
      if (!url || typeof url !== 'string') return '';
      
      try {
        const cleanedUrl = url.replace(COMPILED_REGEX.CLEAN_URL, '$2');
        
        let parsedUrl;
        if (COMPILED_REGEX.ABSOLUTE_URL.test(cleanedUrl)) {
          parsedUrl = new URL(cleanedUrl);
        } else {
          parsedUrl = new URL(cleanedUrl, baseUrl);
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

  // 处理 JSON 内容中的 URL
  function processJsonContent(jsonText, source, baseUrl) {
    try {
      const data = JSON.parse(jsonText);
      const currentPattern = window.filePattern || filePattern;
      const patternPrefix = getPatternPrefix(currentPattern);
      const queue = [{obj: data, path: ''}];
      
      while (queue.length > 0 && queue.length < 1000) {
        const {obj, path} = queue.shift();
        if (typeof obj === 'string' && obj.indexOf(patternPrefix) !== -1) {
          VideoUrlProcessor.processUrl(obj, `${source}:json:${path}`, baseUrl);
        } else if (obj && typeof obj === 'object') {
          const keys = Object.keys(obj).slice(0, 100);
          for (const key of keys) {
            const newPath = path ? `${path}.${key}` : key;
            queue.push({obj: obj[key], path: newPath});
          }
        }
      }
    } catch (e) {}
  }

  // 处理网络请求 URL
  function handleNetworkUrl(url, source, content, contentType, baseUrl) {
    if (url) VideoUrlProcessor.processUrl(url, source, baseUrl);
    if (content && typeof content === 'string') {
      extractAndProcessUrls(content, `${source}:content`, baseUrl);
      if (contentType?.includes('application/json')) {
        processJsonContent(content, source, baseUrl);
      }
    }
  }

  // 网络请求拦截器
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
            VideoUrlProcessor.processUrl(this._url, 'XHR直接媒体拦截');
          }
          if (this._url) {
            VideoUrlProcessor.processUrl(this._url, 'XHR请求');
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
          handleNetworkUrl(this._url, 'XHR');
          const handleLoad = () => {
            if (this.responseURL) handleNetworkUrl(this.responseURL, 'XHR响应');
            if (this.responseType === '' || this.responseType === 'text') {
              handleNetworkUrl(null, 'XHR响应内容', this.responseText, null, this.responseURL);
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
            VideoUrlProcessor.processUrl(url, 'Fetch直接媒体拦截');
            return Promise.resolve(new Response('', {
              status: 200,
              headers: {'content-type': 'text/plain'},
              url: url
            }));
          }
          handleNetworkUrl(url, 'Fetch请求');
          
          const fetchPromise = originalFetch.apply(this, arguments);
          fetchPromise.then(response => {
            const contentType = response.headers.get('content-type')?.toLowerCase();
            if (contentType && (
                contentType.includes('application/json') ||
                contentType.includes('application/x-mpegURL') ||
                contentType.includes('text/plain')
            )) {
              response.clone().text().then(text => {
                handleNetworkUrl(response.url, 'Fetch响应', text, contentType, response.url);
              }).catch(() => {});
            } else {
              handleNetworkUrl(response.url, 'Fetch响应');
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
              VideoUrlProcessor.processUrl(this.url, '媒体源');
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
                        VideoUrlProcessor.processUrl(video.src, '媒体源视频');
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

  // DOM 扫描器
  const DOMScanner = {
    processedElements: new WeakSet(), // 已处理元素
    lastFullScanTime: 0, // 上次完整扫描时间
    cachedElements: null, // 缓存的元素
    lastSelectorTime: 0, // 上次选择器时间
    SELECTOR_CACHE_TTL: 3000, // 选择器缓存有效期
    isScanning: false, // 扫描状态
    
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
    
    querySelectorMedia(root) {
      const selector = getMediaSelector() + ',[data-src],[data-url]';
      return root.querySelectorAll(selector);
    },

    // 扫描元素属性
    scanAttributes(element) {
      if (!element || !element.attributes) return;
      const currentPattern = window.filePattern || filePattern;
      const patternPrefix = getPatternPrefix(currentPattern);
      
      for (const attr of element.attributes) {
        if (attr.value && typeof attr.value === 'string') {
          if (attr.value.indexOf(patternPrefix) !== -1) {
            VideoUrlProcessor.processUrl(attr.value, `DOM属性:${attr.name}`);
          }
        }
      }
    },

    // 扫描视频元素
    scanMediaElement(element) {
      if (!element || element.tagName !== 'VIDEO') return;
      
      if (element.src) {
        VideoUrlProcessor.processUrl(element.src, '视频src属性');
      }
      if (element.currentSrc) {
        VideoUrlProcessor.processUrl(element.currentSrc, '视频currentSrc');
      }
      
      const sources = element.querySelectorAll('source');
      for (const source of sources) {
        const src = source.src || source.getAttribute('src');
        if (src) {
          VideoUrlProcessor.processUrl(src, '视频source标签');
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
                VideoUrlProcessor.processUrl(value, '视频src设置');
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
        const currentPattern = window.filePattern || filePattern;
        const patternPrefix = getPatternPrefix(currentPattern);
        
        for (const element of elements) {
          if (!element || this.processedElements.has(element)) continue;
          
          this.processedElements.add(element);
          this.scanAttributes(element);
          this.scanMediaElement(element);
          
          if (element.tagName === 'A' && element.href) {
            VideoUrlProcessor.processUrl(element.href, 'anchor链接');
          }
          if (isFullScan && element.attributes) {
            for (const attr of element.attributes) {
              if (attr.name.startsWith('data-') && attr.value && attr.value.indexOf(patternPrefix) !== -1) {
                VideoUrlProcessor.processUrl(attr.value, 'data属性');
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
      const currentPattern = window.filePattern || filePattern;
      const patternPrefix = getPatternPrefix(currentPattern);
      
      for (const script of scripts) {
        const content = script.textContent;
        if (content && typeof content === 'string' && content.indexOf(patternPrefix) !== -1) {
          extractAndProcessUrls(content, '脚本内容');
        }
      }
    }
  };

  // 处理 URL 变化
  const handleUrlChange = debounce(() => {
    DOMScanner.scanPage(document);
  }, 300);

  // 处理待处理队列
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
        VideoUrlProcessor.processUrl(url, 'DOM变化');
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
        const currentPattern = window.filePattern || filePattern;
        const patternPrefix = getPatternPrefix(currentPattern);
        
        for (const mutation of mutations) {
          if (mutation.addedNodes.length > 0) {
            for (const node of mutation.addedNodes) {
              if (!node || node.nodeType !== 1) continue;
              if (node.tagName === 'VIDEO') {
                newVideos.add(node);
              }
              if (node instanceof Element && node.attributes) {
                for (const attr of node.attributes) {
                  if (attr.value && typeof attr.value === 'string' && attr.value.indexOf(patternPrefix) !== -1) {
                    pendingProcessQueue.add(attr.value);
                  }
                }
              }
            }
          }
          if (mutation.type === 'attributes' && mutation.target) {
            const newValue = mutation.target.getAttribute(mutation.attributeName);
            if (newValue && typeof newValue === 'string') {
              if (newValue.indexOf(patternPrefix) !== -1) {
                pendingProcessQueue.add(newValue);
                if (['src', 'data-src', 'href'].includes(mutation.attributeName)) {
                  VideoUrlProcessor.processUrl(newValue, '属性变化');
                }
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
      VideoUrlProcessor.processUrl(window.location.href, '页面URL');
    }
    DOMScanner.scanPage(document);
  }

  initializeDetector();

  // 清理探测器
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
    patternPrefixCache.clear();
  };
  
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
