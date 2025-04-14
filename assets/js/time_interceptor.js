(function() {
  if (window._timeInterceptorInitialized) return;
  window._timeInterceptorInitialized = true;

  const originalDate = window.Date;
  const timeOffset = typeof window.TIME_OFFSET === 'number' ? window.TIME_OFFSET : 0;
  const requestFlags = {
    'Date': false,
    'performance.now': false,
    'media.currentTime': false
  };

  function requestTime(method) {
    if (!requestFlags[method] && window.TimeCheck) {
      requestFlags[method] = true;
      window.TimeCheck.postMessage(JSON.stringify({
        type: 'timeRequest',
        method: method
      }));
    }
  }

  function getAdjustedTime() {
    requestTime('Date');
    const now = new originalDate().getTime();
    return new originalDate(now + timeOffset);
  }

  window.Date = function(...args) {
    return args.length === 0 ? getAdjustedTime() : new originalDate(...args);
  };
  window.Date.prototype = originalDate.prototype;
  window.Date.now = () => {
    requestTime('Date');
    return getAdjustedTime().getTime();
  };
  window.Date.parse = originalDate.parse;
  window.Date.UTC = originalDate.UTC;

  const originalPerformanceNow = window.performance && window.performance.now ?
    window.performance.now.bind(window.performance) : null;

  if (originalPerformanceNow) {
    window.performance.now = () => {
      requestTime('performance.now');
      return originalPerformanceNow() + timeOffset;
    };
  }

  function setupMediaElement(element) {
    if (!element || element._timeProxied) return;
    element._timeProxied = true;
    const originalGetTime = () => element.currentTime;
    const originalSetTime = (value) => { element.currentTime = value; return value; };
    const elementProto = Object.getPrototypeOf(element);
    const originalDescriptor = Object.getOwnPropertyDescriptor(elementProto, 'currentTime');

    if (originalDescriptor) {
      Object.defineProperty(element, 'currentTime', {
        get: () => {
          requestTime('media.currentTime');
          const originalValue = originalDescriptor.get ?
            originalDescriptor.get.call(element) : 0;
          return originalValue + (timeOffset / 1000);
        },
        set: (value) => {
          if (originalDescriptor.set) {
            return originalDescriptor.set.call(element, value - (timeOffset / 1000));
          }
          return value;
        },
        configurable: true,
        enumerable: true
      });
    } else {
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

  const observerCallback = (mutations) => {
    for (const mutation of mutations) {
      if (mutation.type === 'childList') {
        for (const node of mutation.addedNodes) {
          if (node instanceof HTMLMediaElement) {
            setupMediaElement(node);
          }
          if (node.querySelectorAll) {
            node.querySelectorAll('video,audio').forEach(setupMediaElement);
          }
        }
      }
    }
  };

  const setupObserver = () => {
    const targetNode = document.body || document.documentElement;
    if (targetNode) {
      const observer = new MutationObserver(observerCallback);
      observer.observe(targetNode, {
        childList: true,
        subtree: true
      });
      document.querySelectorAll('video,audio').forEach(setupMediaElement);
      window._timeInterceptorObserver = observer;
    } else {
      setTimeout(setupObserver, 100);
    }
  };

  setupObserver();

  window._cleanupTimeInterceptor = () => {
    window.Date = originalDate;
    if (originalPerformanceNow && window.performance) {
      window.performance.now = originalPerformanceNow;
    }
    if (window._timeInterceptorObserver) {
      window._timeInterceptorObserver.disconnect();
      delete window._timeInterceptorObserver;
    }
    delete window._timeInterceptorInitialized;
  };
})();
