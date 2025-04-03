// 修改代码开始
(async function() {
  try {
    // 检查 class 是否发生变化的工具函数
    function checkClassChange(element, originalClass, delay = 500) {
      return new Promise(resolve => {
        setTimeout(() => {
          const updatedClass = element.getAttribute('class') || '';
          resolve(originalClass !== updatedClass);
        }, delay);
      });
    }

    function findAndClick() {
      // 使用占位符 SEARCH_TEXT 和 TARGET_INDEX，由Dart代码动态替换
      const searchText = 'SEARCH_TEXT';
      const targetIndex = TARGET_INDEX;

      // 获取所有文本和元素节点，优化过滤无关节点
      const walk = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
        {
          acceptNode: function(node) {
            if (node.nodeType === Node.ELEMENT_NODE) {
              // 跳过无关标签，提高遍历效率
              if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
                return NodeFilter.FILTER_REJECT;
              }
              return NodeFilter.FILTER_ACCEPT;
            }
            // 只接受非空文本节点
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

      // 遍历节点寻找匹配文本
      let node;
      while (node = walk.nextNode()) {
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
        } else if (node.nodeType === Node.ELEMENT_NODE) {
          const children = Array.from(node.childNodes);
          // 提前检查是否有文本子节点，避免不必要拼接
          const hasText = children.some(child => child.nodeType === Node.TEXT_NODE && child.textContent.trim());
          if (hasText) {
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
      }

      // 未找到目标节点时记录错误并退出
      if (!foundNode) {
        console.error('未找到匹配的元素');
        return;
      }

      try {
        // 获取原始 class 并尝试点击目标节点
        const originalClass = foundNode.getAttribute('class') || '';
        foundNode.click();

        // 检查点击后 class 是否变化，等待时间可配置（默认 500ms）
        checkClassChange(foundNode, originalClass, 500).then(changed => {
          if (changed) {
            console.info('节点点击成功，class 发生变化');
          } else if (foundNode.parentElement) {
            // 若点击无效，尝试点击父节点
            foundNode.parentElement.click();
            // 此处不再验证父节点点击结果，符合你的要求
          }
        });
      } catch (e) {
        console.error('点击操作失败:', e);
      }
    }

    findAndClick();
  } catch (e) {
    console.error('JavaScript 执行时发生错误:', e);
  }
})();
// 修改代码结束
