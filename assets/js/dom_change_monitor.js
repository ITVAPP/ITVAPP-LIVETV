// 监控DOM变化并发送通知
(function() {
  // 定义常量配置
  const CONFIG = {
    DEBOUNCE_DELAY: 200, // 防抖延迟
    MIN_NOTIFICATION_INTERVAL: 300, // 最小通知间隔
    INITIAL_CHECK_DELAY: 800, // 初始检查延迟
    CHANNEL_NAME: '%CHANNEL_NAME%', // 通知通道名称
    MONITORED_TAGS: ['DIV', 'TABLE', 'UL', 'IFRAME'], // 监控的标签
    CHANGE_MESSAGE: 'CONTENT_CHANGED', // 通知消息内容
    CONTENT_READY_MESSAGE: 'CONTENT_READY', // 内容准备就绪消息
    CHECK_INTERVAL: 500, // 检查间隔(毫秒)
    MIN_CONTENT_LENGTH: 5000, // 最小内容长度阈值 - 保留此逻辑
    MAX_WAIT_TIME: 10000, // 最大等待时间(毫秒)
    MONITORED_SELECTORS: '.decrypted-link, img[src="copy.png"]', // 关键内容选择器
    DEBUG: true // 开启调试日志
  };

  // 调试日志函数
  const debugLog = function(message) {
    if (CONFIG.DEBUG) {
      console.log(`[DOM监控] ${message}`);
    }
  };

  debugLog(`脚本初始化，通道名: ${CONFIG.CHANNEL_NAME}`);

  // 使用Set加速标签查找
  const MONITORED_TAGS_SET = new Set(CONFIG.MONITORED_TAGS);

  // 发送通知
  const sendNotification = function(message) {
    try {
      debugLog(`尝试通过主通道发送消息: ${message}`);
      // 检查通道是否存在
      if (window[CONFIG.CHANNEL_NAME]) {
        window[CONFIG.CHANNEL_NAME].postMessage(message);
        debugLog(`消息已成功通过主通道发送: ${message}`);
        return;
      } else {
        debugLog(`主通道不存在: ${CONFIG.CHANNEL_NAME}`);
      }
    } catch (e) {
      debugLog(`通过主通道发送消息失败: ${e.message}`);
      // 备用：使用BroadcastChannel或CustomEvent
      try {
        debugLog('尝试通过BroadcastChannel发送消息');
        const channel = new BroadcastChannel(CONFIG.CHANNEL_NAME);
        channel.postMessage(message);
        channel.close();
        debugLog(`消息已通过BroadcastChannel发送: ${message}`);
      } catch (e2) {
        debugLog(`通过BroadcastChannel发送消息失败: ${e2.message}`);
        // 最后尝试使用CustomEvent
        try {
          debugLog('尝试通过CustomEvent发送消息');
          const event = new CustomEvent('content-change', { detail: { message } });
          document.dispatchEvent(event);
          debugLog(`消息已通过CustomEvent发送: ${message}`);
        } catch (e3) {
          debugLog(`所有发送方式均失败: ${e3.message}`);
        }
      }
    }
  };

  // 主动检测内容准备情况
  const checkContentReadiness = function() {
    // 定义内容就绪条件
    const isContentReady = function() {
      // 检查是否有足够的HTML内容
      const contentLength = document.documentElement.outerHTML.length;
      // 检查是否存在关键内容元素
      const hasKeyElements = document.querySelectorAll(CONFIG.MONITORED_SELECTORS).length > 0;
      // 检查页面加载状态
      const pageState = document.readyState;
      
      // 调试日志
      debugLog(`内容检测: 长度=${contentLength}, 关键元素=${hasKeyElements}, 状态=${pageState}`);
      
      // 判断内容是否足够处理 - 保留内容长度检查
      return (contentLength > CONFIG.MIN_CONTENT_LENGTH || hasKeyElements) && 
             (pageState === "interactive" || pageState === "complete");
    };

    let readinessReported = false;
    let startTime = Date.now();
    let checkInterval = setInterval(() => {
      // 检查是否超时
      if (Date.now() - startTime > CONFIG.MAX_WAIT_TIME) {
        clearInterval(checkInterval);
        // 超时后尝试使用当前内容，如果还没有报告就绪
        if (!readinessReported) {
          readinessReported = true;
          debugLog(`内容检测超时 (${CONFIG.MAX_WAIT_TIME}ms)，发送内容就绪通知`);
          sendNotification(CONFIG.CONTENT_READY_MESSAGE);
        }
        return;
      }

      // 检查内容是否准备就绪
      if (isContentReady() && !readinessReported) {
        clearInterval(checkInterval);
        readinessReported = true;
        debugLog('内容准备就绪，发送通知');
        sendNotification(CONFIG.CONTENT_READY_MESSAGE);
      }
    }, CONFIG.CHECK_INTERVAL);
    
    debugLog('开始内容就绪检测循环');
  };

  // 记录状态
  let lastNotificationTime = Date.now(); // 上次通知时间
  let debounceTimeout = null; // 防抖定时器

  // 检查是否有相关标签变化
  const hasRelevantTagChanges = function(mutations) {
    for (let mutation of mutations) {
      if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
        for (let node of mutation.addedNodes) {
          if (node.nodeType === 1) {
            // 检查是否是我们监控的标签
            if (MONITORED_TAGS_SET.has(node.tagName)) {
              debugLog(`检测到监控标签变化: ${node.tagName}`);
              return true;
            }
            
            // 检查是否包含我们监控的标签
            if (node.querySelector && CONFIG.MONITORED_TAGS.some(tag => node.querySelector(tag))) {
              debugLog(`检测到包含监控标签的节点变化`);
              return true;
            }
            
            // 特别检查是否为copy.png图像
            if (node.tagName === 'IMG' && 
                (node.getAttribute('src') === 'copy.png' || 
                 node.src.endsWith('/copy.png'))) {
              debugLog('检测到copy.png图像添加');
              return true;
            }
          }
        }
      }
    }
    return false;
  };

  // 防抖处理内容变化通知 - 简化版，不再计算变化百分比
  const notifyContentChange = function(mutations) {
    debugLog(`检测到DOM变化，共 ${mutations.length} 个`);
    
    if (debounceTimeout) clearTimeout(debounceTimeout);
    debounceTimeout = setTimeout(function() {
      const now = Date.now();
      if (now - lastNotificationTime < CONFIG.MIN_NOTIFICATION_INTERVAL) {
        debugLog(`忽略过于频繁的通知 (间隔<${CONFIG.MIN_NOTIFICATION_INTERVAL}ms)`);
        return;
      }
      
      // 检查是否有相关变化
      if (hasRelevantTagChanges(mutations)) {
        debugLog('检测到相关变化，发送通知');
      } else {
        debugLog('发送一般内容变化通知');
      }
      
      // 简化：总是发送通知，不检查变化百分比
      lastNotificationTime = now;
      sendNotification(CONFIG.CHANGE_MESSAGE);
      
      debounceTimeout = null;
    }, CONFIG.DEBOUNCE_DELAY);
  };

  // 清理资源
  const cleanup = function() {
    debugLog('清理资源');
    if (debounceTimeout) clearTimeout(debounceTimeout);
  };

  // 初始化监控
  const initialize = function() {
    debugLog('初始化DOM变化监控');
    const observer = new MutationObserver(notifyContentChange);
    observer.observe(document.body, { childList: true, subtree: true, attributes: false, characterData: false });
    
    // 简化，直接发送通知
    setTimeout(function() {
      // 检查页面上是否已有copy.png图像
      const hasCopyImages = document.querySelectorAll('img[src="copy.png"]').length > 0;
      if (hasCopyImages) {
        debugLog('页面初始化时发现copy.png图像');
      }
      
      debugLog('初始化延迟后发送内容变化通知');
      sendNotification(CONFIG.CHANGE_MESSAGE);
      lastNotificationTime = Date.now();
    }, CONFIG.INITIAL_CHECK_DELAY);
    
    window.addEventListener('beforeunload', cleanup);
    debugLog('DOM变化监控初始化完成');
  };

  // 立即启动内容就绪检查 - 不等待DOMContentLoaded
  debugLog('开始内容就绪检查');
  checkContentReadiness();

  // 确保DOM加载后初始化完整监控
  if (document.readyState === 'loading') {
    debugLog('页面加载中，等待DOMContentLoaded事件');
    document.addEventListener('DOMContentLoaded', initialize);
  } else {
    debugLog('页面已加载，立即初始化监控');
    initialize();
  }
})();
