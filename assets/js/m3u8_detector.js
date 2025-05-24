// 流媒体探测器：检测页面中的 m3u8 等流媒体文件
(function() {
  // 防止重复初始化
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true; // 标记初始化完成

  // 使用LRU缓存存储已处理URL
  class LRUCache {
    constructor(capacity) {
      this.capacity = capacity; // 设置缓存容量
      this.cache = new Map(); // 初始化缓存映射
    }
    
    has(key) {
      const hasKey = this.cache.has(key); // 检查键是否存在
      if (hasKey) {
        // 访问时将键移到最后
        const value = this.cache.get(key);
        this.cache.delete(key);
        this.cache.set(key, value);
      }
      return hasKey;
    }
    
    add(key) {
      // 如果键已存在，先删除再添加，确保它在最后位置
      if (this.cache.has(key)) {
        this.cache.delete(key);
      } else if (this.cache.size >= this.capacity) {
        // 删除最不常用的项（第一个）
        const oldestKey = this.cache.keys().next().value;
        this.cache.delete(oldestKey);
      }
      this.cache.set(key, true); // 添加新键
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

  // 预编译通用正则表达式
  const COMPILED_REGEX = {
    CLEAN_URL: /\\(\/|\\|"|')|([^:])\/\/+|[\s'"]+/g, // 清理URL的正则
    ABSOLUTE_URL: /^https?:\/\//i // HTTP/HTTPS协议正则
  };

  // 正则表达式缓存
  const fileRegexCache = new Map(); // 缓存文件正则
  const urlRegexCache = new Map(); // 缓存URL正则

  // 获取文件正则表达式
  const getFileRegex = (pattern) => {
    if (!fileRegexCache.has(pattern)) {
      fileRegexCache.set(pattern, new RegExp(`\\.${pattern}([?#]|$)`, 'i')); // 创建并缓存文件正则
    }
    return fileRegexCache.get(pattern);
  };

  // 获取URL正则表达式
  const getUrlRegex = (pattern) => {
    if (!urlRegexCache.has(pattern)) {
      urlRegexCache.set(pattern, new RegExp(`[^\\s'"()<>{}\\[\\]]*?\\.${pattern}[^\\s'"()<>{}\\[\\]]*`, 'g')); // 创建并缓存URL正则
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
  ]; // 支持的媒体类型

  // 缓存媒体选择器，避免重复构建
  let cachedMediaSelector = null; // 媒体选择器缓存
  let lastPatternForSelector = null; // 上次选择器模式

  function getMediaSelector() {
    const currentPattern = window.filePattern || filePattern; // 获取当前文件模式
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
      ].join(','); // 构建并缓存媒体选择器
    }
    return cachedMediaSelector;
  }

  // 更新文件模式和相关正则表达式
  window.updateFilePattern = function(newPattern) {
    if (newPattern && typeof newPattern === 'string' && newPattern !== filePattern) {
      window.filePattern = newPattern; // 更新全局文件模式
      fileRegexCache.clear(); // 清空文件正则缓存
      urlRegexCache.clear(); // 清空URL正则缓存
      cachedMediaSelector = null; // 清空选择器缓存
      lastPatternForSelector = null; // 重置模式
      console.log(`[M3U8Detector] 文件模式已更新为: ${newPattern}`);
    }
  };

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

  // ===== 检测直接媒体文件URL =====
  function isDirectMediaUrl(url) {
    if (!url || typeof url !== 'string') return false;
    
    try {
      const parsedUrl = new URL(url, window.location.href); // 解析URL
      const pathname = parsedUrl.pathname.toLowerCase(); // 获取路径小写
      const currentPattern = window.filePattern || filePattern; // 当前文件模式
      return pathname.endsWith(`.${currentPattern}`) ||
             pathname.endsWith('.flv') ||
             pathname.endsWith('.mp4') || 
             pathname.endsWith('.mp3') || 
             pathname.endsWith('.wav') || 
             pathname.endsWith('.ogg') || 
             pathname.endsWith('.webm'); // 检查是否为媒体文件
    } catch (e) {
      const lowerUrl = url.toLowerCase(); // URL转小写
      const currentPattern = window.filePattern || filePattern;
      const urlWithoutParams = lowerUrl.split('?')[0].split('#')[0]; // 移除参数和锚点
      const extensionPattern = new RegExp(`\\.(${currentPattern}|flv|mp4|mp3|wav|ogg|webm)$`); // 媒体扩展名正则
      return extensionPattern.test(urlWithoutParams); // 使用正则匹配
    }
  }

  // 提取并处理URL
  function extractAndProcessUrls(text, source, baseUrl) {
    if (!text || typeof text !== 'string') return;
    const currentPattern = window.filePattern || filePattern;
    if (!text.includes('.' + currentPattern)) return; // 检查是否包含目标扩展名
    const urlRegex = getUrlRegex(currentPattern); // 获取URL正则
    const matches = text.match(urlRegex) || []; // 匹配所有URL
    for (const match of matches) {
      const cleanUrl = match.replace(/^["'\s]+/, ''); // 清理URL前缀
      VideoUrlProcessor.processUrl(cleanUrl, 0, source, baseUrl); // 处理URL
    }
  }

  // URL处理工具
  const VideoUrlProcessor = {
    processUrl(url, depth = 0, source = 'unknown', baseUrl) {
      if (!url || typeof url !== 'string' || depth > MAX_RECURSION_DEPTH || processedUrls.has(url)) return; // 验证URL有效性
      try {
        url = this.normalizeUrl(url, baseUrl); // 规范化URL
        if (!url || processedUrls.has(url)) return;
        const currentPattern = window.filePattern || filePattern;
        const fileRegex = getFileRegex(currentPattern); // 获取文件正则
        if (fileRegex.test(url)) {
          processedUrls.add(url); // 缓存已处理URL
          if (window.M3U8Detector && typeof window.M3U8Detector.postMessage === 'function') {
            window.M3U8Detector.postMessage(JSON.stringify({
              type: 'url',
              url,
              source
            })); // 发送URL消息
          }
        }
      } catch (e) {
        console.warn('[M3U8Detector] URL处理异常:', e.message);
      }
    },

    normalizeUrl(url, baseUrl = window.location.href) {
      if (!url || typeof url !== 'string') return '';
      try {
        url = url.replace(COMPILED_REGEX.CLEAN_URL, '$2'); // 清理URL格式
        let parsedUrl;
        if (COMPILED_REGEX.ABSOLUTE_URL.test(url)) {
          parsedUrl = new URL(url); // 处理绝对URL
        } else {
          parsedUrl = new URL(url, baseUrl); // 补全相对URL
        }
        parsedUrl.hostname = parsedUrl.hostname.toLowerCase(); // 主机名转小写
        if ((parsedUrl.protocol === 'http:' && parsedUrl.port === '80') || 
            (parsedUrl.protocol === 'https:' && parsedUrl.port === '443')) {
          parsedUrl.port = ''; // 移除默认端口
        }
        parsedUrl.hash = ''; // 移除锚点
        return parsedUrl.toString(); // 返回规范化URL
      } catch (e) {
        console.warn('[M3U8Detector] URL规范化失败:', e.message);
        return url; // 解析失败返回原URL
      }
    }
  };

  // 处理JSON内容中的URL
  function processJsonContent(jsonText, source, baseUrl) {
    try {
      const data = JSON.parse(jsonText); // 解析JSON
      const currentPattern = window.filePattern || filePattern;
      const queue = [{obj: data, path: ''}]; // 初始化处理队列
      const processedNodes = 0;
      while (queue.length > 0 && queue.length < 1000) { // 限制节点数量
        const {obj, path} = queue.shift();
        if (typeof obj === 'string' && obj.includes('.' + currentPattern)) {
          VideoUrlProcessor.processUrl(obj, 0, `${source}:json:${path}`, baseUrl); // 处理字符串URL
        } else if (obj && typeof obj === 'object') {
          const keys = Object.keys(obj).slice(0, 100); // 限制属性数量
          for (const key of keys) {
            const newPath = path ? `${path}.${key}` : key;
            queue.push({obj: obj[key], path: newPath}); // 添加子节点到队列
          }
        }
      }
    } catch (e) {
      console.warn('[M3U8Detector] JSON解析失败:', e.message);
    }
  }

  // 共用网络URL处理函数
  function handleNetworkUrl(url, source, content, contentType, baseUrl) {
    if (url) VideoUrlProcessor.processUrl(url, 0, source, baseUrl); // 处理网络URL
    if (content && typeof content === 'string') {
      extractAndProcessUrls(content, `${source}:content`, baseUrl); // 提取内容中的URL
      if (contentType?.includes('application/json')) {
        try {
          processJsonContent(content, source, baseUrl); // 处理JSON内容
        } catch (e) {
          console.warn('[M3U8Detector] JSON解析失败:', e.message);
        }
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
        this._isDirectMedia = isDirectMediaUrl(this._url); // 检查是否为直接媒体URL
        if (this._isDirectMedia) {
          console.log("[M3U8Detector] 检测到直接媒体URL (XHR):", this._url);
          VideoUrlProcessor.processUrl(this._url, 0, 'xhr:direct_media_intercepted'); // 处理直接媒体URL
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
            }); // 模拟加载完成
            this.dispatchEvent(new Event('load')); // 触发load事件
          }, 0);
          return; // 不执行原始请求
        }
        handleNetworkUrl(this._url, 'xhr'); // 处理XHR请求URL
        const handleLoad = () => {
          if (this.responseURL) handleNetworkUrl(this.responseURL, 'xhr:response'); // 处理响应URL
          if (this.responseType === '' || this.responseType === 'text') {
            handleNetworkUrl(null, 'xhr:responseContent', this.responseText, null, this.responseURL); // 处理响应内容
          }
        };
        this.addEventListener('load', handleLoad); // 监听加载事件
        return originalSend.apply(this, arguments);
      };
    },

    setupFetchInterceptor() {
      const originalFetch = window.fetch;
      window.fetch = function(input, init) {
        const url = (input instanceof Request) ? input.url : input; // 获取请求URL
        const isDirectMedia = isDirectMediaUrl(url); // 检查是否为直接媒体URL
        if (isDirectMedia && url) {
          console.log("[M3U8Detector] 检测到直接媒体URL (fetch):", url);
          VideoUrlProcessor.processUrl(url, 0, 'fetch:direct_media_intercepted'); // 处理直接媒体URL
          return Promise.resolve(new Response('', {
            status: 200,
            headers: {'content-type': 'text/plain'},
            url: url
          })); // 返回空响应
        }
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
            }).catch(err => {
              console.warn('[M3U8Detector] 读取fetch响应失败:', err.message);
            });
          } else {
            handleNetworkUrl(response.url, 'fetch:response'); // 处理响应URL
          }
          return response;
        }).catch(err => {
          console.warn('[M3U8Detector] fetch请求失败:', err.message);
          throw err;
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
          const url = originalCreateObjectURL.call(this, obj); // 创建对象URL
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
                    video.addEventListener('loadedmetadata', handleMetadata); // 监听元数据加载
                  }
                });
              } catch (e) {
                console.warn('[M3U8Detector] MediaSource处理异常:', e.message);
              }
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
      if (root !== document) {
        return this.querySelectorMedia(root); // 非document直接查询
      }
      const now = Date.now();
      if (!this.cachedElements || (now - this.lastSelectorTime > this.SELECTOR_CACHE_TTL)) {
        this.cachedElements = this.querySelectorMedia(document); // 更新缓存
        this.lastSelectorTime = now;
      }
      return this.cachedElements;
    },
    
    querySelectorMedia(root) {
      const selector = getMediaSelector() + ',[data-src],[data-url]'; // 构建查询选择器
      return root.querySelectorAll(selector); // 查询媒体元素
    },

    scanAttributes(element) {
      if (!element || !element.attributes) return;
      for (const attr of element.attributes) {
        if (attr.value && typeof attr.value === 'string') {
          VideoUrlProcessor.processUrl(attr.value, 0, `attribute:${attr.name}`); // 处理元素属性URL
        }
      }
    },

    scanMediaElement(element) {
      if (!element || element.tagName !== 'VIDEO') return;
      if (element.src) {
        VideoUrlProcessor.processUrl(element.src, 0, 'video:src'); // 处理video的src
      }
      if (element.currentSrc) {
        VideoUrlProcessor.processUrl(element.currentSrc, 0, 'video:currentSrc'); // 处理video的currentSrc
      }
      const sources = element.querySelectorAll('source');
      for (const source of sources) {
        const src = source.src || source.getAttribute('src');
        if (src) {
          VideoUrlProcessor.processUrl(src, 0, 'video:source'); // 处理source的src
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
        } catch (e) {
          console.warn('[M3U8Detector] src属性监控失败:', e.message);
        }
      }
    },

    scanPage(root = document) {
      const now = Date.now();
      const isFullScan = now - this.lastFullScanTime > CONFIG.fullScanInterval; // 检查是否需要全面扫描
      if (isFullScan) {
        this.lastFullScanTime = now;
        this.processedCount = 0; // 重置计数
        this.cachedElements = null; // 清除缓存
      }
      try {
        const elements = this.getMediaElements(root); // 获取媒体元素
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
      } catch (e) {
        console.warn('[M3U8Detector] DOM扫描异常:', e.message);
      }
    },

    scanScripts() {
      try {
        const scripts = document.querySelectorAll('script:not([src])'); // 获取内联脚本
        for (const script of scripts) {
          const content = script.textContent;
          if (content && typeof content === 'string') {
            extractAndProcessUrls(content, 'script:regex'); // 提取脚本中的URL
          }
        }
      } catch (e) {
        console.warn('[M3U8Detector] 脚本扫描异常:', e.message);
      }
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
      const currentQueue = new Set(pendingProcessQueue); // 复制当前队列
      pendingProcessQueue.clear(); // 清空待处理队列
      processingQueueTimer = null;
      const urlsToProcess = []; // 待处理URL
      const nodesToScan = new Set(); // 待扫描节点
      currentQueue.forEach(item => {
        if (typeof item === 'string') {
          urlsToProcess.push(item); // 收集字符串URL
        } else if (item && item.parentNode) {
          nodesToScan.add(item.parentNode); // 收集父节点
        }
      });
      urlsToProcess.forEach(url => {
        VideoUrlProcessor.processUrl(url, 0, 'mutation:string'); // 批量处理URL
      });
      nodesToScan.forEach(node => {
        DOMScanner.scanPage(node); // 扫描节点
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
    const timeSinceLastScan = now - lastScanTime;
    if (timeSinceLastScan >= SCAN_INTERVAL) {
      lastScanTime = now;
      DOMScanner.scanPage(document); // 执行定期扫描
      setTimeout(scheduleNextScan, SCAN_INTERVAL);
    } else {
      const remainingTime = SCAN_INTERVAL - timeSinceLastScan;
      setTimeout(scheduleNextScan, remainingTime); // 调度下次扫描
    }
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
                  if (attr.value && typeof attr.value === 'string') {
                    pendingProcessQueue.add(attr.value); // 添加属性值到队列
                  }
                }
              }
            }
          }
          if (mutation.type === 'attributes' && mutation.target) {
            const newValue = mutation.target.getAttribute(mutation.attributeName);
            if (newValue && typeof newValue === 'string') {
              pendingProcessQueue.add(newValue); // 添加变化的属性值
              const pattern = window.filePattern || filePattern;
              if (['src', 'data-src', 'href'].includes(mutation.attributeName) && 
                  newValue.includes('.' + pattern)) {
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
      window.addEventListener('popstate', handleUrlChange); // 监听历史变化
      window.addEventListener('hashchange', handleUrlChange); // 监听hash变化
      if (window.requestIdleCallback) {
        requestIdleCallback(() => DOMScanner.scanPage(document), { timeout: 1000 }); // 空闲时扫描
      } else {
        setTimeout(() => DOMScanner.scanPage(document), 100);
      }
      setTimeout(scheduleNextScan, SCAN_INTERVAL); // 启动定期扫描
    } catch (e) {
      console.error('[M3U8Detector] 初始化失败:', e.message);
    }
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
    cachedMediaSelector = null; // 清除选择器缓存
    lastPatternForSelector = null; // 清除模式缓存
    fileRegexCache.clear(); // 清除文件正则缓存
    urlRegexCache.clear(); // 清除URL正则缓存
  };

  // 外部接口
  window.checkMediaElements = function(root) {
    try {
      if (root) DOMScanner.scanPage(root); // 扫描指定根节点的媒体元素
    } catch (e) {
      console.error('[M3U8Detector] 检查媒体元素时出错:', e);
    }
  };
  
  window.efficientDOMScan = function() {
    try {
      DOMScanner.scanPage(document); // 执行高效DOM扫描
    } catch (e) {
      console.error('[M3U8Detector] 高效DOM扫描时出错:', e);
    }
  };
  
  if (window.M3U8Detector) {
    try {
      window.M3U8Detector.postMessage(JSON.stringify({
        type: 'init',
        message: 'M3U8Detector initialized'
      })); // 发送初始化消息
    } catch (e) {
      console.warn('[M3U8Detector] 发送初始化消息失败:', e.message);
    }
  }
})();
