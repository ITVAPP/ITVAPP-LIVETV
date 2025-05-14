// 监控DOM变化并发送通知
(function() {
  // 定义常量配置
  const CONFIG = {
    SIGNIFICANT_CHANGE_PERCENT: 5.0, // 内容变化阈值（%）
    DEBOUNCE_DELAY: 200, // 防抖延迟
    MIN_NOTIFICATION_INTERVAL: 300, // 最小通知间隔
    INITIAL_CHECK_DELAY: 800, // 初始检查延迟
    CHANNEL_NAME: '%CHANNEL_NAME%', // 通知通道名称
    MONITORED_TAGS: ['DIV', 'TABLE', 'UL', 'IFRAME'], // 监控的标签
    CHANGE_MESSAGE: 'CONTENT_CHANGED' // 通知消息内容
  };

  // 使用Set加速标签查找
  const MONITORED_TAGS_SET = new Set(CONFIG.MONITORED_TAGS);

  // 初始化BroadcastChannel
  let channel;
  try {
    channel = new BroadcastChannel(CONFIG.CHANNEL_NAME);
  } catch (e) {
    channel = null; // 通道不可用时置空
  }

  // 发送通知，优先使用BroadcastChannel，失败时用自定义事件
  const sendNotification = function(message) {
    try {
      if (channel) {
        channel.postMessage(message);
      } else {
        throw new Error('Channel not available');
      }
    } catch (e) {
      const event = new CustomEvent('content-change', { detail: { message } });
      document.dispatchEvent(event);
    }
  };

  // 记录状态
  let initialContentLength = 0; // 初始内容长度
  let lastNotificationTime = Date.now(); // 上次通知时间
  let lastContentLength = 0; // 上次内容长度
  let debounceTimeout = null; // 防抖定时器

  // 计算内容特征（标签数、子元素数、文本长度）
  const getContentSignature = function() {
    return {
      monitoredCount: document.querySelectorAll(CONFIG.MONITORED_TAGS.join(',')).length,
      elementCount: document.body.childElementCount,
      textLength: document.body.textContent?.length || 0
    };
  };

  // 计算内容变化百分比
  const getChangePercent = function(oldSig, newSig) {
    if (!oldSig || !newSig) return 100;
    const monitoredChange = Math.abs(newSig.monitoredCount - oldSig.monitoredCount) / Math.max(oldSig.monitoredCount, 1);
    const elementChange = Math.abs(newSig.elementCount - oldSig.elementCount) / Math.max(oldSig.elementCount, 1);
    const textChange = Math.abs(newSig.textLength - oldSig.textLength) / Math.max(oldSig.textLength, 1);
    return (monitoredChange * 0.5 + elementChange * 0.3 + textChange * 0.2) * 100;
  };

  // 记录最后内容特征
  let lastContentSignature = null;

  // 评估内容变化
  const evaluateContentChanges = function(mutations) {
    if (!hasRelevantTagChanges(mutations)) return 0;
    const currentSignature = getContentSignature();
    const changePercent = getChangePercent(lastContentSignature, currentSignature);
    lastContentSignature = currentSignature;
    return changePercent;
  };

  // 防抖处理内容变化通知
  const notifyContentChange = function(mutations) {
    if (debounceTimeout) clearTimeout(debounceTimeout);
    debounceTimeout = setTimeout(function() {
      const now = Date.now();
      if (now - lastNotificationTime < CONFIG.MIN_NOTIFICATION_INTERVAL) return;
      let changePercent = 0;
      if (mutations) {
        changePercent = evaluateContentChanges(mutations);
      } else {
        const currentContentLength = document.body.innerHTML.length;
        changePercent = Math.abs(currentContentLength - lastContentLength) / Math.max(lastContentLength, 1) * 100;
        lastContentLength = currentContentLength;
      }
      if (changePercent > CONFIG.SIGNIFICANT_CHANGE_PERCENT) {
        lastNotificationTime = now;
        sendNotification(CONFIG.CHANGE_MESSAGE);
      }
      debounceTimeout = null;
    }, CONFIG.DEBOUNCE_DELAY);
  };

  // 检查是否有相关标签变化
  const hasRelevantTagChanges = function(mutations) {
    for (let mutation of mutations) {
      if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
        for (let node of mutation.addedNodes) {
          if (node.nodeType === 1) {
            if (MONITORED_TAGS_SET.has(node.tagName)) return true;
            if (node.querySelector && CONFIG.MONITORED_TAGS.some(tag => node.querySelector(tag))) return true;
          }
        }
      }
    }
    return false;
  };

  // 清理资源
  const cleanup = function() {
    if (debounceTimeout) clearTimeout(debounceTimeout);
    if (channel) channel.close();
  };

  // 初始化监控
  const initialize = function() {
    initialContentLength = document.body.innerHTML.length;
    lastContentLength = initialContentLength;
    lastContentSignature = getContentSignature();
    const observer = new MutationObserver(notifyContentChange);
    observer.observe(document.body, { childList: true, subtree: true, attributes: false, characterData: false });
    setTimeout(function() {
      const currentContentLength = document.body.innerHTML.length;
      const contentChangePct = Math.abs(currentContentLength - initialContentLength) / Math.max(initialContentLength, 1) * 100;
      if (contentChangePct > CONFIG.SIGNIFICANT_CHANGE_PERCENT) {
        sendNotification(CONFIG.CHANGE_MESSAGE);
        lastContentLength = currentContentLength;
        lastNotificationTime = Date.now();
      }
    }, CONFIG.INITIAL_CHECK_DELAY);
    window.addEventListener('beforeunload', cleanup);
  };

  // 确保DOM加载后初始化
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
  } else {
    initialize();
  }
})();
