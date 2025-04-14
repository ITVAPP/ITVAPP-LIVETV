// 时间拦截器
(function() {
  // 避免重复初始化，确保脚本只执行一次
  if (window._itvapp_time_interceptor_initialized) return;
  window._itvapp_time_interceptor_initialized = true;
  
  // 保存原始对象和方法
  const _original = {
    Date: window.Date,
    DateNow: window.Date.now,
    DateParse: window.Date.parse,
    DateUTC: window.Date.UTC,
    PerformanceNow: window.performance && window.performance.now ? 
      window.performance.now.bind(window.performance) : null
  };
  
  // 使用安全方式获取时间偏移
  const timeOffset = TIME_OFFSET || 0;
  
  if (timeOffset === 0) {
    // 无偏移时，不修改任何对象，直接返回
    console.info('时间偏移为0，无需拦截');
    return;
  }
  
  // 状态标记对象，使用独立命名空间
  const _itvappRequestFlags = {
    Date: false,
    PerformanceNow: false,
    MediaCurrentTime: false
  };
  
  // 发送时间请求的通用函数
  function requestTime(method) {
    try {
      if (!_itvappRequestFlags[method] && window.TimeCheck) {
        _itvappRequestFlags[method] = true;
        window.TimeCheck.postMessage(JSON.stringify({
          type: 'timeRequest',
          method: method
        }));
      }
    } catch (e) {
      // 忽略错误，确保不影响页面
    }
  }
  
  // 创建调整后的Date构造函数
  function ITVAppDate(...args) {
    if (args.length === 0) {
      // 零参数调用使用调整后的时间
      requestTime('Date');
      const now = new _original.Date().getTime();
      return new _original.Date(now + timeOffset);
    }
    // 有参数时直接使用原始Date
    return new _original.Date(...args);
  }
  
  // 复制原型方法和属性
  ITVAppDate.prototype = _original.Date.prototype;
  
  // 设置静态方法
  ITVAppDate.now = function() {
    requestTime('Date');
    const now = _original.DateNow.call(_original.Date);
    return now + timeOffset;
  };
  
  // 保留其他原始Date静态方法
  ITVAppDate.parse = _original.DateParse;
  ITVAppDate.UTC = _original.DateUTC;
  ITVAppDate.toString = function() { return _original.Date.toString(); };
  
  // 创建调整后的performance.now函数
  function ITVAppPerformanceNow() {
    if (!_original.PerformanceNow) return 0;
    requestTime('PerformanceNow');
    return _original.PerformanceNow() + timeOffset;
  }
  
  // 提供获取调整时间的函数而不直接覆盖全局对象
  window._itvapp_getAdjustedDate = function() {
    return ITVAppDate;
  };
  
  window._itvapp_getAdjustedTime = function() {
    requestTime('Date');
    return _original.DateNow.call(_original.Date) + timeOffset;
  };
  
  window._itvapp_getAdjustedPerformanceNow = ITVAppPerformanceNow;
  
  // 处理媒体元素时间的通用函数
  function setupMediaElement(element) {
    if (!element || element._itvapp_timeProxied) return;
    element._itvapp_timeProxied = true;
    
    try {
      // 获取原始描述符
      const elementProto = Object.getPrototypeOf(element);
      const originalDescriptor = Object.getOwnPropertyDescriptor(elementProto, 'currentTime');
      
      if (originalDescriptor && originalDescriptor.configurable) {
        // 保存原始getter/setter引用
        const originalGetter = originalDescriptor.get;
        const originalSetter = originalDescriptor.set;
        
        // 创建媒体时间代理属性
        Object.defineProperty(element, 'currentTime', {
          get: function() {
            requestTime('MediaCurrentTime');
            // 调用原始getter并添加偏移
            const originalTime = originalGetter ? originalGetter.call(this) : 0;
            return originalTime + (timeOffset / 1000); // 毫秒转秒
          },
          set: function(value) {
            // 调用原始setter并减去偏移
            if (originalSetter) {
              return originalSetter.call(this, value - (timeOffset / 1000));
            }
            return value;
          },
          configurable: true,
          enumerable: true
        });
      }
    } catch (e) {
      // 忽略错误，确保不影响原始功能
      console.error('设置媒体元素时间代理失败:', e);
    }
  }
  
  // 使用私有MutationObserver监控媒体元素
  let mediaObserver = null;
  
  try {
    // 仅当需要时初始化观察器
    if (typeof MutationObserver !== 'undefined') {
      mediaObserver = new MutationObserver(mutations => {
        for (const mutation of mutations) {
          if (mutation.type === 'childList') {
            mutation.addedNodes.forEach(node => {
              // 直接检查节点
              if (node instanceof HTMLMediaElement) {
                setupMediaElement(node);
              }
              
              // 检查节点中的媒体元素
              if (node.querySelectorAll) {
                try {
                  node.querySelectorAll('video,audio').forEach(media => {
                    setupMediaElement(media);
                  });
                } catch (e) {
                  // 忽略错误
                }
              }
            });
          }
        }
      });
      
      // 等待DOM可用
      if (document.body) {
        mediaObserver.observe(document.body, {
          childList: true,
          subtree: true
        });
        
        // 初始化现有媒体元素
        document.querySelectorAll('video,audio').forEach(setupMediaElement);
      } else {
        // 文档尚未加载，等待DOMContentLoaded
        document.addEventListener('DOMContentLoaded', () => {
          if (document.body) {
            mediaObserver.observe(document.body, {
              childList: true,
              subtree: true
            });
            document.querySelectorAll('video,audio').forEach(setupMediaElement);
          }
        });
      }
    }
  } catch (e) {
    console.error('初始化媒体元素观察器失败:', e);
  }

 // 可选地覆盖全局Date对象
  // 默认情况下不覆盖全局对象，使用钩子函数访问
  // 如果页面需要调整时间，可以使用window._itvapp_getAdjustedTime
  
  // 控制是否直接覆盖全局对象的开关
  const shouldOverrideGlobals = false; // 默认不覆盖
  
  if (shouldOverrideGlobals) {
    // 直接覆盖全局Date
    window.Date = ITVAppDate;
    
    // 覆盖performance.now
    if (_original.PerformanceNow && window.performance) {
      window.performance.now = ITVAppPerformanceNow;
    }
  }
  
  // 资源清理函数
  window._cleanupITVAppTimeInterceptor = () => {
    // 恢复全局对象（如果已覆盖）
    if (window.Date !== _original.Date) {
      window.Date = _original.Date;
    }
    
    if (window.performance && window.performance.now !== _original.PerformanceNow) {
      window.performance.now = _original.PerformanceNow;
    }
    
    // 停止媒体观察器
    if (mediaObserver) {
      mediaObserver.disconnect();
      mediaObserver = null;
    }
    
    // 清理标记和钩子函数
    delete window._itvapp_time_interceptor_initialized;
    delete window._itvapp_getAdjustedDate;
    delete window._itvapp_getAdjustedTime;
    delete window._itvapp_getAdjustedPerformanceNow;
    delete window._cleanupITVAppTimeInterceptor;
  };
})();
