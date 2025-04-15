  // 时间修改器
(function() {
  if (window._timeInterceptorInitialized) return;
  window._timeInterceptorInitialized = true;

  const originalDate = window.Date;
  const timeOffset = 0; // Will be dynamically replaced by Dart code
  let timeRequested = false;
  
  // 时间来源类型枚举
  const TimeSourceType = {
    DATE: 'Date',
    DATE_NOW: 'Date.now',
    PERFORMANCE: 'performance.now',
    MEDIA: 'media.currentTime',
    RAF: 'requestAnimationFrame'
  };
  
  // 发送时间请求事件
  function sendTimeRequest(type, detail = {}) {
    if (!timeRequested) {
      timeRequested = true;
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'timeRequest',
        method: type,
        detail: detail
      }));
    }
  }

  // 核心时间调整函数
  function getAdjustedTime() {
    sendTimeRequest(TimeSourceType.DATE);
    return new originalDate(new originalDate().getTime() + timeOffset);
  }

  // 代理Date构造函数 (保留原逻辑)
  window.Date = function(...args) {
    return args.length === 0 ? getAdjustedTime() : new originalDate(...args);
  };

  // 保持原型链和方法 (保留原逻辑)
  window.Date.prototype = originalDate.prototype;
  window.Date.now = () => {
    sendTimeRequest(TimeSourceType.DATE_NOW);
    return getAdjustedTime().getTime();
  };
  window.Date.parse = originalDate.parse;
  window.Date.UTC = originalDate.UTC;

  // 拦截performance.now (保留原逻辑)
  const originalPerformanceNow = window.performance.now.bind(window.performance);
  let perfTimeRequested = false;
  window.performance.now = () => {
    if (!perfTimeRequested) {
      perfTimeRequested = true;
      sendTimeRequest(TimeSourceType.PERFORMANCE);
    }
    return originalPerformanceNow() + timeOffset;
  };
  
  // 添加requestAnimationFrame拦截 (新增)
  const originalRAF = window.requestAnimationFrame;
  window.requestAnimationFrame = callback => {
    return originalRAF(timestamp => {
      // 应用时间偏移
      const adjustedTimestamp = timestamp + timeOffset;
      sendTimeRequest(TimeSourceType.RAF, { original: timestamp, adjusted: adjustedTimestamp });
      callback(adjustedTimestamp);
    });
  };
  
  // 添加console.time拦截 (新增)
  const originalConsoleTime = console.time;
  const originalConsoleTimeEnd = console.timeEnd;
  
  if (originalConsoleTime) {
    console.time = function(label) {
      sendTimeRequest('console.time', { label });
      return originalConsoleTime.apply(this, arguments);
    };
  }
  
  if (originalConsoleTimeEnd) {
    console.timeEnd = function(label) {
      sendTimeRequest('console.timeEnd', { label });
      return originalConsoleTimeEnd.apply(this, arguments);
    };
  }

  // 媒体元素时间处理 (增强处理)
  let mediaTimeRequested = false;
  function setupMediaElement(element) {
    if (element._timeProxied) return;
    element._timeProxied = true;
    
    // 保存原始getter和setter
    const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'currentTime');
    const originalGetter = descriptor.get;
    const originalSetter = descriptor.set;

    Object.defineProperty(element, 'currentTime', {
      get: function() {
        if (!mediaTimeRequested) {
          mediaTimeRequested = true;
          sendTimeRequest(TimeSourceType.MEDIA, { element: element.tagName, src: element.src });
        }
        const originalTime = originalGetter.call(this);
        const adjustedTime = originalTime + (timeOffset / 1000);
        return adjustedTime;
      },
      set: function(value) {
        // 反向调整：减去偏移量
        const originalValue = value - (timeOffset / 1000);
        return originalSetter.call(this, originalValue);
      }
    });
    
    // 同时处理duration属性
    if (!element._durationProxied) {
      element._durationProxied = true;
      const durationDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'duration');
      if (durationDescriptor && durationDescriptor.get) {
        const originalDurationGetter = durationDescriptor.get;
        Object.defineProperty(element, 'duration', {
          get: function() {
            return originalDurationGetter.call(this);
          }
        });
      }
    }
    
    // 处理时间事件
    const timeEvents = ['timeupdate', 'durationchange', 'seeking', 'seeked'];
    timeEvents.forEach(eventType => {
      const originalAddEventListener = element.addEventListener;
      element.addEventListener = function(type, listener, options) {
        if (type === eventType) {
          const wrappedListener = function(event) {
            // 包装事件对象，注入调整后的时间
            const wrappedEvent = new Event(type);
            Object.assign(wrappedEvent, event);
            wrappedEvent._originalTime = event.target.currentTime;
            listener.call(this, wrappedEvent);
          };
          return originalAddEventListener.call(this, type, wrappedListener, options);
        }
        return originalAddEventListener.call(this, type, listener, options);
      };
    });
  }

  // 监听新媒体元素 (保留原逻辑)
  const observer = new MutationObserver(mutations => {
    mutations.forEach(mutation => {
      mutation.addedNodes.forEach(node => {
        if (node instanceof HTMLMediaElement) setupMediaElement(node);
      });
    });
  });

  observer.observe(document.documentElement, {
    childList: true,
    subtree: true
  });

  // 初始化现有媒体元素 (保留原逻辑)
  document.querySelectorAll('video,audio').forEach(setupMediaElement);

  // 资源清理 (增强版)
  window._cleanupTimeInterceptor = () => {
    // 恢复原始对象和方法
    window.Date = originalDate;
    window.performance.now = originalPerformanceNow;
    window.requestAnimationFrame = originalRAF;
    
    if (originalConsoleTime) console.time = originalConsoleTime;
    if (originalConsoleTimeEnd) console.timeEnd = originalConsoleTimeEnd;
    
    // 移除观察者
    observer.disconnect();
    
    // 清理标志
    delete window._timeInterceptorInitialized;
    delete window._originalDate;
    delete window._originalPerformanceNow;
    delete window._originalRAF;
    delete window._originalConsoleTime;
    delete window._originalConsoleTimeEnd;
    
    // 通知清理完成
    if (window.TimeCheck) {
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'cleanup',
        status: 'success'
      }));
    }
  };
  
  // 初始化通知
  if (window.TimeCheck) {
    window.TimeCheck.postMessage(JSON.stringify({
      type: 'init',
      offset: timeOffset,
      status: 'success'
    }));
  }
})();
