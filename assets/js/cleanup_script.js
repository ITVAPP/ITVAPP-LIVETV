// 资源清理脚本
(function() {
  // 定义清理状态对象，记录各项清理操作的结果
  const cleanupStatus = {
    xhrAborted: 0, // 已中止的XHR请求计数
    timeoutsCleared: 0, // 已清理的定时器计数
    intervalsCleared: 0, // 已清理的间隔器计数
    listenersRemoved: 0, // 已移除的事件监听器计数
    socketsClose: 0, // 已关闭的WebSocket连接计数
    fetchAborted: 0, // 已中止的Fetch请求计数
    mediaReset: 0, // 已重置的媒体元素计数
    imagesAborted: 0, // 已中止的图片加载计数
    serviceWorkersUnregistered: 0 // 已注销的Service Worker计数
  };

  // 更新清理状态的辅助函数
  function updateStatus(key, value) {
    cleanupStatus[key] = value; // 更新指定状态字段
  }

  // 停止页面加载
  try {
    window.stop(); // 终止页面所有加载活动
    updateStatus('pageStopped', true);
  } catch (e) {
    console.error('停止页面加载失败', e);
    updateStatus('pageStopped', false);
  }

  // 清理时间拦截器
  try {
    if (window._cleanupTimeInterceptor) {
      window._cleanupTimeInterceptor(); // 执行时间拦截器清理
      updateStatus('timeInterceptorCleaned', true);
    }
  } catch (e) {
    console.error('清理时间拦截器失败', e);
    updateStatus('timeInterceptorCleaned', false);
  }

  // 清理所有活跃的XHR请求
  try {
    const activeXhrs = window._activeXhrs || [];
    activeXhrs.forEach(xhr => {
      try {
        xhr.abort(); // 中止单个XHR请求
        cleanupStatus.xhrAborted++;
      } catch (e) {}
    });
    
    // 拦截新的XHR请求
    if (window.XMLHttpRequest) {
      const origXHR = window.XMLHttpRequest;
      window.XMLHttpRequest = function() {
        const xhr = new origXHR();
        xhr.abort = function() { return true; }; // 模拟中止操作
        xhr.open = function() { return null; }; // 阻止请求打开
        xhr.send = function() { return null; }; // 阻止请求发送
        return xhr;
      };
      updateStatus('xhrBlocked', true);
    }
  } catch (e) {
    console.error('中止XHR请求失败', e);
    updateStatus('xhrBlocked', false);
  }

  // 清理所有Fetch请求
  try {
    if (window._abortController) {
      window._abortController.abort(); // 中止现有Fetch请求
      cleanupStatus.fetchAborted++;
    }
    
    // 阻止新的Fetch请求
    if (window.fetch) {
      window.fetch = function() { 
        return Promise.resolve(new Response('', {
          status: 499,
          statusText: 'Client Closed Request' // 模拟请求关闭
        }));
      };
      updateStatus('fetchBlocked', true);
    }
  } catch (e) {
    console.error('中止Fetch请求失败', e);
    updateStatus('fetchBlocked', false);
  }
  
  // 清理Beacon请求
  try {
    if (navigator.sendBeacon) {
      navigator.sendBeacon = function() { return false; }; // 阻止Beacon请求
      updateStatus('beaconBlocked', true);
    }
  } catch (e) {
    console.error('清理Beacon请求失败', e);
    updateStatus('beaconBlocked', false);
  }

  // 清理所有定时器
  try {
    window.setTimeout = function() { return 0; }; // 阻止新定时器创建
    window.setInterval = function() { return 0; }; // 阻止新间隔器创建
    window.requestAnimationFrame = function() { return 0; }; // 阻止动画帧请求
    cleanupStatus.timeoutsCleared = 1;
    cleanupStatus.intervalsCleared = 1;
    updateStatus('timerFunctionsBlocked', true);
  } catch (e) {
    console.error('清理定时器失败', e);
    updateStatus('timerFunctionsBlocked', false);
  }

  // 清理所有事件监听器
  try {
    const commonEvents = [
      'scroll', 'resize', 'load', 'unload', 'beforeunload',
      'popstate', 'hashchange', 'visibilitychange', 'online', 'offline',
      'message', 'storage', 'focus', 'blur', 'error'
    ];
    
    // 通用事件监听器清理函数
    function removeListeners(target, events) {
      events.forEach(event => {
        try {
          target.removeEventListener(event, target[`_${event}Handler`]); // 移除指定事件监听器
          cleanupStatus.listenersRemoved++;
        } catch (e) {}
      });
    }
    
    removeListeners(window, commonEvents); // 清理window事件监听器
    removeListeners(document, commonEvents); // 清理document事件监听器
    
    const originalAddEventListener = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function() { return null; }; // 阻止新监听器添加
    
    window._originalAddEventListener = originalAddEventListener; // 保存原始函数
    updateStatus('eventListenersBlocked', true);
  } catch (e) {
    console.error('清理事件监听器失败', e);
    updateStatus('eventListenersBlocked', false);
  }

  // 清理M3U8检测器
  try {
    if (window._cleanupM3U8Detector) {
      window._cleanupM3U8Detector(); // 执行M3U8检测器清理
      updateStatus('m3u8DetectorCleaned', true);
    }
  } catch (e) {
    console.error('清理M3U8检测器失败', e);
    updateStatus('m3u8DetectorCleaned', false);
  }

  // 终止所有MediaSource操作
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
            mediaElement.pause(); // 暂停媒体播放
            mediaElement.removeAttribute('src'); // 移除媒体源
            mediaElement.load(); // 重置媒体元素
            cleanupStatus.mediaReset++;
            
            mediaElement.play = function() { 
              return Promise.reject(new DOMException('NotAllowedError')); // 阻止播放
            };
          } catch (e) {
            console.error('重置媒体元素失败', e);
          }
        }
      });
      
      if (window.URL && window.URL.createObjectURL) {
        const originalCreateObjectURL = window.URL.createObjectURL;
        window.URL.createObjectURL = function(obj) {
          if (obj instanceof MediaSource) {
            return '#blocked-media-source'; // 阻止MediaSource创建
          }
          return originalCreateObjectURL.apply(this, arguments);
        };
      }
      
      updateStatus('mediaSourceBlocked', true);
    }
  } catch (e) {
    console.error('终止MediaSource操作失败', e);
    updateStatus('mediaSourceBlocked', false);
  }

  // 清理所有WebSocket连接
  try {
    const sockets = window._webSockets || [];
    sockets.forEach(socket => {
      try {
        socket.close(); // 关闭WebSocket连接
        cleanupStatus.socketsClose++;
      } catch (e) {}
    });
    
    if (window.WebSocket) {
      const OrigWebSocket = window.WebSocket;
      window.WebSocket = function() {
        const socket = {
          close: function() {}, // 模拟关闭
          send: function() { return false; }, // 阻止数据发送
          addEventListener: function() {}, // 阻止事件监听
          removeEventListener: function() {} // 阻止事件移除
        };
        
        setTimeout(() => {
          if (this.onerror) this.onerror(new Event('error')); // 触发错误事件
          if (this.onclose) this.onclose(new CloseEvent('close')); // 触发关闭事件
        }, 0);
        
        return socket;
      };
      window._OrigWebSocket = OrigWebSocket; // 保存原始WebSocket
      updateStatus('websocketsBlocked', true);
    }
  } catch (e) {
    console.error('清理WebSocket连接失败', e);
    updateStatus('websocketsBlocked', false);
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
            controller.abort(); // 中止未完成请求
            cleanupStatus.networkAborted++;
          } catch(e) {}
        }
      });
    }
  } catch (e) {
    console.error('停止网络请求失败', e);
    updateStatus('networkAborted', false);
  }

  // 清理所有未完成的图片加载
  try {
    document.querySelectorAll('img').forEach(img => {
      if (!img.complete) {
        const originalSrc = img.src;
        img.src = ''; // 停止图片加载
        cleanupStatus.imagesAborted++;
        
        Object.defineProperty(img, 'src', {
          set: function() { return ''; }, // 阻止重新设置src
          get: function() { return ''; } // 返回空src
        });
      }
    });
    updateStatus('imageLoadingBlocked', true);
  } catch (e) {
    console.error('清理图片加载失败', e);
    updateStatus('imageLoadingBlocked', false);
  }
  
  // 清理Service Worker
  try {
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      navigator.serviceWorker.getRegistrations().then(registrations => {
        registrations.forEach(registration => {
          registration.unregister(); // 注销Service Worker
          cleanupStatus.serviceWorkersUnregistered++;
        });
      });
      updateStatus('serviceWorkersCleaned', true);
    }
  } catch (e) {
    console.error('清理Service Worker失败', e);
    updateStatus('serviceWorkersCleaned', false);
  }

  // 清理全局变量
  try {
    delete window._timeInterceptorInitialized; // 移除时间拦截器初始化标志
    delete window._originalDate; // 移除原始Date对象
    delete window._originalPerformanceNow; // 移除原始performance.now
    delete window._originalRAF; // 移除原始requestAnimationFrame
    delete window._originalConsoleTime; // 移除原始console.time
    delete window._originalConsoleTimeEnd; // 移除原始console.timeEnd
    delete window._m3u8DetectorInitialized; // 移除M3U8检测器初始化标志
    delete window._cleanupTimeInterceptor; // 移除时间拦截器清理函数
    delete window._cleanupM3U8Detector; // 移除M3U8检测器清理函数
    updateStatus('globalVariablesCleaned', true);
  } catch (e) {
    console.error('清理全局变量失败', e);
    updateStatus('globalVariablesCleaned', false);
  }
  
  // 报告清理完成状态
  if (window.CleanupCompleted) {
    window.CleanupCompleted.postMessage(JSON.stringify({
      type: 'cleanup',
      status: 'completed',
      details: cleanupStatus
    }));
  }
  
  console.info('页面资源清理完成', cleanupStatus);
})();
