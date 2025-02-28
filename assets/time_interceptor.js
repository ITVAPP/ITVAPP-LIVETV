// 北京时间注入脚本
(function() {
  if (window._timeInterceptorInitialized) return;
  window._timeInterceptorInitialized = true;

  const originalDate = window.Date;
  // 使用占位符 TIME_OFFSET，由Dart代码动态替换
  const timeOffset = TIME_OFFSET;
  let timeRequested = false;

  // 核心时间调整函数
  function getAdjustedTime() {
    if (!timeRequested) {
      timeRequested = true;
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'timeRequest',
        method: 'Date'
      }));
    }
    return new originalDate(new originalDate().getTime() + timeOffset);
  }

  // 代理Date构造函数
  window.Date = function(...args) {
    return args.length === 0 ? getAdjustedTime() : new originalDate(...args);
  };

  // 保持原型链和方法
  window.Date.prototype = originalDate.prototype;
  window.Date.now = () => {
    if (!timeRequested) {
      timeRequested = true;
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'timeRequest',
        method: 'Date.now'
      }));
    }
    return getAdjustedTime().getTime();
  };
  window.Date.parse = originalDate.parse;
  window.Date.UTC = originalDate.UTC;

  // 拦截performance.now
  const originalPerformanceNow = window.performance.now.bind(window.performance);
  let perfTimeRequested = false;
  window.performance.now = () => {
    if (!perfTimeRequested) {
      perfTimeRequested = true;
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'timeRequest',
        method: 'performance.now'
      }));
    }
    return originalPerformanceNow() + timeOffset;
  };

  // 媒体元素时间处理
  let mediaTimeRequested = false;
  function setupMediaElement(element) {
    if (element._timeProxied) return;
    element._timeProxied = true;

    Object.defineProperty(element, 'currentTime', {
      get: () => {
        if (!mediaTimeRequested) {
          mediaTimeRequested = true;
          window.TimeCheck.postMessage(JSON.stringify({
            type: 'timeRequest',
            method: 'media.currentTime'
          }));
        }
        return (element.getRealCurrentTime?.() ?? 0) + (timeOffset / 1000);
      },
      set: value => element.setRealCurrentTime?.(value - (timeOffset / 1000))
    });
  }

  // 监听新媒体元素
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
