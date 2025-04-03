// 修改代码开始
(function() {
  if (window._timeInterceptorInitialized) return;
  window._timeInterceptorInitialized = true;

  const originalDate = window.Date;
  // 使用占位符 TIME_OFFSET，由Dart代码动态替换，若未替换则默认为0
  const timeOffset = typeof TIME_OFFSET === 'number' ? TIME_OFFSET : 0;
  let timeRequested = false;
  let perfTimeRequested = false;
  let mediaTimeRequested = false;

  // 抽象发送时间请求的通用函数，避免重复代码
  function requestTime(method) {
    const requestedFlags = {
      'Date': timeRequested,
      'Date.now': timeRequested,
      'performance.now': perfTimeRequested,
      'media.currentTime': mediaTimeRequested
    };
    const setRequestedFlags = {
      'Date': () => timeRequested = true,
      'Date.now': () => timeRequested = true,
      'performance.now': () => perfTimeRequested = true,
      'media.currentTime': () => mediaTimeRequested = true
    };

    if (!requestedFlags[method] && window.TimeCheck) {
      setRequestedFlags[method]();
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'timeRequest',
        method: method
      }));
    }
  }

  // 核心时间调整函数，优化减少重复对象创建
  function getAdjustedTime() {
    requestTime('Date');
    const now = new originalDate().getTime();
    return new originalDate(now + timeOffset);
  }

  // 代理Date构造函数
  window.Date = function(...args) {
    return args.length === 0 ? getAdjustedTime() : new originalDate(...args);
  };

  // 保持原型链和方法
  window.Date.prototype = originalDate.prototype;
  window.Date.now = () => {
    requestTime('Date.now');
    return getAdjustedTime().getTime();
  };
  window.Date.parse = originalDate.parse;
  window.Date.UTC = originalDate.UTC;

  // 拦截performance.now
  const originalPerformanceNow = window.performance.now.bind(window.performance);
  window.performance.now = () => {
    requestTime('performance.now');
    return originalPerformanceNow() + timeOffset;
  };

  // 媒体元素时间处理，添加兼容性检查
  function setupMediaElement(element) {
    if (element._timeProxied) return;
    element._timeProxied = true;

    // 确保getRealCurrentTime和setRealCurrentTime可用
    element.getRealCurrentTime = element.getRealCurrentTime || (() => element.currentTime || 0);
    element.setRealCurrentTime = element.setRealCurrentTime || (value => element.currentTime = value);

    Object.defineProperty(element, 'currentTime', {
      get: () => {
        requestTime('media.currentTime');
        return element.getRealCurrentTime() + (timeOffset / 1000);
      },
      set: value => element.setRealCurrentTime(value - (timeOffset / 1000))
    });
  }

  // 监听新媒体元素，缩小监听范围至body
  const observer = new MutationObserver(mutations => {
    mutations.forEach(mutation => {
      mutation.addedNodes.forEach(node => {
        if (node instanceof HTMLMediaElement) setupMediaElement(node);
      });
    });
  });

  observer.observe(document.body || document.documentElement, {
    childList: true,
    subtree: true
  });

  // 初始化现有媒体元素
  document.querySelectorAll('video,audio').forEach(setupMediaElement);

  // 资源清理
  window._cleanupTimeInterceptor = () => {
    window.Date = originalDate;
    window.performance.now = originalPerformanceNow;
    observer.disconnect();
    delete window._timeInterceptorInitialized;
  };
})();
// 修改代码结束
