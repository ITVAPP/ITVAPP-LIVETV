// 自动点击器：查找并点击页面中匹配特定文本的元素
(function() {
  // 搜索目标文本
  const searchText = "";
  // 目标匹配项索引
  const targetIndex = 0;
  
  // 创建消息发送函数
  function sendClickLog(type, message, details = {}) {
    if (window.ClickHandler) {
      try {
        window.ClickHandler.postMessage(JSON.stringify({
          type: type,
          message: message,
          details: details,
          time: new Date().toISOString()
        }));
      } catch (e) {
        console.error('发送点击日志失败:', e);
      }
    }
  }
  
  // 查找并点击匹配文本的节点
  function findAndClick() {
    // 开始查找记录
    sendClickLog('start', '开始查找点击目标', { searchText, targetIndex });
    
    // 验证搜索文本是否有效
    if (searchText === undefined || searchText === null) {
      sendClickLog('error', '搜索文本未定义');
      console.error('搜索文本未定义');
      return;
    }
    
    // 验证目标索引是否为非负整数
    if (typeof targetIndex !== 'number' || targetIndex < 0) {
      sendClickLog('error', '目标索引无效，应为非负整数');
      console.error('目标索引无效，应为非负整数');
      return;
    }
    
    // 处理特殊选择器模式: click-xxx@值@文本
    if (searchText.startsWith('click-')) {
      // 修改部分开始: 支持更灵活的属性选择器
      if (searchText.split('@').length >= 3) {
        const parts = searchText.split('@');
        const attributeName = parts[0].substring(6); // 去掉"click-"前缀，获取属性名
        const attributeValue = parts[1]; // 属性值，可能为空字符串
        const textContent = parts[2]; // 要查找的文本内容
        
        sendClickLog('info', `使用${attributeName}+文本过滤模式`, { 
          [attributeName]: attributeValue, 
          textFilter: textContent 
        });
        
        // 动态构建选择器，支持任意属性名
        const elements = document.querySelectorAll(`[${attributeName}="${attributeValue}"]`);
        
        if (elements.length === 0) {
          sendClickLog('error', `未找到${attributeName}为"${attributeValue}"的元素`);
          console.error(`未找到${attributeName}为"${attributeValue}"的元素`);
          return;
        }
        
        sendClickLog('info', `找到${elements.length}个匹配${attributeName}的元素`);
        
        // 过滤出同时包含目标文本的元素
        const matchingElements = Array.from(elements).filter(el => 
          el.textContent.includes(textContent)
        );
        
        if (matchingElements.length === 0) {
          sendClickLog('error', `未找到${attributeName}为"${attributeValue}"且包含文字"${textContent}"的元素`);
          console.error(`未找到${attributeName}为"${attributeValue}"且包含文字"${textContent}"的元素`);
          return;
        }
        
        sendClickLog('info', `过滤后剩余${matchingElements.length}个元素`);
        
        // 检查是否有足够的元素匹配目标索引
        if (targetIndex >= matchingElements.length) {
          sendClickLog('error', `找到${matchingElements.length}个匹配元素，但目标索引${targetIndex}超出范围`);
          console.error(`找到${matchingElements.length}个匹配元素，但目标索引${targetIndex}超出范围`);
          return;
        }
        
        // 点击目标索引位置的元素
        sendClickLog('success', `即将点击第${targetIndex}个元素`, {
          tagName: matchingElements[targetIndex].tagName,
          id: matchingElements[targetIndex].id,
          className: matchingElements[targetIndex].className
        });
        
        clickAndDetectChanges(matchingElements[targetIndex]);
        return;
      } else {
        // 不符合双@格式要求
        sendClickLog('error', `无效的点击命令格式，需要双@格式 (如 click-data-gid@值@文本 或 click-data-type@@文本)`);
        console.error(`无效的点击命令格式，需要双@格式 (如 click-data-gid@值@文本 或 click-data-type@@文本)`);
        return;
      }
      // 修改部分结束
    }
    
    // 配置树遍历器，筛选文本和元素节点
    const walk = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
      {
        // 筛选节点，优化遍历效率
        acceptNode: function(node) {
          // 处理元素节点，排除无关标签
          if (node.nodeType === Node.ELEMENT_NODE) {
            if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
              return NodeFilter.FILTER_REJECT; // 跳过脚本、样式等子树
            }
            return NodeFilter.FILTER_ACCEPT;
          }
          
          // 仅接受非空文本节点
          if (node.nodeType === Node.TEXT_NODE) {
            return node.textContent.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
          }
          
          return NodeFilter.FILTER_SKIP;
        }
      }
    );

    let currentIndex = 0; // 跟踪当前匹配索引
    let node;
    
    sendClickLog('info', '开始遍历DOM树查找文本节点');
    
    // 遍历节点，查找目标文本
    while ((node = walk.nextNode())) {
      let matchFound = false;
      let targetNode = null;
      
      // 检查文本节点是否匹配
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent.trim();
        if (text === searchText) {
          matchFound = true;
          targetNode = node.parentElement; // 获取文本节点的父元素
          sendClickLog('info', `在文本节点中找到匹配: "${text}"`);
        }
      }
      // 检查元素节点的直接子文本是否匹配
      else if (node.nodeType === Node.ELEMENT_NODE) {
        const children = Array.from(node.childNodes);
        const directText = children
          .filter(child => child.nodeType === Node.TEXT_NODE)
          .map(child => child.textContent.trim())
          .join('');
        if (directText === searchText) {
          matchFound = true;
          targetNode = node; // 直接使用匹配的元素
          sendClickLog('info', `在元素节点直接子文本中找到匹配: "${directText}"`);
        }
      }
      
      // 处理匹配结果
      if (matchFound) {
        if (currentIndex === targetIndex) {
          sendClickLog('success', `找到目标匹配项(索引:${currentIndex})`, {
            nodeType: targetNode.nodeType,
            tagName: targetNode.tagName,
            id: targetNode.id,
            className: targetNode.className
          });
          clickAndDetectChanges(targetNode); // 点击目标节点
          return;
        }
        sendClickLog('info', `找到匹配项，但索引不符(当前:${currentIndex}, 目标:${targetIndex})`);
        currentIndex++;
      }
    }

    // 未找到匹配项时输出提示
    sendClickLog('error', `未找到匹配"${searchText}"的元素（索引：${targetIndex}）`);
    console.error(`未找到匹配"${searchText}"的元素（索引：${targetIndex}）`);
  }

  /**
   * 获取节点当前状态
   * @param {HTMLElement} node - 要检查的节点
   * @return {Object} 包含节点各项状态的对象
   */
  function getNodeState(node) {
    // 获取节点样式和页面状态
    const computedStyle = window.getComputedStyle(node);
    
    return {
      class: node.getAttribute('class') || '', // 节点类名
      style: node.getAttribute('style') || '', // 内联样式
      display: computedStyle.display, // 显示状态
      visibility: computedStyle.visibility, // 可见性
      videoCount: document.querySelectorAll('video').length, // 视频元素数量
      iframeCount: document.querySelectorAll('iframe').length // iframe元素数量
    };
  }

  // 执行点击并检测状态变化
  function clickAndDetectChanges(node, isParentNode = false) {
    try {
      const states = getNodeState(node);
      
      sendClickLog('click', `即将点击${isParentNode ? '父' : ''}节点`, {
        tagName: node.tagName,
        id: node.id,
        className: node.className
      });
      
      // 模拟点击操作
      node.click();
      
      // 延迟检查状态变化
      setTimeout(() => {
        // 获取点击后的节点状态
        const newStates = getNodeState(node);
        
        // 确定节点类型描述
        const nodeType = isParentNode ? '父节点' : '节点';
        
        // 检测并报告状态变化
        if (states.class !== newStates.class) {
          sendClickLog('success', `${nodeType}点击成功，class发生变化`);
          console.info(`${nodeType}点击成功，class发生变化`);
        } else if (states.style !== newStates.style) {
          sendClickLog('success', `${nodeType}点击成功，style发生变化`);
          console.info(`${nodeType}点击成功，style发生变化`);
        } else if (states.display !== newStates.display || states.visibility !== newStates.visibility) {
          sendClickLog('success', `${nodeType}点击成功，显示状态发生变化`);
          console.info(`${nodeType}点击成功，显示状态发生变化`);
        } else if (newStates.videoCount > states.videoCount) {
          sendClickLog('success', `${nodeType}点击成功，新video元素出现`);
          console.info(`${nodeType}点击成功，新video元素出现`);
        } else if (newStates.iframeCount > states.iframeCount) {
          sendClickLog('success', `${nodeType}点击成功，新iframe元素出现`);
          console.info(`${nodeType}点击成功，新iframe元素出现`);
        } else if (!isParentNode && node.parentElement) {
          sendClickLog('info', `${nodeType}点击未检测到变化，尝试点击父节点`);
          // 尝试点击父节点
          clickAndDetectChanges(node.parentElement, true);
        } else {
          sendClickLog('info', '点击操作完成，但未检测到明显变化');
          console.info('点击操作完成，但未检测到明显变化');
        }
      }, 500);
    } catch (e) {
      sendClickLog('error', `${isParentNode ? '父' : ''}节点点击操作失败`, { error: e.toString() });
      console.error(`${isParentNode ? '父' : ''}节点点击操作失败:`, e);
    }
  }

  // 启动自动点击功能
  findAndClick();
})();
