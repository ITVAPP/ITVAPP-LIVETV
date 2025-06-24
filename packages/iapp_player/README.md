# IAppPlayer

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![GitHub Issues](https://img.shields.io/github/issues/你的用户名/MyCustomPlayer)](https://github.com/你的用户名/MyCustomPlayer/issues)
[![GitHub Stars](https://img.shields.io/github/stars/你的用户名/MyCustomPlayer)](https://github.com/你的用户名/MyCustomPlayer/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/你的用户名/MyCustomPlayer)](https://github.com/你的用户名/MyCustomPlayer/network)

> 🎥 **IAppPlayer** 是一个基于 Flutter 开发的高性能视频和音频播放器，不但支持多种流媒体格式，还针对低配置设备（如果TV和车机系统）进行了大量的优化！

## ✨ 功能特性

- 修复常见错误
- 重构播放器，针对 AndroidX Media3 做了大量优化适配
- 高级配置选项（支持设置优先软件或硬件解码，音频支持仅显示播放控件）
- 支持使用 Cronet 数据源和自动降级 Http 数据源（仅在安卓系统）
- 支持 FFmpeg 软件解码器，增强媒体格式支持
- 支持 RTMP 协议（包括分段字幕、音轨切换）
- 支持 RTSP 协议（包括轨道选择、分段字幕、音轨切换）
- 支持 HLS 协议（包括轨道选择、分段字幕、音轨切换）
- 支持 DASH 协议（包括轨道选择、字幕、音轨切换）
- 支持 SmoothStreaming 协议（包括轨道选择、字幕、音轨切换）
- 支持播放列表功能
- 支持 ListView 视频播放
- 支持字幕功能（支持 SRT、WEBVTT 格式及 HTML 标签，HLS 字幕，视频多字幕切换）
- 支持HTTP头部设置
- 支持视频适配（BoxFit）
- 支持播放速度调节
- 支持多种分辨率切换
- 支持缓存功能
- 支持通知功能
- 支持画中画模式
- 支持DRM保护（包括令牌、Widevine、FairPlay EZDRM）
- ……更多功能待体验！

## 🚀 快速开始

### 📋 环境要求

- Java 11+ / Node.js 16+
- Android SDK 30+
- 其他平台特定依赖（请查看具体平台文档）

### 📦 安装步骤

1. **克隆仓库**
   ```bash
   git clone https://github.com/你的用户名/MyCustomPlayer.git
   ```

2. **进入项目目录**
   ```bash
   cd MyCustomPlayer
   ```

3. **安装依赖**
   ```bash
   npm install
   # 或者使用其他包管理器
   # yarn install
   # ./gradlew build
   ```

4. **构建项目**
   ```bash
   npm run build
   # 或者
   # ./gradlew build
   ```

### 💻 使用示例

```javascript
import { MyCustomPlayer } from 'com.mycustomplayer';

// 创建播放器实例
const player = new MyCustomPlayer({
  url: 'https://example.com/video.mp4',
  autoplay: true,
  controls: true,
  responsive: true
});

// 开始播放
player.play();

// 监听事件
player.on('ready', () => {
  console.log('播放器准备就绪');
});

player.on('error', (error) => {
  console.error('播放错误:', error);
});
```

更多详细用法请参考 [📖 API 文档](docs/) 或代码注释。

## 📄 许可证

本项目遵循 **Apache License, Version 2.0** 开源协议。

### 许可证要求

根据 Apache 2.0 许可证：

- ✅ **可以自由使用、修改和分发**
- ✅ **可用于商业目的**
- ✅ **可以私有化修改**
- ⚠️ **需要保留版权声明和许可证**

### 版权信息

**原项目版权：**
```
Copyright 2020 Jakub Homlala and Better Player / Chewie / Video Player contributors
```

**本项目版权：**
```
Copyright [WWW.ITVAPP.NET] 2025 for modifications
```

完整许可证文本请查看 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- 特别感谢 [Better Player / Chewie / Video Player] 项目提供的优秀开源代码基础。
- 本项目在以上播放器的开源基础上进行定制化开发，旨在为特定需求提供更好的解决方案。

## 📞 联系方式

- 🐛 **问题反馈**：[GitHub Issues](https://github.com/你的用户名/MyCustomPlayer/issues)
- 📧 **邮箱联系**：你的邮箱地址
- 💬 **社区讨论**：[加入我们的讨论](https://github.com/你的用户名/MyCustomPlayer/discussions)

## 🚨 重要提示

本库不对video_player库引发的问题负责，仅作为其上层UI封装。

即：应用中因视频播放导致的PlatformExceptions（平台异常）均由video_player库引起。

请向Flutter团队提交相关问题。

## 🔀 Flutter版本兼容性

本库至少尽力支持Flutter倒数第二个版本（N-1支持）。

但因Flutter版本重大变化，可能无法完全保证兼容性，必要时将发布重大或次要版本更新。

---

<div align="center">

**如果这个项目对你有帮助，请给个 ⭐ Star 支持一下！**

[⬆ 回到顶部](#mycustomplayer)

</div>
