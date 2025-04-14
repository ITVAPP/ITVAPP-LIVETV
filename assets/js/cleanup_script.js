// 停止页面加载
window.stop();

// 清理时间拦截器
if (window._cleanupTimeInterceptor) {
  window._cleanupTimeInterceptor();
}

// 清理所有活跃的XHR请求
const activeXhrs = window._activeXhrs || [];
activeXhrs.forEach(xhr => xhr.abort());

// 清理所有Fetch请求
if (window._abortController) {
  window._abortController.abort();
}

// 清理所有定时器
const highestTimeoutId = window.setTimeout(() => {}, 0);
for (let i = 0; i <= highestTimeoutId; i++) {
  window.clearTimeout(i);
  window.clearInterval(i);
}

// 清理所有事件监听器
window.removeEventListener('scroll', window._scrollHandler);
window.removeEventListener('popstate', window._urlChangeHandler);
window.removeEventListener('hashchange', window._urlChangeHandler);

// 清理M3U8检测器
if(window._cleanupM3U8Detector) {
  window._cleanupM3U8Detector();
}

// 终止所有正在进行的MediaSource操作
if (window.MediaSource) {
  const mediaSources = document.querySelectorAll('video source');
  mediaSources.forEach(source => {
    const mediaElement = source.parentElement;
    if (mediaElement) {
      mediaElement.pause();
      mediaElement.removeAttribute('src');
      mediaElement.load();
    }
  });
}

// 清理所有websocket连接
const sockets = window._webSockets || [];
sockets.forEach(socket => socket.close());

// 停止所有进行中的网络请求
if (window.performance && window.performance.getEntries) {
  const resources = window.performance.getEntries().filter(e =>
    e.initiatorType === 'xmlhttprequest' ||
    e.initiatorType === 'fetch' ||
    e.initiatorType === 'beacon'
  );
  resources.forEach(resource => {
    if (resource.duration === 0) {
      try {
        const controller = new AbortController();
        controller.abort();
      } catch(e) {}
    }
  });
}

// 清理所有未完成的图片加载
document.querySelectorAll('img').forEach(img => {
  if (!img.complete) {
    img.src = '';
  }
});

// 清理全局变量
delete window._timeInterceptorInitialized;
delete window._originalDate;
delete window._originalPerformanceNow;
delete window._originalRAF;
delete window._originalConsoleTime;
delete window._originalConsoleTimeEnd;
delete window._cleanupTimeInterceptor;
