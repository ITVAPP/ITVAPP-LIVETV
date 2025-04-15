// 资源清理脚本：清理页面资源（如请求、定时器、事件监听器等），防止内存泄漏
(function() {
  // 创建清理状态对象，记录各项清理操作的结果
  const cleanupStatus = {
    xhrAborted: 0,
    timeoutsCleared: 0,
    intervalsCleared: 0,
    listenersRemoved: 0,
    socketsClose: 0,
    fetchAborted: 0,
    mediaReset: 0,
    networkAborted: 0,
    imagesAborted: 0,
    serviceWorkersUnregistered: 0
  };
  
  // 停止页面加载
  try {
    window.stop(); // 中止页面所有加载活动
    cleanupStatus.pageStopped = true;
  } catch (e) {
    console.error('停止页面加载失败', e);
    cleanupStatus.pageStopped = false;
  }

  // 清理时间拦截器
  try {
    if (window._cleanupTimeInterceptor) {
      window._cleanupTimeInterceptor(); // 执行时间拦截器清理
      cleanupStatus.timeInterceptorCleaned = true;
    }
  } catch (e) {
    console.error('清理时间拦截器失败', e);
    cleanupStatus.timeInterceptorCleaned = false;
  }

  // 清理所有活跃的 XHR 请求
  try {
    const activeXhrs = window._activeXhrs || [];
    activeXhrs.forEach(xhr => {
      try {
        xhr.abort(); // 中止单个 XHR 请求
        cleanupStatus.xhrAborted++;
      } catch (e) {}
    });
    
    // 拦截新 XHR 请求并立即中止
    if (window.XMLHttpRequest) {
      const origXHR = window.XMLHttpRequest;
      window.XMLHttpRequest = function() {
        const xhr = new origXHR();
        xhr.abort = function() { return true; }; // 重写 abort 方法
        xhr.open = function() { return null; }; // 重写 open 方法
        xhr.send = function() { return null; }; // 重写 send 方法
        return xhr;
      };
      cleanupStatus.xhrBlocked = true;
    }
  } catch (e) {
    console.error('中止 XHR 请求失败', e);
    cleanupStatus.xhrBlocked = false;
  }

  // 清理所有 Fetch 请求
  try {
    if (window._abortController) {
      window._abortController.abort(); // 中止现有 Fetch 请求
      cleanupStatus.fetchAborted++;
    }
    
    // 阻止新 Fetch 请求
    if (window.fetch) {
      window.fetch = function() { 
        return Promise.resolve(new Response('', {
          status: 499,
          statusText: 'Client Closed Request'
        })); // 返回模拟的 499 响应
      };
      cleanupStatus.fetchBlocked = true;
    }
  } catch (e) {
    console.error('中止 Fetch 请求失败', e);
    cleanupStatus.fetchBlocked = false;
  }
  
  // 清理 Beacon 请求
  try {
    if (navigator.sendBeacon) {
      navigator.sendBeacon = function() { return false; }; // 阻止 Beacon 请求
      cleanupStatus.beaconBlocked = true;
    }
  } catch (e) {
    cleanupStatus.beaconBlocked = false;
  }

  // 清理所有定时器
  try {
    const highestTimeoutId = window.setTimeout(() => {}, 0); // 获取最高 setTimeout ID
    for (let i = 0; i <= highestTimeoutId; i++) {
      window.clearTimeout(i); // 清除单个 setTimeout
      cleanupStatus.timeoutsCleared++;
    }
    
    const highestIntervalId = window.setInterval(() => {}, 100000); // 获取最高 setInterval ID
    for (let i = 0; i <= highestIntervalId; i++) {
      window.clearInterval(i); // 清除单个 setInterval
      cleanupStatus.intervalsCleared++;
    }
    
    // 覆盖定时器函数，防止新定时器创建
    window.setTimeout = function() { return 0; };
    window.setInterval = function() { return 0; };
    window.requestAnimationFrame = function() { return 0; };
    
    cleanupStatus.timerFunctionsBlocked = true;
  } catch (e) {
    console.error('清理定时器失败', e);
    cleanupStatus.timerFunctionsBlocked = false;
  }

  // 清理所有事件监听器
  try {
    const commonEvents = [
      'scroll', 'resize', 'load', 'unload', 'beforeunload',
      'popstate', 'hashchange', 'visibilitychange', 'online', 'offline',
      'message', 'storage', 'focus', 'blur', 'error'
    ];
    
    // 清理 window 上的事件监听器
    commonEvents.forEach(event => {
      try {
        window.removeEventListener(event, null, true);
        window.removeEventListener(event, null, false);
        window.removeEventListener(event, window[`_${event}Handler`]);
        cleanupStatus.listenersRemoved++;
      } catch (e) {}
    });
    
    // 清理 document 上的事件监听器
    commonEvents.forEach(event => {
      try {
        document.removeEventListener(event, null, true);
        document.removeEventListener(event, null, false);
        document.removeEventListener(event, document[`_${event}Handler`]);
        cleanupStatus.listenersRemoved++;
      } catch (e) {}
    });
    
    // 覆盖 addEventListener，防止新监听器添加
    const originalAddEventListener = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function() { return null; };
    
    window._originalAddEventListener = originalAddEventListener; // 保存原始函数
    cleanupStatus.eventListenersBlocked = true;
  } catch (e) {
    console.error('清理事件监听器失败', e);
    cleanupStatus.eventListenersBlocked = false;
  }

  // 清理 M3U8 检测器
  try {
    if (window._cleanupM3U8Detector) {
      window._cleanupM3U8Detector(); // 执行 M3U8 检测器清理
      cleanupStatus.m3u8DetectorCleaned = true;
    }
  } catch (e) {
    console.error('清理 M3U8 检测器失败', e);
    cleanupStatus.m3u8DetectorCleaned = false;
  }

  // 终止所有 MediaSource 操作
  try {
    if (window.MediaSource) {
      const mediaSources = document.querySelectorAll('video source');
      mediaSources.forEach(source => {
        const mediaElement = source.parentElement;
        if (mediaElement) {
          const wasPlaying = !mediaElement.paused; // 保存播放状态
          const currentTime = mediaElement.currentTime; // 保存当前时间
          const currentVolume = mediaElement.volume; // 保存音量
          
          try {
            mediaElement.pause(); // 暂停媒体
            mediaElement.removeAttribute('src'); // 移除 src 属性
            mediaElement.load(); // 重新加载媒体
            cleanupStatus.mediaReset++;
            mediaElement.play = function() { 
              return Promise.reject(new DOMException('NotAllowedError')); // 重写 play 方法
            };
          } catch (e) {
            console.error('重置媒体元素失败', e);
          }
        }
      });
      
      // 处理无 source 的 video 元素
      const videoElements = document.querySelectorAll('video:not([source])');
      videoElements.forEach(video => {
        try {
          if (video.src) {
            video.pause(); // 暂停视频
            video.removeAttribute('src'); // 移除 src 属性
            video.load(); // 重新加载视频
            video.play = function() {
              return Promise.reject(new DOMException('NotAllowedError')); // 重写 play 方法
            };
            cleanupStatus.mediaReset++;
          }
        } catch (e) {}
      });
      
      // 阻止新 MediaSource 创建
      if (window.URL && window.URL.createObjectURL) {
        const originalCreateObjectURL = window.URL.createObjectURL;
        window.URL.createObjectURL = function(obj) {
          if (obj instanceof MediaSource) {
            return '#blocked-media-source'; // 阻止 MediaSource URL 创建
          }
          return originalCreateObjectURL.apply(this, arguments);
        };
      }
      
      cleanupStatus.mediaSourceBlocked = true;
    }
  } catch (e) {
    console.error('终止 MediaSource 操作失败', e);
    cleanupStatus.mediaSourceBlocked = false;
  }

  // 清理所有 WebSocket 连接
  try {
    const sockets = window._webSockets || [];
    sockets.forEach(socket => {
      try {
        socket.close(); // 关闭单个 WebSocket
        cleanupStatus.socketsClose++;
      } catch (e) {}
    });
    
    // 阻止新 WebSocket 连接
    if (window.WebSocket) {
      const OrigWebSocket = window.WebSocket;
      window.WebSocket = function() {
        const socket = {
          close: function() {},
          send: function() { return false; },
          addEventListener: function() {},
          removeEventListener: function() {}
        };
        
        // 模拟 error 和 close 事件
        setTimeout(() => {
          if (this.onerror) this.onerror(new Event('error'));
          if (this.onclose) this.onclose(new CloseEvent('close'));
        }, 0);
        
        return socket;
      };
      window._OrigWebSocket = OrigWebSocket; // 保存原始 WebSocket
      cleanupStatus.websocketsBlocked = true;
    }
  } catch (e) {
    console.error('清理 WebSocket 连接失败', e);
    cleanupStatus.websocketsBlocked = false;
  }

  // 停止所有进行中的网络请求
  try {
    if (window.performance && window.performance.getEntries) {
      const resources = window.performance.getEntries().filter(e =>
        e.initiatorType === 'xmlhttprequest' ||
        e.initiatorType === 'fetch' ||
        e.initiatorType === 'beacon'
      );
      resources.forEach(resource => {
        if (resource.duration === 0) {
          try {
            const controller = new AbortController();
            controller.abort(); // 中止未完成网络请求
            cleanupStatus.networkAborted++;
          } catch(e) {}
        }
      });
    }
  } catch (e) {
    console.error('停止网络请求失败', e);
  }

  // 清理所有未完成的图片加载
  try {
    document.querySelectorAll('img').forEach(img => {
      if (!img.complete) {
        const originalSrc = img.src;
        img.src = ''; // 停止图片加载
        cleanupStatus.imagesAborted++;
        
        // 防止重新加载图片
        Object.defineProperty(img, 'src', {
          set: function() { return ''; },
          get: function() { return ''; }
        });
      }
    });
    cleanupStatus.imageLoadingBlocked = true;
  } catch (e) {
    console.error('清理图片加载失败', e);
    cleanupStatus.imageLoadingBlocked = false;
  }
  
  // 清理 Service Worker
  try {
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      navigator.serviceWorker.getRegistrations().then(registrations => {
        registrations.forEach(registration => {
          registration.unregister(); // 注销 Service Worker
          cleanupStatus.serviceWorkersUnregistered++;
        });
      });
    }
    cleanupStatus.serviceWorkersCleaned = true;
  } catch (e) {
    console.error('清理 Service Worker 失败', e);
    cleanupStatus.serviceWorkersCleaned = false;
  }

  // 清理全局变量
  try {
    delete window._timeInterceptorInitialized; // 移除时间拦截器初始化标志
    delete window._originalDate; // 移除原始 Date 对象
    delete window._originalPerformanceNow; // 移除原始 performance.now
    delete window._originalRAF; // 移除原始 requestAnimationFrame
    delete window._originalConsoleTime; // 移除原始 console.time
    delete window._originalConsoleTimeEnd; // 移除原始 console.timeEnd
    delete window._m3u8DetectorInitialized; // 移除 M3U8 检测器初始化标志
    delete window._cleanupTimeInterceptor; // 移除时间拦截器清理函数
    delete window._cleanupM3U8Detector; // 移除 M3U8 检测器清理函数
    cleanupStatus.globalVariablesCleaned = true;
  } catch (e) {
    console.error('清理全局变量失败', e);
    cleanupStatus.globalVariablesCleaned = false;
  }
  
  // 返回清理状态
  if (window.CleanupCompleted) {
    window.CleanupCompleted.postMessage(JSON.stringify({
      type: 'cleanup',
      status: 'completed',
      details: cleanupStatus
    })); // 通知清理完成
  }
})();
