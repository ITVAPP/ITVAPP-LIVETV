(function() {
  console.log("注入DOM变化监听器");
  
  // 获取初始内容长度
  const initialContentLength = document.body.innerHTML.length;
  console.log("初始内容长度: " + initialContentLength);
  
  // 跟踪状态
  let lastNotificationTime = Date.now();
  let lastContentLength = initialContentLength;
  let debounceTimeout = null;
  
  // 优化的内容变化通知函数 - 使用防抖动减少不必要的通知
  const notifyContentChange = function() {
    if (debounceTimeout) {
      clearTimeout(debounceTimeout);
    }
    
    debounceTimeout = setTimeout(function() {
      const now = Date.now();
      // 检查距离上次通知的时间是否足够长
      if (now - lastNotificationTime < 1000) {
        return; // 忽略过于频繁的通知
      }
      
      // 获取当前内容长度
      const currentContentLength = document.body.innerHTML.length;
      
      // 计算内容变化百分比
      const changePercent = Math.abs(currentContentLength - lastContentLength) / lastContentLength * 100;
      
      // 只有变化超过阈值时才通知
      if (changePercent > {{SIGNIFICANT_CHANGE_PERCENT}}) {
        console.log("检测到显著内容变化: " + changePercent.toFixed(2) + "%");
        
        // 更新状态
        lastNotificationTime = now;
        lastContentLength = currentContentLength;
        
        // 通知应用内容变化
        {{CHANNEL_NAME}}.postMessage('CONTENT_CHANGED');
      }
      
      debounceTimeout = null;
    }, 200); // 200ms防抖动延迟
  };
  
  // 创建性能优化的MutationObserver
  const observer = new MutationObserver(function(mutations) {
    // 快速检查是否有相关变化
    let hasRelevantChanges = false;
    
    // 只检查有意义的变化
    for (let i = 0; i < mutations.length; i++) {
      const mutation = mutations[i];
      
      // 检查是否为内容或结构变化
      if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
        // 检查添加的节点是否包含实质性内容
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
    
    // 只有检测到相关变化时才触发通知
    if (hasRelevantChanges) {
      notifyContentChange();
    }
  });
  
  // 配置观察者 - 只观察必要的变化
  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: false,
    characterData: false
  });
  
  // 页面加载后延迟检查一次内容
  setTimeout(function() {
    const currentContentLength = document.body.innerHTML.length;
    const contentChangePct = Math.abs(currentContentLength - initialContentLength) / initialContentLength * 100;
    console.log("延迟检查内容变化百分比: " + contentChangePct.toFixed(2) + "%");
    
    if (contentChangePct > {{SIGNIFICANT_CHANGE_PERCENT}}) {
      console.log("延迟检测到显著内容变化");
      {{CHANNEL_NAME}}.postMessage('CONTENT_CHANGED');
      lastContentLength = currentContentLength;
      lastNotificationTime = Date.now();
    }
  }, 1000);
})();
