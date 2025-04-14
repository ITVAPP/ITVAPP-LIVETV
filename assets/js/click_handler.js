// 自动点击注入
(function() {
  // 避免重复初始化
  if (window._itvapp_click_initialized) return;
  window._itvapp_click_initialized = true;
  
  // 保存原始方法引用
  const _originalClickMethod = HTMLElement.prototype.click;
  
  try {
    function findAndClick() {
      // 使用占位符 SEARCH_TEXT 和 TARGET_INDEX，由Dart代码动态替换
      const searchText = 'SEARCH_TEXT';
      const targetIndex = parseInt('TARGET_INDEX') || 0;
      
      // 获取所有文本和元素节点
      const walk = document.createTreeWalker(
        document.body,
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
      
      // 检查是否找到匹配节点
      if (!foundNode) {
        // 优化：添加更详细的错误信息
        console.error(`未找到匹配的元素 "${searchText}"，或索引 ${targetIndex} 超出范围（共找到 ${matches.length} 个匹配）`);
        return;
      }
      
      // 尝试点击并验证效果
      safeClick(foundNode);
    }
    
    /**
     * 安全点击节点并验证点击效果
     * @param {Element} node - 要点击的节点
     */
    function safeClick(node) {
      try {
        // 记录原始类名用于后续对比
        const originalClass = node.getAttribute('class') || '';
        
        // 安全点击：使用原始click方法而不是直接调用node.click()
        console.info('正在点击目标节点...');
        if (node && typeof _originalClickMethod === 'function') {
          _originalClickMethod.call(node);
        } else {
          // 回退方案：如果无法获取原始click方法，使用dispatch事件
          const clickEvent = new MouseEvent('click', {
            view: window,
            bubbles: true,
            cancelable: true
          });
          node.dispatchEvent(clickEvent);
        }
        
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
            
            // 同样使用安全点击方法
            if (parentNode && typeof _originalClickMethod === 'function') {
              _originalClickMethod.call(parentNode);
            } else {
              const clickEvent = new MouseEvent('click', {
                view: window,
                bubbles: true,
                cancelable: true
              });
              parentNode.dispatchEvent(clickEvent);
            }
            
            // 检查父节点点击效果
            setTimeout(() => {
              const parentUpdatedClass = parentNode.getAttribute('class') || '';
              if (parentOriginalClass !== parentUpdatedClass) {
                console.info('父节点点击成功，class 发生变化');
              } else {
                console.info('点击操作完成，但未观察到明显的DOM变化');
              }
            }, 350);
          } else {
            console.info('点击操作完成，但未观察到明显的DOM变化');
          }
        }, 350);
      } catch (e) {
        console.error('点击操作失败:', e.message || e);
      }
    }
    
    // 使用微任务延迟执行，避免干扰页面初始加载
    setTimeout(() => {
      findAndClick();
    }, 50);
    
    // 清理函数
    window._cleanupITVAppClick = function() {
      delete window._itvapp_click_initialized;
      delete window._cleanupITVAppClick;
    };
  } catch (e) {
    console.error('JavaScript 执行时发生错误:', e.message || e.toString());
  }
})();
