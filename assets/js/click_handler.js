// 自动点击器：查找并点击页面中匹配特定文本的元素 
(function() {
  // 搜索目标文本
  const searchText = "";
  // 目标匹配项索引
  const targetIndex = 0;
  
  // 创建消息发送函数，记录点击日志
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
  
  /**
   * 查找元素通用函数，支持ID和Class选择器
   * @param {string} selector - 选择器（去掉click-前缀）
   * @param {string} [textFilter] - 可选的文本过滤条件
   * @returns {HTMLElement[]} 匹配的元素数组
   */
  function findElementsBySelector(selector, textFilter = '') {
    // 记录查找模式
    sendClickLog('info', textFilter ? 
      `使用选择器+文本过滤模式` : 
      `使用纯选择器模式`, 
      { selector, textFilter });
    
    // 验证选择器有效性
    if (!selector) {
      sendClickLog('error', '选择器为空');
      console.error('选择器为空');
      return [];
    }
    
    // 查找ID和Class匹配元素
    const idElements = document.querySelectorAll(`#${selector}`);
    const classElements = document.querySelectorAll(`.${selector}`);
    
    // 合并查找到的元素
    let elements = [...Array.from(idElements), ...Array.from(classElements)];
    
    // 检查是否找到元素
    if (elements.length === 0) {
      sendClickLog('error', `未找到ID或Class为"${selector}"的元素`);
      console.error(`未找到ID或Class为"${selector}"的元素`);
      return [];
    }
    
    // 记录找到的元素数量
    sendClickLog('info', `找到${elements.length}个匹配选择器的元素`);
    
    // 根据文本过滤元素
    if (textFilter) {
      elements = elements.filter(el => {
        // 获取元素文本内容
        const elementText = el.textContent.trim();
        // 检查是否包含过滤文本
        return elementText.includes(textFilter);
      });
      
      // 检查过滤后结果
      if (elements.length === 0) {
        sendClickLog('error', `未找到ID或Class为"${selector}"且包含文字"${textFilter}"的元素`);
        console.error(`未找到ID或Class为"${selector}"且包含文字"${textFilter}"的元素`);
        return [];
      }
      
      // 记录过滤后元素数量
      sendClickLog('info', `过滤后剩余${elements.length}个元素`);
    }
    
    return elements;
  }
  
  /**
   * 点击元素前的验证和执行
   * @param {HTMLElement[]} elements - 匹配的元素数组
   * @param {number} targetIndex - 目标索引
   */
  function validateAndClickElement(elements, targetIndex) {
    // 验证目标索引是否有效
    if (targetIndex >= elements.length) {
      sendClickLog('error', `找到${elements.length}个匹配元素，但目标索引${targetIndex}超出范围`);
      console.error(`找到${elements.length}个匹配元素，但目标索引${targetIndex}超出范围`);
      return;
    }
    
    // 记录即将点击的元素信息
    sendClickLog('success', `即将点击第${targetIndex}个元素`, {
      tagName: elements[targetIndex].tagName,
      id: elements[targetIndex].id,
      className: elements[targetIndex].className
    });
    
    // 执行点击并检测变化
    clickAndDetectChanges(elements[targetIndex]);
  }
  
  // 查找并点击匹配文本的节点
  function findAndClick() {
    // 记录查找开始
    sendClickLog('start', '开始查找点击目标', { searchText, targetIndex });
    
    // 验证搜索文本
    if (searchText === undefined || searchText === null) {
      sendClickLog('error', '搜索文本未定义');
      console.error('搜索文本未定义');
      return;
    }
    
    // 验证目标索引
    if (typeof targetIndex !== 'number' || targetIndex < 0) {
      sendClickLog('error', '目标索引无效，应为非负整数');
      console.error('目标索引无效，应为非负整数');
      return;
    }
    
    // 处理特殊选择器模式
    if (searchText.startsWith('click-')) {
      // 处理双@格式
      if (searchText.split('@').length >= 3) {
        const parts = searchText.split('@');
        const attributeName = parts[0].substring(6); // 获取属性名
        const attributeValue = parts[1]; // 获取属性值
        const textContent = parts[2]; // 获取文本内容
        
        // 记录查找模式
        sendClickLog('info', `使用${attributeName}+文本过滤模式`, { 
          [attributeName]: attributeValue, 
          textFilter: textContent 
        });
        
        // 查找匹配属性的元素
        const elements = document.querySelectorAll(`[${attributeName}="${attributeValue}"]`);
        
        // 检查是否找到元素
        if (elements.length === 0) {
          sendClickLog('error', `未找到${attributeName}为"${attributeValue}"的元素`);
          console.error(`未找到${attributeName}为"${attributeValue}"的元素`);
          return;
        }
        
        // 记录找到的元素数量
        sendClickLog('info', `找到${elements.length}个匹配${attributeName}的元素`);
        
        // 过滤包含目标文本的元素
        const matchingElements = Array.from(elements).filter(el => 
          el.textContent.includes(textContent)
        );
        
        // 检查过滤后结果
        if (matchingElements.length === 0) {
          sendClickLog('error', `未找到${attributeName}为"${attributeValue}"且包含文字"${textContent}"的元素`);
          console.error(`未找到${attributeName}为"${attributeValue}"且包含文字"${textContent}"的元素`);
          return;
        }
        
        // 记录过滤后元素数量
        sendClickLog('info', `过滤后剩余${matchingElements.length}个元素`);
        
        // 执行点击验证
        validateAndClickElement(matchingElements, targetIndex);
        return;
      } 
      // 处理单@或无@格式
      else {
        if (searchText.includes('@')) {
          // 单@格式: click-xxx@text
          const parts = searchText.split('@');
          const selector = parts[0].substring(6); // 获取选择器
          const textFilter = parts[1] || '';
          
          // 查找并点击元素
          const elements = findElementsBySelector(selector, textFilter);
          if (elements.length > 0) {
            validateAndClickElement(elements, targetIndex);
          }
          return;
        } else {
          // 无@格式: click-xxx
          const selector = searchText.substring(6); // 获取选择器
          
          // 查找并点击元素
          const elements = findElementsBySelector(selector);
          if (elements.length > 0) {
            validateAndClickElement(elements, targetIndex);
          }
          return;
        }
      }
    }
    
    // 配置DOM树遍历器
    const walk = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
      {
        // 筛选节点以优化遍历
        acceptNode: function(node) {
          // 排除无关元素节点
          if (node.nodeType === Node.ELEMENT_NODE) {
            if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
              return NodeFilter.FILTER_REJECT;
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

    let currentIndex = 0; // 跟踪匹配索引
    let node;
    
    // 记录DOM树遍历开始
    sendClickLog('info', '开始遍历DOM树查找文本节点');
    
    // 遍历查找目标文本
    while ((node = walk.nextNode())) {
      let matchFound = false;
      let targetNode = null;
      
      // 检查文本节点匹配
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent.trim();
        if (text === searchText) {
          matchFound = true;
          targetNode = node.parentElement; // 获取父元素
          sendClickLog('info', `在文本节点中找到匹配: "${text}"`);
        }
      }
      // 检查元素节点子文本匹配
      else if (node.nodeType === Node.ELEMENT_NODE) {
        const children = Array.from(node.childNodes);
        const directText = children
          .filter(child => child.nodeType === Node.TEXT_NODE)
          .map(child => child.textContent.trim())
          .join('');
        if (directText === searchText) {
          matchFound = true;
          targetNode = node; // 使用匹配元素
          sendClickLog('info', `在元素节点直接子文本中找到匹配: "${directText}"`);
        }
      }
      
      // 处理匹配结果
      if (matchFound) {
        if (currentIndex === targetIndex) {
          // 记录找到目标
          sendClickLog('success', `找到目标匹配项(索引:${currentIndex})`, {
            nodeType: targetNode.nodeType,
            tagName: targetNode.tagName,
            id: targetNode.id,
            className: targetNode.className
          });
          // 点击目标节点
          clickAndDetectChanges(targetNode);
          return;
        }
        // 记录非目标匹配
        sendClickLog('info', `找到匹配项，但索引不符(当前:${currentIndex}, 目标:${targetIndex})`);
        currentIndex++;
      }
    }

    // 记录未找到匹配
    sendClickLog('error', `未找到匹配"${searchText}"的元素（索引：${targetIndex}）`);
    console.error(`未找到匹配"${searchText}"的元素（索引：${targetIndex}）`);
  }

  /**
   * 获取节点状态
   * @param {HTMLElement} node - 目标节点
   * @return {Object} 节点状态对象
   */
  function getNodeState(node) {
    // 获取节点计算样式
    const computedStyle = window.getComputedStyle(node);
    
    return {
      class: node.getAttribute('class') || '', // 节点类名
      style: node.getAttribute('style') || '', // 内联样式
      display: computedStyle.display, // 显示状态
      visibility: computedStyle.visibility, // 可见性
      videoCount: document.querySelectorAll('video').length, // 视频元素数
      iframeCount: document.querySelectorAll('iframe').length // iframe元素数
    };
  }

  /**
   * 执行点击并检测状态变化
   * @param {HTMLElement} node - 目标节点
   * @param {boolean} isParentNode - 是否为父节点
   */
  function clickAndDetectChanges(node, isParentNode = false) {
    try {
      // 记录点击前状态
      const states = getNodeState(node);
      
      // 记录点击操作
      sendClickLog('click', `即将点击${isParentNode ? '父' : ''}节点`, {
        tagName: node.tagName,
        id: node.id,
        className: node.className
      });
      
      // 执行点击
      node.click();
      
      // 延迟检测变化
      setTimeout(() => {
        // 获取点击后状态
        const newStates = getNodeState(node);
        
        // 确定节点类型
        const nodeType = isParentNode ? '父节点' : '节点';
        
        // 检查状态变化
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
          // 尝试点击父节点
          sendClickLog('info', `${nodeType}点击未检测到变化，尝试点击父节点`);
          clickAndDetectChanges(node.parentElement, true);
        } else {
          // 记录无明显变化
          sendClickLog('info', '点击操作完成，但未检测到明显变化');
          console.info('点击操作完成，但未检测到明显变化');
        }
      }, 500);
    } catch (e) {
      // 记录点击异常
      sendClickLog('error', `${isParentNode ? '父' : ''}节点点击操作失败`, { error: e.toString() });
      console.error(`${isParentNode ? '父' : ''}节点点击操作失败:`, e);
    }
  }

  // 启动自动点击
  findAndClick();
})();
