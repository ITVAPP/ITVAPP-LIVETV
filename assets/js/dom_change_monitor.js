(function() {
  // 配置参数
  const CONFIG = {
    CHECK_INTERVAL: 500, // 检查间隔（毫秒）
    MIN_CONTENT_LENGTH: 8888, // 最小内容长度
    MAX_WAIT_TIME: 8000, // 最大等待时间
    MONITORED_SELECTORS: 'span[class="decrypted-link"], img[src="copy.png"], img[src$="/copy.png"]', // 监控的选择器
    CHANNEL_NAME: 'AppChannel', // 通知通道名称
    CONTENT_READY_MESSAGE: 'CONTENT_READY', // 内容就绪消息
    CONTENT_CHANGED_MESSAGE: 'CONTENT_CHANGED' // 内容变化消息
  };
  
  // 初始化 AppChannel，避免未定义
  window[CONFIG.CHANNEL_NAME] = window[CONFIG.CHANNEL_NAME] || {
    postMessage: message => {} // 空函数，无输出
  };
  
  // 缓存元素查询结果
  let cachedElements = null;
  let cachedElementsCount = 0;
  let cachedTimestamp = 0;
  const CACHE_TTL = 1000;
  
  // 跟踪状态
  let readinessCheckInterval = null;
  let readinessReported = false;
  let lastReportedCount = 0;
  
  // 日志函数 - 发送到Dart
  const logToDart = function(type, message) {
    try {
      if (window[CONFIG.CHANNEL_NAME]) {
        window[CONFIG.CHANNEL_NAME].postMessage(`[JS_LOG:${type}] ${message}`);
      }
    } catch (e) {
      // 无法处理的错误，日志功能本身失败
    }
  };
  
  // 发送通知
  const sendNotification = function(message) {
    try {
      if (window[CONFIG.CHANNEL_NAME]) {
        window[CONFIG.CHANNEL_NAME].postMessage(message);
        logToDart("INFO", "已发送消息: " + message);
      }
    } catch (e) {
      logToDart("ERROR", "消息发送失败: " + e.message);
    }
  };
  
  // 检查关键元素，使用缓存
  const hasKeyElements = function() {
    const now = Date.now();
    if (cachedElements !== null && now - cachedTimestamp < CACHE_TTL) {
      return cachedElements;
    }
    
    const elements = document.querySelectorAll(CONFIG.MONITORED_SELECTORS);
    const result = elements.length > 0;
    cachedElements = result;
    cachedElementsCount = elements.length;
    cachedTimestamp = now;
    
    logToDart("INFO", "元素检查: " + (result ? "找到 " + elements.length + " 个元素" : "未找到元素"));
    return result;
  };
  
  // 获取当前关键元素数量
  const getElementsCount = function() {
    hasKeyElements(); // 更新缓存
    return cachedElementsCount;
  };
  
  // 检查内容就绪状态
  const checkContentReadiness = function() {
    const startTime = Date.now();
    logToDart("INFO", "开始检查内容就绪状态");
    
    const isContentReady = function() {
      const contentLength = document.documentElement.outerHTML.length;
      const elementsExist = hasKeyElements();
      const elementsCount = getElementsCount();
      
      logToDart("DEBUG", "内容检查 - 长度: " + contentLength + ", 元素数: " + elementsCount);
      
      // 检测内容变化
      if (elementsExist && elementsCount !== lastReportedCount && readinessReported) {
        lastReportedCount = elementsCount;
        logToDart("INFO", "内容已变化，当前元素数: " + elementsCount);
        sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
      }
      
      return contentLength >= CONFIG.MIN_CONTENT_LENGTH && elementsExist;
    };
    
    // 立即进行一次检查
    if (isContentReady()) {
      logToDart("INFO", "内容立即就绪");
      sendNotification(CONFIG.CONTENT_READY_MESSAGE);
      readinessReported = true;
      lastReportedCount = getElementsCount();
      return;
    }
    
    readinessCheckInterval = setInterval(() => {
      const elapsedTime = Date.now() - startTime;
      
      if (elapsedTime > CONFIG.MAX_WAIT_TIME) {
        logToDart("WARN", "超过最大等待时间: " + elapsedTime + "ms");
        clearInterval(readinessCheckInterval);
        readinessCheckInterval = null;
        return;
      }
      
      if (isContentReady()) {
        clearInterval(readinessCheckInterval);
        readinessCheckInterval = null;
        
        if (!readinessReported) {
          readinessReported = true;
          lastReportedCount = getElementsCount();
          logToDart("INFO", "内容就绪，耗时: " + elapsedTime + "ms");
          sendNotification(CONFIG.CONTENT_READY_MESSAGE);
        }
      }
    }, CONFIG.CHECK_INTERVAL);
  };
  
  // 监听DOM变化
  const setupMutationObserver = function() {
    if (!window.MutationObserver) {
      logToDart("WARN", "MutationObserver不可用");
      return null;
    }
    
    const observer = new MutationObserver((mutations) => {
      if (readinessReported) {
        const currentCount = document.querySelectorAll(CONFIG.MONITORED_SELECTORS).length;
        if (currentCount !== lastReportedCount) {
          logToDart("INFO", "检测到DOM变化，元素变化: " + lastReportedCount + " -> " + currentCount);
          lastReportedCount = currentCount;
          sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
        }
      }
    });
    
    observer.observe(document.body, {
      childList: true,
      subtree: true
    });
    
    logToDart("INFO", "已设置DOM变化监听器");
    
    // 清理函数
    return function() {
      observer.disconnect();
      logToDart("INFO", "已断开DOM变化监听器");
    };
  };
  
  // 清理资源
  let disconnectObserver = null;
  const cleanup = function() {
    logToDart("INFO", "开始清理资源");
    
    if (readinessCheckInterval) {
      clearInterval(readinessCheckInterval);
      readinessCheckInterval = null;
    }
    
    if (disconnectObserver) {
      disconnectObserver();
      disconnectObserver = null;
    }
    
    window.removeEventListener('beforeunload', cleanup);
  };
  
  // 添加清理监听
  window.addEventListener('beforeunload', cleanup);
  
  // 立即开始检查
  logToDart("INFO", "内容监控已初始化，监控选择器: " + CONFIG.MONITORED_SELECTORS);
  checkContentReadiness();
  
  // 设置DOM变化监听
  disconnectObserver = setupMutationObserver();
  
  // 周期性检查内容变化（补充方式）
  setInterval(() => {
    if (readinessReported) {
      const currentCount = document.querySelectorAll(CONFIG.MONITORED_SELECTORS).length;
      if (currentCount !== lastReportedCount) {
        logToDart("INFO", "周期检查发现变化: " + lastReportedCount + " -> " + currentCount);
        lastReportedCount = currentCount;
        sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
      }
    }
  }, 1000); // 每秒检查一次
})();
