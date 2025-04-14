/**
 * Click Handler Script
 * Finds and clicks elements with specific text content
 */
(function() {
  // Search text and index will be replaced dynamically
  const searchText = "";
  const targetIndex = 0;
  
  function findAndClick() {
    // 获取所有文本和元素节点
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

    // 记录找到的匹配
    const matches = [];
    let currentIndex = 0;
    let foundNode = null;

    // 遍历节点
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

    try {
      // 优先点击节点本身
      const originalClass = foundNode.getAttribute('class') || '';
      foundNode.click();

      // 等待 500ms 检查 class 是否发生变化
      setTimeout(() => {
        const updatedClass = foundNode.getAttribute('class') || '';
        if (originalClass !== updatedClass) {
          console.info('节点点击成功，class 发生变化');
        } else if (foundNode.parentElement) {
          // 尝试点击父节点
          const parentOriginalClass = foundNode.parentElement.getAttribute('class') || '';
          foundNode.parentElement.click();

          setTimeout(() => {
            const parentUpdatedClass = foundNode.parentElement.getAttribute('class') || '';
            if (parentOriginalClass !== parentUpdatedClass) {
              console.info('父节点点击成功，class 发生变化');
            } 
          }, 500);
        } 
      }, 500);
    } catch (e) {
      console.error('点击操作失败:', e);
    }
  }

  // Execute click operation
  findAndClick();
})();
