// 模拟用户行为（鼠标移动、点击、滚动、表单提交）并定时检查表单
(function() {
  try {
    // 定义表单检查和用户行为模拟的常量配置
    const CONFIG = {
      FORM: {
        FORM_ID: 'form1', // 表单ID
        SEARCH_INPUT_ID: 'search', // 搜索输入框ID
        CHECK_INTERVAL_MS: 500, // 表单检查间隔
        BACKUP_CHECK_RATIO: 1.5 // 备份检查间隔倍数
      },
      MOUSE: {
        MOVEMENT_STEPS: 5, // 鼠标移动步数
        MOVEMENT_OFFSET: 10, // 鼠标移动偏移量（像素）
        MOVEMENT_DELAY_MS: 30, // 鼠标移动延迟
        HOVER_TIME_MS: 50, // 鼠标悬停时间
        PRESS_TIME_MS: 100, // 鼠标按下时间
        INITIAL_X_RATIO: 0.5, // 初始X坐标窗口宽度比例
        INITIAL_Y_RATIO: 0.5 // 初始Y坐标窗口高度比例
      },
      BEHAVIOR: {
        ACTION_DELAY_MS: 200, // 操作间隔
        DOUBLE_CLICK_DELAY_MS: 100, // 双击间隔
        SCROLL_PROBABILITY: 0.7, // 滚动概率
        SCROLL_BACK_PROBABILITY: 0.3, // 回滚概率
        MIN_SCROLL_AMOUNT: 10, // 最小滚动量（像素）
        MAX_SCROLL_AMOUNT: 100, // 最大滚动量（像素）
        SCROLL_STEPS_MIN: 5, // 最小滚动步数
        SCROLL_STEPS_MAX: 9, // 最大滚动步数
        SCROLL_STEP_DELAY_MIN: 30, // 最小滚动步延迟
        SCROLL_STEP_DELAY_MAX: 50, // 最大滚动步延迟
        SCROLL_REST_MIN: 200, // 滚动后最小休息时间
        SCROLL_REST_MAX: 300, // 滚动后最大休息时间
        FALLBACK_DELAY_MS: 300, // 备用方案延迟
        NOTIFICATION_DELAY_MS: 200 // 通知延迟
      },
      PATH: {
        BEZIER_CONTROL_POINT1_X_RATIO: 0.4, // 贝塞尔曲线控制点1 X比例
        BEZIER_CONTROL_POINT1_Y_RATIO: 0.2, // 贝塞尔曲线控制点1 Y比例
        BEZIER_CONTROL_POINT2_X_RATIO: 0.8, // 贝塞尔曲线控制点2 X比例
        BEZIER_CONTROL_POINT2_Y_RATIO: 0.7, // 贝塞尔曲线控制点2 Y比例
        PATH_VARIANCE_RATIO: 0.15, // 路径变化比例
        JITTER_DISTANCE_MULTIPLIER: 0.005 // 抖动距离乘数
      },
      ELEMENT: {
        EMPTY_SPACE_OFFSET: 25, // 输入框上方空白偏移量（像素）
        MIN_Y_POSITION: 5, // 最小Y坐标（像素）
        ELEMENT_SEARCH_MAX_ATTEMPTS: 5, // 查找元素最大尝试次数
        ELEMENT_SEARCH_STEP: 2 // 查找元素Y偏移步长
      }
    };

    // 初始化表单检查状态
    window.__formCheckState = {
      formFound: false, // 表单是否找到
      checkInterval: null, // 主定时器ID
      searchKeyword: "%SEARCH_KEYWORD%", // 搜索关键词（由Dart替换）
      lastCheckTime: Date.now(), // 上次检查时间
      backupTimerId: null // 备份定时器ID
    };

    window.__humanBehaviorSimulationRunning = false; // 用户行为模拟运行状态

    // 存储所有定时器ID的数组
    if (!window.__allFormIntervals) {
      window.__allFormIntervals = [];
    }

    // 验证搜索关键词，防止XSS攻击
    function sanitizeSearchKeyword(keyword) {
      if (!keyword || typeof keyword !== 'string') return '';
      return keyword.replace(/[&<>"']/g, match => ({ '&': '&', '<': '<', '>': '>', '"': '"', "'": ''' })[match]);
    }

    // 记录错误信息到控制台和AppChannel
    function logError(context, error) {
      if (window.AppChannel) {
        window.AppChannel.postMessage(`错误 [${context}]: ${error.message || error}`);
      }
      console.error(`[${context}]`, error);
    }

    // 清除所有表单检查定时器
    function clearAllFormCheckInterval() {
      try {
        if (window.__formCheckState.checkInterval) {
          clearInterval(window.__formCheckState.checkInterval);
          window.__formCheckState.checkInterval = null;
        }
        if (window.__formCheckState.backupTimerId) {
          clearTimeout(window.__formCheckState.backupTimerId);
          window.__formCheckState.backupTimerId = null;
        }
        if (window.__allFormIntervals?.length) {
          window.__allFormIntervals.forEach(id => clearInterval(id));
          window.__allFormIntervals = [];
        }
      } catch (e) {
        logError('清除定时器', e);
      }
    }

    // 创建鼠标事件
    function createMouseEvent(type, x, y, buttons) {
      return new MouseEvent(type, { view: window, bubbles: true, cancelable: true, clientX: x, clientY: y, buttons: buttons || 0 });
    }

    // 执行表单提交的备用处理
    function executeFormSubmitFallback() {
      try {
        const form = document.getElementById(CONFIG.FORM.FORM_ID);
        const submitButton = form?.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
        if (submitButton) {
          submitButton.click();
        } else if (form) {
          form.submit();
        }
        if (window.AppChannel) {
          window.AppChannel.postMessage('FORM_SUBMITTED');
        }
        return true;
      } catch (e) {
        logError('表单提交备用处理', e);
        if (window.AppChannel) {
          window.AppChannel.postMessage('FORM_PROCESS_FAILED');
        }
        return false;
      }
    }

    // 模拟用户行为（鼠标移动、点击、输入）
    function simulateHumanBehavior(searchKeyword) {
      return new Promise(resolve => {
        if (window.__humanBehaviorSimulationRunning) {
          if (window.AppChannel) {
            window.AppChannel.postMessage("模拟真人行为已在运行，跳过");
          }
          return resolve(false);
        }
        window.__humanBehaviorSimulationRunning = true;

        const sanitizedKeyword = sanitizeSearchKeyword(searchKeyword);
        const searchInput = document.getElementById(CONFIG.FORM.SEARCH_INPUT_ID);

        if (!searchInput) {
          if (window.AppChannel) {
            window.AppChannel.postMessage("未找到搜索输入框");
          }
          window.__humanBehaviorSimulationRunning = false;
          return resolve(false);
        }

        let lastX = window.innerWidth * CONFIG.MOUSE.INITIAL_X_RATIO; // 初始鼠标X坐标
        let lastY = window.innerHeight * CONFIG.MOUSE.INITIAL_Y_RATIO; // 初始鼠标Y坐标

        // 获取输入框位置
        function getInputPosition() {
          const rect = searchInput.getBoundingClientRect();
          return { top: rect.top, left: rect.left, right: rect.right, bottom: rect.bottom, width: rect.width, height: rect.height };
        }

        // 模拟鼠标平滑移动
        async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
          const distance = Math.sqrt(Math.pow(toX - fromX, 2) + Math.pow(toY - fromY, 2));
          const steps = Math.min(CONFIG.MOUSE.MOVEMENT_STEPS + Math.floor(Math.random() * 3), Math.max(3, Math.ceil(distance / 20)));
          const variance = distance * CONFIG.PATH.PATH_VARIANCE_RATIO;
          const cp1x = fromX + (toX - fromX) * CONFIG.PATH.BEZIER_CONTROL_POINT1_X_RATIO + (Math.random() * 2 - 1) * variance;
          const cp1y = fromY + (toY - fromY) * CONFIG.PATH.BEZIER_CONTROL_POINT1_Y_RATIO + (Math.random() * 2 - 1) * variance;
          const cp2x = fromX + (toX - fromX) * CONFIG.PATH.BEZIER_CONTROL_POINT2_X_RATIO + (Math.random() * 2 - 1) * variance;
          const cp2y = fromY + (toY - fromY) * CONFIG.PATH.BEZIER_CONTROL_POINT2_Y_RATIO + (Math.random() * 2 - 1) * variance;
          const jitterAmount = Math.max(1, distance * CONFIG.PATH.JITTER_DISTANCE_MULTIPLIER);

          for (let i = 0; i < steps; i++) {
            const t = i / steps;
            const easedT = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
            const oneMinusT = 1 - easedT, oneMinusTSquared = oneMinusT * oneMinusT, tSquared = easedT * easedT;
            const bx = oneMinusT * oneMinusT * oneMinusT * fromX + 3 * oneMinusTSquared * easedT * cp1x + 3 * oneMinusT * tSquared * cp2x + easedT * tSquared * toX;
            const by = oneMinusT * oneMinusT * oneMinusT * fromY + 3 * oneMinusTSquared * easedT * cp1y + 3 * oneMinusT * tSquared * cp2y + easedT * tSquared * toY;
            const jitterX = (Math.random() * 2 - 1) * jitterAmount;
            const jitterY = (Math.random() * 2 - 1) * jitterAmount;
            const curX = bx + jitterX, curY = by + jitterY;

            if (steps <= 5 || i % 2 === 0 || i === steps - 1) {
              const mousemoveEvent = createMouseEvent('mousemove', curX, curY);
              const elementAtPoint = document.elementFromPoint(curX, curY) || document.body;
              elementAtPoint.dispatchEvent(mousemoveEvent);
            }
            await new Promise(r => setTimeout(r, CONFIG.MOUSE.MOVEMENT_DELAY_MS * (0.8 + Math.random() * 0.4)));
          }
        }

        // 模拟随机页面滚动
        async function addRandomScrolling() {
          if (Math.random() < CONFIG.BEHAVIOR.SCROLL_PROBABILITY) {
            const scrollDirection = Math.random() < 0.6 ? 1 : -1;
            const scrollAmount = Math.floor(CONFIG.BEHAVIOR.MIN_SCROLL_AMOUNT + Math.random() * CONFIG.BEHAVIOR.MAX_SCROLL_AMOUNT) * scrollDirection;
            if (window.AppChannel) {
              window.AppChannel.postMessage("执行随机滚动: " + scrollAmount + "px");
            }
            const scrollSteps = CONFIG.BEHAVIOR.SCROLL_STEPS_MIN + Math.floor(Math.random() * (CONFIG.BEHAVIOR.SCROLL_STEPS_MAX - CONFIG.BEHAVIOR.SCROLL_STEPS_MIN));
            const scrollStep = scrollAmount / scrollSteps;
            const scrollStepValues = Array.from({ length: scrollSteps }, (_, i) => Math.sin((i / scrollSteps) * Math.PI) * scrollStep);

            for (let i = 0; i < scrollSteps; i++) {
              window.scrollBy(0, scrollStepValues[i]);
              await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.SCROLL_STEP_DELAY_MIN + Math.random() * (CONFIG.BEHAVIOR.SCROLL_STEP_DELAY_MAX - CONFIG.BEHAVIOR.SCROLL_STEP_DELAY_MIN)));
            }
            if (Math.random() < CONFIG.BEHAVIOR.SCROLL_BACK_PROBABILITY) {
              await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.SCROLL_REST_MIN + Math.random() * (CONFIG.BEHAVIOR.SCROLL_REST_MAX - CONFIG.BEHAVIOR.SCROLL_REST_MIN)));
              for (let i = 0; i < scrollSteps; i++) {
                window.scrollBy(0, -scrollStepValues[i]);
                await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.SCROLL_STEP_DELAY_MIN + Math.random() * (CONFIG.BEHAVIOR.SCROLL_STEP_DELAY_MAX - CONFIG.BEHAVIOR.SCROLL_STEP_DELAY_MIN)));
              }
            }
            await new Promise(r => setTimeout(r, 150 + Math.random() * 200));
          }
        }

        // 模拟鼠标悬停
        async function simulateHover(targetElement, x, y) {
          return new Promise(hoverResolve => {
            try {
              const mouseoverEvent = createMouseEvent('mouseover', x, y);
              targetElement.dispatchEvent(mouseoverEvent);
              setTimeout(hoverResolve, CONFIG.MOUSE.HOVER_TIME_MS);
            } catch (e) {
              logError('模拟悬停', e);
              hoverResolve();
            }
          });
        }

        // 模拟鼠标点击（支持双击）
        async function simulateClick(targetElement, x, y, useDblClick = false) {
          return new Promise(clickResolve => {
            try {
              const mousedownEvent1 = createMouseEvent('mousedown', x, y, 1);
              targetElement.dispatchEvent(mousedownEvent1);
              setTimeout(() => {
                const mouseupEvent1 = createMouseEvent('mouseup', x, y, 0);
                targetElement.dispatchEvent(mouseupEvent1);
                const clickEvent1 = createMouseEvent('click', x, y);
                targetElement.dispatchEvent(clickEvent1);
                if (useDblClick) {
                  setTimeout(() => {
                    const mousedownEvent2 = createMouseEvent('mousedown', x, y, 1);
                    targetElement.dispatchEvent(mousedownEvent2);
                    setTimeout(() => {
                      const mouseupEvent2 = createMouseEvent('mouseup', x, y, 0);
                      targetElement.dispatchEvent(mouseupEvent2);
                      const clickEvent2 = createMouseEvent('click', x, y);
                      targetElement.dispatchEvent(clickEvent2);
                      const dblClickEvent = createMouseEvent('dblclick', x, y);
                      targetElement.dispatchEvent(dblClickEvent);
                      if (targetElement === searchInput) searchInput.focus();
                      lastX = x; lastY = y;
                      clickResolve();
                    }, CONFIG.MOUSE.PRESS_TIME_MS);
                  }, CONFIG.BEHAVIOR.DOUBLE_CLICK_DELAY_MS);
                } else {
                  if (targetElement === searchInput) searchInput.focus();
                  lastX = x; lastY = y;
                  clickResolve();
                }
              }, CONFIG.MOUSE.PRESS_TIME_MS);
            } catch (e) {
              logError('模拟点击', e);
              if (window.AppChannel) {
                window.AppChannel.postMessage("点击操作出错: " + e);
              }
              clickResolve();
            }
          });
        }

        // 点击目标元素（输入框或附近区域）
        async function clickTarget(isInputBox) {
          try {
            const pos = getInputPosition();
            let targetX, targetY, elementDescription, targetElement;
            if (isInputBox) {
              targetX = pos.left + pos.width * 0.5;
              targetY = pos.top + pos.height * 0.5;
              elementDescription = "输入框";
              targetElement = searchInput;
            } else {
              targetX = pos.left + pos.width * 0.5;
              targetY = Math.max(pos.top - CONFIG.ELEMENT.EMPTY_SPACE_OFFSET, CONFIG.ELEMENT.MIN_Y_POSITION);
              elementDescription = "输入框上方空白处";
              targetElement = document.elementFromPoint(targetX, targetY);
              if (!targetElement) {
                for (let attempt = 1; attempt <= CONFIG.ELEMENT.ELEMENT_SEARCH_MAX_ATTEMPTS; attempt++) {
                  targetY += CONFIG.ELEMENT.ELEMENT_SEARCH_STEP;
                  targetElement = document.elementFromPoint(targetX, targetY);
                  if (targetElement) break;
                }
                targetElement = targetElement || document.body;
              }
            }
            await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
            await simulateHover(targetElement, targetX, targetY);
            await simulateClick(targetElement, targetX, targetY, !isInputBox);
            if (window.AppChannel) {
              window.AppChannel.postMessage("点击" + elementDescription + "完成");
            }
            return true;
          } catch (e) {
            logError('点击目标', e);
            if (window.AppChannel) {
              window.AppChannel.postMessage("点击操作出错: " + e);
            }
            return false;
          }
        }

        // 填写搜索输入框
        async function fillSearchInput() {
          try {
            searchInput.value = '';
            searchInput.value = sanitizedKeyword;
            const inputEvent = new Event('input', { bubbles: true, cancelable: true });
            searchInput.dispatchEvent(inputEvent);
            const changeEvent = new Event('change', { bubbles: true, cancelable: true });
            searchInput.dispatchEvent(changeEvent);
            if (window.AppChannel) {
              window.AppChannel.postMessage("填写了搜索关键词: " + sanitizedKeyword);
            }
            return true;
          } catch (e) {
            logError('填写搜索关键词', e);
            if (window.AppChannel) {
              window.AppChannel.postMessage("填写搜索关键词出错: " + e);
            }
            return false;
          }
        }

        // 点击搜索按钮或提交表单
        async function clickSearchButton() {
          try {
            const form = document.getElementById(CONFIG.FORM.FORM_ID);
            if (!form) return false;
            const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
            if (!submitButton) {
              form.submit();
              return true;
            }
            const rect = submitButton.getBoundingClientRect();
            const targetX = rect.left + rect.width * 0.5;
            const targetY = rect.top + rect.height * 0.5;
            await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
            await simulateHover(submitButton, targetX, targetY);
            await simulateClick(submitButton, targetX, targetY, false);
            if (window.AppChannel) {
              window.AppChannel.postMessage("点击搜索按钮完成");
            }
            return true;
          } catch (e) {
            logError('点击搜索按钮', e);
            if (window.AppChannel) {
              window.AppChannel.postMessage("点击搜索按钮出错: " + e);
            }
            return executeFormSubmitFallback();
          }
        }

        // 定义点击序列配置
        const clickSequence = [
          { action: 'click', target: true },
          { action: 'delay' },
          { action: 'click', target: false },
          { action: 'delay' },
          { action: 'click', target: true },
          { action: 'delay' },
          { action: 'click', target: false },
          { action: 'delay' },
          { action: 'click', target: true },
          { action: 'fill' },
          { action: 'delay' },
          { action: 'click', target: false },
          { action: 'delay' },
          { action: 'submit' }
        ];

        // 执行用户行为模拟序列
        async function executeSequence() {
          try {
            await addRandomScrolling();
            for (let step of clickSequence) {
              if (step.action === 'click') await clickTarget(step.target);
              else if (step.action === 'fill') await fillSearchInput();
              else if (step.action === 'delay') await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.ACTION_DELAY_MS));
              else if (step.action === 'submit') await clickSearchButton();
            }
            window.__humanBehaviorSimulationRunning = false;
            resolve(true);
          } catch (e) {
            logError('执行序列', e);
            if (window.AppChannel) {
              window.AppChannel.postMessage("模拟序列执行出错: " + e);
            }
            window.__humanBehaviorSimulationRunning = false;
            resolve(false);
          }
        }

        executeSequence();
      });
    }

    // 提交搜索表单
    async function submitSearchForm() {
      const form = document.getElementById(CONFIG.FORM.FORM_ID);
      const searchInput = document.getElementById(CONFIG.FORM.SEARCH_INPUT_ID);
      if (!form || !searchInput) return false;
      try {
        const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword);
        if (result) {
          if (window.AppChannel) {
            setTimeout(() => window.AppChannel.postMessage('FORM_SUBMITTED'), CONFIG.BEHAVIOR.NOTIFICATION_DELAY_MS);
          }
          return true;
        }
        return executeFormSubmitFallback();
      } catch (e) {
        logError('提交搜索表单', e);
        if (window.AppChannel) {
          window.AppChannel.postMessage('SIMULATION_FAILED');
        }
        return executeFormSubmitFallback();
      }
    }

    // 检查表单元素是否存在
    function checkFormElements() {
      try {
        if (window.__formCheckState.formFound || window.__humanBehaviorSimulationRunning) return;
        window.__formCheckState.lastCheckTime = Date.now();
        const form = document.getElementById(CONFIG.FORM.FORM_ID);
        const searchInput = document.getElementById(CONFIG.FORM.SEARCH_INPUT_ID);
        if (form && searchInput) {
          window.__formCheckState.formFound = true;
          clearAllFormCheckInterval();
          (async () => {
            try {
              const result = await submitSearchForm();
              if (!result && window.AppChannel) {
                window.AppChannel.postMessage('FORM_PROCESS_FAILED');
              }
            } catch (e) {
              logError('表单处理', e);
              if (window.AppChannel) {
                window.AppChannel.postMessage('FORM_PROCESS_FAILED');
              }
            }
          })();
        }
      } catch (e) {
        logError('检查表单元素', e);
      }
    }

    // 设置备份定时器
    function setupBackupTimer() {
      if (window.__formCheckState.backupTimerId) clearTimeout(window.__formCheckState.backupTimerId);
      window.__formCheckState.backupTimerId = setTimeout(function backupCheck() {
        if (!window.__formCheckState.formFound) {
          checkFormElements();
          if (!window.__formCheckState.checkInterval) setupMainTimer();
          window.__formCheckState.backupTimerId = setTimeout(backupCheck, CONFIG.FORM.CHECK_INTERVAL_MS * CONFIG.FORM.BACKUP_CHECK_RATIO);
        }
      }, CONFIG.FORM.CHECK_INTERVAL_MS * CONFIG.FORM.BACKUP_CHECK_RATIO);
    }

    // 设置主定时器
    function setupMainTimer() {
      if (window.__formCheckState.checkInterval) clearInterval(window.__formCheckState.checkInterval);
      if (!window.__allFormIntervals) window.__allFormIntervals = [];
      const intervalId = setInterval(checkFormElements, CONFIG.FORM.CHECK_INTERVAL_MS);
      window.__formCheckState.checkInterval = intervalId;
      window.__allFormIntervals.push(intervalId);
    }

    // 初始化定时器和表单检查
    clearAllFormCheckInterval();
    setupMainTimer();
    setupBackupTimer();
    checkFormElements();

    // 页面加载完成时检查表单
    if (document.readyState !== 'complete') {
      window.addEventListener('load', () => {
        if (!window.__formCheckState.formFound) checkFormElements();
      });
    }
  } catch (e) {
    // 最终备用方案：直接填写并提交表单
    setTimeout(() => {
      try {
        const form = document.getElementById('form1');
        const searchInput = document.getElementById('search');
        if (form && searchInput) {
          const keyword = "%SEARCH_KEYWORD%";
          searchInput.value = keyword;
          form.submit();
          if (window.AppChannel) {
            window.AppChannel.postMessage('FORM_SUBMITTED');
          }
        }
      } catch (innerError) {
        if (window.AppChannel) {
          window.AppChannel.postMessage('最终备用方案失败: ' + innerError);
        }
      }
    }, CONFIG.BEHAVIOR.FALLBACK_DELAY_MS);
  }
})();
