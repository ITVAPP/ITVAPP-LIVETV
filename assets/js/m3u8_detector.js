  // 流媒体探测器
(function() {
  // 避免重复初始化 (保留原逻辑)
  if (window._m3u8DetectorInitialized) return;
  window._m3u8DetectorInitialized = true;

  // 初始化状态
  const processedUrls = new Set();
  const MAX_RECURSION_DEPTH = 3;
  let observer = null;
  
  // File pattern will be dynamically replaced
  const filePattern = "m3u8";

  // URL处理工具 (优化URL处理逻辑)
  const VideoUrlProcessor = {
    processUrl(url, depth = 0, source = 'unknown') {
      if (!url || typeof url !== 'string' || 
          depth > MAX_RECURSION_DEPTH || 
          processedUrls.has(url)) return;

      // URL标准化
      url = this.normalizeUrl(url);

      // Base64处理
      if (url.includes('base64,')) {
        this.handleBase64Url(url, depth, source);
        return;
      }

      // 检查目标文件类型
      const pattern = new RegExp('\\.(' + filePattern + '|m3u8|ts|mp4|flv)([?#]|$)', 'i');
      if (pattern.test(url)) {
        processedUrls.add(url);
        window.M3U8Detector?.postMessage(JSON.stringify({
          type: 'url',
          url: url,
          source: source
        }));
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
    },

    handleBase64Url(url, depth, source) {
      try {
        const base64Content = url.split('base64,')[1];
        const decodedContent = atob(base64Content);
        
        // 尝试同时检查多种媒体格式
        const patterns = [filePattern, 'm3u8', 'mp4', 'flv', 'ts'];
        for (const pattern of patterns) {
          if (decodedContent.includes('.' + pattern)) {
            this.processUrl(decodedContent, depth + 1, source + ':base64');
          }
        }
      } catch (e) {
        console.error('Base64解码失败:', e);
      }
    }
  };

  // 网络请求拦截器 (保留核心逻辑，添加详细日志)
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
        if (this._url) VideoUrlProcessor.processUrl(this._url, 0, 'xhr');
        
        // 添加响应处理
        this.addEventListener('load', function() {
          if (this.responseURL) {
            VideoUrlProcessor.processUrl(this.responseURL, 0, 'xhr:response');
          }
          
          // 检查响应内容
          if (this.responseType === '' || this.responseType === 'text') {
            try {
              const responseText = this.responseText;
              if (responseText && responseText.includes('.' + filePattern)) {
                // 用正则匹配URL
                const pattern = new RegExp(`(?:https?://|//|/)[^'"\\s,()<>{}\\[\\]]*?\\.${filePattern}[^'"\\s,()<>{}\\[\\]]*`, 'g');
                const matches = responseText.match(pattern);
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
          VideoUrlProcessor.processUrl(response.url, 0, 'fetch:response');
          
          // 检查可能的JSON响应中的URL
          if (response.headers.get('content-type')?.includes('application/json')) {
            response.clone().text().then(text => {
              if (text && text.includes('.' + filePattern)) {
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

    setupMediaSourceInterceptor() {
      if (!window.MediaSource) return;

      const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
      MediaSource.prototype.addSourceBuffer = function(mimeType) {
        const supportedTypes = {
          'm3u8': ['application/x-mpegURL', 'application/vnd.apple.mpegURL'],
          'flv': ['video/x-flv', 'application/x-flv', 'flv-application/octet-stream'],
          'mp4': ['video/mp4', 'application/mp4']
        };

        const currentTypes = supportedTypes[filePattern] || [];
        if (currentTypes.some(type => mimeType.includes(type))) {
          VideoUrlProcessor.processUrl(this.url, 0, 'mediaSource');
        }
        return originalAddSourceBuffer.call(this, mimeType);
      };
      
      // 添加MSE URL监控
      try {
        const originalURL = window.URL || window.webkitURL;
        if (originalURL && originalURL.createObjectURL) {
          const originalCreateObjectURL = originalURL.createObjectURL;
          originalURL.createObjectURL = function(obj) {
            const url = originalCreateObjectURL.call(this, obj);
            if (obj instanceof MediaSource) {
              // 使用MutationObserver监控创建的MediaSource
              setTimeout(() => {
                const videoElements = document.querySelectorAll('video');
                videoElements.forEach(video => {
                  if (video.src === url) {
                    video.addEventListener('loadedmetadata', () => {
                      if (video.duration > 0 && video.src) {
                        VideoUrlProcessor.processUrl(video.src, 0, 'mediaSource:video');
                      }
                    });
                  }
                });
              }, 100);
            }
            return url;
          };
        }
      } catch (e) {
        console.error('MediaSource URL拦截失败:', e);
      }
    }
  };

  // DOM扫描器 (增强DOM扫描能力)
  const DOMScanner = {
    processedElements: new Set(),
    lastFullScanTime: 0,

    scanAttributes(element) {
      for (const attr of element.attributes) {
        if (attr.value) VideoUrlProcessor.processUrl(attr.value, 0, 'attribute:' + attr.name);
      }
    },

    scanMediaElement(element) {
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
      const now = Date.now();
      const isFullScan = now - this.lastFullScanTime > 5000; // 每5秒做一次完整扫描
      
      if (isFullScan) {
        this.lastFullScanTime = now;
      }
      
      // 基于选择器的扫描 (原始逻辑)
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

      root.querySelectorAll(selector).forEach(element => {
        if (this.processedElements.has(element)) return;
        this.processedElements.add(element);

        this.scanAttributes(element);
        this.scanMediaElement(element);
      });
      
      // 扫描所有iframe
      root.querySelectorAll('iframe').forEach(iframe => {
        try {
          if (iframe.contentDocument && iframe.contentDocument.documentElement) {
            this.scanPage(iframe.contentDocument);
          }
        } catch (e) {
          // 跨域iframe无法访问
        }
      });

      if (isFullScan) {
        // 检查所有<a>标签
        root.querySelectorAll('a').forEach(a => {
          if (a.href && !this.processedElements.has(a)) {
            this.processedElements.add(a);
            VideoUrlProcessor.processUrl(a.href, 0, 'anchor');
          }
        });
        
        // 全面扫描所有可能的元素
        this.scanAllDataAttributes(root);
        this.scanScripts();
      }
    },
    
    scanAllDataAttributes(root) {
      // 查找所有含data-属性的元素
      const allElements = root.querySelectorAll('[data-*]');
      allElements.forEach(el => {
        if (this.processedElements.has(el)) return;
        this.processedElements.add(el);
        
        // 检查所有data-属性
        Array.from(el.attributes)
          .filter(attr => attr.name.startsWith('data-'))
          .forEach(attr => {
            if (attr.value) {
              VideoUrlProcessor.processUrl(attr.value, 0, 'data-attribute');
            }
          });
      });
    },

    scanScripts() {
      document.querySelectorAll('script:not([src])').forEach(script => {
        if (!script.textContent) return;
        
        // 扩展查找多种文件模式
        const patterns = [filePattern, 'm3u8', 'mp4', 'flv', 'ts'];
        
        for (const pattern of patterns) {
          const patternStr = '.' + pattern;
          let index = script.textContent.indexOf(patternStr);
          
          while (index !== -1) {
            const extracted = this.extractUrlFromScript(script.textContent, index);
            if (extracted.url.includes('http')) {
              VideoUrlProcessor.processUrl(extracted.url, 0, 'script:' + pattern);
            }
            index = script.textContent.indexOf(patternStr, extracted.endIndex);
          }
        }
      });
    },

    extractUrlFromScript(content, startIndex) {
      let urlStart = startIndex;
      let urlEnd = startIndex;

      // 向前查找 URL 起点
      while (urlStart > 0) {
        const char = content[urlStart - 1];
        if (char === '"' || char === "'" || char === ' ' || char === '\\n') break;
        urlStart--;
      }

      // 向后查找 URL 终点
      while (urlEnd < content.length) {
        const char = content[urlEnd];
        if (char === '"' || char === "'" || char === ' ' || char === '\\n') break;
        urlEnd++;
      }

      return {
        url: content.substring(urlStart, urlEnd).trim(),
        endIndex: urlEnd
      };
    }
  };

  // 增强型播放器检测 (新增)
  const PlayerDetector = {
    knownPlayerClasses: [
      'player', 'video-js', 'jwplayer', 'html5-video-player', 'video-player',
      'video_player', 'media-player', 'flowplayer', 'vjs-player', 'mejs-player'
    ],
    
    setupPlayerDetection() {
      // 监控播放器API
      const playerAPIs = [
        'videojs', 'jwplayer', 'flowplayer', 'Player', 'createPlayer',
        'DPlayer', 'Hls', 'flvjs', 'dashjs', 'Plyr', 'MediaElementPlayer'
      ];
      
      playerAPIs.forEach(api => {
        if (window[api]) {
          this.hookPlayerAPI(api);
        } else {
          Object.defineProperty(window, api, {
            configurable: true,
            enumerable: true,
            get: function() { return this['_' + api]; },
            set: function(value) {
              this['_' + api] = value;
              PlayerDetector.hookPlayerAPI(api, value);
            }
          });
        }
      });
    },
    
    hookPlayerAPI(apiName, apiObj) {
      try {
        const api = apiObj || window[apiName];
        if (!api || api._hooked) return;
        
        console.info('检测到播放器API: ' + apiName);
        api._hooked = true;
        
        // 根据不同播放器API实现不同的钩子
        if (apiName === 'videojs' && typeof api === 'function') {
          const originalVideojs = api;
          window[apiName] = function() {
            const player = originalVideojs.apply(this, arguments);
            if (player && player.src) {
              const originalSrc = player.src;
              player.src = function(src) {
                if (src && typeof src === 'string') {
                  VideoUrlProcessor.processUrl(src, 0, 'player:videojs');
                } else if (src && typeof src === 'object' && src.src) {
                  VideoUrlProcessor.processUrl(src.src, 0, 'player:videojs');
                }
                return originalSrc.apply(this, arguments);
              };
            }
            return player;
          };
        } else if (apiName === 'Hls' && api.isSupported) {
          const originalLoadSource = api.prototype.loadSource;
          api.prototype.loadSource = function(url) {
            if (url) VideoUrlProcessor.processUrl(url, 0, 'player:hls');
            return originalLoadSource.call(this, url);
          };
        } else if (apiName === 'flvjs' && api.createPlayer) {
          const originalCreatePlayer = api.createPlayer;
          api.createPlayer = function(mediaDataSource) {
            if (mediaDataSource && mediaDataSource.url) {
              VideoUrlProcessor.processUrl(mediaDataSource.url, 0, 'player:flvjs');
            }
            return originalCreatePlayer.call(this, mediaDataSource);
          };
        }
      } catch (e) {
        console.error('Hook播放器API失败: ' + apiName, e);
      }
    },
    
    init() {
      this.setupPlayerDetection();
      
      // 特定播放器支持
      this.setupHlsSupport();
      this.setupDashSupport();
    },
    
    setupHlsSupport() {
      if (window.Hls) {
        const originalLoadSource = window.Hls.prototype.loadSource;
        window.Hls.prototype.loadSource = function(url) {
          if (url) VideoUrlProcessor.processUrl(url, 0, 'hls:loadSource');
          return originalLoadSource.call(this, url);
        };
      }
    },
    
    setupDashSupport() {
      if (window.dashjs && window.dashjs.MediaPlayer) {
        const originalAttachSource = window.dashjs.MediaPlayer.prototype.attachSource;
        window.dashjs.MediaPlayer.prototype.attachSource = function(url) {
          if (url) VideoUrlProcessor.processUrl(url, 0, 'dash:attachSource');
          return originalAttachSource.call(this, url);
        };
      }
    }
  };

  // 处理 URL 变化的函数
  function handleUrlChange() {
    DOMScanner.scanPage(document);
  }

  // 初始化检测器
  function initializeDetector() {
    // 设置网络拦截 (保留原逻辑)
    NetworkInterceptor.setupXHRInterceptor();
    NetworkInterceptor.setupFetchInterceptor();
    NetworkInterceptor.setupMediaSourceInterceptor();
    
    // 初始化播放器检测
    PlayerDetector.init();

    // 设置 DOM 观察 (增强MutationObserver回调)
    observer = new MutationObserver(mutations => {
      const processQueue = new Set();
      const newVideos = new Set();

      mutations.forEach(mutation => {
        // 处理新增节点
        mutation.addedNodes.forEach(node => {
          if (node.nodeType === 1) {
            // 检查新增的video元素
            if (node.tagName === 'VIDEO') {
              newVideos.add(node);
            }
            
            // 检查新增的player元素
            if (PlayerDetector.knownPlayerClasses.some(cls => 
                (node.className && node.className.includes(cls)) || 
                (node.id && node.id.includes('player')))) {
              console.info('检测到可能的播放器元素: ', node);
              processQueue.add(node);
            }
            
            if (node instanceof Element) {
              for (const attr of node.attributes) {
                if (attr.value) processQueue.add(attr.value);
              }
            }
            
            // 检查是否是iframe并扫描
            if (node.tagName === 'IFRAME') {
              try {
                setTimeout(() => {
                  if (node.contentDocument) {
                    DOMScanner.scanPage(node.contentDocument);
                  }
                }, 500);
              } catch (e) {
                // 跨域iframe
              }
            }
          }
        });

        // 处理属性变化
        if (mutation.type === 'attributes') {
          const newValue = mutation.target.getAttribute(mutation.attributeName);
          if (newValue) processQueue.add(newValue);
          
          // 检查特定属性是否与播放相关
          if (['src', 'data-src', 'href'].includes(mutation.attributeName)) {
            if (newValue && newValue.includes('.' + filePattern)) {
              VideoUrlProcessor.processUrl(newValue, 0, 'attribute:change');
            }
          }
        }
      });

      // 优先处理新增的视频元素
      newVideos.forEach(video => {
        DOMScanner.scanMediaElement(video);
      });

      // 使用requestIdleCallback处理队列
      if (window.requestIdleCallback) {
        requestIdleCallback(() => {
          processQueue.forEach(item => {
            if (typeof item === 'string') {
              VideoUrlProcessor.processUrl(item, 0, 'mutation:string');
            } else {
              DOMScanner.scanPage(item.parentNode || document);
            }
          });
        }, { timeout: 1000 });
      } else {
        // 降级方案
        setTimeout(() => {
          processQueue.forEach(item => {
            if (typeof item === 'string') {
              VideoUrlProcessor.processUrl(item, 0, 'mutation:string');
            } else {
              DOMScanner.scanPage(item.parentNode || document);
            }
          });
        }, 100);
      }
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true
    });

    // URL 变化处理
    window.addEventListener('popstate', handleUrlChange);
    window.addEventListener('hashchange', handleUrlChange);

    // 初始扫描
    if (window.requestIdleCallback) {
      requestIdleCallback(() => {
        DOMScanner.scanPage(document);
      }, { timeout: 1000 });
    } else {
      setTimeout(() => {
        DOMScanner.scanPage(document);
      }, 100);
    }
    
    // 定期全面扫描
    setInterval(() => {
      if (!document.hidden) {
        DOMScanner.scanPage(document);
      }
    }, 1000); // 每1秒扫描一次
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
    processedUrls.clear();
    DOMScanner.processedElements.clear();
  };

  // 公开常用方法给外部调用
  window.checkMediaElements = function(root) {
    if (root) DOMScanner.scanPage(root);
  };
  
  window.efficientDOMScan = function() {
    DOMScanner.scanPage(document);
  };
  
  // 初始化通知
  if (window.M3U8Detector) {
    window.M3U8Detector.postMessage(JSON.stringify({
      type: 'init',
      message: 'M3U8Detector initialized'
    }));
  }
})();
