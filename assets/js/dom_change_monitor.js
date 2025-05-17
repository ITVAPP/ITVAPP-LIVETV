(function() {
  // 配置参数
  const CONFIG = {
    CHECK_INTERVAL: 500, // 检查间隔（毫秒）
    MIN_CONTENT_LENGTH: 8888, // 最小内容长度
    MAX_WAIT_TIME: 8000, // 最大等待时间
    MONITORED_SELECTORS: '.decrypted-link, img[src="copy.png"], img[src$="/copy.png"]', // 监控的选择器
    CHANNEL_NAME: 'AppChannel', // 通知通道名称
    CONTENT_READY_MESSAGE: 'CONTENT_READY' // 内容就绪消息
  };
  
  // 初始化 AppChannel，避免未定义
  window[CONFIG.CHANNEL_NAME] = window[CONFIG.CHANNEL_NAME] || {
    postMessage: message => {} // 空函数，无输出
  };
  
  // 缓存元素查询结果
  let cachedElements = null;
  let cachedTimestamp = 0;
  const CACHE_TTL = 1000;
  
  // 跟踪状态
  let readinessCheckInterval = null;
  let readinessReported = false;

  // 发送通知
  const sendNotification = function(message) {
    try {
      if (window[CONFIG.CHANNEL_NAME]) {
        window[CONFIG.CHANNEL_NAME].postMessage(message);
      }
    } catch (e) {
    }
  };

  // 检查关键元素，使用缓存
  const hasKeyElements = function() {
    const now = Date.now();
    if (cachedElements !== null && now - cachedTimestamp < CACHE_TTL) {
      return cachedElements;
    }
    
    const result = document.querySelectorAll(CONFIG.MONITORED_SELECTORS).length > 0;
    cachedElements = result;
    cachedTimestamp = now;
    return result;
  };

  // 检查内容就绪状态
  const checkContentReadiness = function() {
    const startTime = Date.now();
    
    const isContentReady = function() {
      const contentLength = document.documentElement.outerHTML.length;
      const elementsExist = hasKeyElements();
      
      return contentLength >= CONFIG.MIN_CONTENT_LENGTH && elementsExist;
    };

    // 立即进行一次检查
    if (isContentReady()) {
      sendNotification(CONFIG.CONTENT_READY_MESSAGE);
      readinessReported = true;
      return;
    }

    readinessCheckInterval = setInterval(() => {
      if (Date.now() - startTime > CONFIG.MAX_WAIT_TIME) {
        clearInterval(readinessCheckInterval);
        readinessCheckInterval = null;
        return;
      }
      
      if (isContentReady()) {
        clearInterval(readinessCheckInterval);
        readinessCheckInterval = null;
        
        if (!readinessReported) {
          readinessReported = true;
          sendNotification(CONFIG.CONTENT_READY_MESSAGE);
        }
      }
    }, CONFIG.CHECK_INTERVAL);
  };

  // 清理资源
  const cleanup = function() {
    if (readinessCheckInterval) {
      clearInterval(readinessCheckInterval);
      readinessCheckInterval = null;
    }
    
    window.removeEventListener('beforeunload', cleanup);
  };

  // 添加清理监听
  window.addEventListener('beforeunload', cleanup);

  // 立即开始检查
  checkContentReadiness();
})();
