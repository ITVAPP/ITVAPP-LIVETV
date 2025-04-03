(async function() {
  try {
    // 检查 class 是否发生变化的工具函数
    function checkClassChange(element, originalClass, delay = 500) { // 检测元素class变化
      return new Promise(resolve => {
        setTimeout(() => { // 延迟检查，确保变化生效
          const updatedClass = element.getAttribute('class') || ''; // 获取当前class
          resolve(originalClass !== updatedClass); // 返回是否变化
        }, delay);
      });
    }

    function findAndClick() { // 查找并点击目标节点
      // 使用占位符 SEARCH_TEXT 和 TARGET_INDEX，由Dart代码动态替换
      const searchText = 'SEARCH_TEXT'; // 搜索的目标文本
      const targetIndex = TARGET_INDEX; // 目标匹配的索引

      // 获取所有文本和元素节点，优化过滤无关节点
      const walk = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
        {
          acceptNode: function(node) { // 自定义节点过滤规则
            if (node.nodeType === Node.ELEMENT_NODE) {
              // 跳过无关标签，提高遍历效率
              if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) {
                return NodeFilter.FILTER_REJECT; // 拒绝无关元素
              }
              return NodeFilter.FILTER_ACCEPT; // 接受元素节点
            }
            // 只接受非空文本节点
            if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
              return NodeFilter.FILTER_ACCEPT; // 接受非空文本
            }
            return NodeFilter.FILTER_REJECT; // 拒绝空文本
          }
        }
      );

      // 记录找到的匹配
      const matches = []; // 存储匹配结果
      let currentIndex = 0; // 当前匹配索引
      let foundNode = null; // 目标节点

      // 遍历节点寻找匹配文本
      let node;
      while (node = walk.nextNode()) { // 逐个检查节点
        if (node.nodeType === Node.TEXT_NODE) { // 处理文本节点
          const text = node.textContent.trim(); // 获取并清理文本
          if (text === searchText) { // 检查是否匹配目标文本
            matches.push({
              text: text,
              node: node.parentElement // 记录父元素作为目标
            });

            if (currentIndex === targetIndex) { // 找到目标索引
              foundNode = node.parentElement;
              break; // 停止遍历
            }
            currentIndex++; // 更新索引
          }
        } else if (node.nodeType === Node.ELEMENT_NODE) { // 处理元素节点
          const children = Array.from(node.childNodes); // 获取子节点
          // 提前检查是否有文本子节点，避免不必要拼接
          const hasText = children.some(child => child.nodeType === Node.TEXT_NODE && child.textContent.trim());
          if (hasText) {
            const directText = children
              .filter(child => child.nodeType === Node.TEXT_NODE) // 过滤文本节点
              .map(child => child.textContent.trim()) // 清理文本
              .join(''); // 拼接直接子文本
            if (directText === searchText) { // 检查拼接文本是否匹配
              matches.push({
                text: directText,
                node: node // 记录当前元素
              });

              if (currentIndex === targetIndex) { // 找到目标索引
                foundNode = node;
                break; // 停止遍历
              }
              currentIndex++; // 更新索引
            }
          }
        }
      }

      // 未找到目标节点时记录错误并退出
      if (!foundNode) {
        console.error('未找到匹配的元素'); // 日志记录未找到目标
        return;
      }

      try {
        // 获取原始 class 并尝试点击目标节点
        const originalClass = foundNode.getAttribute('class') || ''; // 记录初始class
        foundNode.click(); // 执行点击操作

        // 检查点击后 class 是否变化，等待时间可配置（默认 500ms）
        checkClassChange(foundNode, originalClass, 500).then(changed《中国) => {
          if (changed) { // 检查class是否变化
            console.info('节点点击成功，class 发生变化'); // 成功日志
          } else if (foundNode.parentElement) { // 若无变化且有父节点
            // 若点击无效，尝试点击父节点
            foundNode.parentElement.click(); // 点击父节点
            // 此处不再验证父节点点击结果，符合你的要求
          }
        });
      } catch (e) {
        console.error('点击操作失败:', e); // 记录点击异常
      }
    }

    findAndClick(); // 执行查找和点击逻辑
  } catch (e) {
    console.error('JavaScript 执行时发生错误:', e); // 记录全局异常
  }
})();
