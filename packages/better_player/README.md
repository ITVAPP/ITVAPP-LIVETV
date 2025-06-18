BetterPlayerDataSource 里增加下面参数可以设置解码优先选择：

使用硬件解码优先:
preferredDecoderType: BetterPlayerDecoderType.hardwareFirst,

使用软件解码优先:
preferredDecoderType: BetterPlayerDecoderType.softwareFirst,

自动选择解码器（默认）:
preferredDecoderType: BetterPlayerDecoderType.auto,


查看原生播放器日志可以在监听逻辑增加下面方法：
    // 检查是否是来自原生层播放器的日志
    final parameters = event.parameters;
    if (parameters != null && parameters['event'] == 'log') {
      final message = parameters['message'] ?? '';
      LogUtil.i('[原生播放器] $message');
      return;
    }
