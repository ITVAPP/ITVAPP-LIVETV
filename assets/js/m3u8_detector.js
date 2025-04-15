(function() {
  // 避免重复初始化 (保留原逻辑)
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

  // 定义全局常量
  const CONSTANTS = {
    MAX_RECURSION_DEPTH: 3,               // 最大递归深度
    SCAN_INTERVAL_MS: 1000,               // 定期扫描间隔（毫秒）
    IDLE_CALLBACK_TIMEOUT_MS: 500,        // requestIdleCallback 超时（毫秒）
    SET_TIMEOUT_DELAY_MS: 100,            // setTimeout 延迟（毫秒）
    PROCESSED_URLS_MAX_SIZE: 10000,       // processedUrls 最大容量
    JSON_RESPONSE_MAX_SIZE: 1024 * 1024,  // JSON 响应最大大小（1MB）
  };

  // 初始化状态
  const processedUrls = new Set();
  let observer = null;
  
  // File pattern will be dynamically replaced
  const filePattern = "m3u8";

  // 预编译正则表达式以优化性能
  const filePatternRegex = new RegExp(`\\.(${filePattern})([?#]|$)`, 'i');
  // 全局正则表达式常量（用于脚本和响应内容）
  const URL_PATTERN_REGEX = new RegExp(`https?://[^\\s'"]*\\.${filePattern}[^\\s'"]*`, 'g');

  // URL处理工具 (优化URL处理逻辑，仅保留filePattern检查)
  const VideoUrlProcessor = {
    processUrl(url, depth = 0, source = 'unknown') {
      // 验证输入参数
      if (!url || typeof url !== 'string' || 
          depth > CONSTANTS.MAX_RECURSION_DEPTH || 
          processedUrls.has(url)) return;

      // URL标准化
      url = this.normalizeUrl(url);

      // 检查目标文件类型
      if (filePatternRegex.test(url)) {
        processedUrls.add(url);
        // 逐条发送 postMessage，兼容 Dart 的 M3U8Detector
        window.M3U8Detector?.postMessage(JSON.stringify({
          type: 'url',
          url: url,
          source: source
        }));

        // 清理 processedUrls 超过最大容量
        if (processedUrls.size > CONSTANTS.PROCESSED_URLS_MAX_SIZE) {
          const iterator = processedUrls.values();
          for (let i = 0; i < processedUrls.size - CONSTANTS.PROCESSED_URLS_MAX_SIZE / 2; i++) {
            processedUrls.delete(iterator.next().value);
          }
        }
      }
    },

    normalizeUrl(url) {
      // URL标准化逻辑保持不变
      if (url.startsWith('/')) {
        const baseUrl = new URL(window.location.href);
        return baseUrl.protocol + '//' + baseUrl.host + url;
      }
      if (!url.startsWith('http')) {
        return new URL(url, window.location.href).toString();
      }
      return url;
    }
  };

  // 网络请求拦截器 (仅保留XHR和Fetch，优化filePattern检查)
  const NetworkInterceptor = {
    setupXHRInterceptor() {
      const XHR = XMLHttpRequest.prototype;
      const originalOpen = XHR.open;
      const originalSend = XHR.send;

      XHR.open = function() {
        this._url = arguments[1];
        return originalOpen.apply(this, arguments);
      };

      XHR.send = function() {
        // 仅在 send 时处理 _url
        if (this._url) VideoUrlProcessor.processUrl(this._url, 0, 'xhr');
        
        // 添加响应处理
        this.addEventListener('load', function() {
          // 仅处理 responseURL（避免与 _url 重复）
          if (this.responseURL && this.responseURL !== this._url) {
            VideoUrlProcessor.processUrl(this.responseURL, 0, 'xhr:response');
          }
          
          // 检查响应内容
          if (this.responseType === '' || this.responseType === 'text') {
            try {
              const responseText = this.responseText;
              if (responseText && responseText.length <= CONSTANTS.JSON_RESPONSE_MAX_SIZE && responseText.includes('.' + filePattern)) {
                // 使用全局正则表达式
                const matches = responseText.match(URL_PATTERN_REGEX);
                if (matches) {
                  matches.forEach(url => 
                    VideoUrlProcessor.processUrl(url, 0, 'xhr:responseContent')
                  );
                }
              }
            } catch (e) {
              // 忽略响应内容解析错误
            }
          }
        });
        
        return originalSend.apply(this, arguments);
      };
    },

    setupFetchInterceptor() {
      const originalFetch = window.fetch;
      window.fetch = function(input) {
        const url = (input instanceof Request) ? input.url : input;
        VideoUrlProcessor.processUrl(url, 0, 'fetch');
        
        // 处理响应
        const fetchPromise = originalFetch.apply(this, arguments);
        fetchPromise.then(response => {
          // 仅处理 response.url（避免与 input.url 重复）
          if (response.url !== url) {
            VideoUrlProcessor.processUrl(response.url, 0, 'fetch:response');
          }
          
          // 检查可能的JSON响应中的URL
          if (response.headers.get('content-type')?.includes('application/json')) {
            response.clone().text().then(text => {
              if (text && text.length <= CONSTANTS.JSON_RESPONSE_MAX_SIZE && text.includes('.' + filePattern)) {
                try {
                  const data = JSON.parse(text);
                  // 递归搜索JSON中的URL
                  (function searchJsonForUrls(obj, path = '') {
                    if (!obj) return;
                    
                    if (typeof obj === 'string' && obj.includes('.' + filePattern)) {
                      VideoUrlProcessor.processUrl(obj, 0, 'fetch:json:' + path);
                    } else if (typeof obj === 'object') {
                      for (const key in obj) {
                        searchJsonForUrls(obj[key], path ? path + '.' + key : key);
                      }
                    }
                  })(data);
                } catch (e) {
                  // 忽略JSON解析错误
                }
              }
            }).catch(() => {});
          }
        }).catch(() => {});
        
        return fetchPromise;
      };
    },
  };

  // DOM扫描器 (仅扫描filePattern相关元素、视频元素和脚本)
  const DOMScanner = {
    processedElements: new Set(),
    lastFullScanTime: 0,

    scanAttributes(element) {
      // 检查元素的class、data-*、href和data-src属性
      for (const attr of element.attributes) {
        if (['class', 'href', 'data-src'].includes(attr.name) || attr.name.startsWith(`data-${filePattern}`)) {
          if (attr.value) VideoUrlProcessor.processUrl(attr.value, 0, 'attribute:' + attr.name);
        }
      }
    },

    scanMediaElement(element) {
      // 处理视频元素（<video>和<source>）
      if (element.tagName === 'VIDEO') {
        [element.src, element.currentSrc].forEach(src => {
          if (src) VideoUrlProcessor.processUrl(src, 0, 'video:src');
        });

        element.querySelectorAll('source').forEach(source => {
          const src = source.src || source.getAttribute('src');
          if (src) VideoUrlProcessor.processUrl(src, 0, 'video:source');
        });
        
        // 监控视频元素的src变化
        if (!element._srcObserved) {
          element._srcObserved = true;
          const originalSrcSetter = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src').set;
          
          Object.defineProperty(element, 'src', {
            set: function(value) {
              if (value) VideoUrlProcessor.processUrl(value, 0, 'video:src:setter');
              return originalSrcSetter.call(this, value);
            },
            get: function() {
              return this.getAttribute('src');
            }
          });
        }
      }
    },

    scanPage(root = document) {
      // 优化选择器，优先扫描高概率元素
      const selector = [
        `a[href*="${filePattern}"]`,
        `[data-${filePattern}]`,
        `[data-src*="${filePattern}"]`,
        'video',
        'source'
      ].join(',');

      // 性能日志
      const startTime = performance.now();
      root.querySelectorAll(selector).forEach(element => {
        if (this.processedElements.has(element)) return;
        this.processedElements.add(element);

        this.scanAttributes(element);
        this.scanMediaElement(element);
      });
      const endTime = performance.now();
      console.debug(`DOMScanner.scanPage 耗时: ${(endTime - startTime).toFixed(2)}ms`);
    },

    scanScripts() {
      // 性能日志
      const startTime = performance.now();
      // 仅由 MutationObserver 触发具体脚本扫描，避免全量扫描
      const endTime = performance.now();
      console.debug(`DOMScanner.scanScripts 耗时: ${(endTime - startTime).toFixed(2)}ms`);
    },

    scanSingleScript(script) {
      if (!script.textContent) return;
      
      // 使用全局正则表达式提取 URL
      const matches = script.textContent.match(URL_PATTERN_REGEX);
      if (matches) {
        matches.forEach(url => {
          if (url.includes('http') && filePatternRegex.test(url)) {
            VideoUrlProcessor.processUrl(url, 0, 'script:' + filePattern);
          }
        });
      }
    },

    extractUrlFromScript(content, startIndex) {
      let urlStart = startIndex;
      let urlEnd = startIndex;

      // 向前查找 URL 起点
      while (urlStart > 0) {
        const char = content[urlStart - 1];
        if (char === '"' || char === "'" || char === ' ' || char === '\n') break;
        urlStart--;
      }

      // 向后查找 URL 终点
      while (urlEnd < content.length) {
        const char = content[urlEnd];
        if (char === '"' || char === "'" || char === ' ' || char === '\n') break;
        urlEnd++;
      }

      return {
        url: content.substring(urlStart, urlEnd).trim(),
        endIndex: urlEnd
      };
    }
  };

  // 初始化检测器
  function initializeDetector() {
    // 设置网络拦截
    NetworkInterceptor.setupXHRInterceptor();
    NetworkInterceptor.setupFetchInterceptor();

    // 设置 DOM 观察
    observer = new MutationObserver(mutations => {
      const processQueue = new Set();
      const newVideos = new Set();
      const newScripts = new Set();

      mutations.forEach(mutation => {
        // 处理新增节点
        mutation.addedNodes.forEach(node => {
          if (node.nodeType === 1) {
            // 检查新增的video或source元素
            if (node.tagName === 'VIDEO' || node.tagName === 'SOURCE') {
              newVideos.add(node);
            }
            // 检查新增的script元素
            if (node.tagName === 'SCRIPT' && !node.src) {
              newScripts.add(node);
            }
            
            // 检查filePattern相关元素
            if ((node.className && node.className.includes(filePattern)) ||
                (node.hasAttribute(`data-${filePattern}`)) ||
                (node.tagName === 'A' && node.href && node.href.includes(filePattern)) ||
                (node.hasAttribute('data-src') && node.getAttribute('data-src').includes(filePattern))) {
              processQueue.add(node);
            }
            
            if (node instanceof Element) {
              for (const attr of node.attributes) {
                if (attr.value && (
                    attr.name === 'href' ||
                    attr.name === 'data-src' ||
                    attr.name.startsWith(`data-${filePattern}`)
                )) {
                  processQueue.add(attr.value);
                }
              }
            }
          }
        });

        // 处理属性变化
        if (mutation.type === 'attributes') {
          const newValue = mutation.target.getAttribute(mutation.attributeName);
          if (newValue && (
              mutation.attributeName === 'href' ||
              mutation.attributeName === 'data-src' ||
              mutation.attributeName.startsWith(`data-${filePattern}`)
          )) {
            processQueue.add(newValue);
          }
        }
      });

      // 优先处理新增的视频元素
      newVideos.forEach(video => {
        DOMScanner.scanMediaElement(video);
      });

      // 处理新增的脚本
      newScripts.forEach(script => {
        DOMScanner.scanSingleScript(script);
      });

      // 处理队列
      if (window.requestIdleCallback) {
        requestIdleCallback(() => {
          processQueue.forEach(item => {
            if (typeof item === 'string') {
              VideoUrlProcessor.processUrl(item, 0, 'mutation:string');
            } else {
              DOMScanner.scanPage(item.parentNode || document);
            }
          });
        }, { timeout: CONSTANTS.IDLE_CALLBACK_TIMEOUT_MS });
      } else {
        setTimeout(() => {
          processQueue.forEach(item => {
            if (typeof item === 'string') {
              VideoUrlProcessor.processUrl(item, 0, 'mutation:string');
            } else {
              DOMScanner.scanPage(item.parentNode || document);
            }
          });
        }, CONSTANTS.SET_TIMEOUT_DELAY_MS);
      }
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true
    });

    // 初始扫描
    if (window.requestIdleCallback) {
      requestIdleCallback(() => {
        DOMScanner.scanPage(document);
        // 初始扫描所有脚本
        document.querySelectorAll('script:not([src])').forEach(script => {
          DOMScanner.scanSingleScript(script);
        });
      }, { timeout: CONSTANTS.IDLE_CALLBACK_TIMEOUT_MS });
    } else {
      setTimeout(() => {
        DOMScanner.scanPage(document);
        // 初始扫描所有脚本
        document.querySelectorAll('script:not([src])').forEach(script => {
          DOMScanner.scanSingleScript(script);
        });
      }, CONSTANTS.SET_TIMEOUT_DELAY_MS);
    }
    
    // 定期扫描
    setInterval(() => {
      if (!document.hidden) {
        DOMScanner.scanPage(document);
        // 脚本扫描由 MutationObserver 接管
      }
    }, CONSTANTS.SCAN_INTERVAL_MS);
  }

  // 初始化检测器
  initializeDetector();

  // 清理函数
  window._cleanupM3U8Detector = () => {
    // 清理观察器和事件监听
    if (observer) {
      observer.disconnect();
    }
    delete window._m3u8DetectorInitialized;
    processedUrls.clear();
    DOMScanner.processedElements.clear();
  };

  // 公开常用方法
  window.checkMediaElements = function(root) {
    if (root) DOMScanner.scanPage(root);
  };
  
  window.efficientDOMScan = function() {
    DOMScanner.scanPage(document);
    // 脚本扫描由 MutationObserver 接管
  };
  
  // 初始化通知
  if (window.M3U8Detector) {
    window.M3U8Detector.postMessage(JSON.stringify({
      type: 'init',
      message: 'M3U8Detector initialized'
    }));
  }
})();
