# MCP Bridge - Android Studio 源码

## 项目说明

本项目是 MCP Bridge v1.0.0 的逆向工程源码，通过 jadx + apktool 从 APK 反编译得到。

**MCP Bridge** 是一个将本地 MCP（Model Context Protocol）服务通过 Bore 隧道暴露到公网的 Android 应用。

## 功能特性

- 🔗 **MCP 内网穿透**：将本地 MCP 服务通过 bore 隧道暴露到公网
- 📱 **前台服务**：以后台服务方式运行，保持隧道连接
- 🎨 **iOS 风格 UI**：采用 iOS 风格设计界面
- 🔐 **HMAC 认证**：支持 bore 协议的 HMAC-SHA256 认证
- 📋 **一键复制**：快速复制 MCP 连接地址

## 技术栈

- **开发语言**：Kotlin（反编译为 Java）
- **最低 SDK**：API 26 (Android 8.0)
- **目标 SDK**：API 34 (Android 14)
- **UI 框架**：AndroidX AppCompat + Material Design
- **异步处理**：Kotlin Coroutines
- **隧道协议**：Bore（纯 Java 实现）

## 项目结构

```
MCP_Bridge_source/
├── app/
│   ├── build.gradle              # 模块级构建配置
│   ├── proguard-rules.pro        # 混淆规则
│   └── src/
│       └── main/
│           ├── AndroidManifest.xml  # 应用清单
│           ├── java/
│           │   └── com/mcpbridge/
│           │       ├── MainActivity.java    # 主界面
│           │       ├── TunnelService.java   # 隧道前台服务
│           │       └── BoreClient.java      # Bore 协议客户端
│           └── res/                 # 资源文件
│               ├── layout/          # 布局文件
│               ├── drawable/        # 图片资源
│               ├── values/          # 字符串、颜色、样式
│               └── ...
├── build.gradle                    # 项目级构建配置
├── settings.gradle                 # 项目设置
└── gradle.properties               # Gradle 属性
```

## 核心类说明

### MainActivity
主界面 Activity，包含：
- 隧道启动/停止/复制按钮
- 本地端口、远程服务器、认证密钥配置
- 运行状态显示
- 公网地址和 MCP 地址显示
- 运行日志显示

### TunnelService
前台服务，负责：
- 管理 BoreClient 生命周期
- 显示运行状态通知
- 通过 LocalBroadcastManager 与 Activity 通信

### BoreClient
纯 Java 实现的 Bore 隧道协议客户端：
- 控制连接（端口 7835）
- HMAC-SHA256 认证握手
- 多连接数据转发
- JSON 消息协议（null 字节分隔）

## 使用方法

1. 在 MT 管理器中启动 APK MCP 服务
2. 记住端口号（默认 8787）
3. 打开 MCP Bridge，点击「启动隧道」
4. 复制 MCP 地址，粘贴到 iMa Copilot 中连接
5. 保持应用后台运行

## 构建说明

```bash
# 构建 Debug 版本
./gradlew assembleDebug

# 构建 Release 版本
./gradlew assembleRelease
```

## 注意事项

1. **源码来源**：本源码由 APK 反编译得到，可能存在少量反编译错误
2. **R 类**：项目中的 R 类由构建系统自动生成，无需手动创建
3. **资源文件**：布局、字符串等资源已从二进制 XML 还原为文本 XML
4. **第三方库**：依赖库通过 Gradle 管理，无需手动引入

## 默认配置

| 配置项 | 默认值 |
|--------|--------|
| 本地端口 | 8787 |
| 远程服务器 | bore.pub |
| 认证密钥 | 空（公共服务器） |
| 控制端口 | 7835 |
