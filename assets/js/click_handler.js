(function() {
  // 查找并点击匹配文本的页面元素
  const searchText = ""; // 目标搜索文本
  const targetIndex = 0; // 目标匹配项索引
  
  const domCache = {
    totalElements: null, // DOM元素总数缓存
    bodyElements: null, // body元素总数缓存
    computedStyles: new WeakMap(), // 计算样式缓存
    lastCacheTime: 0, // 最近缓存时间
    cacheValidityMs: 1000, // 缓存有效期（毫秒）
    
    // 获取DOM元素总数并缓存
    getTotalElements() {
      const now = Date.now();
      if (this.totalElements === null || (now - this.lastCacheTime) > this.cacheValidityMs) {
        this.totalElements = document.querySelectorAll('*').length;
        this.bodyElements = document.body ? document.body.querySelectorAll('*').length : 0;
        this.lastCacheTime = now;
      }
      return this.totalElements;
    },
    
    // 获取body元素总数
    getBodyElements() {
      this.getTotalElements();
      return this.bodyElements;
    },
    
    // 获取元素计算样式并缓存
    getComputedStyle(element) {
      if (!this.computedStyles.has(element)) {
        this.computedStyles.set(element, window.getComputedStyle(element));
      }
      return this.computedStyles.get(element);
    },
    
    // 清理缓存
    clearCache() {
      this.totalElements = null;
      this.bodyElements = null;
      this.computedStyles = new WeakMap();
      this.lastCacheTime = 0;
    }
  };
  
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
  
  // 查找元素（支持ID、Class、文本过滤）
  function findElementsBySelector(selector, textFilter = '') {
    if (!selector) {
      return [];
    }
    
    const elements = Array.from(document.querySelectorAll(`#${selector}, .${selector}`));
    
    let finalElements = elements;
    if (textFilter) {
      finalElements = elements.filter(el => el.textContent.trim().includes(textFilter));
    }
    
    if (finalElements.length === 0) {
      sendClickLog('error', '未找到元素');
    }
    
    return finalElements;
  }
  
  // 解析特殊选择器（click-格式）
  function parseSpecialSelector(searchText) {
    if (!searchText.startsWith('click-')) return null;
    
    const parts = searchText.split('@');
    const partsCount = parts.length;
    
    if (partsCount >= 3) {
      return {
        type: 'attribute_with_text',
        attributeName: parts[0].substring(6),
        attributeValue: parts[1],
        textContent: parts[2]
      };
    } else if (partsCount === 2) {
      return {
        type: 'selector_with_text',
        selector: parts[0].substring(6),
        textFilter: parts[1] || ''
      };
    } else {
      return {
        type: 'pure_selector',
        selector: searchText.substring(6)
      };
    }
  }
  
  // 验证并点击目标元素
  function validateAndClickElement(elements, targetIndex) {
    if (targetIndex >= elements.length) {
      return false;
    }
    
    clickAndDetectChanges(elements[targetIndex]);
    return true;
  }
  
  // 查找并点击匹配文本的节点
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
    
    // 使用TreeWalker遍历DOM查找文本
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
    
    let node;
    while ((node = walk.nextNode())) {
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
          return true;
        }
        currentIndex++;
      }
    }

    sendClickLog('error', '未找到元素');
    
    return false;
  }

  // 获取节点状态（类、样式、显示状态）
  function getNodeState(node) {
    const computedStyle = domCache.getComputedStyle(node);
    
    return {
      class: node.getAttribute('class') || '',
      style: node.getAttribute('style') || '',
      display: computedStyle.display,
      visibility: computedStyle.visibility
    };
  }

  // 执行点击并检测状态变化
  function clickAndDetectChanges(node, isParentNode = false) {
    try {
      const videoCountBefore = document.querySelectorAll('video').length;
      const iframeCountBefore = document.querySelectorAll('iframe').length;
      const nodeStateBefore = getNodeState(node);
      
      node.click();
      
      setTimeout(() => {
        domCache.clearCache();
        
        const videoCountAfter = document.querySelectorAll('video').length;
        const iframeCountAfter = document.querySelectorAll('iframe').length;
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
      if (retryTimer) clearInterval(retryTimer);
      return;
    }

    const found = findAndClick();
    
    if (!found && !clickExecuted && retryCount < maxRetries) {
      retryCount++;
      sendClickLog('info', `未找到，将在${retryInterval}ms后重试`, {
        attempt: retryCount,
        remaining: maxRetries - retryCount
      });

      if (!retryTimer) {
        retryTimer = setInterval(() => {
          findAndClickWithRetry();
        }, retryInterval);
      }
    } else if (!found && retryCount >= maxRetries) {
      sendClickLog('error', `达到最大重试${maxRetries}次`, {
        totalAttempts: retryCount + 1
      });
      if (retryTimer) clearInterval(retryTimer);
    } else if (found || clickExecuted) {
      sendClickLog('success', '查找成功，停止重试', { totalAttempts: retryCount + 1 });
      if (retryTimer) clearInterval(retryTimer);
    }
  }

  // 包装clickAndDetectChanges以标记点击状态
  const originalClickAndDetectChanges = clickAndDetectChanges;
  clickAndDetectChanges = function(node, isParentNode = false) {
    clickExecuted = true;
    if (retryTimer) clearInterval(retryTimer);
    return originalClickAndDetectChanges.call(this, node, isParentNode);
  };

  // 启动自动点击
  findAndClickWithRetry();
})();
