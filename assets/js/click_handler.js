(function() {
  // Search text and index will be replaced dynamically
  const searchText = "";
  const targetIndex = 0;
  
  function findAndClick() {
    // 获取所有文本和元素节点 (保留原逻辑)
    const walk = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
      {
        acceptNode: function(node) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
              return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
          if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
            return NodeFilter.FILTER_ACCEPT;
          }
          return NodeFilter.FILTER_REJECT;
        }
      }
    );

    // 保留原有匹配逻辑
    const matches = [];
    let currentIndex = 0;
    let foundNode = null;

    // 遍历节点 (保留原逻辑)
    let node;
    while (node = walk.nextNode()) {
      // 处理文本节点
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent.trim();
        if (text === searchText) {
          matches.push({
            text: text,
            node: node.parentElement
          });

          if (currentIndex === targetIndex) {
            foundNode = node.parentElement;
            break;
          }
          currentIndex++;
        }
      }
      // 处理元素节点
      else if (node.nodeType === Node.ELEMENT_NODE) {
        const children = Array.from(node.childNodes);
        const directText = children
          .filter(child => child.nodeType === Node.TEXT_NODE)
          .map(child => child.textContent.trim())
          .join('');

        if (directText === searchText) {
          matches.push({
            text: directText,
            node: node
          });

          if (currentIndex === targetIndex) {
            foundNode = node;
            break;
          }
          currentIndex++;
        }
      }
    }

    if (!foundNode) {
      console.error('未找到匹配的元素');
      return;
    }

    // 优化点击检测部分
    try {
      // 记录多个状态变量用于检测
      const originalClass = foundNode.getAttribute('class') || '';
      const originalStyle = foundNode.getAttribute('style') || '';
      const originalDisplay = window.getComputedStyle(foundNode).display;
      const originalVisibility = window.getComputedStyle(foundNode).visibility;
      const videoCountBefore = document.querySelectorAll('video').length;
      const iframeBefore = document.querySelectorAll('iframe').length;
      
      // 执行点击
      foundNode.click();
      
      // 等待检测变化
      setTimeout(() => {
        // 检查多种可能的变化
        const newClass = foundNode.getAttribute('class') || '';
        const newStyle = foundNode.getAttribute('style') || '';
        const newDisplay = window.getComputedStyle(foundNode).display;
        const newVisibility = window.getComputedStyle(foundNode).visibility;
        const videoCountAfter = document.querySelectorAll('video').length;
        const iframeAfter = document.querySelectorAll('iframe').length;
        
        const hasClassChange = originalClass !== newClass;
        const hasStyleChange = originalStyle !== newStyle;
        const hasDisplayChange = originalDisplay !== newDisplay;
        const hasVisibilityChange = originalVisibility !== newVisibility;
        const hasNewVideo = videoCountAfter > videoCountBefore;
        const hasNewIframe = iframeAfter > iframeBefore;
        
        let successMessage = '';
        
        if (hasClassChange) successMessage = '节点点击成功，class发生变化';
        else if (hasStyleChange) successMessage = '节点点击成功，style发生变化';
        else if (hasDisplayChange || hasVisibilityChange) successMessage = '节点点击成功，显示状态发生变化';
        else if (hasNewVideo) successMessage = '节点点击成功，新video元素出现';
        else if (hasNewIframe) successMessage = '节点点击成功，新iframe元素出现';
        
        if (successMessage) {
          console.info(successMessage);
          return;
        }
        
        // 如果节点自身点击没有明显变化，尝试父节点
        if (foundNode.parentElement) {
          // 复用相同的点击检测策略，但针对父节点
          const parent = foundNode.parentElement;
          const parentOriginalClass = parent.getAttribute('class') || '';
          const parentOriginalStyle = parent.getAttribute('style') || '';
          
          parent.click();
          
          setTimeout(() => {
            const parentNewClass = parent.getAttribute('class') || '';
            const parentNewStyle = parent.getAttribute('style') || '';
            const videoCountAfterParent = document.querySelectorAll('video').length;
            
            if (parentOriginalClass !== parentNewClass) {
              console.info('父节点点击成功，class发生变化');
            } else if (parentOriginalStyle !== parentNewStyle) {
              console.info('父节点点击成功，style发生变化');
            } else if (videoCountAfterParent > videoCountAfter) {
              console.info('父节点点击成功，新video元素出现');
            } else {
              console.info('点击操作完成，但未检测到明显变化');
            }
          }, 500);
        } else {
          console.info('点击操作完成，但未检测到明显变化');
        }
      }, 500);
    } catch (e) {
      console.error('点击操作失败:', e);
    }
  }

  // Execute click operation
  findAndClick();
})();
