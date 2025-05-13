/// 监控页面内容变化，检测显著变化后通过通道通知
(function() {
  // 记录初始页面内容长度
  const initialContentLength = document.body.innerHTML.length;
  // 定义内容变化阈值
  const SIGNIFICANT_CHANGE_PERCENT = 5.0;

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
      if (now - lastNotificationTime < 1000) {
        return;
      }

      const currentContentLength = document.body.innerHTML.length;
      const changePercent = Math.abs(currentContentLength - lastContentLength) / lastContentLength * 100;

      if (changePercent > SIGNIFICANT_CHANGE_PERCENT) {
        lastNotificationTime = now;
        lastContentLength = currentContentLength;
        %CHANNEL_NAME%.postMessage('CONTENT_CHANGED'); // 通知内容显著变化
      }

      debounceTimeout = null;
    }, 200);
  };

  // 监控DOM变化
  const observer = new MutationObserver(function(mutations) {
    let hasRelevantChanges = false;

    for (let i = 0; i < mutations.length; i++) {
      const mutation = mutations[i];
      if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
        for (let j = 0; j < mutation.addedNodes.length; j++) {
          const node = mutation.addedNodes[j];
          if (node.nodeType === 1 && (node.tagName === 'DIV' ||
                                      node.tagName === 'TABLE' ||
                                      node.tagName === 'UL' ||
                                      node.tagName === 'IFRAME')) {
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

    if (contentChangePct > SIGNIFICANT_CHANGE_PERCENT) {
      %CHANNEL_NAME%.postMessage('CONTENT_CHANGED'); // 通知初始内容显著变化
      lastContentLength = currentContentLength;
      lastNotificationTime = Date.now();
    }
  }, 1000);
})();
