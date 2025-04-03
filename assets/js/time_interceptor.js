(function() {
  // 避免重复初始化，确保脚本只执行一次
  if (window._timeInterceptorInitialized) return;
  window._timeInterceptorInitialized = true;

  const originalDate = window.Date; // 保存原始Date构造函数
  // 使用占位符 TIME_OFFSET，由Dart代码动态替换，默认值为0
  const timeOffset = typeof TIME_OFFSET === 'number' ? TIME_OFFSET : 0;
  let timeRequested = false; // 标记Date时间是否已请求
  let perfTimeRequested = false; // 标记performance时间是否已请求
  let mediaTimeRequested = false; // 标记媒体时间是否已请求

  // 抽象发送时间请求的通用函数，避免重复代码
  function requestTime(method) { // 发送时间请求并标记状态
    const requestedFlags = { // 各方法的时间请求状态
      'Date': timeRequested,
      'Date.now': timeRequested,
      'performance.now': perfTimeRequested,
      'media.currentTime': mediaTimeRequested
    };
    const setRequestedFlags = { // 设置对应方法的状态
      'Date': () => timeRequested = true,
      'Date.now': () => timeRequested = true,
      'performance.now': () => perfTimeRequested = true,
      'media.currentTime': () => mediaTimeRequested = true
    };

    if (!requestedFlags[method] && window.TimeCheck) { // 未请求且TimeCheck可用
      setRequestedFlags[method](); // 更新状态
      window.TimeCheck.postMessage(JSON.stringify({ // 发送时间请求消息
        type: 'timeRequest',
        method: method
      }));
    }
  }

  // 核心时间调整函数，优化减少重复对象创建
  function getAdjustedTime() { // 获取调整后的当前时间
    requestTime('Date'); // 请求Date时间
    const now = new originalDate().getTime(); // 获取原始时间戳
    return new originalDate(now + timeOffset); // 返回调整后的时间
  }

  // 代理Date构造函数
  window.Date = function(...args) { // 重写Date，支持无参和有参调用
    return args.length === 0 ? getAdjustedTime() : new originalDate(...args);
  };

  // 保持原型链和静态方法
  window.Date.prototype = originalDate.prototype; // 继承原始原型
  window.Date.now = () => { // 重写Date.now，返回调整后的时间戳
    requestTime('Date.now');
    return getAdjustedTime().getTime();
  };
  window.Date.parse = originalDate.parse; // 保留原始parse方法
  window.Date.UTC = originalDate.UTC; // 保留原始UTC方法

  // 拦截performance.now
  const originalPerformanceNow = window.performance.now.bind(window.performance); // 保存原始performance.now
  window.performance.now = () => { // 重写performance.now，添加偏移
    requestTime('performance.now');
    return originalPerformanceNow() + timeOffset;
  };

  // 媒体元素时间处理，添加兼容性检查
  function setupMediaElement(element) { // 设置媒体元素时间代理
    if (element._timeProxied) return; // 避免重复代理
    element._timeProxied = true; // 标记已代理

    // 确保getRealCurrentTime和setRealCurrentTime可用
    element.getRealCurrentTime = element.getRealCurrentTime || (() => element.currentTime || 0); // 获取真实时间
    element.setRealCurrentTime = element.setRealCurrentTime || (value => element.currentTime = value); // 设置真实时间

    Object.defineProperty(element, 'currentTime', { // 重定义currentTime属性
      get: () => { // 获取时添加偏移（单位：秒）
        requestTime('media.currentTime');
        return element.getRealCurrentTime() + (timeOffset / 1000);
      },
      set: value => element.setRealCurrentTime(value - (timeOffset / 1000)) // 设置时减去偏移
    });
  }

  // 监听新媒体元素，缩小监听范围至body
  const observer = new MutationObserver(mutations => { // 监听DOM变化
    mutations.forEach(mutation => { // 处理每个变化
      mutation.addedNodes.forEach(node => { // 检查新增节点
        if (node instanceof HTMLMediaElement) setupMediaElement(node); // 代理媒体元素
      });
    });
  });

  observer.observe(document.body || document.documentElement, { // 开始观察DOM
    childList: true, // 监听子节点变化
    subtree: true // 监听整个子树
  });

  // 初始化现有媒体元素
  document.querySelectorAll('video,audio').forEach(setupMediaElement); // 代理页面已有媒体元素

  // 资源清理
  window._cleanupTimeInterceptor = () => { // 清理函数，恢复原始状态
    window.Date = originalDate; // 恢复原始Date
    window.performance.now = originalPerformanceNow; // 恢复原始performance.now
    observer.disconnect(); // 停止DOM观察
    delete window._timeInterceptorInitialized; // 清除初始化标记
  };
})();
