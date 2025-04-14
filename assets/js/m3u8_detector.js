(function () {
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

  const processedUrls = new Set();
  const MAX_RECURSION_DEPTH = 3;
  let observer = null;
  const filePattern = 'FILE_PATTERN'; // 由 Dart 替换

  const VideoUrlProcessor = {
    processUrl(url, depth = 0) {
      if (!url || typeof url !== 'string' || 
          depth > MAX_RECURSION_DEPTH || 
          processedUrls.has(url)) return;

      url = this.normalizeUrl(url);
      processedUrls.add(url);
      
      if (url.includes('.' + filePattern)) {
        window.M3U8Detector && window.M3U8Detector.postMessage(url);
      }
    },

    normalizeUrl(url) {
      try {
        if (url.startsWith('/')) {
          const baseUrl = new URL(window.location.href);
          return baseUrl.protocol + '//' + baseUrl.host + url;
        }
        if (!url.startsWith('http')) {
          return new URL(url, window.location.href).toString();
        }
        return url;
      } catch (e) {
        return url;
      }
    }
  };

  const NetworkInterceptor = {
    setupXHRInterceptor() {
      const XHR = XMLHttpRequest.prototype;
      const originalOpen = XHR.open;
      const originalSend = XHR.send;

      XHR.open = function() {
        try {
          this._url = arguments[1];
          return originalOpen.apply(this, arguments);
        } catch (e) {
          console.error('XHR open interceptor error:', e);
          return originalOpen.apply(this, arguments);
        }
      };

      XHR.send = function() {
        try {
          if (this._url) VideoUrlProcessor.processUrl(this._url, 0);
          return originalSend.apply(this, arguments);
        } catch (e) {
          console.error('XHR send interceptor error:', e);
          return originalSend.apply(this, arguments);
        }
      };
    },

    setupFetchInterceptor() {
      const originalFetch = window.fetch;
      window.fetch = function(input, ...args) {
        try {
          const url = (input instanceof Request) ? input.url : input;
          if (url) VideoUrlProcessor.processUrl(url, 0);
          return originalFetch.apply(this, [input, ...args]);
        } catch (e) {
          console.error('Fetch interceptor error:', e);
          return originalFetch.apply(this, [input, ...args]);
        }
      };
    },

    setupMediaSourceInterceptor() {
      if (!window.MediaSource) return;

      const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
      MediaSource.prototype.addSourceBuffer = function(mimeType) {
        try {
          const supportedTypes = {
            'm3u8': ['application/x-mpegURL', 'application/vnd.apple.mpegURL'],
            'flv': ['video/x-flv', 'application/x-flv', 'flv-application/octet-stream'],
            'mp4': ['video/mp4', 'application/mp4']
          };
          const currentTypes = supportedTypes[filePattern] || [];
          const url = this.url || window.location.href;
          if (currentTypes.some(type => mimeType.includes(type))) {
            VideoUrlProcessor.processUrl(url, 0);
          }
          return originalAddSourceBuffer.call(this, mimeType);
        } catch (e) {
          console.error('MediaSource interceptor error:', e);
          return originalAddSourceBuffer.call(this, mimeType);
        }
      };
    }
  };

  const DOMScanner = {
    processedElements: new WeakSet(),
    scanAttributes(element) {
      for (const attr of element.attributes) {
        if (attr.value) VideoUrlProcessor.processUrl(attr.value, 0);
      }
    },
    scanMediaElement(element) {
      if (element.tagName === 'VIDEO') {
        element.src && VideoUrlProcessor.processUrl(element.src, 0);
        element.currentSrc && VideoUrlProcessor.processUrl(element.currentSrc, 0);
        element.querySelectorAll('source').forEach(source => {
          const src = source.src || source.getAttribute('src');
          if (src) VideoUrlProcessor.processUrl(src, 0);
        });
      }
    },
    scanPage(root = document) {
      const selector = [
        'video', 'source', '[class*="video"]', '[class*="player"]',
        `[class*="${filePattern}"]`, `[data-${filePattern}]`,
        `a[href*="${filePattern}"]`, `[data-src*="${filePattern}"]`
      ].join(',');
      try {
        root.querySelectorAll(selector).forEach(element => {
          if (this.processedElements.has(element)) return;
          this.processedElements.add(element);
          this.scanAttributes(element);
          this.scanMediaElement(element);
        });
        this.scanScripts();
      } catch (e) {
        console.error('DOM scan error:', e);
      }
    },
    scanScripts() {
      document.querySelectorAll('script:not([src])').forEach(script => {
        if (!script.textContent) return;
        try {
          const pattern = '\\.' + filePattern;
          const regex = new RegExp(`https?://[^\\s'"]*${pattern}[^\\s'"]*`, 'g');
          let match;
          const content = script.textContent;
          while ((match = regex.exec(content)) !== null) {
            VideoUrlProcessor.processUrl(match[0], 0);
          }
        } catch (e) {
          console.error('Script scan error:', e);
        }
      });
    }
  };

  function initializeDetector() {
    NetworkInterceptor.setupXHRInterceptor();
    NetworkInterceptor.setupFetchInterceptor();
    NetworkInterceptor.setupMediaSourceInterceptor();

    let debounceTimer = null;
    const urlChangeHandler = () => { DOMScanner.scanPage(document); };

    observer = new MutationObserver(mutations => {
      const processQueue = new Set();
      mutations.forEach(mutation => {
        mutation.addedNodes.forEach(node => {
          if (node.nodeType === 1) {
            if (node.matches && node.matches('video,source,[class*="video"],[class*="player"]')) {
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
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        if (typeof requestIdleCallback === 'function') {
          requestIdleCallback(() => {
            processQueue.forEach(item => {
              if (typeof item === 'string') {
                VideoUrlProcessor.processUrl(item, 0);
              } else if (item && item.parentNode) {
                DOMScanner.scanPage(item.parentNode || document);
              }
            });
          }, { timeout: 1000 });
        } else {
          setTimeout(() => {
            processQueue.forEach(item => {
              if (typeof item === 'string') {
                VideoUrlProcessor.processUrl(item, 0);
              } else if (item && item.parentNode) {
                DOMScanner.scanPage(item.parentNode || document);
              }
            });
          }, 0);
        }
      }, 100);
    });

    observer.observe(document.documentElement, {
      childList: true, subtree: true, attributes: true
    });

    window.addEventListener('popstate', urlChangeHandler);
    window.addEventListener('hashchange', urlChangeHandler);

    if (typeof requestIdleCallback === 'function') {
      requestIdleCallback(() => { DOMScanner.scanPage(document); }, { timeout: 1000 });
    } else {
      setTimeout(() => { DOMScanner.scanPage(document); }, 0);
    }

    window._m3u8DetectorHandlers = { urlChangeHandler };
  }

  initializeDetector();

  window._cleanupM3U8Detector = () => {
    if (observer) { observer.disconnect(); }
    const handlers = window._m3u8DetectorHandlers || {};
    if (handlers.urlChangeHandler) {
      window.removeEventListener('popstate', handlers.urlChangeHandler);
      window.removeEventListener('hashchange', handlers.urlChangeHandler);
    }
    delete window._m3u8DetectorHandlers;
    delete window._m3u8DetectorInitialized;
    // 显式恢复 fetch 和 XHR
    window.fetch = window.fetch.originalFetch || window.fetch;
    XMLHttpRequest.prototype.open = XMLHttpRequest.prototype.open.originalOpen || XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.send = XMLHttpRequest.prototype.send.originalSend || XMLHttpRequest.prototype.send;
  };
})();
