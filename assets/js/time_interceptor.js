// 时间修改器：拦截和调整页面时间相关操作，支持动态时间偏移
(function() {
  // 防止重复初始化
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
  
  // 时间来源类型枚举
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

  // 获取调整后的当前时间
  function getAdjustedTime() {
    sendTimeRequest(TimeSourceType.DATE);
    return new originalDate(originalDate.now() + timeOffset); // 使用原生 Date.now()
  }

  // 代理 Date 构造函数，支持无参和有参调用
  window.Date = function(...args) {
    return args.length === 0 ? getAdjustedTime() : new originalDate(...args);
  };

  // 保持 Date 原型链和静态方法
  window.Date.prototype = originalDate.prototype;
  window.Date.now = () => {
    sendTimeRequest(TimeSourceType.DATE_NOW);
    return originalDate.now() + timeOffset; // 返回调整后的时间戳
  };
  window.Date.parse = originalDate.parse; // 保留原始 parse 方法
  window.Date.UTC = originalDate.UTC; // 保留原始 UTC 方法

  // 拦截 performance.now 方法
  const originalPerformanceNow = window.performance.now.bind(window.performance);
  window.performance.now = () => {
    sendTimeRequest(TimeSourceType.PERFORMANCE);
    return originalPerformanceNow() + timeOffset; // 返回调整后的性能时间
  };
  
  // 拦截 requestAnimationFrame 方法
  const originalRAF = window.requestAnimationFrame;
  window.requestAnimationFrame = callback => {
    if (!callback) return originalRAF(callback); // 处理无效回调
    return originalRAF(timestamp => {
      const adjustedTimestamp = timestamp + timeOffset; // 调整时间戳
      sendTimeRequest(TimeSourceType.RAF, { original: timestamp, adjusted: adjustedTimestamp });
      callback(adjustedTimestamp); // 调用回调函数
    });
  };
  
  // 拦截 console.time 方法
  const originalConsoleTime = console.time;
  const originalConsoleTimeEnd = console.timeEnd;
  
  if (originalConsoleTime) {
    console.time = function(label) {
      sendTimeRequest(TimeSourceType.CONSOLE_TIME, { label });
      return originalConsoleTime.apply(this, arguments); // 执行原始 console.time
    };
  }
  
  if (originalConsoleTimeEnd) {
    console.timeEnd = function(label) {
      sendTimeRequest(TimeSourceType.CONSOLE_TIME_END, { label });
      return originalConsoleTimeEnd.apply(this, arguments); // 执行原始 console.timeEnd
    };
  }

  // 使用 WeakMap 存储事件监听器映射 - 优化版：简化结构
  const listenerMap = new WeakMap();
  
  // 创建或获取监听器的包装函数
  function getWrappedListener(element, type, listener) {
    let elementMap = listenerMap.get(element);
    if (!elementMap) {
      elementMap = new Map();
      listenerMap.set(element, elementMap);
    }
    
    const key = `${type}:${listener}`; // 组合键，避免嵌套Map
    let wrapped = elementMap.get(key);
    if (!wrapped) {
      wrapped = function(event) {
        const wrappedEvent = new Event(type);
        Object.assign(wrappedEvent, event);
        wrappedEvent._originalTime = event.target.currentTime;
        listener.call(this, wrappedEvent);
      };
      elementMap.set(key, wrapped);
    }
    return wrapped;
  }
  
  // 获取媒体元素 currentTime 和 duration 属性描述符
  const currentTimeDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'currentTime');
  const durationDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'duration');
  
  // 定义时间相关事件列表
  const timeEvents = ['timeupdate', 'durationchange', 'seeking', 'seeked'];
  
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
        return originalTime + (timeOffset / 1000); // 转换为秒并调整
      },
      set: function(value) {
        const originalValue = value - (timeOffset / 1000); // 反向调整时间
        return originalSetter.call(this, originalValue);
      }
    });
    
    // 代理 duration 属性
    if (durationDescriptor && durationDescriptor.get) {
      const originalDurationGetter = durationDescriptor.get;
      Object.defineProperty(element, 'duration', {
        get: function() {
          return originalDurationGetter.call(this); // 返回原始 duration
        }
      });
    }
    
    // 重写 addEventListener 方法 - 优化版
    element.addEventListener = function(type, listener, options) {
      if (timeEvents.includes(type) && listener) {
        const wrappedListener = getWrappedListener(element, type, listener);
        return originalAddEventListener.call(this, type, wrappedListener, options);
      }
      return originalAddEventListener.call(this, type, listener, options);
    };
    
    // 重写 removeEventListener 方法 - 优化版
    element.removeEventListener = function(type, listener, options) {
      if (timeEvents.includes(type) && listener) {
        const elementMap = listenerMap.get(element);
        if (elementMap) {
          const key = `${type}:${listener}`;
          const wrappedListener = elementMap.get(key);
          if (wrappedListener) {
            originalRemoveEventListener.call(this, type, wrappedListener, options);
            elementMap.delete(key);
            if (elementMap.size === 0) {
              listenerMap.delete(element);
            }
            return;
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
        if (node instanceof HTMLMediaElement) setupMediaElement(node); // 初始化新媒体元素
      });
    });
  });

  // 启动 DOM 观察，捕获所有媒体元素
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true
  });

  // 初始化页面现有媒体元素 - 优化版：一次查询
  const mediaElements = document.querySelectorAll('video, audio');
  for (let i = 0; i < mediaElements.length; i++) {
    setupMediaElement(mediaElements[i]);
  }

  // 提供清理函数以恢复原始状态
  window._cleanupTimeInterceptor = () => {
    window.Date = originalDate; // 恢复原始 Date
    window.performance.now = originalPerformanceNow; // 恢复原始 performance.now
    window.requestAnimationFrame = originalRAF; // 恢复原始 requestAnimationFrame
    
    if (originalConsoleTime) console.time = originalConsoleTime; // 恢复原始 console.time
    if (originalConsoleTimeEnd) console.timeEnd = originalConsoleTimeEnd; // 恢复原始 console.timeEnd
    
    // 清理媒体元素代理 - 优化版
    const allMediaElements = document.querySelectorAll('video, audio');
    for (let i = 0; i < allMediaElements.length; i++) {
      const element = allMediaElements[i];
      if (element._timeProxied) {
        if (element._originalAddEventListener) {
          element.addEventListener = element._originalAddEventListener; // 恢复 addEventListener
          delete element._originalAddEventListener;
        }
        if (element._originalRemoveEventListener) {
          element.removeEventListener = element._originalRemoveEventListener; // 恢复 removeEventListener
          delete element._originalRemoveEventListener;
        }
        
        delete element._timeProxied; // 移除代理标志
      }
    }
    
    observer.disconnect(); // 停止 DOM 观察
    
    delete window._timeInterceptorInitialized; // 清理初始化标志
    
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
