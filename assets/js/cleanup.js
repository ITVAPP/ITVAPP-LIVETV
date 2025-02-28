// URL整理注入
window.stop();
if (window._cleanupTimeInterceptor) window._cleanupTimeInterceptor();
const activeXhrs = window._activeXhrs || []; activeXhrs.forEach(xhr => xhr.abort());
if (window._abortController) window._abortController.abort();
const highestTimeoutId = window.setTimeout(() => {}, 0);
for (let i = 0; i <= highestTimeoutId; i++) { window.clearTimeout(i); window.clearInterval(i); }
window.removeEventListener('scroll', window._scrollHandler);
window.removeEventListener('popstate', window._urlChangeHandler);
window.removeEventListener('hashchange', window._urlChangeHandler);
if (window._cleanupM3U8Detector) window._cleanupM3U8Detector();
document.querySelectorAll('video source').forEach(source => {
  const mediaElement = source.parentElement;
  if (mediaElement) { mediaElement.pause(); mediaElement.removeAttribute('src'); mediaElement.load(); }
});
const sockets = window._webSockets || []; sockets.forEach(socket => socket.close());
if (window.performance && window.performance.getEntries) {
  window.performance.getEntries().filter(e => 
    ['xmlhttprequest', 'fetch', 'beacon'].includes(e.initiatorType) && e.duration === 0
  ).forEach(() => { try { new AbortController().abort(); } catch(e) {} });
}
document.querySelectorAll('img').forEach(img => { if (!img.complete) img.src = ''; });
delete window._timeInterceptorInitialized;
delete window._originalDate;
delete window._originalPerformanceNow;
delete window._originalRAF;
delete window._originalConsoleTime;
delete window._originalConsoleTimeEnd;
delete window._cleanupTimeInterceptor;
