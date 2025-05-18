(function() {
    // 定义监控配置参数
    const CONFIG = {
        CHECK_INTERVAL: 500, // 检查间隔（毫秒）
        MIN_CONTENT_LENGTH: 8888, // 最小内容长度
        MAX_WAIT_TIME: 8000, // 最大等待时间
        MONITORED_SELECTORS: 'span[class="decrypted-link"], img[src="copy.png"], img[src$="/copy.png"]', // 监控的选择器
        CHANNEL_NAME: 'AppChannel', // 通知通道名称
        CONTENT_READY_MESSAGE: 'CONTENT_READY', // 内容就绪消息
        CONTENT_CHANGED_MESSAGE: 'CONTENT_CHANGED' // 内容变化消息
    };

    // 初始化通知通道，防止未定义
    window[CONFIG.CHANNEL_NAME] = window[CONFIG.CHANNEL_NAME] || {
        postMessage: message => {} // 空函数，无输出
    };

    // 定义状态跟踪变量
    let readinessCheckInterval = null;
    let readinessReported = false;
    let lastReportedCount = 0;
    let lastReportedLength = 0; // 跟踪上次报告的内容长度

    // 发送日志到Dart
    const logToDart = function(message) {
        try {
            if (window[CONFIG.CHANNEL_NAME]) {
                window[CONFIG.CHANNEL_NAME].postMessage(`DOM监听器: ${message}`);
            }
        } catch (e) {
            // 日志功能失败，静默处理
        }
    };

    // 发送通知消息
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

    // 获取最新HTML内容长度
    const getLatestHtmlLength = function() {
        try {
            void document.documentElement.offsetHeight; // 强制刷新DOM布局
            return document.documentElement.outerHTML.length;
        } catch (e) {
            logToDart("获取HTML长度失败: " + e.message);
            return 0;
        }
    };

    // 检查关键元素存在性及数量
    const hasKeyElements = function() {
        try {
            const elements = document.querySelectorAll(CONFIG.MONITORED_SELECTORS);
            const count = elements.length;
            logToDart("元素检查: " + (count ? "找到 " + count + " 个元素" : "未找到元素"));
            return { exists: count > 0, count };
        } catch (e) {
            logToDart("元素检查失败: " + e.message);
            return { exists: false, count: 0 };
        }
    };

    // 检查内容是否就绪
    const checkContentReadiness = function() {
        const startTime = Date.now();
        logToDart("开始检查内容就绪状态");

        const isContentReady = function() {
            const contentLength = getLatestHtmlLength();
            const elemResult = hasKeyElements();
            logToDart("内容检查 - 长度: " + contentLength + ", 元素数: " + elemResult.count);

            // 检测内容变化
            if (elemResult.exists && elemResult.count !== lastReportedCount && readinessReported) {
                lastReportedCount = elemResult.count;
                lastReportedLength = contentLength;
                logToDart("内容已变化，元素数: " + elemResult.count + ", 长度: " + contentLength);
                sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
            } else if (contentLength > lastReportedLength + 1000 && readinessReported) {
                lastReportedLength = contentLength;
                logToDart("内容长度显著变化: " + contentLength);
                sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
            }

            return contentLength >= CONFIG.MIN_CONTENT_LENGTH || elemResult.exists;
        };

        // 立即检查内容
        if (isContentReady()) {
            const currentLength = getLatestHtmlLength();
            const currentElements = hasKeyElements();
            logToDart("内容立即就绪，长度: " + currentLength);
            sendNotification(CONFIG.CONTENT_READY_MESSAGE);
            readinessReported = true;
            lastReportedCount = currentElements.count;
            lastReportedLength = currentLength;
            return;
        }

        // 定时检查内容
        readinessCheckInterval = setInterval(() => {
            const elapsedTime = Date.now() - startTime;

            if (elapsedTime > CONFIG.MAX_WAIT_TIME) {
                logToDart("超过最大等待时间: " + elapsedTime + "ms");
                clearInterval(readinessCheckInterval);
                readinessCheckInterval = null;

                if (!readinessReported) {
                    const finalLength = getLatestHtmlLength();
                    if (finalLength > 1000) {
                        logToDart("超时但内容非空，长度: " + finalLength + "，视为就绪");
                        readinessReported = true;
                        lastReportedLength = finalLength;
                        sendNotification(CONFIG.CONTENT_READY_MESSAGE);
                    }
                }
                return;
            }

            if (isContentReady()) {
                clearInterval(readinessCheckInterval);
                readinessCheckInterval = null;

                if (!readinessReported) {
                    readinessReported = true;
                    lastReportedLength = getLatestHtmlLength();
                    lastReportedCount = hasKeyElements().count;
                    logToDart("内容就绪，耗时: " + elapsedTime + "ms, 长度: " + lastReportedLength);
                    sendNotification(CONFIG.CONTENT_READY_MESSAGE);
                }
            }
        }, CONFIG.CHECK_INTERVAL);
    };

    // 设置DOM变化监听
    const setupMutationObserver = function() {
        if (!window.MutationObserver) {
            logToDart("MutationObserver不可用");
            return null;
        }

        const observer = new MutationObserver((mutations) => {
            if (readinessReported) {
                const currentLength = getLatestHtmlLength();
                const currentElements = hasKeyElements();

                if (currentElements.count !== lastReportedCount || currentLength > lastReportedLength + 1000) {
                    logToDart("检测到DOM变化，元素: " + lastReportedCount + 
                             " -> " + currentElements.count + ", 长度: " + 
                             lastReportedLength + " -> " + currentLength);
                    lastReportedCount = currentElements.count;
                    lastReportedLength = currentLength;
                    sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
                }
            }
        });

        observer.observe(document.body, { childList: true, subtree: true });
        logToDart("已设置DOM变化监听器");

        return function() {
            observer.disconnect();
            logToDart("已断开DOM变化监听器");
        };
    };

    // 清理资源
    let disconnectObserver = null;
    const cleanup = function() {
        logToDart("开始清理资源");

        if (readinessCheckInterval) {
            clearInterval(readinessCheckInterval);
            readinessCheckInterval = null;
        }

        if (disconnectObserver) {
            disconnectObserver();
            disconnectObserver = null;
        }

        window.removeEventListener('beforeunload', cleanup);
    };

    // 注册清理事件
    window.addEventListener('beforeunload', cleanup);

    // 初始化内容监控
    logToDart("内容监控已初始化，监控选择器: " + CONFIG.MONITORED_SELECTORS);
    checkContentReadiness();

    // 初始化DOM变化监听
    disconnectObserver = setupMutationObserver();

    // 周期性检查内容变化
    setInterval(() => {
        if (readinessReported) {
            const currentElements = hasKeyElements();
            const currentLength = getLatestHtmlLength();

            if (currentElements.count !== lastReportedCount || currentLength > lastReportedLength + 2000) {
                logToDart("周期检查发现变化: 元素 " + lastReportedCount + 
                         " -> " + currentElements.count + ", 长度 " + 
                         lastReportedLength + " -> " + currentLength);
                lastReportedCount = currentElements.count;
                lastReportedLength = currentLength;
                sendNotification(CONFIG.CONTENT_CHANGED_MESSAGE);
            }
        }
    }, 1000); // 每秒检查一次
})();
