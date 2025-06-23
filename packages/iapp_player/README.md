# MyCustomPlayer

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![GitHub Issues](https://img.shields.io/github/issues/你的用户名/MyCustomPlayer)](https://github.com/你的用户名/MyCustomPlayer/issues)
[![GitHub Stars](https://img.shields.io/github/stars/你的用户名/MyCustomPlayer)](https://github.com/你的用户名/MyCustomPlayer/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/你的用户名/MyCustomPlayer)](https://github.com/你的用户名/MyCustomPlayer/network)

> 🎥 一个基于 [Better Player](https://github.com/jhomlala/betterplayer) 的高性能视频播放器

**MyCustomPlayer** 是一个经过大幅修改和优化的视频播放器项目，在原 Better Player 的基础上进行了全面的包名和文件结构重构，同时保留核心功能并引入了自定义改进。

## ✨ 功能特性

- 🎬 **高质量播放** - 支持多种视频格式的流畅播放
- 📦 **优化架构** - 重构的包名和文件结构，更符合现代开发规范
- 🎨 **自定义 UI** - 可定制的播放器界面和交互体验
- 🚀 **性能优化** - 优化的流媒体处理和更低的延迟
- 📱 **跨平台** - 支持多个平台的一致播放体验

## 🔄 修改内容

本项目基于 [Better Player](https://github.com/jhomlala/betterplayer) 开发，主要修改包括：

### 📂 包名和文件结构
- **包名更改**：从 `com.betterplayer` 统一改为 `com.mycustomplayer`
- **文件重命名**：按新命名规范重构几乎所有源文件
- **模块化设计**：增强代码结构的模块化和可维护性

### 🛠️ 功能优化
- 更新依赖库版本，提升兼容性和性能
- 优化播放器逻辑，减少延迟并修复已知问题
- 增强错误处理和异常恢复机制

> **📝 注意**：由于修改涉及几乎所有文件，具体更改请参考源代码或 [CHANGELOG.md](CHANGELOG.md)

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

## 🤝 贡献指南

我们欢迎并感谢任何形式的贡献！

### 如何贡献

1. 🍴 **Fork** 本仓库
2. 🌟 创建你的功能分支
   ```bash
   git checkout -b feature/新功能名称
   ```
3. 💾 提交更改
   ```bash
   git commit -m 'feat: 添加新功能描述'
   ```
4. 📤 推送分支
   ```bash
   git push origin feature/新功能名称
   ```
5. 🔃 提交 **Pull Request**

### 代码规范

- 遵循现有的代码风格
- 添加适当的测试用例
- 更新相关文档

更多详情请阅读 [贡献指南](CONTRIBUTING.md)。

## 📄 许可证

本项目遵循 **Apache License, Version 2.0** 开源协议。

### 许可证要求

根据 Apache 2.0 许可证：

- ✅ **可以自由使用、修改和分发**
- ✅ **可用于商业目的**
- ✅ **可以私有化修改**
- ⚠️ **需要保留版权声明和许可证**
- ⚠️ **需要说明修改内容**

### 版权信息

**原项目版权：**
```
Copyright 2020 Jakub Homlala and Better Player / Chewie / Video Player contributors
```

**本项目修改版权：**
```
Copyright [你的名字] 2025 for modifications
```

完整许可证文本请查看 [LICENSE](LICENSE) 文件。

## 🙏 致谢

特别感谢 [Better Player](https://github.com/jhomlala/betterplayer) 项目及其贡献者们提供的优秀开源代码基础。本项目在其基础上进行定制化开发，旨在为特定需求提供更好的解决方案。

## 📞 联系方式

- 🐛 **问题反馈**：[GitHub Issues](https://github.com/你的用户名/MyCustomPlayer/issues)
- 📧 **邮箱联系**：你的邮箱地址
- 💬 **社区讨论**：[加入我们的讨论](https://github.com/你的用户名/MyCustomPlayer/discussions)

---

<div align="center">

**如果这个项目对你有帮助，请给个 ⭐ Star 支持一下！**

[⬆ 回到顶部](#mycustomplayer)

</div>
