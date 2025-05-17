// 监控DOM变化并发送通知
(function() {
  // 配置监控参数与消息类型
  const CONFIG = {
    DEBOUNCE_DELAY: 200, // 防抖延迟（毫秒）
    MIN_NOTIFICATION_INTERVAL: 500, // 最小通知间隔（毫秒）
    INITIAL_CHECK_DELAY: 800, // 初始检查延迟（毫秒）
    CHANNEL_NAME: '%CHANNEL_NAME%', // 通知通道名称
    MONITORED_TAGS: ['DIV', 'TABLE', 'UL', 'IFRAME'], // 监控的HTML标签
    CHANGE_MESSAGE: 'CONTENT_CHANGED', // 内容变化消息
    CONTENT_READY_MESSAGE: 'CONTENT_READY', // 内容就绪消息
    CHECK_INTERVAL: 500, // 内容检查间隔（毫秒）
    MIN_CONTENT_LENGTH: 8888, // 最小内容长度（字节）
    MAX_WAIT_TIME: 8000, // 最大等待时间（毫秒）
    MONITORED_SELECTORS: '.decrypted-link, img[src="copy.png"], img[src$="/copy.png"]', // 监控的CSS选择器
  };

  // 加速标签查找的Set集合
  const MONITORED_TAGS_SET = new Set(CONFIG.MONITORED_TAGS);
  
  // 缓存有效期（毫秒）
  const CACHE_TTL = 1000; // 元素查询缓存有效期1秒
  
  // 缓存元素查询结果，提升性能
  let cachedElements = null;
  let cachedTimestamp = 0;
  
  // 跟踪通知与监控状态
  let lastNotificationTime = Date.now();
  let debounceTimeout = null;
  let readinessCheckInterval = null;
  let observer = null;
  let readinessReported = false;

  // 发送通知，支持多种通道
  const sendNotification = function(message) {
    try {
      if (window[CONFIG.CHANNEL_NAME]) {
        window[CONFIG.CHANNEL_NAME].postMessage(message);
        return;
      }
    } catch (e) {
      try {
        const channel = new BroadcastChannel(CONFIG.CHANNEL_NAME);
        channel.postMessage(message);
        channel.close();
      } catch (e2) {
        try {
          const event = new CustomEvent('content-change', { detail: { message } });
          document.dispatchEvent(event);
        } catch (e3) {
          // 所有发送方式失败，无操作
        }
      }
    }
  };

  // 查询关键元素，使用缓存减少DOM操作
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

  // 定期检查内容就绪状态
  const checkContentReadiness = function() {
    const startTime = Date.now();
    
    const isContentReady = function() {
      const contentLength = document.documentElement.outerHTML.length;
      
      // 只判断内容长度和关键元素，删除pageState判断
      return contentLength >= CONFIG.MIN_CONTENT_LENGTH && hasKeyElements();
    };

    readinessCheckInterval = setInterval(() => {
      if (Date.now() - startTime > CONFIG.MAX_WAIT_TIME || isContentReady()) {
        clearInterval(readinessCheckInterval);
        readinessCheckInterval = null;
        
        if (!readinessReported) {
          readinessReported = true;
          sendNotification(CONFIG.CONTENT_READY_MESSAGE);
        }
      }
    }, CONFIG.CHECK_INTERVAL);
  };

  // 检查DOM变化是否涉及监控标签或选择器
  const hasRelevantTagChanges = function(mutations) {
    const hasAddedNodes = mutations.some(mutation => 
      mutation.type === 'childList' && mutation.addedNodes.length > 0
    );
    
    if (!hasAddedNodes) return false;
    
    for (let i = 0; i < mutations.length; i++) {
      const mutation = mutations[i];
      if (mutation.type !== 'childList' || mutation.addedNodes.length === 0) continue;
      
      const addedNodes = mutation.addedNodes;
      for (let j = 0; j < addedNodes.length; j++) {
        const node = addedNodes[j];
        if (node.nodeType !== 1) continue;
        
        if (MONITORED_TAGS_SET.has(node.tagName)) return true;
        if (node.matches && node.matches(CONFIG.MONITORED_SELECTORS)) return true;
        
        if (node.querySelector) {
          if (node.querySelector(CONFIG.MONITORED_SELECTORS)) return true;
          
          for (let k = 0; k < CONFIG.MONITORED_TAGS.length; k++) {
            if (node.querySelector(CONFIG.MONITORED_TAGS[k])) return true;
          }
        }
      }
    }
    return false;
  };

  // 防抖处理DOM变化通知
  const notifyContentChange = function(mutations) {
    const now = Date.now();
    if (now - lastNotificationTime < CONFIG.MIN_NOTIFICATION_INTERVAL) {
      return;
    }
    
    if (debounceTimeout) {
      clearTimeout(debounceTimeout);
      debounceTimeout = null;
    }
    
    debounceTimeout = setTimeout(function() {
      if (hasRelevantTagChanges(mutations)) {
        lastNotificationTime = Date.now();
        sendNotification(CONFIG.CHANGE_MESSAGE);
      }
      debounceTimeout = null;
    }, CONFIG.DEBOUNCE_DELAY);
  };

  // 清理资源，释放定时器与监听
  const cleanup = function() {
    if (debounceTimeout) {
      clearTimeout(debounceTimeout);
      debounceTimeout = null;
    }
    
    if (readinessCheckInterval) {
      clearInterval(readinessCheckInterval);
      readinessCheckInterval = null;
    }
    
    if (observer) {
      observer.disconnect();
      observer = null;
    }
    
    window.removeEventListener('beforeunload', cleanup);
  };

  // 初始化DOM变化监控
  const initialize = function() {
    observer = new MutationObserver(notifyContentChange);
    observer.observe(document.body, { 
      childList: true, 
      subtree: true, 
      attributes: false, 
      characterData: false 
    });
    window.addEventListener('beforeunload', cleanup);
  };

  // 启动内容就绪检查
  checkContentReadiness();

  // 确保DOM加载后初始化监控
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
  } else {
    initialize();
  }
})();
