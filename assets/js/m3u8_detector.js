// 流媒体探测器：检测页面中的 m3u8 等流媒体文件
(function() {
  // 防止重复初始化
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

  // 过滤规则（由Dart端注入）
  // INJECT_WHITE_EXTENSIONS
  // INJECT_BLOCKED_EXTENSIONS  
  // INJECT_INVALID_PATTERNS

  // 管理 URL 缓存，优化查询性能
  class LRUCache {
    constructor(capacity) {
      this.capacity = capacity; // 缓存容量
      this.cache = new Map(); // 缓存存储
    }
    
    // 检查键是否存在
    has(key) {
      return this.cache.has(key);
    }
    
    // 访问键并更新顺序
    access(key) {
      const hasKey = this.cache.has(key);
      if (hasKey) {
        const value = this.cache.get(key);
        this.cache.delete(key);
        this.cache.set(key, value);
      }
      return hasKey;
    }
    
    // 添加键，移除最旧项
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

  const processedUrls = new LRUCache(1000); // 已处理 URL 缓存
  const MAX_RECURSION_DEPTH = 3; // 最大递归深度
  const MAX_PENDING_QUEUE_SIZE = 1000; // 待处理队列最大大小
  let observer = null; // DOM 变化观察器
  const filePattern = "m3u8"; // 默认文件模式
  
  const CONFIG = {
    fullScanInterval: 3000 // 完整扫描间隔（毫秒）
  };

  const COMPILED_REGEX = {
    CLEAN_URL: /\\(\/|\\|"|')|([^:])\/\/+|[\s'"]+/g, // URL 清理正则
    ABSOLUTE_URL: /^https?:\/\//i // 绝对 URL 检测正则
  };

  const fileRegexCache = new Map(); // 文件正则缓存
  const urlRegexCache = new Map(); // URL 正则缓存

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

  // URL过滤函数（检查是否应该阻止）
  function shouldBlockUrl(url) {
    if (!url || typeof url !== 'string') return false;
    const lowerUrl = url.toLowerCase();
    
    // 白名单优先 - 如果在白名单中，不阻止
    if (typeof WHITE_EXTENSIONS !== 'undefined' && WHITE_EXTENSIONS && WHITE_EXTENSIONS.length > 0) {
      for (const ext of WHITE_EXTENSIONS) {
        if (lowerUrl.includes(ext.toLowerCase())) {
          console.log('白名单通过:', url);
          return false;
        }
      }
    }
    
    // 检查屏蔽扩展名
    if (typeof BLOCKED_EXTENSIONS !== 'undefined' && BLOCKED_EXTENSIONS && BLOCKED_EXTENSIONS.length > 0) {
      for (const ext of BLOCKED_EXTENSIONS) {
        if (lowerUrl.includes(ext.toLowerCase())) {
          console.log('屏蔽扩展名阻止:', url, '(匹配:', ext, ')');
          return true;
        }
      }
    }
    
    // 检查无效模式（广告、跟踪等）
    if (typeof INVALID_PATTERNS !== 'undefined' && INVALID_PATTERNS && INVALID_PATTERNS.length > 0) {
      for (const pattern of INVALID_PATTERNS) {
        if (lowerUrl.includes(pattern.toLowerCase())) {
          console.log('无效模式阻止:', url, '(匹配:', pattern, ')');
          return true;
        }
      }
    }
    
    return false;
  }

  // 修改被阻止的URL，使其无法加载
  function disableBlockedUrl(url) {
    if (!url || typeof url !== 'string' || !shouldBlockUrl(url)) return url;
    
    // 将扩展名前添加 'x'，使其无效
    const modifiedUrl = url.replace(/\.([a-zA-Z0-9]+)(?=[?#]|$)/, '.x$1');
    if (modifiedUrl !== url) {
      console.log('[拦截器] 修改URL:', url, '->', modifiedUrl);
    }
    return modifiedUrl;
  }

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

  // 处理媒体 URL
  const VideoUrlProcessor = {
    processUrl(url, depth = 0, source = 'unknown', baseUrl) {
      if (!url || typeof url !== 'string' || depth > MAX_RECURSION_DEPTH || processedUrls.has(url)) return;
      
      url = this.normalizeUrl(url, baseUrl);
      if (!url || processedUrls.has(url)) return;
      
      // 检查是否应该阻止此URL
      if (shouldBlockUrl(url)) {
        console.log('URL被过滤规则阻止:', url);
        return;
      }
      
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
    } catch (e) {}
  }

  // 处理网络请求 URL
  function handleNetworkUrl(url, source, content, contentType, baseUrl) {
    if (url) VideoUrlProcessor.processUrl(url, 0, source, baseUrl);
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
          this._shouldBlock = shouldBlockUrl(this._url);
          this._isDirectMedia = isDirectMediaUrl(this._url);
          
          if (this._shouldBlock) {
            console.log('阻止XHR请求:', this._url);
            this._blockedByFilter = true;
            return;
          }
          
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
          
          if (this._blockedByFilter) {
            // 模拟请求失败
            setTimeout(() => {
              Object.defineProperty(this, 'status', { value: 0, writable: false, configurable: true });
              Object.defineProperty(this, 'readyState', { value: 4, writable: false, configurable: true });
              Object.defineProperty(this, 'response', { value: '', writable: false, configurable: true });
              Object.defineProperty(this, 'responseText', { value: '', writable: false, configurable: true });
              this.dispatchEvent(new Event('error'));
              this.dispatchEvent(new Event('loadend'));
            }, 0);
            return;
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
          const shouldBlock = shouldBlockUrl(url);
          const isDirectMedia = isDirectMediaUrl(url);
          
          if (shouldBlock) {
            console.log('阻止Fetch请求:', url);
            // 返回一个失败的Promise
            return Promise.reject(new Error('请求被过滤规则阻止'));
          }
          
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
              }).catch(() => {});
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
            if (this.url && !shouldBlockUrl(this.url)) {
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
                      if (video.duration > 0 && video.src && !shouldBlockUrl(video.src)) {
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
      
      for (const attr of element.attributes) {
        if (attr.value && typeof attr.value === 'string') {
          // 修改被阻止的URL
          const modifiedValue = disableBlockedUrl(attr.value);
          if (modifiedValue !== attr.value) {
            element.setAttribute(attr.name, modifiedValue);
          }
          
          // 继续原有的m3u8检测
          if (attr.value.includes('.' + currentPattern)) {
            VideoUrlProcessor.processUrl(attr.value, 0, `attribute:${attr.name}`);
          }
        }
      }
    },

    // 扫描视频元素
    scanMediaElement(element) {
      if (!element || element.tagName !== 'VIDEO') return;
      
      // 修改被阻止的URL
      if (element.src) {
        const modifiedSrc = disableBlockedUrl(element.src);
        if (modifiedSrc !== element.src) {
          element.src = modifiedSrc;
        } else {
          VideoUrlProcessor.processUrl(element.src, 0, 'video:src');
        }
      }
      if (element.currentSrc && !shouldBlockUrl(element.currentSrc)) {
        VideoUrlProcessor.processUrl(element.currentSrc, 0, 'video:currentSrc');
      }
      
      const sources = element.querySelectorAll('source');
      for (const source of sources) {
        const src = source.src || source.getAttribute('src');
        if (src) {
          const modifiedSrc = disableBlockedUrl(src);
          if (modifiedSrc !== src) {
            source.setAttribute('src', modifiedSrc);
          } else {
            VideoUrlProcessor.processUrl(src, 0, 'video:source');
          }
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
                const modifiedValue = disableBlockedUrl(value);
                if (modifiedValue !== value) {
                  return originalSrcSetter.call(this, modifiedValue);
                }
                VideoUrlProcessor.processUrl(value, 0, 'video:src:setter');
                return originalSrcSetter.call(this, value);
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
        
        for (const element of elements) {
          if (!element || this.processedElements.has(element)) continue;
          
          this.processedElements.add(element);
          this.scanAttributes(element);
          this.scanMediaElement(element);
          
          if (element.tagName === 'A' && element.href) {
            const modifiedHref = disableBlockedUrl(element.href);
            if (modifiedHref !== element.href) {
              element.href = modifiedHref;
            } else {
              VideoUrlProcessor.processUrl(element.href, 0, 'anchor');
            }
          }
          if (isFullScan && element.attributes) {
            for (const attr of element.attributes) {
              if (attr.name.startsWith('data-') && attr.value && attr.value.includes('.' + currentPattern)) {
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
      const currentPattern = window.filePattern || filePattern;
      
      for (const script of scripts) {
        const content = script.textContent;
        if (content && typeof content === 'string' && content.includes('.' + currentPattern)) {
          extractAndProcessUrls(content, 'script:regex');
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
    
    if (pendingProcessQueue.size > MAX_PENDING_QUEUE_SIZE) {
      const items = Array.from(pendingProcessQueue);
      pendingProcessQueue.clear();
      items.slice(-MAX_PENDING_QUEUE_SIZE).forEach(item => pendingProcessQueue.add(item));
    }
    
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

  // 拦截 innerHTML 和 insertAdjacentHTML
  function interceptHTMLInsertion() {
    const originalInnerHTMLDescriptor = Object.getOwnPropertyDescriptor(Element.prototype, 'innerHTML');
    const originalInsertAdjacentHTML = Element.prototype.insertAdjacentHTML;
    
    // 处理HTML字符串中的URL
    const processHTMLString = (html) => {
      if (!html || typeof html !== 'string') return html;
      
      // 处理标签属性中的URL
      html = html.replace(/(src|href|data|poster|srcset)\s*=\s*["']([^"']+)["']/gi, (match, attr, url) => {
        const modifiedUrl = disableBlockedUrl(url);
        if (modifiedUrl !== url) {
          return `${attr}="${modifiedUrl}"`;
        }
        return match;
      });
      
      // 处理内联样式中的URL
      html = html.replace(/style\s*=\s*["']([^"']+)["']/gi, (match, style) => {
        const processedStyle = style.replace(/url\(['"]?([^'")]+)['"]?\)/g, (urlMatch, url) => {
          const modifiedUrl = disableBlockedUrl(url);
          if (modifiedUrl !== url) {
            return `url('${modifiedUrl}')`;
          }
          return urlMatch;
        });
        return `style="${processedStyle}"`;
      });
      
      return html;
    };
    
    Object.defineProperty(Element.prototype, 'innerHTML', {
      set(value) {
        if (value && typeof value === 'string') {
          value = processHTMLString(value);
        }
        return originalInnerHTMLDescriptor.set.call(this, value);
      },
      get: originalInnerHTMLDescriptor.get,
      configurable: true
    });
    
    Element.prototype.insertAdjacentHTML = function(position, html) {
      if (html && typeof html === 'string') {
        html = processHTMLString(html);
      }
      return originalInsertAdjacentHTML.call(this, position, html);
    };
  }

  // 处理内联样式
  function processInlineStyles() {
    // 处理 style 属性
    document.querySelectorAll('[style*="url("]').forEach(element => {
      let styleText = element.getAttribute('style');
      const processedStyle = styleText.replace(/url\(['"]?([^'")]+)['"]?\)/g, (match, url) => {
        const modifiedUrl = disableBlockedUrl(url);
        if (modifiedUrl !== url) {
          return `url('${modifiedUrl}')`;
        }
        return match;
      });
      
      if (processedStyle !== styleText) {
        element.setAttribute('style', processedStyle);
      }
    });
    
    // 处理 <style> 标签
    document.querySelectorAll('style').forEach(styleTag => {
      if (styleTag.textContent && styleTag.textContent.includes('url(')) {
        const processedContent = styleTag.textContent.replace(/url\(['"]?([^'")]+)['"]?\)/g, (match, url) => {
          const modifiedUrl = disableBlockedUrl(url);
          if (modifiedUrl !== url) {
            return `url('${modifiedUrl}')`;
          }
          return match;
        });
        
        if (processedContent !== styleTag.textContent) {
          styleTag.textContent = processedContent;
        }
      }
    });
  }

  // 处理已存在的元素
  function processExistingElements() {
    // 处理所有可能包含URL的属性
    const urlAttributes = ['src', 'href', 'data', 'poster', 'srcset'];
    const selector = urlAttributes.map(attr => `[${attr}]`).join(',');
    
    document.querySelectorAll(selector).forEach(element => {
      urlAttributes.forEach(attr => {
        const value = element.getAttribute(attr);
        if (value) {
          const modifiedValue = disableBlockedUrl(value);
          if (modifiedValue !== value) {
            element.setAttribute(attr, modifiedValue);
          }
        }
      });
    });
    
    // 处理内联样式
    processInlineStyles();
  }

  // 初始化探测器
  function initializeDetector() {
    NetworkInterceptor.setupXHRInterceptor();
    NetworkInterceptor.setupFetchInterceptor();
    NetworkInterceptor.setupMediaSourceInterceptor();
    
    // 拦截HTML插入
    interceptHTMLInsertion();
    
    try {
      observer = new MutationObserver(mutations => {
        const newVideos = new Set();
        const currentPattern = window.filePattern || filePattern;
        
        for (const mutation of mutations) {
          if (mutation.addedNodes.length > 0) {
            for (const node of mutation.addedNodes) {
              if (!node || node.nodeType !== 1) continue;
              if (node.tagName === 'VIDEO') {
                newVideos.add(node);
              }
              if (node instanceof Element && node.attributes) {
                // 立即处理新增元素的属性
                DOMScanner.scanAttributes(node);
                // 递归处理子元素
                if (node.querySelectorAll) {
                  node.querySelectorAll('*').forEach(child => {
                    DOMScanner.scanAttributes(child);
                  });
                }
                
                for (const attr of node.attributes) {
                  if (attr.value && typeof attr.value === 'string' && attr.value.includes('.' + currentPattern)) {
                    pendingProcessQueue.add(attr.value);
                  }
                }
              }
            }
          }
          if (mutation.type === 'attributes' && mutation.target) {
            const newValue = mutation.target.getAttribute(mutation.attributeName);
            if (newValue && typeof newValue === 'string') {
              // 立即修改被阻止的URL
              const modifiedValue = disableBlockedUrl(newValue);
              if (modifiedValue !== newValue) {
                mutation.target.setAttribute(mutation.attributeName, modifiedValue);
                continue;
              }
              
              if (newValue.includes('.' + currentPattern)) {
                pendingProcessQueue.add(newValue);
                if (['src', 'data-src', 'href'].includes(mutation.attributeName)) {
                  VideoUrlProcessor.processUrl(newValue, 0, 'attribute:change');
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
    
    // 处理已存在的元素
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', processExistingElements);
    } else {
      processExistingElements();
    }
    
    if (window.location.href) {
      VideoUrlProcessor.processUrl(window.location.href, 0, 'immediate:page_url');
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
  };

  window.checkMediaElements = function(root) {
    if (root) DOMScanner.scanPage(root);
  };
  
  window.efficientDOMScan = function() {
    DOMScanner.scanPage(document);
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
