/// 检查页面是否有指定的元素
(function() {
    // 配置参数
    const CONFIG = {
        CHECK_INTERVAL: 500, // 检查间隔（毫秒）
        MIN_CONTENT_LENGTH: 8888, // 最小内容长度阈值
        MONITORED_SELECTORS: 'span[class="decrypted-link"], img[src="copy.png"], img[src$="/copy.png"]', // 监控的选择器
        CHANNEL_NAME: 'AppChannel', // 通信通道名称
        CONTENT_READY_MESSAGE: 'CONTENT_READY', // 内容就绪消息
        CONTENT_ERROR_MESSAGE: 'CONTENT_ERROR', // 内容错误消息
        MAX_WAIT_TIME: 6000 // 最大等待时间6秒
    };
    
    // 初始化通信通道
    window[CONFIG.CHANNEL_NAME] = window[CONFIG.CHANNEL_NAME] || {
        postMessage: message => {} // 空函数，防止未定义错误
    };
    
    // 任务完成标志
    let taskCompleted = false;
    
    // 记录开始时间
    const startTime = Date.now();
    
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
    
    // 优化的内容长度获取函数
    const getContentLength = function() {
        if (!document.body) return 0;
        
        // 先尝试使用textContent
        const textLength = document.body.textContent.length;
        
        // 如果文本长度已经满足条件，直接返回
        if (textLength >= CONFIG.MIN_CONTENT_LENGTH) {
            return textLength;
        }
        
        // 如果文本长度不够，再检查HTML长度
        return Math.max(textLength, document.body.innerHTML.length);
    };
    
    // 核心检查函数：检查是否满足条件
    const checkConditions = function() {
        // 任务已完成，停止检查
        if (taskCompleted) {
            return;
        }
        
        try {
            // 检查是否超时
            const elapsedTime = Date.now() - startTime;
            if (elapsedTime > CONFIG.MAX_WAIT_TIME) {
                // 超时了还没找到目标元素，认为页面有问题
                taskCompleted = true;
                logToDart(`超时未找到目标元素，已等待 ${elapsedTime}ms`);
                sendNotification(CONFIG.CONTENT_ERROR_MESSAGE);
                return;
            }
            
            // 获取当前状态
            const elements = document.querySelectorAll(CONFIG.MONITORED_SELECTORS);
            const elementCount = elements.length;
            
            // 使用优化后的内容长度获取方法
            const contentLength = getContentLength();
            
            // 判断是否满足条件
            const hasTargetElements = elementCount > 0;
            const hasEnoughContent = contentLength >= CONFIG.MIN_CONTENT_LENGTH;
            
            // 同时满足 找到目标元素（元素数量 > 0）和 内容长度足够 条件才会发送 CONTENT_READY
            if (hasTargetElements && hasEnoughContent) {
                // 条件满足，发送通知并标记任务完成
                taskCompleted = true;
                logToDart(`条件满足，任务完成 - 元素: ${elementCount}, 长度: ${contentLength}, 耗时: ${elapsedTime}ms`);
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
