// 监控DOM变化并发送通知
(function() {
  // 定义常量配置
  const CONFIG = {
    DEBOUNCE_DELAY: 200, // 防抖延迟
    MIN_NOTIFICATION_INTERVAL: 500, // 最小通知间隔
    INITIAL_CHECK_DELAY: 800, // 初始检查延迟
    CHANNEL_NAME: '%CHANNEL_NAME%', // 通知通道名称
    MONITORED_TAGS: ['DIV', 'TABLE', 'UL', 'IFRAME'], // 监控的标签
    CHANGE_MESSAGE: 'CONTENT_CHANGED', // 通知消息内容
    CONTENT_READY_MESSAGE: 'CONTENT_READY', // 内容准备就绪消息
    CHECK_INTERVAL: 500, // 检查间隔(毫秒)
    MIN_CONTENT_LENGTH: 8000, // 最小内容长度阈值
    MAX_WAIT_TIME: 10000, // 最大等待时间(毫秒)
    MONITORED_SELECTORS: '.decrypted-link, img[src="copy.png"], img[src$="/copy.png"]', // 关键内容选择器
  };

  // 使用Set加速标签查找
  const MONITORED_TAGS_SET = new Set(CONFIG.MONITORED_TAGS);

  // 发送通知
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
          // 所有发送方式均失败
        }
      }
    }
  };

  // 主动检测内容准备情况
  const checkContentReadiness = function() {
    const isContentReady = function() {
      const contentLength = document.documentElement.outerHTML.length;
      const hasKeyElements = document.querySelectorAll(CONFIG.MONITORED_SELECTORS).length > 0;
      const pageState = document.readyState;
      
      // 修改：避免处理过短的HTML内容，确保内容真正加载
      if (contentLength < 1000 && !hasKeyElements) {
        return false;
      }
      
      return (contentLength > CONFIG.MIN_CONTENT_LENGTH || hasKeyElements) && 
             (pageState === "interactive" || pageState === "complete");
    };

    let readinessReported = false;
    let startTime = Date.now();
    let checkInterval = setInterval(() => {
      if (Date.now() - startTime > CONFIG.MAX_WAIT_TIME) {
        clearInterval(checkInterval);
        if (!readinessReported) {
          readinessReported = true;
          sendNotification(CONFIG.CONTENT_READY_MESSAGE);
        }
        return;
      }
      if (isContentReady() && !readinessReported) {
        clearInterval(checkInterval);
        readinessReported = true;
        sendNotification(CONFIG.CONTENT_READY_MESSAGE);
      }
    }, CONFIG.CHECK_INTERVAL);
  };

  // 记录状态
  let lastNotificationTime = Date.now();
  let debounceTimeout = null;

  // 检查是否有相关标签变化
  const hasRelevantTagChanges = function(mutations) {
    for (let mutation of mutations) {
      if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
        for (let node of mutation.addedNodes) {
          if (node.nodeType === 1) {
            // 检查节点是否为监控的标签
            if (MONITORED_TAGS_SET.has(node.tagName)) {
              return true;
            }
            // 检查节点内是否包含监控的标签
            if (node.querySelector && CONFIG.MONITORED_TAGS.some(tag => node.querySelector(tag))) {
              return true;
            }
            // 检查节点或其子元素是否匹配特定选择器(.decrypted-link或copy.png图片)
            if ((node.matches && node.matches(CONFIG.MONITORED_SELECTORS)) || 
                (node.querySelector && node.querySelector(CONFIG.MONITORED_SELECTORS))) {
              return true;
            }
          }
        }
      }
    }
    return false;
  };

  // 防抖处理内容变化通知
  const notifyContentChange = function(mutations) {
    if (debounceTimeout) clearTimeout(debounceTimeout);
    debounceTimeout = setTimeout(function() {
      const now = Date.now();
      if (now - lastNotificationTime < CONFIG.MIN_NOTIFICATION_INTERVAL) {
        return;
      }
      if (hasRelevantTagChanges(mutations)) {
        lastNotificationTime = now;
        sendNotification(CONFIG.CHANGE_MESSAGE);
      }
      debounceTimeout = null;
    }, CONFIG.DEBOUNCE_DELAY);
  };

  // 清理资源
  const cleanup = function() {
    if (debounceTimeout) clearTimeout(debounceTimeout);
  };

  // 初始化监控
  const initialize = function() {
    const observer = new MutationObserver(notifyContentChange);
    observer.observe(document.body, { childList: true, subtree: true, attributes: false, characterData: false });
    setTimeout(function() {
      sendNotification(CONFIG.CHANGE_MESSAGE);
      lastNotificationTime = Date.now();
    }, CONFIG.INITIAL_CHECK_DELAY);
    window.addEventListener('beforeunload', cleanup);
  };

  // 立即启动内容就绪检查
  checkContentReadiness();

  // 确保DOM加载后初始化完整监控
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
  } else {
    initialize();
  }
})();
