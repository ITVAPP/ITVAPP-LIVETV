// 资源清理脚本
(function() {
  // 创建清理状态对象
  const cleanupStatus = {
    xhrAborted: 0,
    timeoutsCleared: 0,
    intervalsCleared: 0,
    listenersRemoved: 0,
    socketsClose: 0,
    fetchAborted: 0,
    mediaReset: 0
  };
  
  // 停止页面加载
  try {
    window.stop();
    cleanupStatus.pageStopped = true;
  } catch (e) {
    console.error('停止页面加载失败', e);
    cleanupStatus.pageStopped = false;
  }

  // 清理时间拦截器
  try {
    if (window._cleanupTimeInterceptor) {
      window._cleanupTimeInterceptor();
      cleanupStatus.timeInterceptorCleaned = true;
    }
  } catch (e) {
    console.error('清理时间拦截器失败', e);
    cleanupStatus.timeInterceptorCleaned = false;
  }

  // 清理所有活跃的XHR请求
  try {
    const activeXhrs = window._activeXhrs || [];
    activeXhrs.forEach(xhr => {
      try {
        xhr.abort();
        cleanupStatus.xhrAborted++;
      } catch (e) {}
    });
    
    // 拦截新的XHR请求并立即中止
    if (window.XMLHttpRequest) {
      const origXHR = window.XMLHttpRequest;
      window.XMLHttpRequest = function() {
        const xhr = new origXHR();
        xhr.abort = function() { return true; };
        xhr.open = function() { return null; };
        xhr.send = function() { return null; };
        return xhr;
      };
      cleanupStatus.xhrBlocked = true;
    }
  } catch (e) {
    console.error('中止XHR请求失败', e);
    cleanupStatus.xhrBlocked = false;
  }

  // 清理所有Fetch请求
  try {
    if (window._abortController) {
      window._abortController.abort();
      cleanupStatus.fetchAborted++;
    }
    
    // 阻止新的fetch请求
    if (window.fetch) {
      window.fetch = function() { 
        return Promise.resolve(new Response('', {
          status: 499,
          statusText: 'Client Closed Request'
        }));
      };
      cleanupStatus.fetchBlocked = true;
    }
  } catch (e) {
    console.error('中止Fetch请求失败', e);
    cleanupStatus.fetchBlocked = false;
  }
  
  // 清理Beacon请求
  try {
    if (navigator.sendBeacon) {
      navigator.sendBeacon = function() { return false; };
      cleanupStatus.beaconBlocked = true;
    }
  } catch (e) {
    cleanupStatus.beaconBlocked = false;
  }

  // 清理所有定时器
  try {
    // 获取最高定时器ID
    const highestTimeoutId = window.setTimeout(() => {}, 0);
    // 清理所有setTimeout
    for (let i = 0; i <= highestTimeoutId; i++) {
      window.clearTimeout(i);
      cleanupStatus.timeoutsCleared++;
    }
    
    // 获取最高间隔器ID
    const highestIntervalId = window.setInterval(() => {}, 100000);
    // 清理所有setInterval
    for (let i = 0; i <= highestIntervalId; i++) {
      window.clearInterval(i);
      cleanupStatus.intervalsCleared++;
    }
    
    // 覆盖定时器函数，防止新的定时器创建
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
    // 常见的事件监听器
    const commonEvents = [
      'scroll', 'resize', 'load', 'unload', 'beforeunload',
      'popstate', 'hashchange', 'visibilitychange', 'online', 'offline',
      'message', 'storage', 'focus', 'blur', 'error'
    ];
    
    // 清理window上的事件监听器
    commonEvents.forEach(event => {
      try {
        window.removeEventListener(event, null, true);
        window.removeEventListener(event, null, false);
        window.removeEventListener(event, window[`_${event}Handler`]);
        cleanupStatus.listenersRemoved++;
      } catch (e) {}
    });
    
    // 清理document上的事件监听器
    commonEvents.forEach(event => {
      try {
        document.removeEventListener(event, null, true);
        document.removeEventListener(event, null, false);
        document.removeEventListener(event, document[`_${event}Handler`]);
        cleanupStatus.listenersRemoved++;
      } catch (e) {}
    });
    
    // 覆盖addEventListener，防止新的监听器添加
    const originalAddEventListener = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function() { return null; };
    
    // 保存原始函数，以便以后可能的恢复
    window._originalAddEventListener = originalAddEventListener;
    
    cleanupStatus.eventListenersBlocked = true;
  } catch (e) {
    console.error('清理事件监听器失败', e);
    cleanupStatus.eventListenersBlocked = false;
  }

  // 清理M3U8检测器
  try {
    if (window._cleanupM3U8Detector) {
      window._cleanupM3U8Detector();
      cleanupStatus.m3u8DetectorCleaned = true;
    }
  } catch (e) {
    console.error('清理M3U8检测器失败', e);
    cleanupStatus.m3u8DetectorCleaned = false;
  }

  // 终止所有正在进行的MediaSource操作
  try {
    if (window.MediaSource) {
      const mediaSources = document.querySelectorAll('video source');
      mediaSources.forEach(source => {
        const mediaElement = source.parentElement;
        if (mediaElement) {
          // 保存当前状态
          const wasPlaying = !mediaElement.paused;
          const currentTime = mediaElement.currentTime;
          const currentVolume = mediaElement.volume;
          
          try {
            // 停止媒体
            mediaElement.pause();
            mediaElement.removeAttribute('src');
            mediaElement.load();
            cleanupStatus.mediaReset++;
            
            // 重写play方法阻止播放
            mediaElement.play = function() { 
              return Promise.reject(new DOMException('NotAllowedError')); 
            };
          } catch (e) {
            console.error('重置媒体元素失败', e);
          }
        }
      });
      
      // 阻止新的MediaSource创建
      if (window.URL && window.URL.createObjectURL) {
        const originalCreateObjectURL = window.URL.createObjectURL;
        window.URL.createObjectURL = function(obj) {
          if (obj instanceof MediaSource) {
            return '#blocked-media-source';
          }
          return originalCreateObjectURL.apply(this, arguments);
        };
      }
      
      cleanupStatus.mediaSourceBlocked = true;
    }
  } catch (e) {
    console.error('终止MediaSource操作失败', e);
    cleanupStatus.mediaSourceBlocked = false;
  }

  // 清理所有websocket连接
  try {
    const sockets = window._webSockets || [];
    sockets.forEach(socket => {
      try {
        socket.close();
        cleanupStatus.socketsClose++;
      } catch (e) {}
    });
    
    // 阻止新的WebSocket连接
    if (window.WebSocket) {
      const OrigWebSocket = window.WebSocket;
      window.WebSocket = function() {
        const socket = {
          close: function() {},
          send: function() { return false; },
          addEventListener: function() {},
          removeEventListener: function() {}
        };
        
        // 模拟error和close事件
        setTimeout(() => {
          if (this.onerror) this.onerror(new Event('error'));
          if (this.onclose) this.onclose(new CloseEvent('close'));
        }, 0);
        
        return socket;
      };
      window._OrigWebSocket = OrigWebSocket;
      cleanupStatus.websocketsBlocked = true;
    }
  } catch (e) {
    console.error('清理WebSocket连接失败', e);
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
            controller.abort();
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
        img.src = '';
        cleanupStatus.imagesAborted++;
        
        // 防止重新加载
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
  
  // 清理Service Worker
  try {
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      navigator.serviceWorker.getRegistrations().then(registrations => {
        registrations.forEach(registration => {
          registration.unregister();
          cleanupStatus.serviceWorkersUnregistered++;
        });
      });
    }
    cleanupStatus.serviceWorkersCleaned = true;
  } catch (e) {
    console.error('清理Service Worker失败', e);
    cleanupStatus.serviceWorkersCleaned = false;
  }

  // 清理全局变量
  try {
    delete window._timeInterceptorInitialized;
    delete window._originalDate;
    delete window._originalPerformanceNow;
    delete window._originalRAF;
    delete window._originalConsoleTime;
    delete window._originalConsoleTimeEnd;
    delete window._m3u8DetectorInitialized;
    delete window._cleanupTimeInterceptor;
    delete window._cleanupM3U8Detector;
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
    }));
  }
  
  console.info('页面资源清理完成', cleanupStatus);
})();
