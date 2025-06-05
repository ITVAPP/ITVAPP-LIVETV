(function() {
  // 查找并点击匹配文本的页面元素
  const searchText = ""; // 目标搜索文本
  const targetIndex = 0; // 目标匹配项索引
  
  // 获取元素文本预览（截断至maxLength）
  function getElementTextPreview(element, maxLength = 50) {
    if (!element || !element.textContent) return '';
    return element.textContent.trim().substring(0, maxLength);
  }
  
  // 提取元素基本信息（标签、ID、类、文本）
  function getElementInfo(element, includeText = true, textLength = 50) {
    if (!element) return null;
    
    const info = {
      tagName: element.tagName,
      id: element.id || '',
      className: element.className || ''
    };
    
    if (includeText) {
      info.textPreview = getElementTextPreview(element, textLength);
    }
    
    return info;
  }
  
  // 批量获取元素信息（最多maxCount个）
  function getElementsInfo(elements, maxCount = 3, includeText = true) {
    return elements.slice(0, maxCount).map(el => getElementInfo(el, includeText));
  }
  
  // 发送点击日志
  function sendClickLog(type, message, details = {}) {
    if (window.ClickHandler) {
      try {
        window.ClickHandler.postMessage(JSON.stringify({
          type,
          message,
          details,
          time: new Date().toISOString()
        }));
      } catch (e) {}
    }
  }
  
  // 查找元素（支持ID、Class、文本过滤）- 优化版
  function findElementsBySelector(selector, textFilter = '') {
    if (!selector) {
      return [];
    }
    
    // 直接使用NodeList，避免不必要的Array.from转换
    const nodeList = document.querySelectorAll(`#${selector}, .${selector}`);
    
    if (!textFilter) {
      // 如果没有文本过滤，直接返回NodeList转数组
      const elements = Array.from(nodeList);
      if (elements.length === 0) {
        sendClickLog('error', '未找到元素');
      }
      return elements;
    }
    
    // 只在需要文本过滤时才转换和过滤
    const elements = [];
    for (let i = 0; i < nodeList.length; i++) {
      if (nodeList[i].textContent.trim().includes(textFilter)) {
        elements.push(nodeList[i]);
      }
    }
    
    if (elements.length === 0) {
      sendClickLog('error', '未找到元素');
    }
    
    return elements;
  }
  
  // 解析特殊选择器（click-格式）- 优化版
  function parseSpecialSelector(searchText) {
    if (!searchText.startsWith('click-')) return null;
    
    // 一次性获取所有部分，避免重复split
    const atIndex = searchText.indexOf('@');
    if (atIndex === -1) {
      return {
        type: 'pure_selector',
        selector: searchText.substring(6)
      };
    }
    
    const firstPart = searchText.substring(6, atIndex);
    const remaining = searchText.substring(atIndex + 1);
    const secondAtIndex = remaining.indexOf('@');
    
    if (secondAtIndex === -1) {
      return {
        type: 'selector_with_text',
        selector: firstPart,
        textFilter: remaining || ''
      };
    }
    
    return {
      type: 'attribute_with_text',
      attributeName: firstPart,
      attributeValue: remaining.substring(0, secondAtIndex),
      textContent: remaining.substring(secondAtIndex + 1)
    };
  }
  
  // 验证并点击目标元素
  function validateAndClickElement(elements, targetIndex) {
    if (targetIndex >= elements.length) {
      return false;
    }
    
    clickAndDetectChanges(elements[targetIndex]);
    return true;
  }
  
  // 查找并点击匹配文本的节点 - 优化版
  function findAndClick() {
    if (searchText === undefined || searchText === null) {
      sendClickLog('error', '搜索文本未定义');
      return false;
    }
    
    if (typeof targetIndex !== 'number' || targetIndex < 0) {
      sendClickLog('error', '目标索引无效');
      return false;
    }
    
    const selectorInfo = parseSpecialSelector(searchText);
    if (selectorInfo) {
      if (selectorInfo.type === 'attribute_with_text') {
        const { attributeName, attributeValue, textContent } = selectorInfo;
        const elements = document.querySelectorAll(`[${attributeName}="${attributeValue}"]`);
        
        if (elements.length === 0) {
          return false;
        }
        
        const matchingElements = Array.from(elements).filter(el => 
          el.textContent.includes(textContent)
        );
        
        if (matchingElements.length === 0) {
          return false;
        }
        
        return validateAndClickElement(matchingElements, targetIndex);
      } 
      else if (selectorInfo.type === 'selector_with_text') {
        const { selector, textFilter } = selectorInfo;
        const elements = findElementsBySelector(selector, textFilter);
        if (elements.length > 0) {
          return validateAndClickElement(elements, targetIndex);
        }
        return false;
      } 
      else if (selectorInfo.type === 'pure_selector') {
        const { selector } = selectorInfo;
        const elements = findElementsBySelector(selector);
        if (elements.length > 0) {
          return validateAndClickElement(elements, targetIndex);
        }
        return false;
      }
    }
    
    // 使用TreeWalker遍历DOM查找文本 - 添加早期终止优化
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
          
          if (node.nodeType === Node.TEXT_NODE) {
            const text = node.textContent;
            return text && /\S/.test(text) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
          }
          
          return NodeFilter.FILTER_SKIP;
        }
      }
    );

    let currentIndex = 0;
    let targetFound = false; // 添加找到标志，用于早期终止
    
    let node;
    while ((node = walk.nextNode()) && !targetFound) { // 找到目标后立即停止
      let matchFound = false;
      let targetNode = null;
      
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent.trim();
        if (text === searchText) {
          matchFound = true;
          targetNode = node.parentElement;
          sendClickLog('info', `找到文本节点匹配: "${text}"`, {
            matchIndex: currentIndex
          });
        }
      }
      else if (node.nodeType === Node.ELEMENT_NODE) {
        const children = Array.from(node.childNodes);
        const directText = children
          .filter(child => child.nodeType === Node.TEXT_NODE)
          .map(child => child.textContent.trim())
          .join('');
        if (directText === searchText) {
          matchFound = true;
          targetNode = node;
          sendClickLog('info', `找到元素子文本匹配: "${directText}"`, {
            matchIndex: currentIndex
          });
        }
      }
      
      if (matchFound) {
        if (currentIndex === targetIndex) {
          sendClickLog('success', '找到点击元素');
          clickAndDetectChanges(targetNode);
          targetFound = true; // 设置找到标志
          return true;
        }
        currentIndex++;
      }
    }

    sendClickLog('error', '未找到元素');
    
    return false;
  }

  // 获取节点状态（类、样式、显示状态）- 直接获取最新状态
  function getNodeState(node) {
    const computedStyle = window.getComputedStyle(node); // 直接获取最新计算样式
    
    return {
      class: node.getAttribute('class') || '',
      style: node.getAttribute('style') || '',
      display: computedStyle.display,
      visibility: computedStyle.visibility
    };
  }

  // 执行点击并检测状态变化 - 优化版
  function clickAndDetectChanges(node, isParentNode = false) {
    try {
      // 缓存初始查询结果
      const videosBefore = document.querySelectorAll('video');
      const iframesBefore = document.querySelectorAll('iframe');
      const videoCountBefore = videosBefore.length;
      const iframeCountBefore = iframesBefore.length;
      const nodeStateBefore = getNodeState(node);
      
      node.click();
      
      setTimeout(() => {
        // 重新查询并比较数量
        const videosAfter = document.querySelectorAll('video');
        const iframesAfter = document.querySelectorAll('iframe');
        const videoCountAfter = videosAfter.length;
        const iframeCountAfter = iframesAfter.length;
        const nodeStateAfter = getNodeState(node);
        const nodeType = isParentNode ? '父节点' : '节点';
        
        // 检测是否有任何变化
        if (nodeStateBefore.class !== nodeStateAfter.class ||
            nodeStateBefore.style !== nodeStateAfter.style ||
            nodeStateBefore.display !== nodeStateAfter.display ||
            nodeStateBefore.visibility !== nodeStateAfter.visibility ||
            videoCountAfter > videoCountBefore ||
            iframeCountAfter > iframeCountBefore) {
          sendClickLog('success', `${nodeType}点击成功，检测到变化`);
        } else if (!isParentNode && node.parentElement) {
          sendClickLog('info', '点击无变化，尝试父节点', {
            parentInfo: getElementInfo(node.parentElement)
          });
          clickAndDetectChanges(node.parentElement, true);
        } else {
          sendClickLog('info', '点击无明显变化');
        }
      }, 500);
    } catch (e) {
      sendClickLog('error', `${isParentNode ? '父' : ''}节点点击失败`, { 
        error: e.message
      });
    }
  }

  // 重试机制配置
  let retryTimer = null;
  let retryCount = 0;
  const maxRetries = 8;
  const retryInterval = 1000;
  let clickExecuted = false;

  // 带重试的查找点击函数
  function findAndClickWithRetry() {
    if (clickExecuted) {
      if (retryTimer) clearTimeout(retryTimer);
      return;
    }

    const attemptStartTime = Date.now();
    const found = findAndClick();
    
    if (!found && !clickExecuted && retryCount < maxRetries) {
      retryCount++;
      sendClickLog('info', `未找到，将在${retryInterval}ms后重试`, {
        attempt: retryCount,
        remaining: maxRetries - retryCount
      });

      retryTimer = setTimeout(() => {
        retryTimer = null; // 清理定时器引用
        findAndClickWithRetry();
      }, retryInterval);
    } else if (!found && retryCount >= maxRetries) {
      sendClickLog('error', `达到最大重试${maxRetries}次`, {
        totalAttempts: retryCount + 1
      });
      if (retryTimer) clearTimeout(retryTimer);
    } else if (found || clickExecuted) {
      sendClickLog('success', '查找成功，停止重试', { totalAttempts: retryCount + 1 });
      if (retryTimer) clearTimeout(retryTimer);
    }
  }

  // 标记点击状态
  const originalClickAndDetectChanges = clickAndDetectChanges;
  clickAndDetectChanges = function(node, isParentNode = false) {
    clickExecuted = true;
    if (retryTimer) clearTimeout(retryTimer);
    return originalClickAndDetectChanges.call(this, node, isParentNode);
  };

  // 启动自动点击
  findAndClickWithRetry();
})();
