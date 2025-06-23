IAppPlayerDataSource 里增加下面参数可以设置解码优先选择：

使用硬件解码优先:
preferredDecoderType: IAppPlayerDecoderType.hardwareFirst,

使用软件解码优先:
preferredDecoderType: IAppPlayerDecoderType.softwareFirst,

自动选择解码器（默认）:
preferredDecoderType: IAppPlayerDecoderType.auto,


