(function() {
  // 初始化检查，避免重复执行
  if (window._timeInterceptorInitialized) return;
  window._timeInterceptorInitialized = true;

  // 保存原始对象
  const originalDate = window.Date; // 保存原始 Date 对象
  const originalPerformanceNow = window.performance.now.bind(window.performance); // 保存原始 performance.now 方法
  const originalRAF = window.requestAnimationFrame; // 保存原始 requestAnimationFrame 方法
  const originalConsoleTime = console.time; // 保存原始 console.time 方法
  const originalConsoleTimeEnd = console.timeEnd; // 保存原始 console.timeEnd 方法

  // 时间偏移量，单位为毫秒
  const timeOffset = 0; // 将由 Dart 代码动态替换
  // 时间请求状态管理
  const requestStates = {
    date: false, // Date 请求状态
    dateNow: false, // Date.now 请求状态
    performance: false, // performance.now 请求状态
    media: false, // 媒体元素请求状态
    raf: false, // requestAnimationFrame 请求状态
    consoleTime: false // console.time 请求状态
  };

  // 时间来源类型枚举
  const TimeSourceType = {
    DATE: 'Date', // Date 类型
    DATE_NOW: 'Date.now', // Date.now 类型
    PERFORMANCE: 'performance.now', // performance.now 类型
    MEDIA: 'media.currentTime', // 媒体 currentTime 类型
    RAF: 'requestAnimationFrame', // requestAnimationFrame 类型
    CONSOLE_TIME: 'console.time' // console.time 类型
  };

  // 发送时间请求事件
  function sendTimeRequest(type, detail = {}) {
    if (!requestStates[type] && window.TimeCheck) {
      requestStates[type] = true; // 标记请求已发送
      // 过滤不可序列化的属性
      const safeDetail = {};
      for (const [key, value] of Object.entries(detail)) {
        if (typeof value !== 'object' || value instanceof Event) {
          safeDetail[key] = value; // 仅保留可序列化值
        }
      }
      try {
        window.TimeCheck.postMessage(JSON.stringify({
          type: 'timeRequest', // 请求类型
          method: type, // 请求方法
          detail: safeDetail // 安全详情
        }));
      } catch (e) {
        console.warn('时间请求发送失败:', e); // 捕获发送错误
      }
    }
  }

  // 获取调整后的时间（缓存短期结果）
  let lastAdjustedTime = null; // 缓存最近调整时间
  let lastAdjustedTimestamp = 0; // 缓存最近时间戳
  function getAdjustedTime() {
    const now = Date.now(); // 获取当前时间
    if (lastAdjustedTime && now - lastAdjustedTimestamp < 10) {
      return new originalDate(lastAdjustedTime.getTime()); // 返回缓存时间
    }
    sendTimeRequest(TimeSourceType.DATE); // 发送 Date 请求
    lastAdjustedTime = new originalDate(new originalDate().getTime() + Math.min(Math.max(timeOffset, -86400000), 86400000)); // 计算调整时间
    lastAdjustedTimestamp = now; // 更新时间戳
    return new originalDate(lastAdjustedTime.getTime()); // 返回新时间
  }

  // 代理 Date 构造函数
  window.Date = function(...args) {
    return args.length === 0 ? getAdjustedTime() : new originalDate(...args); // 无参返回调整时间，有参调用原始构造函数
  };
  // 安全继承原始原型
  window.Date.prototype = Object.create(originalDate.prototype); // 继承原始 Date 原型
  window.Date.now = () => {
    sendTimeRequest(TimeSourceType.DATE_NOW); // 发送 Date.now 请求
    return getAdjustedTime().getTime(); // 返回调整后的时间戳
  };
  window.Date.parse = originalDate.parse; // 保留原始 parse 方法
  window.Date.UTC = originalDate.UTC; // 保留原始 UTC 方法

  // 拦截 performance.now
  window.performance.now = () => {
    sendTimeRequest(TimeSourceType.PERFORMANCE); // 发送 performance.now 请求
    return originalPerformanceNow() + Math.min(Math.max(timeOffset, -86400000), 86400000); // 返回调整后的时间
  };

  // 拦截 requestAnimationFrame
  window.requestAnimationFrame = callback => {
    return originalRAF(timestamp => {
      const adjustedTimestamp = timestamp + Math.min(Math.max(timeOffset, -86400000), 86400000); // 调整时间戳
      sendTimeRequest(TimeSourceType.RAF, { original: timestamp, adjusted: adjustedTimestamp }); // 发送 RAF 请求
      callback(adjustedTimestamp); // 调用回调函数
    });
  };

  // 统一拦截 console.time 和 console.timeEnd
  function createConsoleInterceptor(method) {
    return function(label) {
      sendTimeRequest(TimeSourceType.CONSOLE_TIME, { label, method }); // 发送 console.time 请求
      return method.apply(this, arguments); // 调用原始方法
    };
  }
  if (originalConsoleTime) {
    console.time = createConsoleInterceptor(originalConsoleTime); // 代理 console.time
  }
  if (originalConsoleTimeEnd) {
    console.timeEnd = createConsoleInterceptor(originalConsoleTimeEnd); // 代理 console.timeEnd
  }

  // 通用属性代理函数
  function proxyProperty(element, property, transformGet, transformSet) {
    const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, property); // 获取属性描述符
    if (!descriptor || !descriptor.get) return; // 确保属性可代理
    const originalGetter = descriptor.get; // 保存原始 getter
    const originalSetter = descriptor.set; // 保存原始 setter
    Object.defineProperty(element, property, {
      get() {
        const value = originalGetter.call(this); // 获取原始值
        return transformGet ? transformGet(value) : value; // 返回转换值或原始值
      },
      set(value) {
        const transformedValue = transformSet ? transformSet(value) : value; // 转换设置值
        return originalSetter.call(this, transformedValue); // 调用原始 setter
      }
    });
  }

  // 处理媒体元素
  function setupMediaElement(element) {
    if (element._timeProxied) return; // 避免重复代理
    element._timeProxied = true; // 标记已代理

    // 代理 currentTime 属性
    proxyProperty(
      element,
      'currentTime',
      value => {
        sendTimeRequest(TimeSourceType.MEDIA, { element: element.tagName, src: element.src }); // 发送媒体请求
        return value + (timeOffset / 1000); // 调整当前时间
      },
      value => value - (timeOffset / 1000) // 反向调整设置时间
    );

    // 代理 duration 属性（保持原值）
    if (!element._durationProxied) {
      element._durationProxied = true; // 标记 duration 已代理
      proxyProperty(element, 'duration', null, null); // 代理 duration 属性
    }

    // 处理时间相关事件
    const timeEvents = ['timeupdate', 'durationchange', 'seeking', 'seeked']; // 时间相关事件
    const originalAddEventListener = element.addEventListener; // 保存原始 addEventListener
    const listeners = new Map(); // 存储事件监听器
    element.addEventListener = function(type, listener, options) {
      if (timeEvents.includes(type)) {
        const wrappedListener = function(event) {
          const wrappedEvent = new Event(type); // 创建新事件
          Object.assign(wrappedEvent, event); // 复制事件属性
          wrappedEvent._originalTime = event.target.currentTime; // 记录原始时间
          listener.call(this, wrappedEvent); // 调用原始监听器
        };
        listeners.set(listener, wrappedListener); // 存储包装监听器
        return originalAddEventListener.call(this, type, wrappedListener, options); // 调用原始方法
      }
      return originalAddEventListener.call(this, type, listener, options); // 调用原始方法
    };
    // 记录清理函数
    element._removeListeners = () => {
      listeners.forEach((wrapped, original) => {
        element.removeEventListener(timeEvents[0], wrapped); // 移除监听器
      });
      listeners.clear(); // 清空监听器
    };
  }

  // 监听新媒体元素
  const observer = new MutationObserver(mutations => {
    mutations.forEach(mutation => {
      mutation.addedNodes.forEach(node => {
        if (node instanceof HTMLMediaElement) setupMediaElement(node); // 处理新媒体元素
      });
    });
  });
  observer.observe(document.documentElement, { childList: true, subtree: true }); // 监听 DOM 变化

  // 初始化现有媒体元素
  document.querySelectorAll('video,audio').forEach(setupMediaElement); // 处理现有媒体元素

  // 资源清理函数
  window._cleanupTimeInterceptor = () => {
    // 恢复原始对象
    window.Date = originalDate; // 恢复原始 Date
    window.performance.now = originalPerformanceNow; // 恢复原始 performance.now
    window.requestAnimationFrame = originalRAF; // 恢复原始 requestAnimationFrame
    if (originalConsoleTime) console.time = originalConsoleTime; // 恢复原始 console.time
    if (originalConsoleTimeEnd) console.timeEnd = originalConsoleTimeEnd; // 恢复原始 console.timeEnd

    // 清理媒体元素代理
    document.querySelectorAll('video,audio').forEach(element => {
      if (element._timeProxied) {
        delete element._timeProxied; // 移除代理标记
        delete element._durationProxied; // 移除 duration 代理标记
        if (element._removeListeners) {
          element._removeListeners(); // 清理监听器
          delete element._removeListeners; // 移除清理函数
        }
      }
    });

    // 停止观察者
    observer.disconnect(); // 停止 DOM 观察

    // 清理全局标志和引用
    delete window._timeInterceptorInitialized; // 移除初始化标志
    delete window._originalDate; // 移除原始 Date 引用
    delete window._originalPerformanceNow; // 移除原始 performance.now 引用
    delete window._originalRAF; // 移除原始 requestAnimationFrame 引用
    delete window._originalConsoleTime; // 移除原始 console.time 引用
    delete window._originalConsoleTimeEnd; // 移除原始 console.timeEnd 引用

    // 通知清理完成
    if (window.TimeCheck) {
      try {
        window.TimeCheck.postMessage(JSON.stringify({
          type: 'cleanup', // 清理类型
          status: 'success' // 清理状态
        }));
      } catch (e) {
        console.warn('清理通知发送失败:', e); // 捕获通知错误
      }
    }
  };

  // 初始化通知
  if (window.TimeCheck) {
    try {
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'init', // 初始化类型
        offset: timeOffset, // 时间偏移量
        status: 'success' // 初始化状态
      }));
    } catch (e) {
      console.warn('初始化通知发送失败:', e); // 捕获通知错误
    }
  }
})();
