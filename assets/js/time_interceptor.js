(function() {
  // 避免重复初始化，确保脚本只执行一次
  if (window._timeInterceptorInitialized) return;
  window._timeInterceptorInitialized = true;
  
  const originalDate = window.Date; // 保存原始Date构造函数
  
  // 使用安全方式访问TIME_OFFSET，确保不会因未定义变量引发错误
  const timeOffset = typeof window.TIME_OFFSET === 'number' ? window.TIME_OFFSET : 0;
  
  // 状态标记，使用单一对象管理所有请求状态
  const requestFlags = {
    'Date': false,
    'performance.now': false,
    'media.currentTime': false
  };
  
  // 抽象发送时间请求的通用函数，避免重复代码
  function requestTime(method) { // 发送时间请求并标记状态
    // 简化标记逻辑，使用对象属性直接访问
    if (!requestFlags[method] && window.TimeCheck) { // 未请求且TimeCheck可用
      requestFlags[method] = true; // 更新状态
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
    requestTime('Date'); // 使用统一的'Date'标记，简化状态管理
    return getAdjustedTime().getTime();
  };
  window.Date.parse = originalDate.parse; // 保留原始parse方法
  window.Date.UTC = originalDate.UTC; // 保留原始UTC方法
  
  // 拦截performance.now
  const originalPerformanceNow = window.performance && window.performance.now ? 
    window.performance.now.bind(window.performance) : null; // 安全获取原始performance.now
  
  if (originalPerformanceNow) {
    window.performance.now = () => { // 重写performance.now，添加偏移
      requestTime('performance.now');
      return originalPerformanceNow() + timeOffset;
    };
  }
  
  // 媒体元素时间处理，添加兼容性检查
  function setupMediaElement(element) { // 设置媒体元素时间代理
    if (!element || element._timeProxied) return; // 增加null检查并避免重复代理
    element._timeProxied = true; // 标记已代理
    
    // 使用闭包保存原始时间获取和设置函数，避免属性冲突
    const originalGetTime = () => element.currentTime;
    const originalSetTime = (value) => { element.currentTime = value; return value; };
    
    // 保存原始对象引用
    const elementProto = Object.getPrototypeOf(element);
    const originalDescriptor = Object.getOwnPropertyDescriptor(elementProto, 'currentTime');
    
    // 如果无法获取原始描述符，则使用备用方案
    if (originalDescriptor) {
      Object.defineProperty(element, 'currentTime', { // 重定义currentTime属性
        get: () => { // 获取时添加偏移（单位：秒）
          requestTime('media.currentTime');
          // 使用原始描述符的get方法，或默认返回0
          const originalValue = originalDescriptor.get ? 
            originalDescriptor.get.call(element) : 0;
          return originalValue + (timeOffset / 1000);
        },
        set: (value) => {
          // 使用原始描述符的set方法，或什么都不做
          if (originalDescriptor.set) {
            return originalDescriptor.set.call(element, value - (timeOffset / 1000));
          }
          return value;
        },
        configurable: true, // 允许后续可能的修改
        enumerable: true // 保持属性可枚举
      });
    } else {
      // 备用方案：直接重定义currentTime属性
      Object.defineProperty(element, 'currentTime', {
        get: () => {
          requestTime('media.currentTime');
          return originalGetTime() + (timeOffset / 1000);
        },
        set: (value) => originalSetTime(value - (timeOffset / 1000)),
        configurable: true,
        enumerable: true
      });
    }
  }
  
  // 优化MutationObserver配置，提高性能
  const observerCallback = (mutations) => {
    for (const mutation of mutations) {
      // 只处理新增节点
      if (mutation.type === 'childList') {
        for (const node of mutation.addedNodes) {
          // 检查媒体元素
          if (node instanceof HTMLMediaElement) {
            setupMediaElement(node);
          }
          // 检查子树中的媒体元素
          if (node.querySelectorAll) {
            node.querySelectorAll('video,audio').forEach(setupMediaElement);
          }
        }
      }
    }
  };
  
  // 确保document.body存在后再观察
  const setupObserver = () => {
    const targetNode = document.body || document.documentElement;
    if (targetNode) {
      const observer = new MutationObserver(observerCallback);
      observer.observe(targetNode, {
        childList: true, // 监听子节点变化
        subtree: true // 监听整个子树
      });
      
      // 初始化现有媒体元素
      document.querySelectorAll('video,audio').forEach(setupMediaElement);
      
      // 保存observer引用以便清理
      window._timeInterceptorObserver = observer;
    } else {
      // 如果DOM还未准备好，延迟设置
      setTimeout(setupObserver, 100);
    }
  };
  
  // 启动观察器
  setupObserver();
  
  // 资源清理
  window._cleanupTimeInterceptor = () => { // 清理函数，恢复原始状态
    window.Date = originalDate; // 恢复原始Date
    
    if (originalPerformanceNow && window.performance) {
      window.performance.now = originalPerformanceNow; // 恢复原始performance.now
    }
    
    if (window._timeInterceptorObserver) {
      window._timeInterceptorObserver.disconnect(); // 停止DOM观察
      delete window._timeInterceptorObserver; // 删除引用
    }
    
    delete window._timeInterceptorInitialized; // 清除初始化标记
  };
})();
