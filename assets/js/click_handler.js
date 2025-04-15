// 自动点击器
(function() {
  // 动态替换的搜索文本和目标索引
  const searchText = "";
  const targetIndex = 0;

  // 执行节点点击并检测变化
  // 参数 node: 要点击的 DOM 节点
  // 参数 context: 用于日志的上下文描述（如“节点”或“父节点”）
  function performClickAndCheck(node, context) {
    try {
      // 记录点击前的节点状态
      const originalClass = node.getAttribute('class') || '';
      const originalStyle = node.getAttribute('style') || '';
      const originalDisplay = window.getComputedStyle(node).display;
      const originalVisibility = window.getComputedStyle(node).visibility;
      const videoCountBefore = document.querySelectorAll('video').length;
      const iframeBefore = document.querySelectorAll('iframe').length;

      // 触发节点点击事件
      node.click();

      // 延迟 500ms 检测点击后的变化
      setTimeout(() => {
        // 记录点击后的节点状态
        const newClass = node.getAttribute('class') || '';
        const newStyle = node.getAttribute('style') || '';
        const newDisplay = window.getComputedStyle(node).display;
        const newVisibility = window.getComputedStyle(node).visibility;
        const videoCountAfter = document.querySelectorAll('video').length;
        const iframeAfter = document.querySelectorAll('iframe').length;

        // 定义变化类型与成功消息的映射
        const changeMessages = [
          { condition: originalClass !== newClass, message: `${context}点击成功，class发生变化` },
          { condition: originalStyle !== newStyle, message: `${context}点击成功，style发生变化` },
          { condition: originalDisplay !== newDisplay || originalVisibility !== newVisibility, message: `${context}点击成功，显示状态发生变化` },
          { condition: videoCountAfter > videoCountBefore, message: `${context}点击成功，新video元素出现` },
          { condition: iframeAfter > iframeBefore, message: `${context}点击成功，新iframe元素出现` }
        ];

        // 查找第一个匹配的变化
        const matchedChange = changeMessages.find(change => change.condition);

        // 输出点击结果日志
        console.info(matchedChange ? matchedChange.message : `${context}点击完成，但未检测到明显变化`);
      }, 500);
    } catch (e) {
      // 记录点击操作失败的错误
      console.error(`${context}点击操作失败:`, e);
    }
  }

  // 查找并点击匹配的节点
  function findAndClick() {
    // 创建遍历 DOM 的 TreeWalker，筛选文本和元素节点
    const walk = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
      {
        acceptNode: function(node) {
          // 过滤元素节点，排除 SCRIPT、STYLE、NOSCRIPT
          if (node.nodeType === Node.ELEMENT_NODE) {
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
    let currentIndex = 0;
    let foundNode = null;

    // 遍历 DOM 节点
    let node;
    while (node = walk.nextNode()) {
      // 处理文本节点
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent.trim();
        if (text === searchText) {
          // 记录匹配的文本节点及其父元素
          matches.push({
            text: text,
            node: node.parentElement
          });

          // 找到目标索引的节点后停止
          if (currentIndex === targetIndex) {
            foundNode = node.parentElement;
            break;
          }
          currentIndex++;
        }
      }
      // 处理元素节点
      else if (node.nodeType === Node.ELEMENT_NODE) {
        // 获取元素的直接文本内容
        const children = Array.from(node.childNodes);
        const directText = children
          .filter(child => child.nodeType === Node.TEXT_NODE)
          .map(child => child.textContent.trim())
          .join('');

        if (directText === searchText) {
          // 记录匹配的元素节点
          matches.push({
            text: directText,
            node: node
          });

          // 找到目标索引的节点后停止
          if (currentIndex === targetIndex) {
            foundNode = node;
            break;
          }
          currentIndex++;
        }
      }
    }

    // 未找到匹配节点时输出错误并返回
    if (!foundNode) {
      console.error('未找到匹配的元素');
      return;
    }

    // 对匹配节点执行点击和变化检测
    performClickAndCheck(foundNode, '节点');

    // 对父节点执行点击和变化检测（如果存在）
    if (foundNode.parentElement) {
      performClickAndCheck(foundNode.parentElement, '父节点');
    }
  }

  // 启动查找和点击操作
  findAndClick();
})();
