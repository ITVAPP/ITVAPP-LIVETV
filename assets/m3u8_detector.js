// assets/js/m3u8_detector.js
(function() {
  // 避免重复初始化
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

  // 初始化状态
  const processedUrls = new Set();
  const MAX_RECURSION_DEPTH = 3;
  let observer = null;

  // URL处理工具
  const VideoUrlProcessor = {
    processUrl(url, depth = 0) {
      if (!url || typeof url !== 'string' || 
          depth > MAX_RECURSION_DEPTH || 
          processedUrls.has(url)) return;

      // URL标准化
      url = this.normalizeUrl(url);

      // 使用占位符 FILE_PATTERN，由Dart代码动态替换
      if (url.includes('.' + 'FILE_PATTERN')) {
        processedUrls.add(url);
        window.M3U8Detector.postMessage(url);
      }
    },

    normalizeUrl(url) {
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

  // 网络请求拦截器
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
        if (this._url) VideoUrlProcessor.processUrl(this._url, 0);
        return originalSend.apply(this, arguments);
      };
    },

    setupFetchInterceptor() {
      const originalFetch = window.fetch;
      window.fetch = function(input) {
        const url = (input instanceof Request) ? input.url : input;
        VideoUrlProcessor.processUrl(url, 0);
        return originalFetch.apply(this, arguments);
      };
    },

    setupMediaSourceInterceptor() {
      if (!window.MediaSource) return;

      const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
      MediaSource.prototype.addSourceBuffer = function(mimeType) {
        const supportedTypes = {
          'm3u8': ['application/x-mpegURL', 'application/vnd.apple.mpegURL'],
          'flv': ['video/x-flv', 'application/x-flv', 'flv-application/octet-stream'],
          'mp4': ['video/mp4', 'application/mp4']
        };

        // 使用占位符 FILE_PATTERN，由Dart代码动态替换
        const currentTypes = supportedTypes['FILE_PATTERN'] || [];
        if (currentTypes.some(type => mimeType.includes(type))) {
          VideoUrlProcessor.processUrl(this.url, 0);
        }
        return originalAddSourceBuffer.call(this, mimeType);
      };
    }
  };

  // DOM扫描器
  const DOMScanner = {
    processedElements: new Set(),

    scanAttributes(element) {
      for (const attr of element.attributes) {
        if (attr.value) VideoUrlProcessor.processUrl(attr.value, 0);
      }
    },

    scanMediaElement(element) {
      if (element.tagName === 'VIDEO') {
        [element.src, element.currentSrc].forEach(src => {
          if (src) VideoUrlProcessor.processUrl(src, 0);
        });

        element.querySelectorAll('source').forEach(source => {
          const src = source.src || source.getAttribute('src');
          if (src) VideoUrlProcessor.processUrl(src, 0);
        });
      }
    },

    scanPage(root = document) {
      // 使用占位符 FILE_PATTERN，由Dart代码动态替换
      const selector = [
        'video',
        'source',
        '[class*="video"]',
        '[class*="player"]',
        `[class*="FILE_PATTERN"]`,
        `[data-FILE_PATTERN]`,
        `a[href*="FILE_PATTERN"]`,
        `[data-src*="FILE_PATTERN"]`
      ].join(',');

      root.querySelectorAll(selector).forEach(element => {
        if (this.processedElements.has(element)) return;
        this.processedElements.add(element);

        this.scanAttributes(element);
        this.scanMediaElement(element);
      });

      this.scanScripts();
    },

    scanScripts() {
      document.querySelectorAll('script:not([src])').forEach(script => {
        if (!script.textContent) return;
        
        // 使用占位符 FILE_PATTERN，由Dart代码动态替换
        const pattern = '.' + 'FILE_PATTERN';
        let index = script.textContent.indexOf(pattern);
        
        while (index !== -1) {
          const extracted = this.extractUrlFromScript(script.textContent, index);
          if (extracted.url.includes('http')) {
            VideoUrlProcessor.processUrl(extracted.url, 0);
          }
          index = script.textContent.indexOf(pattern, extracted.endIndex);
        }
      });
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
    NetworkInterceptor.setupMediaSourceInterceptor();

    // 设置 DOM 观察
    observer = new MutationObserver(mutations => {
      const processQueue = new Set();

      mutations.forEach(mutation => {
        mutation.addedNodes.forEach(node => {
          if (node.nodeType === 1) {
            if (node.matches('video,source,[class*="video"],[class*="player"]')) {
              processQueue.add(node);
            }
            if (node instanceof Element) {
              for (const attr of node.attributes) {
                if (attr.value) processQueue.add(attr.value);
              }
            }
          }
        });

        if (mutation.type === 'attributes') {
          const newValue = mutation.target.getAttribute(mutation.attributeName);
          if (newValue) processQueue.add(newValue);
        }
      });

      requestIdleCallback(() => {
        processQueue.forEach(item => {
          if (typeof item === 'string') {
            VideoUrlProcessor.processUrl(item, 0);
          } else {
            DOMScanner.scanPage(item.parentNode || document);
          }
        });
      }, { timeout: 1000 });
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true
    });

    // URL 变化处理
    const handleUrlChange = () => {
      DOMScanner.scanPage(document);
    };

    window.addEventListener('popstate', handleUrlChange);
    window.addEventListener('hashchange', handleUrlChange);

    // 初始扫描
    requestIdleCallback(() => {
      DOMScanner.scanPage(document);
    }, { timeout: 1000 });
  }

  // 初始化检测器
  initializeDetector();

  // 清理函数
  window._cleanupM3U8Detector = () => {
    if (observer) {
      observer.disconnect();
    }
    window.removeEventListener('popstate', handleUrlChange);
    window.removeEventListener('hashchange', handleUrlChange);
    delete window._m3u8DetectorInitialized;
  };
})();
