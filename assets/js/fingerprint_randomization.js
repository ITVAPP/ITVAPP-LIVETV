/// 修改 Canvas 指纹、视口信息、屏幕信息、生成会话 ID
(function() {
  // 覆写Canvas指纹以随机化渲染
  const originalGetContext = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function(contextType) {
    const context = originalGetContext.apply(this, arguments);
    if (contextType === '2d') {
      const originalFillText = context.fillText;
      context.fillText = function() {
        context.rotate(Math.random() * 0.0001); // 添加微小旋转扰动
        const result = originalFillText.apply(this, arguments);
        context.rotate(-Math.random() * 0.0001); // 恢复旋转
        return result;
      };
    }
    return context;
  };

  // 随机化视口缩放比例
  const viewportScale = (0.97 + Math.random() * 0.06).toFixed(2);
  const meta = document.querySelector('meta[name="viewport"]');
  if (meta) {
    meta.content = "width=device-width, initial-scale=" + viewportScale + ", maximum-scale=1.0";
  } else {
    const newMeta = document.createElement('meta');
    newMeta.name = 'viewport';
    newMeta.content = "width=device-width, initial-scale=" + viewportScale + ", maximum-scale=1.0";
    if (document.head) document.head.appendChild(newMeta);
  }

  // 随机化屏幕尺寸信息
  const originalWidth = window.screen.width;
  const originalHeight = window.screen.height;
  const offsetX = Math.floor(Math.random() * 4); // 宽度随机偏移
  const offsetY = Math.floor(Math.random() * 4); // 高度随机偏移

  Object.defineProperty(screen, 'width', {
    get: function() { return originalWidth + offsetX; }
  });

  Object.defineProperty(screen, 'height', {
    get: function() { return originalHeight + offsetY; }
  });

  // 生成并存储随机会话ID
  if (!window.sessionStorage.getItem('_sid')) {
    const randomId = Math.random().toString(36).substring(2, 15);
    window.sessionStorage.setItem('_sid', randomId);
  }
})();
