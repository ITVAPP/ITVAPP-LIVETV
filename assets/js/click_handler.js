// 自动点击注入
(async function() {
  try {
    /**
     * 尝试点击节点并验证点击效果
     * @param {Element} node - 要点击的节点
     */
    function tryClickAndVerify(node) {
      try {
        // 记录原始类名用于后续对比
        const originalClass = node.getAttribute('class') || '';
        
        // 点击节点
        console.info('正在点击目标节点...');
        node.click();
        
        // 检查点击效果
        setTimeout(() => {
          const updatedClass = node.getAttribute('class') || '';
          
          if (originalClass !== updatedClass) {
            console.info('节点点击成功，class 发生变化');
          } else if (node.parentElement) {
            // 如目标节点点击无效，尝试点击父节点
            const parentNode = node.parentElement;
            const parentOriginalClass = parentNode.getAttribute('class') || '';
            
            console.info('节点点击无明显效果，尝试点击父节点...');
            parentNode.click();
            
            // 检查父节点点击效果
            setTimeout(() => {
              const parentUpdatedClass = parentNode.getAttribute('class') || '';
              if (parentOriginalClass !== parentUpdatedClass) {
                console.info('父节点点击成功，class 发生变化');
              } else {
                console.info('点击操作完成，但未观察到明显的DOM变化');
              }
            }, 500);
          } else {
            console.info('点击操作完成，但未观察到明显的DOM变化');
          }
        }, 500);
      } catch (e) {
        console.error('点击操作失败:', e.message || e);
      }
    }

    /**
     * 直接点击指定 ID 的元素
     * @param {string} id - 元素 ID
     */
    function clickById(id) {
      const element = document.getElementById(id);
      if (element) {
        console.info(`找到 ID 为 "${id}" 的元素，准备点击`);
        tryClickAndVerify(element);
      } else {
        console.error(`未找到 ID 为 "${id}" 的元素`);
      }
    }

    /**
     * 在指定范围内查找并点击包含特定文本的节点
     * @param {string} searchText - 要查找的文本
     * @param {string} targetIndex - 目标索引
     * @param {Element} scopeElement - 搜索范围（默认 document.body）
     * @returns {boolean} 是否找到并点击
     */
    function findAndClickByText(searchText, targetIndex, scopeElement = document.body) {
      const walk = document.createTreeWalker(
        scopeElement,
        NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
        {
          acceptNode: function(node) {
            // 过滤掉脚本和样式标签
            if (node.nodeType === Node.ELEMENT_NODE) {
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
            if (currentIndex === parseInt(targetIndex)) {
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
            if (currentIndex === parseInt(targetIndex)) {
              foundNode = node;
              break;
            }
            currentIndex++;
          }
        }
      }
      
      // 检查是否找到匹配节点
      if (!foundNode) {
        console.error(`在指定范围内未找到匹配的元素 "${searchText}"，索引 ${targetIndex}，共找到 ${matches.length} 个匹配`);
        return false;
      }
      
      tryClickAndVerify(foundNode);
      return true;
    }

    // 获取动态注入的参数
    const elementId = 'ELEMENT_ID';
    const searchText = 'SEARCH_TEXT';
    const targetIndex = 'TARGET_INDEX';

    if (elementId && elementId !== '' && searchText && searchText !== '') {
      // 优先在指定 ID 下查找 searchText
      console.info(`优先在 ID 为 "${elementId}" 下查找文本: ${searchText}, 索引: ${targetIndex}`);
      const scopeElement = document.getElementById(elementId);
      if (scopeElement) {
        if (!findAndClickByText(searchText, targetIndex, scopeElement)) {
          // 如果 ID 下未找到，回退到全局搜索
          console.info(`ID 为 "${elementId}" 下未找到文本 "${searchText}"，尝试全局搜索`);
          findAndClickByText(searchText, targetIndex);
        }
      } else {
        console.error(`未找到 ID 为 "${elementId}" 的元素，尝试全局搜索`);
        findAndClickByText(searchText, targetIndex);
      }
    } else if (elementId && elementId !== '') {
      // 仅指定 ID，直接点击
      console.info(`执行 ID 点击逻辑，目标 ID: ${elementId}`);
      clickById(elementId);
    } else if (searchText && searchText !== 'SEARCH_TEXT' && searchText !== '') {
      // 仅指定 searchText，全局搜索
      console.info(`执行全局文本点击逻辑，搜索文本: ${searchText}, 索引: ${targetIndex}`);
      findAndClickByText(searchText, targetIndex);
    } else {
      console.error('未提供有效的点击参数（elementId 或 searchText）');
    }
  } catch (e) {
    console.error('JavaScript 执行时发生错误:', e.message || e.toString());
  }
})();
