// 时间修改器：拦截和调整页面时间相关操作，支持动态时间偏移
(function() {
  // 防止重复初始化时间拦截器
  if (window._timeInterceptorInitialized) return;
  window._timeInterceptorInitialized = true;

  // 保存原始 Date 对象以供恢复
  const originalDate = window.Date;
  const timeOffset = 0; // 时间偏移量，由 Dart 代码动态替换
  
  // 管理时间请求状态的映射表
  const timeRequestStatus = {
    DATE: false,
    DATE_NOW: false,
    PERFORMANCE: false,
    MEDIA: false,
    RAF: false,
    CONSOLE_TIME: false,
    CONSOLE_TIME_END: false
  };
  
  // 定义时间来源类型枚举
  const TimeSourceType = {
    DATE: 'Date',
    DATE_NOW: 'Date.now',
    PERFORMANCE: 'performance.now',
    MEDIA: 'media.currentTime',
    RAF: 'requestAnimationFrame',
    CONSOLE_TIME: 'console.time',
    CONSOLE_TIME_END: 'console.timeEnd'
  };
  
  // 发送时间请求事件，仅首次触发
  function sendTimeRequest(type, detail = {}) {
    if (!timeRequestStatus[type] && window.TimeCheck) {
      timeRequestStatus[type] = true;
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'timeRequest',
        method: type,
        detail: detail
      }));
    }
  }

  // 获取偏移调整后的当前时间
  function getAdjustedTime() {
    sendTimeRequest(TimeSourceType.DATE);
    return new originalDate(originalDate.now() + timeOffset);
  }

  // 代理 Date 构造函数，支持无参和有参调用
  window.Date = function(...args) {
    return args.length === 0 ? getAdjustedTime() : new originalDate(...args);
  };

  // 保持 Date 原型链和静态方法
  window.Date.prototype = originalDate.prototype;
  window.Date.now = () => {
    sendTimeRequest(TimeSourceType.DATE_NOW);
    return originalDate.now() + timeOffset;
  };
  window.Date.parse = originalDate.parse;
  window.Date.UTC = originalDate.UTC;

  // 拦截 performance.now 方法
  const originalPerformanceNow = window.performance.now.bind(window.performance);
  window.performance.now = () => {
    sendTimeRequest(TimeSourceType.PERFORMANCE);
    return originalPerformanceNow() + timeOffset;
  };
  
  // 拦截 requestAnimationFrame 方法
  const originalRAF = window.requestAnimationFrame;
  window.requestAnimationFrame = callback => {
    if (!callback) return originalRAF(callback);
    return originalRAF(timestamp => {
      const adjustedTimestamp = timestamp + timeOffset;
      sendTimeRequest(TimeSourceType.RAF, { original: timestamp, adjusted: adjustedTimestamp });
      callback(adjustedTimestamp);
    });
  };
  
  // 拦截 console.time 方法
  const originalConsoleTime = console.time;
  const originalConsoleTimeEnd = console.timeEnd;
  
  if (originalConsoleTime) {
    console.time = function(label) {
      sendTimeRequest(TimeSourceType.CONSOLE_TIME, { label });
      return originalConsoleTime.apply(this, arguments);
    };
  }
  
  if (originalConsoleTimeEnd) {
    console.timeEnd = function(label) {
      sendTimeRequest(TimeSourceType.CONSOLE_TIME_END, { label });
      return originalConsoleTimeEnd.apply(this, arguments);
    };
  }

  // 使用 WeakMap 存储事件监听器映射
  const listenerMap = new WeakMap();
  
  // 定义时间相关事件集合 - 使用Set提升查找性能
  const timeEventsSet = new Set(['timeupdate', 'durationchange', 'seeking', 'seeked']);
  
  // 创建或获取事件监听器包装函数
  function getWrappedListener(element, type, listener) {
    let elementMap = listenerMap.get(element);
    if (!elementMap) {
      elementMap = new Map();
      listenerMap.set(element, elementMap);
    }
    
    // 使用Symbol作为key，避免字符串拼接
    if (!listener._wrapperKey) {
      listener._wrapperKey = Symbol('wrapper');
    }
    const key = listener._wrapperKey;
    
    let typeMap = elementMap.get(key);
    if (!typeMap) {
      typeMap = new Map();
      elementMap.set(key, typeMap);
    }
    
    let wrapped = typeMap.get(type);
    if (!wrapped) {
      wrapped = function(event) {
        const wrappedEvent = new Event(type);
        Object.assign(wrappedEvent, event);
        wrappedEvent._originalTime = event.target.currentTime;
        listener.call(this, wrappedEvent);
      };
      typeMap.set(type, wrapped);
    }
    return wrapped;
  }
  
  // 获取媒体元素 currentTime 属性描述符
  const currentTimeDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'currentTime');
  
  // 设置媒体元素时间代理
  function setupMediaElement(element) {
    if (element._timeProxied) return;
    element._timeProxied = true;
    
    const originalGetter = currentTimeDescriptor.get;
    const originalSetter = currentTimeDescriptor.set;

    // 保存原始事件监听方法
    const originalAddEventListener = element.addEventListener;
    const originalRemoveEventListener = element.removeEventListener;

    // 代理 currentTime 属性
    Object.defineProperty(element, 'currentTime', {
      get: function() {
        sendTimeRequest(TimeSourceType.MEDIA, { element: element.tagName, src: element.src });
        const originalTime = originalGetter.call(this);
        return originalTime + (timeOffset / 1000);
      },
      set: function(value) {
        const originalValue = value - (timeOffset / 1000);
        return originalSetter.call(this, originalValue);
      }
    });
    
    element.addEventListener = function(type, listener, options) {
      if (timeEventsSet.has(type) && listener) {
        const wrappedListener = getWrappedListener(element, type, listener);
        return originalAddEventListener.call(this, type, wrappedListener, options);
      }
      return originalAddEventListener.call(this, type, listener, options);
    };

    element.removeEventListener = function(type, listener, options) {
      if (timeEventsSet.has(type) && listener) {
        const elementMap = listenerMap.get(element);
        if (elementMap && listener._wrapperKey) {
          const typeMap = elementMap.get(listener._wrapperKey);
          if (typeMap) {
            const wrappedListener = typeMap.get(type);
            if (wrappedListener) {
              originalRemoveEventListener.call(this, type, wrappedListener, options);
              typeMap.delete(type);
              if (typeMap.size === 0) {
                elementMap.delete(listener._wrapperKey);
                if (elementMap.size === 0) {
                  listenerMap.delete(element);
                }
              }
              return;
            }
          }
        }
      }
      return originalRemoveEventListener.call(this, type, listener, options);
    };
    
    // 保存原始方法到元素
    element._originalAddEventListener = originalAddEventListener;
    element._originalRemoveEventListener = originalRemoveEventListener;
  }

  // 监听新添加的媒体元素
  const observer = new MutationObserver(mutations => {
    mutations.forEach(mutation => {
      mutation.addedNodes.forEach(node => {
        if (node instanceof HTMLMediaElement) setupMediaElement(node);
      });
    });
  });

  // 启动 DOM 观察，捕获所有媒体元素
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true
  });

  // 初始化页面现有媒体元素
  const mediaElements = document.querySelectorAll('video, audio');
  for (let i = 0; i < mediaElements.length; i++) {
    setupMediaElement(mediaElements[i]);
  }

  // 提供清理函数以恢复原始状态
  window._cleanupTimeInterceptor = () => {
    window.Date = originalDate;
    window.performance.now = originalPerformanceNow;
    window.requestAnimationFrame = originalRAF;
    
    if (originalConsoleTime) console.time = originalConsoleTime;
    if (originalConsoleTimeEnd) console.timeEnd = originalConsoleTimeEnd;
    
    const allMediaElements = document.querySelectorAll('video, audio');
    for (let i = 0; i < allMediaElements.length; i++) {
      const element = allMediaElements[i];
      if (element._timeProxied) {
        if (element._originalAddEventListener) {
          element.addEventListener = element._originalAddEventListener;
          delete element._originalAddEventListener;
        }
        if (element._originalRemoveEventListener) {
          element.removeEventListener = element._originalRemoveEventListener;
          delete element._originalRemoveEventListener;
        }
        
        delete element._timeProxied;
      }
    }
    
    observer.disconnect();
    delete window._timeInterceptorInitialized;
    
    // 通知清理完成
    if (window.TimeCheck) {
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'cleanup',
        status: 'success'
      }));
    }
  };
  
  // 发送初始化完成通知
  if (window.TimeCheck) {
    window.TimeCheck.postMessage(JSON.stringify({
      type: 'init',
      offset: timeOffset,
      status: 'success'
    }));
  }
})();
