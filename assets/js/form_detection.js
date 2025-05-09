(function() {
  console.log("开始注入表单检测脚本");
  
  // 存储检查状态
  window.__formCheckState = {
    formFound: false,
    checkInterval: null,
    searchKeyword: "{{SEARCH_KEYWORD}}"
  };
  
  // 清理检查定时器
  function clearFormCheckInterval() {
    if (window.__formCheckState.checkInterval) {
      clearInterval(window.__formCheckState.checkInterval);
      window.__formCheckState.checkInterval = null;
      console.log("停止表单检测");
    }
  }
  
  // 定义人类行为模拟常量
  const MOUSE_MOVEMENT_STEPS = 6;        // 鼠标移动步数（次数）
  const MOUSE_MOVEMENT_OFFSET = 6;       // 鼠标移动偏移量（像素）
  const MOUSE_MOVEMENT_DELAY_MS = 100;    // 鼠标移动延迟（毫秒）
  const MOUSE_HOVER_TIME_MS = 300;       // 鼠标悬停时间（毫秒）
  const MOUSE_PRESS_TIME_MS = 300;       // 鼠标按压时间（毫秒）
  const ACTION_DELAY_MS = 1000;          // 操作间隔时间（毫秒）
  
  // 改进后的模拟真人行为函数
  function simulateHumanBehavior(searchKeyword) {
    return new Promise((resolve) => {
      if (window.AppChannel) {
        window.AppChannel.postMessage('开始模拟真人行为');
      }
      
      // 获取搜索输入框
      const searchInput = document.getElementById('search');
      
      if (!searchInput) {
        console.log("未找到搜索输入框");
        if (window.AppChannel) {
          window.AppChannel.postMessage("未找到搜索输入框");
        }
        return resolve(false);
      }
      
      // 跟踪上一次点击的位置，用于模拟鼠标移动
      let lastX = window.innerWidth / 2;
      let lastY = window.innerHeight / 2;
      
      // 获取输入框的位置和大小
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
      
      // 模拟鼠标移动轨迹，使用固定步数和固定延迟
      async function moveMouseBetweenPositions(fromX, fromY, toX, toY) {
        const steps = MOUSE_MOVEMENT_STEPS; // 固定步数
        
        if (window.AppChannel) {
          window.AppChannel.postMessage("开始移动鼠标");
        }
        
        for (let i = 0; i < steps; i++) {
          const progress = i / steps;
          // 使用固定偏移量
          const offsetX = Math.sin(progress * Math.PI) * MOUSE_MOVEMENT_OFFSET;
          const offsetY = Math.sin(progress * Math.PI) * MOUSE_MOVEMENT_OFFSET;
          
          const curX = fromX + (toX - fromX) * progress + offsetX;
          const curY = fromY + (toY - fromY) * progress + offsetY;
          
          const mousemoveEvent = new MouseEvent('mousemove', {
            'view': window,
            'bubbles': true,
            'cancelable': true,
            'clientX': curX,
            'clientY': curY
          });
          
          const elementAtPoint = document.elementFromPoint(curX, curY);
          if (elementAtPoint) {
            elementAtPoint.dispatchEvent(mousemoveEvent);
          } else {
            document.body.dispatchEvent(mousemoveEvent);
          }
          
          await new Promise(r => setTimeout(r, MOUSE_MOVEMENT_DELAY_MS)); // 固定延迟
        }
        
        if (window.AppChannel) {
          window.AppChannel.postMessage("完成鼠标移动");
        }
      }
      
      // 模拟鼠标悬停，使用固定时间
      async function simulateHover(targetElement, x, y) {
        return new Promise((hoverResolve) => {
          try {
            const mouseoverEvent = new MouseEvent('mouseover', {
              'view': window,
              'bubbles': true,
              'cancelable': true,
              'clientX': x,
              'clientY': y
            });
            targetElement.dispatchEvent(mouseoverEvent);
            
            // 固定悬停时间
            const hoverTime = MOUSE_HOVER_TIME_MS;
            
            setTimeout(() => {
              hoverResolve();
            }, hoverTime);
          } catch (e) {
            console.log("悬停操作出错: " + e);
            hoverResolve();
          }
        });
      }
      
      // 完整的点击操作，使用固定按压时间
      async function simulateClick(targetElement, x, y) {
        return new Promise((clickResolve) => {
          try {
            // 创建并触发mousedown事件
            const mousedownEvent = new MouseEvent('mousedown', {
              'view': window,
              'bubbles': true,
              'cancelable': true,
              'clientX': x,
              'clientY': y,
              'buttons': 1  // 按下状态
            });
            targetElement.dispatchEvent(mousedownEvent);
            
            // 固定按压时间
            const pressTime = MOUSE_PRESS_TIME_MS;
            
            // 持续按压一段时间后释放
            setTimeout(() => {
              // 创建并触发mouseup事件
              const mouseupEvent = new MouseEvent('mouseup', {
                'view': window,
                'bubbles': true,
                'cancelable': true,
                'clientX': x,
                'clientY': y,
                'buttons': 0  // 释放状态
              });
              targetElement.dispatchEvent(mouseupEvent);
              
              // 创建并触发click事件
              const clickEvent = new MouseEvent('click', {
                'view': window,
                'bubbles': true,
                'cancelable': true,
                'clientX': x,
                'clientY': y
              });
              targetElement.dispatchEvent(clickEvent);
              
              // 如果目标是输入框，确保获得焦点
              if (targetElement === searchInput) {
                searchInput.focus();
              }
              
              // 更新最后点击位置
              lastX = x;
              lastY = y;
              
              // 解析点击操作完成
              clickResolve();
            }, pressTime);
            
          } catch (e) {
            console.log("点击操作出错: " + e);
            if (window.AppChannel) {
              window.AppChannel.postMessage("点击操作出错: " + e);
            }
            clickResolve(); // 即使出错也继续流程
          }
        });
      }
      
      // 获取输入框或输入框上方随机位置，并点击
      async function clickTarget(isInputBox) {
        try {
          const pos = getInputPosition();
          let targetX, targetY, elementDescription;
          let targetElement = null;
          
          if (isInputBox) {
            // 输入框内部位置 (居中位置)
            targetX = pos.left + pos.width * 0.5;
            targetY = pos.top + pos.height * 0.5;
            elementDescription = "输入框";
            
            // 输入框肯定是有效元素
            targetElement = searchInput;
          } else {
            // 输入框上方25px的固定位置
            targetX = pos.left + pos.width * 0.5; // 输入框宽度中心
            targetY = Math.max(pos.top - 25, 5); // 上方25px，确保不小于5px
            elementDescription = "输入框上方空白处";
            
            // 尝试获取该位置的元素
            targetElement = document.elementFromPoint(targetX, targetY);
            
            // 确保我们找到有效元素，如果没有则稍微调整位置
           if (!targetElement) {
             // 尝试向下移动一点
             for (let attempt = 1; attempt <= 5; attempt++) {
               // 每次往下移动2px
               targetY += 2;
               targetElement = document.elementFromPoint(targetX, targetY);
               if (targetElement) break;
             }
             
             // 如果仍然没找到，使用body
             if (!targetElement) {
               console.log("未在指定位置找到元素，使用body");
               targetElement = document.body;
             }
           }
         }
         
         if (window.AppChannel) {
           window.AppChannel.postMessage("准备点击" + elementDescription);
         }
         
         // 先移动鼠标到目标位置
         await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
         
         // 短暂悬停
         await simulateHover(targetElement, targetX, targetY);
         
         // 执行点击操作
         await simulateClick(targetElement, targetX, targetY);
         
         if (window.AppChannel) {
           window.AppChannel.postMessage("点击" + elementDescription + "完成");
         }
         
         return true;
       } catch (e) {
         console.log("点击操作出错: " + e);
         if (window.AppChannel) {
           window.AppChannel.postMessage("点击操作出错: " + e);
         }
         return false;
       }
     }
     
     // 填写搜索关键词
     async function fillSearchInput() {
       try {
         // 先清空输入框
         searchInput.value = '';
         
         // 填写整个关键词
         searchInput.value = searchKeyword;
         
         // 触发input事件
         const inputEvent = new Event('input', { bubbles: true, cancelable: true });
         searchInput.dispatchEvent(inputEvent);
         
         // 触发change事件
         const changeEvent = new Event('change', { bubbles: true, cancelable: true });
         searchInput.dispatchEvent(changeEvent);
         
         if (window.AppChannel) {
           window.AppChannel.postMessage("填写了搜索关键词: " + searchKeyword);
         }
         
         return true;
       } catch (e) {
         console.log("填写搜索关键词出错: " + e);
         if (window.AppChannel) {
           window.AppChannel.postMessage("填写搜索关键词出错: " + e);
         }
         return false;
       }
     }
     
     // 点击搜索按钮
     async function clickSearchButton() {
       try {
         const form = document.getElementById('form1');
         if (!form) {
           console.log("未找到表单");
           return false;
         }
         
         // 查找提交按钮
         const submitButton = form.querySelector('input[type="submit"], button[type="submit"], input[name="Submit"]');
         
         if (!submitButton) {
           console.log("未找到提交按钮，直接提交表单");
           form.submit();
           return true;
         }
         
         // 获取按钮位置
         const rect = submitButton.getBoundingClientRect();
         
         // 按钮内居中位置
         const targetX = rect.left + rect.width * 0.5;
         const targetY = rect.top + rect.height * 0.5;
         
         if (window.AppChannel) {
           window.AppChannel.postMessage("准备点击搜索按钮");
         }
         
         // 先移动鼠标到按钮位置
         await moveMouseBetweenPositions(lastX, lastY, targetX, targetY);
         
         // 悬停在按钮上
         await simulateHover(submitButton, targetX, targetY);
         
         // 执行点击操作
         await simulateClick(submitButton, targetX, targetY);
         
         if (window.AppChannel) {
           window.AppChannel.postMessage("点击搜索按钮完成");
         }
         
         return true;
       } catch (e) {
         console.log("点击搜索按钮出错: " + e);
         if (window.AppChannel) {
           window.AppChannel.postMessage("点击搜索按钮出错: " + e);
         }
         
         // 出错时尝试直接提交表单
         try {
           const form = document.getElementById('form1');
           if (form) form.submit();
         } catch (e2) {
           console.log("备用提交方式也失败: " + e2);
         }
         
         return false;
       }
     }
     
     // 执行完整的模拟操作序列，使用固定延迟
     async function executeSequence() {
       try {
         // 1. 点击输入框并输入
         await clickTarget(true);
         await new Promise(r => setTimeout(r, ACTION_DELAY_MS)); // 固定延迟1000ms
         await fillSearchInput();
         await new Promise(r => setTimeout(r, ACTION_DELAY_MS)); // 固定延迟1000ms
         
         // 2. 点击输入框上方空白处
         await clickTarget(false);
         await new Promise(r => setTimeout(r, ACTION_DELAY_MS)); // 固定延迟1000ms
         
         // 3. 最后点击搜索按钮
         await clickSearchButton();
         
         resolve(true);
       } catch (e) {
         console.log("模拟序列执行出错: " + e);
         if (window.AppChannel) {
           window.AppChannel.postMessage("模拟序列执行出错: " + e);
         }
         resolve(false);
       }
     }
     
     // 开始执行模拟序列
     executeSequence();
   });
 }
 
 // 修改后的表单提交流程，直接使用模拟真人行为函数
 async function submitSearchForm() {
   console.log("准备提交搜索表单");
   
   const form = document.getElementById('form1'); // 所有引擎统一使用相同ID选择器
   const searchInput = document.getElementById('search'); // 所有引擎统一使用相同ID选择器
   
   if (!form || !searchInput) {
     console.log("未找到有效的表单元素");
     // 记录页面状态，方便调试
     console.log("表单数量: " + document.forms.length);
     for(let i = 0; i < document.forms.length; i++) {
       console.log("表单 #" + i + " ID: " + document.forms[i].id);
     }
     
     const inputs = document.querySelectorAll('input');
     console.log("输入框数量: " + inputs.length);
     for(let i = 0; i < inputs.length; i++) {
       console.log("输入 #" + i + " ID: " + inputs[i].id + ", Name: " + inputs[i].name);
     }
     return false;
   }
   
   console.log("找到表单和输入框");
   
   // 执行模拟真人行为（包含所有所需步骤）
   try {
     console.log("开始模拟真人行为");
     const result = await simulateHumanBehavior(window.__formCheckState.searchKeyword);
     
     if (result) {
       console.log("模拟真人行为成功");
       
       // 通知Flutter表单已提交
       if (window.AppChannel) {
         setTimeout(function() {
           window.AppChannel.postMessage('FORM_SUBMITTED');
         }, 300);
       }
       
       return true;
     } else {
       console.log("模拟真人行为失败，尝试常规提交");
       
       // 尝试常规提交方式
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
       } catch (e2) {
         console.log("备用提交方式也失败: " + e2);
         if (window.AppChannel) {
           window.AppChannel.postMessage('FORM_PROCESS_FAILED');
         }
         return false;
       }
     }
   } catch (e) {
     console.log("模拟行为失败: " + e);
     
     // 即使模拟行为失败，我们也继续提交表单
     if (window.AppChannel) {
       window.AppChannel.postMessage('SIMULATION_FAILED');
     }
     
     // 尝试常规提交方式
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
     } catch (e2) {
       console.log("备用提交方式也失败: " + e2);
       if (window.AppChannel) {
         window.AppChannel.postMessage('FORM_PROCESS_FAILED');
       }
       return false;
     }
   }
 }
 
 // 修改: 改进表单检测函数，确保更可靠的异步处理
 function checkFormElements() {
   // 检查表单元素
   const form = document.getElementById('form1');
   const searchInput = document.getElementById('search');
   
   console.log("检查表单元素");
   
   if (form && searchInput) {
     console.log("找到表单元素!");
     window.__formCheckState.formFound = true;
     clearFormCheckInterval();
     
     // 使用立即执行的异步函数包装
     (async function() {
       try {
         const result = await submitSearchForm();
         if (result) {
           console.log("表单处理成功");
         } else {
           console.log("表单处理失败");
           
           // 通知Flutter表单处理失败
           if (window.AppChannel) {
             window.AppChannel.postMessage('FORM_PROCESS_FAILED');
           }
         }
       } catch (e) {
         console.log("表单提交异常: " + e);
         
         // 通知Flutter表单处理失败
         if (window.AppChannel) {
           window.AppChannel.postMessage('FORM_PROCESS_FAILED');
         }
       }
     })();
   }
 }
 
 // 开始定时检查
 clearFormCheckInterval(); // 清除可能存在的旧定时器
 window.__formCheckState.checkInterval = setInterval(checkFormElements, 500); // 每500ms检查一次
 console.log("开始定时检查表单元素");
 
 // 立即执行一次检查
 checkFormElements();
})();
