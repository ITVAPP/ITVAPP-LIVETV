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

  // URL 处理工具，负责标准化和检测 URL
  const VideoUrlProcessor = {
    // 处理 URL，检查是否为目标文件类型
    processUrl(url, depth = 0, source = 'unknown') {
      if (!url || typeof url !== 'string' || 
          depth > MAX_RECURSION_DEPTH || 
          processedUrls.has(url)) return;

      try {
        url = this.normalizeUrl(url); // 标准化 URL
        const pattern = new RegExp('\\.(' + filePattern + ')([?#]|$)', 'i'); // 匹配文件扩展名
        if (pattern.test(url)) {
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
        try {
          if (this._url) VideoUrlProcessor.processUrl(this._url, 0, 'xhr');
          
          this.addEventListener('load', function() {
            try {
              if (this.responseURL) {
                // 处理响应 URL
                VideoUrlProcessor.processUrl(this.responseURL, 0, 'xhr:response');
              }
              
              if (this.responseType === '' || this.responseType === 'text') {
                const responseText = this.responseText;
                if (responseText && responseText.includes('.' + filePattern)) {
                  // 提取响应内容中的 URL
                  const pattern = new RegExp(`(?:https?://|//|/)[^'"\\s,()<>{}\\[\\]]*?\\.${filePattern}[^'"\\s,()<>{}\\[\\]]*`, 'g');
                  const matches = responseText.match(pattern);
                  if (matches) {
                    matches.forEach(url => 
                      VideoUrlProcessor.processUrl(url, 0, 'xhr:responseContent')
                    );
                  }
                }
              }
            } catch (e) {}
          });
        } catch (e) {}
        
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
        
        const originalThen = fetchPromise.then;
        fetchPromise.then = function(onFulfilled, onRejected) {
          const wrappedOnFulfilled = function(response) {
            try {
              VideoUrlProcessor.processUrl(response.url, 0, 'fetch:response'); // 处理响应 URL
              
              if (response.headers.get('content-type')?.includes('application/json')) {
                response.clone().text().then(text => {
                  try {
                    if (text && text.includes('.' + filePattern)) {
                      const data = JSON.parse(text);
                      // 递归搜索 JSON 中的 URL
                      (function searchJsonForUrls(obj, path = '') {
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
                      })(data);
                    }
                  } catch (e) {}
                }).catch(() => {});
              }
            } catch (e) {}
            
            return onFulfilled ? onFulfilled(response) : response;
          };
          
          return originalThen.call(this, wrappedOnFulfilled, onRejected);
        };
        
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
            const supportedTypes = [
              'application/x-mpegURL', 
              'application/vnd.apple.mpegURL', 
              'video/x-flv', 
              'application/x-flv', 
              'flv-application/octet-stream',
              'video/mp4', 
              'application/mp4'
            ];
            if (supportedTypes.some(type => mimeType.includes(type))) {
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
            
            try {
              if (obj instanceof MediaSource) {
                const checkVideoElements = () => {
                  try {
                    const videoElements = document.querySelectorAll('video');
                    videoElements.forEach(video => {
                      if (video && video.src === url) {
                        const handleMetadata = () => {
                          try {
                            if (video.duration > 0 && video.src) {
                              VideoUrlProcessor.processUrl(video.src, 0, 'mediaSource:video');
                            }
                          } catch (e) {}
                          video.removeEventListener('loadedmetadata', handleMetadata);
                        };
                        
                        video.addEventListener('loadedmetadata', handleMetadata);
                      }
                    });
                  } catch (e) {}
                };
                
                if (document.readyState === 'complete') {
                  setTimeout(checkVideoElements, 100);
                } else {
                  window.addEventListener('load', () => setTimeout(checkVideoElements, 100));
                }
              }
            } catch (e) {}
            
            return url;
          };
        }
      } catch (e) {}
    }
  };

  // DOM 扫描器，检测页面中的媒体元素和属性
  const DOMScanner = {
    processedElements: new Set(), // 已处理元素集合
    lastFullScanTime: 0, // 上次全面扫描时间
    processedCount: 0, // 已处理元素计数

    // 清理过期或无效的元素引用
    cleanupProcessedElements() {
      try {
        if (this.processedElements.size > CONFIG.maxProcessedElements) {
          const newSet = new Set();
          let count = 0;
          for (const element of this.processedElements) {
            if (count >= CONFIG.maxProcessedElements / 2) break;
            if (element.isConnected) {
              newSet.add(element);
              count++;
            }
          }
          this.processedElements = newSet;
          this.processedCount = count;
        }
      } catch (e) {
        if (this.processedElements.size > CONFIG.maxProcessedElements * 2) {
          this.processedElements.clear();
          this.processedCount = 0;
        }
      }
    },

    // 扫描元素属性中的 URL
    scanAttributes(element) {
      try {
        if (!element || !element.attributes) return;
        for (const attr of element.attributes) {
          if (attr && attr.value) {
            VideoUrlProcessor.processUrl(attr.value, 0, 'attribute:' + attr.name);
          }
        }
      } catch (e) {}
    },

    // 扫描视频元素及其子节点
    scanMediaElement(element) {
      try {
        if (!element || element.tagName !== 'VIDEO') return;
        if (element.src) {
          VideoUrlProcessor.processUrl(element.src, 0, 'video:src'); // 处理 src 属性
        }
        if (element.currentSrc) {
          VideoUrlProcessor.processUrl(element.currentSrc, 0, 'video:currentSrc'); // 处理当前播放 URL
        }
        const sources = element.querySelectorAll('source');
        sources.forEach(source => {
          try {
            const src = source.src || source.getAttribute('src');
            if (src) {
              VideoUrlProcessor.processUrl(src, 0, 'video:source'); // 处理 source 标签
            }
          } catch (e) {}
        });
        
        if (!element._srcObserved) {
          element._srcObserved = true;
          try {
            const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
            if (descriptor && descriptor.set) {
              const originalSrcSetter = descriptor.set;
              Object.defineProperty(element, 'src', {
                set: function(value) {
                  try {
                    if (value) {
                      VideoUrlProcessor.processUrl(value, 0, 'video:src:setter'); // 监控 src 属性变化
                    }
                  } catch (e) {}
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
      } catch (e) {}
    },

    // 扫描页面中的媒体相关元素
    scanPage(root = document) {
      try {
        const now = Date.now();
        const isFullScan = now - this.lastFullScanTime > CONFIG.fullScanInterval;
        if (isFullScan) {
          this.lastFullScanTime = now;
          this.cleanupProcessedElements(); // 定期清理
        }
        
        const selector = [
          'video',
          'source',
          '[class*="video"]',
          '[class*="player"]',
          `[class*="${filePattern}"]`,
          `[data-${filePattern}]`,
          `a[href*="${filePattern}"]`,
          `[data-src*="${filePattern}"]`
        ].join(',');
        try {
          const elements = root.querySelectorAll(selector);
          elements.forEach(element => {
            try {
              if (!element || this.processedElements.has(element)) return;
              this.processedElements.add(element);
              this.processedCount++;
              this.scanAttributes(element);
              this.scanMediaElement(element);
            } catch (e) {}
          });
        } catch (e) {}
        if (isFullScan) {
          try {
            const anchorElements = root.querySelectorAll('a[href]');
            anchorElements.forEach(a => {
              try {
                if (a && a.href && !this.processedElements.has(a)) {
                  this.processedElements.add(a);
                  this.processedCount++;
                  VideoUrlProcessor.processUrl(a.href, 0, 'anchor'); // 处理链接
                }
              } catch (e) {}
            });
          } catch (e) {}
          this.scanAllDataAttributes(root); // 扫描 data 属性
          this.scanScripts(); // 扫描脚本内容
        }
      } catch (e) {}
    },
    
    // 扫描所有 data 属性
    scanAllDataAttributes(root) {
      try {
        const allElements = root.querySelectorAll('[data-*]');
        allElements.forEach(el => {
          try {
            if (!el || this.processedElements.has(el)) return;
            this.processedElements.add(el);
            this.processedCount++;
            const attributes = Array.from(el.attributes || []);
            attributes
              .filter(attr => attr && attr.name && attr.name.startsWith('data-'))
              .forEach(attr => {
                try {
                  if (attr.value) {
                    VideoUrlProcessor.processUrl(attr.value, 0, 'data-attribute');
                  }
                } catch (e) {}
              });
          } catch (e) {}
        });
      } catch (e) {}
    },

    // 扫描脚本内容中的 URL
    scanScripts() {
      try {
        const scripts = document.querySelectorAll('script:not([src])');
        scripts.forEach(script => {
          try {
            const content = script.textContent;
            if (!content) return;
            const urlRegex = new RegExp(`['"](https?://[^'"]*?\\.${filePattern}[^'"]*?)['"]|['"](/[^'"]*?\\.${filePattern}[^'"]*?)['"]`, 'g');
            let match;
            while ((match = urlRegex.exec(content)) !== null) {
              try {
                const url = match[1] || match[2];
                if (url) {
                  VideoUrlProcessor.processUrl(url, 0, 'script:regex');
                }
              } catch (e) {}
            }
          } catch (e) {}
        });
      } catch (e) {}
    }
  };

  // 处理页面 URL 变化
  function handleUrlChange() {
    try {
      DOMScanner.scanPage(document); // 重新扫描页面
    } catch (e) {}
  }

  // 初始化流媒体检测器
  function initializeDetector() {
    try {
      NetworkInterceptor.setupXHRInterceptor(); // 设置 XHR 拦截
      NetworkInterceptor.setupFetchInterceptor(); // 设置 Fetch 拦截
      NetworkInterceptor.setupMediaSourceInterceptor(); // 设置 MediaSource 拦截
      
      observer = new MutationObserver(mutations => {
        try {
          const processQueue = new Set();
          const newVideos = new Set();
          mutations.forEach(mutation => {
            try {
              mutation.addedNodes.forEach(node => {
                try {
                  if (node && node.nodeType === 1) {
                    if (node.tagName === 'VIDEO') {
                      newVideos.add(node); // 记录新增 video 元素
                    }
                    if (node instanceof Element) {
                      const attributes = Array.from(node.attributes || []);
                      attributes.forEach(attr => {
                        try {
                          if (attr && attr.value) {
                            processQueue.add(attr.value); // 收集属性值
                          }
                        } catch (e) {}
                      });
                    }
                  }
                } catch (e) {}
              });
              if (mutation.type === 'attributes' && mutation.target) {
                try {
                  const newValue = mutation.target.getAttribute(mutation.attributeName);
                  if (newValue) {
                    processQueue.add(newValue);
                    if (['src', 'data-src', 'href'].includes(mutation.attributeName)) {
                      if (newValue && newValue.includes('.' + filePattern)) {
                        VideoUrlProcessor.processUrl(newValue, 0, 'attribute:change'); // 处理属性变化
                      }
                    }
                  }
                } catch (e) {}
              }
            } catch (e) {}
          });
          newVideos.forEach(video => {
            try {
              DOMScanner.scanMediaElement(video); // 处理新增 video 元素
            } catch (e) {}
          });
          const processQueueItems = () => {
            try {
              processQueue.forEach(item => {
                try {
                  if (typeof item === 'string') {
                    VideoUrlProcessor.processUrl(item, 0, 'mutation:string');
                  } else if (item && item.parentNode) {
                    DOMScanner.scanPage(item.parentNode || document);
                  }
                } catch (e) {}
              });
            } catch (e) {}
          };
          if (window.requestIdleCallback) {
            requestIdleCallback(processQueueItems, { timeout: 1000 });
          } else {
            setTimeout(processQueueItems, 100);
          }
        } catch (e) {}
      });
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true
      });
      window.addEventListener('popstate', handleUrlChange); // 监听 URL 变化
      window.addEventListener('hashchange', handleUrlChange);
      const initialScan = () => {
        try {
          DOMScanner.scanPage(document); // 初始页面扫描
        } catch (e) {}
      };
      if (window.requestIdleCallback) {
        requestIdleCallback(initialScan, { timeout: 1000 });
      } else {
        setTimeout(initialScan, 100);
      }
      const intervalId = setInterval(() => {
        try {
          if (!document.hidden) {
            DOMScanner.scanPage(document); // 定期扫描页面
          }
        } catch (e) {}
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
        observer.disconnect(); // 停止 DOM 监控
        observer = null;
      }
      window.removeEventListener('popstate', handleUrlChange);
      window.removeEventListener('hashchange', handleUrlChange);
      if (window._m3u8DetectorIntervalId) {
        clearInterval(window._m3u8DetectorIntervalId); // 清理定时器
        delete window._m3u8DetectorIntervalId;
      }
      delete window._m3u8DetectorInitialized;
      processedUrls.clear(); // 清空 URL 集合
      DOMScanner.processedElements.clear(); // 清空元素集合
      DOMScanner.processedCount = 0;
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
