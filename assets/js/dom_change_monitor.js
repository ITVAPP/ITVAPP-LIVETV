(function() {
    // 配置参数
    const CONFIG = {
        CHECK_INTERVAL: 500, // 检查间隔（毫秒）
        MIN_CONTENT_LENGTH: 8888, // 最小内容长度阈值
        MONITORED_SELECTORS: 'span[class="decrypted-link"], img[src="copy.png"], img[src$="/copy.png"]', // 监控的选择器
        CHANNEL_NAME: 'AppChannel', // 通信通道名称
        CONTENT_READY_MESSAGE: 'CONTENT_READY' // 内容就绪消息
    };
    
    // 初始化通信通道
    window[CONFIG.CHANNEL_NAME] = window[CONFIG.CHANNEL_NAME] || {
        postMessage: message => {} // 空函数，防止未定义错误
    };
    
    // 任务完成标志
    let taskCompleted = false;
    
    // 发送日志到Dart
    const logToDart = function(message) {
        try {
            if (window[CONFIG.CHANNEL_NAME]) {
                window[CONFIG.CHANNEL_NAME].postMessage(`DOM监听器: ${message}`);
            }
        } catch (e) {
            // 静默处理日志发送失败
        }
    };
    
    // 发送通知消息到Dart
    const sendNotification = function(message) {
        try {
            if (window[CONFIG.CHANNEL_NAME]) {
                window[CONFIG.CHANNEL_NAME].postMessage(message);
                logToDart("已发送消息: " + message);
            }
        } catch (e) {
            logToDart("消息发送失败: " + e.message);
        }
    };
    
    // 核心检查函数：检查是否满足条件
    const checkConditions = function() {
        // 任务已完成，停止检查
        if (taskCompleted) {
            return;
        }
        
        try {
            // 获取当前状态
            const elements = document.querySelectorAll(CONFIG.MONITORED_SELECTORS);
            const elementCount = elements.length;
            
            // 确保每次都获取页面的最新内容长度
            const contentLength = document.body ? document.body.innerHTML.length : 0;
            
            // 判断是否满足条件
            const hasTargetElements = elementCount > 0;
            const hasEnoughContent = contentLength >= CONFIG.MIN_CONTENT_LENGTH;
            
            // 同时满足 找到目标元素（元素数量 > 0）和 内容长度足够 条件才会发送 CONTENT_READY
            if (hasTargetElements && hasEnoughContent) {
                // 条件满足，发送通知并标记任务完成
                taskCompleted = true;
                logToDart(`条件满足，任务完成 - 元素: ${elementCount}, 长度: ${contentLength}`);
                sendNotification(CONFIG.CONTENT_READY_MESSAGE);
            }
        } catch (e) {
            logToDart("检查过程出错: " + e.message);
        }
    };
    
    // 立即执行一次检查
    checkConditions();
    
    // 设置定时检查
    const checkInterval = setInterval(function() {
        checkConditions();
        
        // 任务完成后清理定时器
        if (taskCompleted) {
            clearInterval(checkInterval);
        }
    }, CONFIG.CHECK_INTERVAL);
})();
