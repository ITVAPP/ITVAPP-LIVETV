/// 模拟用户行为（鼠标移动、点击、表单提交）、定时检查表单元素
(function() {
  try {
    // 配置常量：定义表单、鼠标、行为和路径参数
    const CONFIG = {
      // 表单配置
      FORM: {
        FORM_ID: 'form1', // 表单ID
        SEARCH_INPUT_ID: 'search', // 搜索输入框ID
        CHECK_INTERVAL_MS: 500, // 表单检查间隔：毫秒
        BACKUP_CHECK_RATIO: 1.5 // 备份检查间隔：主检查倍数
      },

      // 鼠标移动配置
      MOUSE: {
        MOVEMENT_STEPS: 5, // 鼠标移动步数
        MOVEMENT_DELAY_MS: 50, // 鼠标移动延迟：毫秒
        HOVER_TIME_MS: 200, // 鼠标悬停时间：毫秒
        PRESS_TIME_MS: 300, // 鼠标按下时间：毫秒
        INITIAL_X_RATIO: 0.5, // 初始X坐标：窗口宽度比例
        INITIAL_Y_RATIO: 0.5 // 初始Y坐标：窗口高度比例
      },

      // 用户行为配置
      BEHAVIOR: {
        ACTION_DELAY_MS: 350, // 操作间隔：毫秒
        DOUBLE_CLICK_DELAY_MS: 150, // 双击间隔：毫秒
        FALLBACK_DELAY_MS: 300, // 备用方案延迟：毫秒
        NOTIFICATION_DELAY_MS: 300, // 通知延迟：毫秒
      },

      // 鼠标路径配置
      PATH: {
        BEZIER_CONTROL_POINT1_X_RATIO: 0.4, // 贝塞尔第一控制点X比例
        BEZIER_CONTROL_POINT1_Y_RATIO: 0.2, // 贝塞尔第一控制点Y比例
        BEZIER_CONTROL_POINT2_X_RATIO: 0.8, // 贝塞尔第二控制点X比例
        BEZIER_CONTROL_POINT2_Y_RATIO: 0.7, // 贝塞尔第二控制点Y比例
        PATH_VARIANCE_RATIO: 0.15, // 路径变化比例
        JITTER_DISTANCE_MULTIPLIER: 0.005 // 抖动距离乘数
      },

      // 元素位置配置
      ELEMENT: {
        EMPTY_SPACE_OFFSET: 30, // 输入框上方偏移：像素
        MIN_Y_POSITION: 5, // 最小Y坐标：像素
        ELEMENT_SEARCH_MAX_ATTEMPTS: 5, // 查找元素最大尝试次数
        ELEMENT_SEARCH_STEP: 2 // 查找元素Y偏移步长
      }
    };

    // 表单检查状态：跟踪表单检测和模拟状态
    window.__formCheckState = {
      formFound: false, // 表单是否找到
      checkInterval: null, // 主定时器ID
      searchKeyword: "%SEARCH_KEYWORD%", // 搜索关键词：由Dart替换
      lastCheckTime: Date.now(), // 上次检查时间
      backupTimerId: null // 备份定时器ID
    };

    window.__humanBehaviorSimulationRunning = false; // 行为模拟运行状态

    // 清除定时器：清理所有表单检查定时器
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

        // 清理增强定时器：防止内存泄漏
        if (window.__allFormIntervals && Array.isArray(window.__allFormIntervals)) {
          window.__allFormIntervals.forEach(function(id) {
            clearInterval(id);
          });
          window.__allFormIntervals = [];
        } else {
          window.__allFormIntervals = [];
        }
      } catch (e) {
        // 重置定时器数组：确保异常后清理
        window.__allFormIntervals = [];
      }
    }

    // 创建鼠标事件：模拟指定类型和坐标的事件
    function createMouseEvent(type, x, y, buttons) {
      return new MouseEvent(type, {
        'view': window,
        'bubbles': true,
        'cancelable': true,
        'clientX': x,
        'clientY': y,
        'buttons': buttons || 0
      });
    }

    // 发送消息：通过AppChannel发送状态信息
    function sendMessage(message) {
      if (window.AppChannel) {
        window.AppChannel.postMessage(message);
      }
    }

    // 模拟用户行为：执行鼠标移动、点击和表单输入序列
    function simulateHumanBehavior(searchKeyword) {
      return new Promise((resolve) => {
        if (window.__humanBehaviorSimulationRunning) {
          sendMessage("模拟真人行为已在运行中，跳过");
          return resolve(false);
        }

        window.__humanBehaviorSimulationRunning = true;
        const searchInput = document.getElementById(CONFIG.FORM.SEARCH_INPUT_ID);

        if (!searchInput) {
          sendMessage("未找到搜索输入框");
          window.__humanBehaviorSimulationRunning = false;
          return resolve(false);
        }

        let lastX = window.innerWidth * CONFIG.MOUSE.INITIAL_X_RATIO; // 初始X坐标
        let lastY = window.innerHeight * CONFIG.MOUSE.INITIAL_Y_RATIO; // 初始Y坐标

        // 获取输入框位置：计算边界和尺寸
        function getInputPosition() {
          const rect = searchInput.getBoundingClientRect();
          return {
            top: rect.top,
            left: rect.left,
            right: rect.right,
            bottom: rect.bottom,
            width: rect.width,
            height: rect.height
          };
        }

        // 模拟鼠标移动：从起始点到目标点使用贝塞尔曲线
        async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
          const steps = CONFIG.MOUSE.MOVEMENT_STEPS + Math.floor(Math.random() * 3);

          const distance = Math.sqrt(Math.pow(toX - fromX, 2) + Math.pow(toY - fromY, 2));
          const variance = distance * CONFIG.PATH.PATH_VARIANCE_RATIO;

          // 计算贝塞尔控制点：添加随机变化
          const cp1x = fromX + (toX - fromX) * CONFIG.PATH.BEZIER_CONTROL_POINT1_X_RATIO + (Math.random() * 2 - 1) * variance;
          const cp1y = fromY + (toY - fromY) * CONFIG.PATH.BEZIER_CONTROL_POINT1_Y_RATIO + (Math.random() * 2 - 1) * variance;
          const cp2x = fromX + (toX - fromX) * CONFIG.PATH.BEZIER_CONTROL_POINT2_X_RATIO + (Math.random() * 2 - 1) * variance;
          const cp2y = fromY + (toY - fromY) * CONFIG.PATH.BEZIER_CONTROL_POINT2_Y_RATIO + (Math.random() * 2 - 1) * variance;

          // 计算抖动量：模拟真实移动
          const jitterAmount = Math.max(1, distance * CONFIG.PATH.JITTER_DISTANCE_MULTIPLIER);

          for (let i = 0; i < steps; i++) {
            const t = i / steps;

            // 计算缓动函数：优化移动平滑性
            const easedT = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

            // 预计算共用值：减少重复计算
            const oneMinusT = 1 - easedT;
            const oneMinusTSquared = oneMinusT * oneMinusT;
            const oneMinusTCubed = oneMinusTSquared * oneMinusT;
            const easedTSquared = easedT * easedT;
            const easedTCubed = easedTSquared * easedT;

            // 计算贝塞尔曲线坐标
            const bx = oneMinusTCubed * fromX +
                    3 * oneMinusTSquared * easedT * cp1x +
                    3 * oneMinusT * easedTSquared * cp2x +
                    easedTCubed * toX;

            const by = oneMinusTCubed * fromY +
                    3 * oneMinusTSquared * easedT * cp1y +
                    3 * oneMinusT * easedTSquared * cp2y +
                    easedTCubed * toY;

            const jitterX = (Math.random() * 2 - 1) * jitterAmount;
            const jitterY = (Math.random() * 2 - 1) * jitterAmount;

            const curX = bx + jitterX;
            const curY = by + jitterY;

            const mousemoveEvent = createMouseEvent('mousemove', curX, curY);

            const elementAtPoint = document.elementFromPoint(curX, curY);
            if (elementAtPoint) {
              elementAtPoint.dispatchEvent(mousemoveEvent);
            } else {
              document.body.dispatchEvent(mousemoveEvent);
            }

            const stepDelay = CONFIG.MOUSE.MOVEMENT_DELAY_MS * (0.8 + Math.random() * 0.4);
            await new Promise(r => setTimeout(r, stepDelay));
          }
        }

        // 模拟鼠标悬停：触发目标元素悬停事件
        async function simulateHover(targetElement, x, y) {
          return new Promise((hoverResolve) => {
            try {
              const mouseoverEvent = createMouseEvent('mouseover', x, y);
              targetElement.dispatchEvent(mouseoverEvent);

              const hoverTime = CONFIG.MOUSE.HOVER_TIME_MS;

              setTimeout(() => {
                hoverResolve();
              }, hoverTime);
            } catch (e) {
              hoverResolve();
            }
          });
        }

        // 模拟鼠标点击：支持单次和双击
        async function simulateClick(targetElement, x, y, useDblClick = false) {
          return new Promise((clickResolve) => {
            try {
              const mousedownEvent1 = createMouseEvent('mousedown', x, y, 1);
              targetElement.dispatchEvent(mousedownEvent1);

              const pressTime = CONFIG.MOUSE.PRESS_TIME_MS;

              setTimeout(() => {
                const mouseupEvent1 = createMouseEvent('mouseup', x, y, 0);
                targetElement.dispatchEvent(mouseupEvent1);

                const clickEvent1 = createMouseEvent('click', x, y);
                targetElement.dispatchEvent(clickEvent1);

                if (useDblClick) {
                  const dblClickDelayTime = CONFIG.BEHAVIOR.DOUBLE_CLICK_DELAY_MS;

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

                      if (targetElement === searchInput) {
                        searchInput.focus();
                      }

                      lastX = x;
                      lastY = y;

                      clickResolve();
                    }, pressTime);
                  }, dblClickDelayTime);
                } else {
                  if (targetElement === searchInput) {
                    searchInput.focus();
                  }

                  lastX = x;
                  lastY = y;

                  clickResolve();
                }
              }, pressTime);

            } catch (e) {
              sendMessage("点击操作出错: " + e);
              clickResolve();
            }
          });
        }

        // 点击目标元素：处理输入框或附近区域点击
        async function clickTarget(isInputBox) {
          try {
            const pos = getInputPosition();
            let targetX, targetY, elementDescription;
            let targetElement = null;

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

                if (!targetElement) {
                  targetElement = document.body;
                }
              }
            }

            await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
            await simulateHover(targetElement, targetX, targetY);
            await simulateClick(targetElement, targetX, targetY, !isInputBox);

            sendMessage("点击" + elementDescription + "完成");

            return true;
          } catch (e) {
            sendMessage("点击操作出错: " + e);
            return false;
          }
        }

        // 填写搜索输入框：设置关键词并触发输入事件
        async function fillSearchInput() {
          try {
            searchInput.value = '';
            searchInput.value = searchKeyword;

            const inputEvent = new Event('input', { bubbles: true, cancelable: true });
            searchInput.dispatchEvent(inputEvent);

            const changeEvent = new Event('change', { bubbles: true, cancelable: true });
            searchInput.dispatchEvent(changeEvent);

            sendMessage("填写了搜索关键词: " + searchKeyword);

            return true;
          } catch (e) {
            sendMessage("填写搜索关键词出错: " + e);
            return false;
          }
        }

        // 备用表单提交：直接提交或点击提交按钮
        function fallbackFormSubmit(form) {
          try {
            const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
            if (submitButton) {
              submitButton.click();
            } else {
              form.submit();
            }
            
            sendMessage('FORM_SUBMITTED');
            
            return true;
          } catch (e) {
            sendMessage('FORM_PROCESS_FAILED');
            return false;
          }
        }

        // 点击搜索按钮：模拟提交或直接提交表单
        async function clickSearchButton() {
          try {
            const form = document.getElementById(CONFIG.FORM.FORM_ID);
            if (!form) {
              return false;
            }

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

            sendMessage("点击搜索按钮完成");

            return true;
          } catch (e) {
            sendMessage("点击搜索按钮出错: " + e);

            try {
              const form = document.getElementById(CONFIG.FORM.FORM_ID);
              if (form) form.submit();
            } catch (e2) {}

            return false;
          }
        }

        // 执行行为序列：模拟点击、输入和提交
        async function executeSequence() {
          try {
            // 优化后的点击序列，减少冗余但保留足够的真实性
            await clickTarget(true);    // 1. 点击输入框
            await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.ACTION_DELAY_MS));

            await clickTarget(false);   // 2. 点击输入框上方空白处
            await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.ACTION_DELAY_MS));

            await clickTarget(true);    // 3. 点击输入框
            await fillSearchInput();    // 4. 填写搜索关键词
            await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.ACTION_DELAY_MS));
            
            await clickTarget(false);   // 5. 点击输入框上方空白处
            await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.ACTION_DELAY_MS));
            
            await clickSearchButton();   // 6. 点击搜索按钮

            window.__humanBehaviorSimulationRunning = false;

            resolve(true);
          } catch (e) {
            sendMessage("模拟序列执行出错: " + e);
            window.__humanBehaviorSimulationRunning = false;
            resolve(false);
          }
        }

        executeSequence();
      });
    }

    // 提交搜索表单：执行行为模拟或备用提交
    async function submitSearchForm() {
      const form = document.getElementById(CONFIG.FORM.FORM_ID);
      const searchInput = document.getElementById(CONFIG.FORM.SEARCH_INPUT_ID);

      if (!form || !searchInput) {
        return false;
      }

      try {
        const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword);

        if (result) {
          setTimeout(function() {
            sendMessage('FORM_SUBMITTED');
          }, CONFIG.BEHAVIOR.NOTIFICATION_DELAY_MS);

          return true;
        } else {
          // 备用提交：直接提交表单
          return fallbackFormSubmit(form);
        }
      } catch (e) {
        sendMessage('SIMULATION_FAILED');

        // 备用提交：处理异常情况
        return fallbackFormSubmit(form);
      }
    }

    // 检查表单元素：定时检测表单和输入框
    function checkFormElements() {
      try {
        const currentTime = Date.now();
        if (currentTime - window.__formCheckState.lastCheckTime < CONFIG.FORM.CHECK_INTERVAL_MS * 0.5) {
          return; // 避免频繁检查
        }
        
        window.__formCheckState.lastCheckTime = currentTime;
        
        if (window.__formCheckState.formFound || window.__humanBehaviorSimulationRunning) {
          return;
        }

        const form = document.getElementById(CONFIG.FORM.FORM_ID);
        const searchInput = document.getElementById(CONFIG.FORM.SEARCH_INPUT_ID);

        if (form && searchInput) {
          window.__formCheckState.formFound = true;
          clearAllFormCheckInterval();

          (async function() {
            try {
              const result = await submitSearchForm();
              if (!result) {
                sendMessage('FORM_PROCESS_FAILED');
              }
            } catch (e) {
                sendMessage('FORM_PROCESS_FAILED');
            }
          })();
        }
      } catch (e) {
        // 记录异常：帮助诊断表单检测问题
        sendMessage("表单检测异常: " + e.toString());
        
        // 重置检查时间：确保继续运行
        if (window.__formCheckState) {
          window.__formCheckState.lastCheckTime = Date.now();
        }
      }
    }

    // 设置备份定时器：执行备用检查
    function setupBackupTimer() {
      if (window.__formCheckState.backupTimerId) {
        clearTimeout(window.__formCheckState.backupTimerId);
      }

      window.__formCheckState.backupTimerId = setTimeout(function backupCheck() {
        if (!window.__formCheckState.formFound) {
          checkFormElements();

          if (!window.__formCheckState.checkInterval) {
            setupMainTimer();
          }

          window.__formCheckState.backupTimerId = setTimeout(backupCheck, CONFIG.FORM.CHECK_INTERVAL_MS * CONFIG.FORM.BACKUP_CHECK_RATIO);
        }
      }, CONFIG.FORM.CHECK_INTERVAL_MS * CONFIG.FORM.BACKUP_CHECK_RATIO);
    }

    // 设置主定时器：定期检查表单元素
    function setupMainTimer() {
      if (window.__formCheckState.checkInterval) {
        clearInterval(window.__formCheckState.checkInterval);
        
        // 移除旧定时器ID
        if (window.__allFormIntervals && Array.isArray(window.__allFormIntervals)) {
          const index = window.__allFormIntervals.indexOf(window.__formCheckState.checkInterval);
          if (index > -1) {
            window.__allFormIntervals.splice(index, 1);
          }
        }
      }

      if (!window.__allFormIntervals) {
        window.__allFormIntervals = [];
      }

      const intervalId = setInterval(checkFormElements, CONFIG.FORM.CHECK_INTERVAL_MS);
      
      window.__formCheckState.checkInterval = intervalId;
      window.__allFormIntervals.push(intervalId);
    }

    clearAllFormCheckInterval();
    setupMainTimer();
    setupBackupTimer();

    checkFormElements();

    if (document.readyState !== 'complete') {
      window.addEventListener('load', function() {
        if (!window.__formCheckState.formFound) {
          checkFormElements();
        }
      });
    }
  } catch (e) {
    setTimeout(function() {
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
      } catch (innerError) {}
    }, CONFIG.BEHAVIOR.FALLBACK_DELAY_MS);
  }
})();
