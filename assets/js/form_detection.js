/// 模拟用户行为（鼠标移动、点击、表单提交）、定时检查表单元素
(function() {
  try {
    // 定义表单检查和用户行为模拟的常量
    const CONFIG = {
      // 表单相关配置
      FORM: {
        FORM_ID: 'form1',
        SEARCH_INPUT_ID: 'search',
        CHECK_INTERVAL_MS: 500, // 表单检查间隔（毫秒）
        BACKUP_CHECK_RATIO: 1.5 // 备份检查间隔与主检查的倍数关系 
      },

      // 鼠标移动配置
      MOUSE: {
        MOVEMENT_STEPS: 5, // 鼠标移动步数
        MOVEMENT_OFFSET: 10, // 鼠标移动偏移量（像素）
        MOVEMENT_DELAY_MS: 50, // 鼠标移动延迟（毫秒）
        HOVER_TIME_MS: 100, // 鼠标悬停时间（毫秒）
        PRESS_TIME_MS: 200, // 鼠标按下时间（毫秒）
        INITIAL_X_RATIO: 0.5, // 初始鼠标X坐标在窗口宽度的比例
        INITIAL_Y_RATIO: 0.5 // 初始鼠标Y坐标在窗口高度的比例
      },

      // 用户行为模拟配置
      BEHAVIOR: {
        ACTION_DELAY_MS: 300, // 操作间隔（毫秒）
        DOUBLE_CLICK_DELAY_MS: 150, // 双击间隔（毫秒）
        FALLBACK_DELAY_MS: 300, // 备用方案延迟（毫秒）
        NOTIFICATION_DELAY_MS: 300, // 通知延迟（毫秒）
      },

      // 鼠标路径平滑度配置
      PATH: {
        BEZIER_CONTROL_POINT1_X_RATIO: 0.4, // 贝塞尔曲线第一控制点X比例
        BEZIER_CONTROL_POINT1_Y_RATIO: 0.2, // 贝塞尔曲线第一控制点Y比例
        BEZIER_CONTROL_POINT2_X_RATIO: 0.8, // 贝塞尔曲线第二控制点X比例
        BEZIER_CONTROL_POINT2_Y_RATIO: 0.7, // 贝塞尔曲线第二控制点Y比例
        PATH_VARIANCE_RATIO: 0.15, // 路径变化比例
        JITTER_DISTANCE_MULTIPLIER: 0.005 // 抖动距离乘数
      },

      // 元素位置配置
      ELEMENT: {
        EMPTY_SPACE_OFFSET: 30, // 输入框上方空白处偏移量（像素）
        MIN_Y_POSITION: 5, // 最小Y坐标位置（像素）
        ELEMENT_SEARCH_MAX_ATTEMPTS: 5, // 查找元素的最大尝试次数
        ELEMENT_SEARCH_STEP: 2 // 查找元素时的Y偏移步长
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

        // 增强型定时器清理，防止内存泄漏
        if (window.__allFormIntervals && Array.isArray(window.__allFormIntervals)) {
          while (window.__allFormIntervals.length > 0) {
            const id = window.__allFormIntervals.pop();
            clearInterval(id);
          }
        } else {
          window.__allFormIntervals = [];
        }
      } catch (e) {
        // 确保数组被重置
        window.__allFormIntervals = [];
      }
    }

    // 创建鼠标事件
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

    // 模拟用户行为（鼠标移动、点击、输入）
    function simulateHumanBehavior(searchKeyword) {
      return new Promise((resolve) => {
        if (window.__humanBehaviorSimulationRunning) {
          if (window.AppChannel) {
            window.AppChannel.postMessage("模拟真人行为已在运行中，跳过");
          }
          return resolve(false);
        }

        window.__humanBehaviorSimulationRunning = true;

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
          return {
            top: rect.top,
            left: rect.left,
            right: rect.right,
            bottom: rect.bottom,
            width: rect.width,
            height: rect.height
          };
        }

        // 模拟鼠标从起始点到目标点的平滑移动
        async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
          const steps = CONFIG.MOUSE.MOVEMENT_STEPS + Math.floor(Math.random() * 3);

          const distance = Math.sqrt(Math.pow(toX - fromX, 2) + Math.pow(toY - fromY, 2));
          const variance = distance * CONFIG.PATH.PATH_VARIANCE_RATIO;

          // 预计算贝塞尔曲线控制点，减少重复计算
          const cp1x = fromX + (toX - fromX) * CONFIG.PATH.BEZIER_CONTROL_POINT1_X_RATIO + (Math.random() * 2 - 1) * variance;
          const cp1y = fromY + (toY - fromY) * CONFIG.PATH.BEZIER_CONTROL_POINT1_Y_RATIO + (Math.random() * 2 - 1) * variance;
          const cp2x = fromX + (toX - fromX) * CONFIG.PATH.BEZIER_CONTROL_POINT2_X_RATIO + (Math.random() * 2 - 1) * variance;
          const cp2y = fromY + (toY - fromY) * CONFIG.PATH.BEZIER_CONTROL_POINT2_Y_RATIO + (Math.random() * 2 - 1) * variance;

          for (let i = 0; i < steps; i++) {
            const t = i / steps;

            const easedT = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

            const bx = Math.pow(1-easedT, 3) * fromX +
                    3 * Math.pow(1-easedT, 2) * easedT * cp1x +
                    3 * (1-easedT) * Math.pow(easedT, 2) * cp2x +
                    Math.pow(easedT, 3) * toX;

            const by = Math.pow(1-easedT, 3) * fromY +
                    3 * Math.pow(1-easedT, 2) * easedT * cp1y +
                    3 * (1-easedT) * Math.pow(easedT, 2) * cp2y +
                    Math.pow(easedT, 3) * toY;

            const jitterAmount = Math.max(1, distance * CONFIG.PATH.JITTER_DISTANCE_MULTIPLIER);
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

        // 已移除 addRandomScrolling 函数

        // 模拟鼠标悬停
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

        // 模拟鼠标点击（支持双击）
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

            if (window.AppChannel) {
              window.AppChannel.postMessage("点击" + elementDescription + "完成");
            }

            return true;
          } catch (e) {
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
            searchInput.value = searchKeyword;

            const inputEvent = new Event('input', { bubbles: true, cancelable: true });
            searchInput.dispatchEvent(inputEvent);

            const changeEvent = new Event('change', { bubbles: true, cancelable: true });
            searchInput.dispatchEvent(changeEvent);

            if (window.AppChannel) {
              window.AppChannel.postMessage("填写了搜索关键词: " + searchKeyword);
            }

            return true;
          } catch (e) {
            if (window.AppChannel) {
              window.AppChannel.postMessage("填写搜索关键词出错: " + e);
            }
            return false;
          }
        }

        // 封装表单直接提交的备用方案
        function fallbackFormSubmit(form) {
          try {
            const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
            if (submitButton) {
              submitButton.click();
            } else {
              form.submit();
            }
            
            if (window.AppChannel) {
              window.AppChannel.postMessage('FORM_SUBMITTED');
            }
            
            return true;
          } catch (e) {
            if (window.AppChannel) {
              window.AppChannel.postMessage('FORM_PROCESS_FAILED');
            }
            return false;
          }
        }

        // 点击搜索按钮或提交表单
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

            if (window.AppChannel) {
              window.AppChannel.postMessage("点击搜索按钮完成");
            }

            return true;
          } catch (e) {
            if (window.AppChannel) {
              window.AppChannel.postMessage("点击搜索按钮出错: " + e);
            }

            try {
              const form = document.getElementById(CONFIG.FORM.FORM_ID);
              if (form) form.submit();
            } catch (e2) {}

            return false;
          }
        }

        // 执行模拟用户行为序列
        async function executeSequence() {
          try {
            // 优化后的点击序列，减少冗余但保留足够的真实性
            await clickTarget(true);
            await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.ACTION_DELAY_MS));

            await clickTarget(false);
            await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.ACTION_DELAY_MS));

            await clickTarget(true);
            await fillSearchInput();
            await new Promise(r => setTimeout(r, CONFIG.BEHAVIOR.ACTION_DELAY_MS));

            await clickSearchButton();

            window.__humanBehaviorSimulationRunning = false;

            resolve(true);
          } catch (e) {
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

      if (!form || !searchInput) {
        return false;
      }

      try {
        const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword);

        if (result) {
          if (window.AppChannel) {
            setTimeout(function() {
              window.AppChannel.postMessage('FORM_SUBMITTED');
            }, CONFIG.BEHAVIOR.NOTIFICATION_DELAY_MS);
          }

          return true;
        } else {
          // 使用封装的备用表单提交方法
          return fallbackFormSubmit(form);
        }
      } catch (e) {
        if (window.AppChannel) {
          window.AppChannel.postMessage('SIMULATION_FAILED');
        }

        // 使用封装的备用表单提交方法
        return fallbackFormSubmit(form);
      }
    }

    // 检查表单元素是否存在
    function checkFormElements() {
      try {
        if (window.__formCheckState.formFound || window.__humanBehaviorSimulationRunning) {
          return;
        }

        const currentTime = Date.now();
        window.__formCheckState.lastCheckTime = currentTime;

        const form = document.getElementById(CONFIG.FORM.FORM_ID);
        const searchInput = document.getElementById(CONFIG.FORM.SEARCH_INPUT_ID);

        if (form && searchInput) {
          window.__formCheckState.formFound = true;
          clearAllFormCheckInterval();

          (async function() {
            try {
              const result = await submitSearchForm();
              if (!result) {
                if (window.AppChannel) {
                  window.AppChannel.postMessage('FORM_PROCESS_FAILED');
                }
              }
            } catch (e) {
              if (window.AppChannel) {
                window.AppChannel.postMessage('FORM_PROCESS_FAILED');
              }
            }
          })();
        }
      } catch (e) {}
    }

    // 设置备份定时器
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

    // 设置主定时器
    function setupMainTimer() {
      if (window.__formCheckState.checkInterval) {
        clearInterval(window.__formCheckState.checkInterval);
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
