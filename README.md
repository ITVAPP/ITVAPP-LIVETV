当前播放列表 URL 配置 videoDefaultChannelHost() 方法根据用户的语言环境（是否为中文）返回不同的 URL：

中文环境： 'https://gitee.com/AMuMuSir/itvapp_livetv/raw/main/temp';

非中文环境： 'https://raw.githubusercontent.com/aiyakuaile/itvapp_livetv/main/temp';

如何修改播放列表的 URL 如果你想修改这个 URL，例如更改为自己的服务器地址，可以直接修改 videoDefaultChannelHost() 方法中的 URL。例如，将其更改为你的自定义 URL：

static String videoDefaultChannelHost() { return 'https://your-custom-server.com/path/to/playlist'; }

修改步骤 打开 env_util.dart 文件。 找到 videoDefaultChannelHost() 方法。 替换 URL 为你自己的播放列表地址。 完成这些修改后，应用将从你指定的新 URL 加载最新的播放列表。
