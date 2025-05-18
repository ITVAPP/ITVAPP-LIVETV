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
  
  // 跟踪状态
  let readinessCheckInterval = null;
  let readinessReported = false;
  let lastReportedCount = 0;
  let lastReportedLength = 0; // 新增：跟踪上次报告的内容长度
  
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
  
  // 新增：强制获取最新HTML长度
  const getLatestHtmlLength = function() {
    try {
      // 强制浏览器重新计算布局，确保获取最新DOM
      void document.documentElement.offsetHeight;
      return document.documentElement.outerHTML.length;
    } catch (e) {
      logToDart("ERROR", "获取HTML长度失败: " + e.message);
      return 0;
    }
  };
  
  // 检查关键元素，确保每次都获取最新状态
  const hasKeyElements = function() {
    try {
      const elements = document.querySelectorAll(CONFIG.MONITORED_SELECTORS);
      const result = elements.length > 0;
      const count = elements.length;
      
      logToDart("INFO", "元素检查: " + (result ? "找到 " + count + " 个元素" : "未找到元素"));
      return {
        exists: result, 
        count: count
      };
    } catch (e) {
      logToDart("ERROR", "元素检查失败: " + e.message);
      return {
        exists: false,
        count: 0
      };
    }
  };
  
  // 检查内容就绪状态
  const checkContentReadiness = function() {
    const startTime = Date.now();
    logToDart("INFO", "开始检查内容就绪状态");
    
    const isContentReady = function() {
      // 使用新函数获取最新HTML长度
      const contentLength = getLatestHtmlLength();
      const elemResult = hasKeyElements();
      const elementsExist = elemResult.exists;
      const elementsCount = elemResult.count;
      
      logToDart("DEBUG", "内容检查 - 长度: " + contentLength + ", 元素数: " + elementsCount);
      
      // 检测内容变化 - 同时检查长度和元素数量变化
      if (elementsExist && elementsCount !== lastReportedCount && readinessReported) {
        lastReportedCount = elementsCount;
        lastReportedLength = contentLength;
        logToDart("INFO", "内容已变化，当前元素数: " + elementsCount + ", 长度: " + contentLength);
        sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
      } else if (contentLength > lastReportedLength + 1000 && readinessReported) {
        // 检测内容长度显著变化
        lastReportedLength = contentLength;
        logToDart("INFO", "内容长度显著变化: " + contentLength);
        sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
      }
      
      // 修改为OR逻辑，只要满足一个条件即可视为内容就绪
      return contentLength >= CONFIG.MIN_CONTENT_LENGTH || elementsExist;
    };
    
    // 立即进行一次检查
    if (isContentReady()) {
      const currentLength = getLatestHtmlLength();
      const currentElements = hasKeyElements();
      
      logToDart("INFO", "内容立即就绪，长度: " + currentLength);
      sendNotification(CONFIG.CONTENT_READY_MESSAGE);
      readinessReported = true;
      lastReportedCount = currentElements.count;
      lastReportedLength = currentLength;
      return;
    }
    
    readinessCheckInterval = setInterval(() => {
      const elapsedTime = Date.now() - startTime;
      
      if (elapsedTime > CONFIG.MAX_WAIT_TIME) {
        logToDart("WARN", "超过最大等待时间: " + elapsedTime + "ms");
        clearInterval(readinessCheckInterval);
        readinessCheckInterval = null;
        
        // 超时时，如果内容长度大于一定值，也发送就绪通知
        if (!readinessReported) {
          const finalLength = getLatestHtmlLength();
          if (finalLength > 1000) {
            logToDart("INFO", "超时但内容非空，长度: " + finalLength + "，视为就绪");
            readinessReported = true;
            lastReportedLength = finalLength;
            sendNotification(CONFIG.CONTENT_READY_MESSAGE);
          }
        }
        return;
      }
      
      if (isContentReady()) {
        clearInterval(readinessCheckInterval);
        readinessCheckInterval = null;
        
        if (!readinessReported) {
          readinessReported = true;
          lastReportedLength = getLatestHtmlLength();
          lastReportedCount = hasKeyElements().count;
          logToDart("INFO", "内容就绪，耗时: " + elapsedTime + "ms, 长度: " + lastReportedLength);
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
        // 获取最新状态
        const currentLength = getLatestHtmlLength();
        const currentElements = hasKeyElements();
        
        // 检测显著变化
        if (currentElements.count !== lastReportedCount || 
            currentLength > lastReportedLength + 1000) {
          logToDart("INFO", "检测到DOM变化，元素: " + lastReportedCount + 
                   " -> " + currentElements.count + ", 长度: " + 
                   lastReportedLength + " -> " + currentLength);
          lastReportedCount = currentElements.count;
          lastReportedLength = currentLength;
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
      const currentElements = hasKeyElements();
      const currentLength = getLatestHtmlLength();
      
      if (currentElements.count !== lastReportedCount || 
          currentLength > lastReportedLength + 2000) {
        logToDart("INFO", "周期检查发现变化: 元素 " + lastReportedCount + 
                  " -> " + currentElements.count + ", 长度 " + 
                  lastReportedLength + " -> " + currentLength);
        lastReportedCount = currentElements.count;
        lastReportedLength = currentLength;
        sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
      }
    }
  }, 1000); // 每秒检查一次
})();
