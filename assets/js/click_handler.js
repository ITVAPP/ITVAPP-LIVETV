// 自动点击器
// 修改代码开始
// 自动点击器
(function() {
  // Search text and index will be replaced dynamically
  const searchText = ""; // 搜索目标文本
  const targetIndex = 0; // 目标匹配项索引
  
  function findAndClick() {
    // 参数验证
    if (searchText === undefined || searchText === null) {
      console.error('搜索文本未定义');
      return;
    }
    
    // 验证目标索引是否有效
    if (typeof targetIndex !== 'number' || targetIndex < 0) {
      console.error('目标索引无效，应为非负整数');
      return;
    }
    
    // 创建树遍历器，筛选文本和元素节点
    const walk = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
      {
        acceptNode: function(node) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            // 排除脚本、样式等无关元素
            if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
              return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
          // 接受非空文本节点
          if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
            return NodeFilter.FILTER_ACCEPT;
          }
          return NodeFilter.FILTER_REJECT;
        }
      }
    );

    // 存储匹配结果
    const matches = [];
    let currentIndex = 0; // 当前匹配索引
    let foundNode = null; // 目标节点

    // 遍历节点
    let node;
    while ((node = walk.nextNode())) {
      // 处理文本节点
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent.trim();
        if (text === searchText) {
          // 记录匹配的文本和父元素
          matches.push({
            text: text,
            node: node.parentElement
          });

          // 找到目标索引的节点
          if (currentIndex === targetIndex) {
            foundNode = node.parentElement;
            break;
          }
          currentIndex++;
        }
      }
      // 处理元素节点
      else if (node.nodeType === Node.ELEMENT_NODE) {
        // 获取直接子文本内容
        const children = Array.from(node.childNodes);
        const directText = children
          .filter(child => child.nodeType === Node.TEXT_NODE)
          .map(child => child.textContent.trim())
          .join('');

        if (directText === searchText) {
          // 记录匹配的元素
          matches.push({
            text: directText,
            node: node
          });

          // 找到目标索引的节点
          if (currentIndex === targetIndex) {
            foundNode = node;
            break;
          }
          currentIndex++;
        }
      }
    }

    // 未找到目标节点时提示
    if (!foundNode) {
      console.error(`未找到匹配"${searchText}"的元素（索引：${targetIndex}）`);
      return;
    }

    // 执行点击并检测变化
    clickAndDetectChanges(foundNode);
  }

  /**
   * 获取节点当前状态
   * @param {HTMLElement} node - 要检查的节点
   * @return {Object} 包含节点各项状态的对象
   */
  function getNodeState(node) {
    return {
      class: node.getAttribute('class') || '', // 节点类名
      style: node.getAttribute('style') || '', // 节点内联样式
      display: window.getComputedStyle(node).display, // 显示状态
      visibility: window.getComputedStyle(node).visibility, // 可见性
      videoCount: document.querySelectorAll('video').length, // 视频元素数量
      iframeCount: document.querySelectorAll('iframe').length // iframe元素数量
    };
  }

  /**
   * 执行点击并检测状态变化
   * @param {HTMLElement} node - 要点击的节点
   * @param {boolean} isParentNode - 是否为父节点点击
   */
  function clickAndDetectChanges(node, isParentNode = false) {
    try {
      // 记录点击前状态
      const states = getNodeState(node);
      
      // 执行点击
      node.click();
      
      // 延迟检测状态变化
      setTimeout(() => {
        // 获取点击后状态
        const newStates = getNodeState(node);
        
        // 确定节点类型描述
        const nodeType = isParentNode ? '父节点' : '节点';
        
        // 检查状态变化并输出结果
        if (states.class !== newStates.class) {
          console.info(`${nodeType}点击成功，class发生变化`);
        } else if (states.style !== newStates.style) {
          console.info(`${nodeType}点击成功，style发生变化`);
        } else if (states.display !== newStates.display || states.visibility !== newStates.visibility) {
          console.info(`${nodeType}点击成功，显示状态发生变化`);
        } else if (newStates.videoCount > states.videoCount) {
          console.info(`${nodeType}点击成功，新video元素出现`);
        } else if (newStates.iframeCount > states.iframeCount) {
          console.info(`${nodeType}点击成功，新iframe元素出现`);
        } else if (!isParentNode && node.parentElement) {
          // 尝试点击父节点
          clickAndDetectChanges(node.parentElement, true);
        } else {
          console.info('点击操作完成，但未检测到明显变化');
        }
      }, 500);
    } catch (e) {
      // 输出点击失败信息
      console.error(`${isParentNode ? '父' : ''}节点点击操作失败:`, e);
    }
  }

  // 启动自动点击
  findAndClick();
})();
// 修改代码结束
