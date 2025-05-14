(function() {
  // 定义所有常量
  const CONFIG = {
    // 定义内容变化阈值（百分比）
    SIGNIFICANT_CHANGE_PERCENT: 5.0,
    // 防抖延迟时间（毫秒）
    DEBOUNCE_DELAY: 200,
    // 最小通知间隔（毫秒）
    MIN_NOTIFICATION_INTERVAL: 500,
    // 初始检查延迟（毫秒）
    INITIAL_CHECK_DELAY: 800,
    // 通道名称
    CHANNEL_NAME: '%CHANNEL_NAME%',
    // 需要监控变化的标签
    MONITORED_TAGS: ['DIV', 'TABLE', 'UL', 'IFRAME'],
    // 通知消息内容
    CHANGE_MESSAGE: 'CONTENT_CHANGED'
  };

  // 记录初始页面内容长度
  const initialContentLength = document.body.innerHTML.length;

  // 初始化通知时间和内容长度
  let lastNotificationTime = Date.now();
  let lastContentLength = initialContentLength;
  let debounceTimeout = null;

  // 防抖通知内容变化
  const notifyContentChange = function() {
    if (debounceTimeout) {
      clearTimeout(debounceTimeout);
    }

    debounceTimeout = setTimeout(function() {
      const now = Date.now();
      if (now - lastNotificationTime < CONFIG.MIN_NOTIFICATION_INTERVAL) {
        return;
      }

      const currentContentLength = document.body.innerHTML.length;
      const changePercent = Math.abs(currentContentLength - lastContentLength) / lastContentLength * 100;

      if (changePercent > CONFIG.SIGNIFICANT_CHANGE_PERCENT) {
        lastNotificationTime = now;
        lastContentLength = currentContentLength;
        CONFIG.CHANNEL_NAME.postMessage(CONFIG.CHANGE_MESSAGE); // 通知内容显著变化
      }

      debounceTimeout = null;
    }, CONFIG.DEBOUNCE_DELAY);
  };

  // 监控DOM变化
  const observer = new MutationObserver(function(mutations) {
    let hasRelevantChanges = false;

    for (let i = 0; i < mutations.length; i++) {
      const mutation = mutations[i];
      if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
        for (let j = 0; j < mutation.addedNodes.length; j++) {
          const node = mutation.addedNodes[j];
          if (node.nodeType === 1 && CONFIG.MONITORED_TAGS.includes(node.tagName)) {
            hasRelevantChanges = true;
            break;
          }
        }
        if (hasRelevantChanges) break;
      }
    }

    if (hasRelevantChanges) {
      notifyContentChange();
    }
  });

  // 配置并启动DOM变化监控
  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: false,
    characterData: false
  });

  // 初始检查内容变化
  setTimeout(function() {
    const currentContentLength = document.body.innerHTML.length;
    const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;

    if (contentChangePct > CONFIG.SIGNIFICANT_CHANGE_PERCENT) {
      CONFIG.CHANNEL_NAME.postMessage(CONFIG.CHANGE_MESSAGE); // 通知初始内容显著变化
      lastContentLength = currentContentLength;
      lastNotificationTime = Date.now();
    }
  }, CONFIG.INITIAL_CHECK_DELAY);
})();
