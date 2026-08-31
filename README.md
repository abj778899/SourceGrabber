# 源码抓取器 (SourceGrabber)

一个 iOS 网页源码抓取工具，支持查看网页 HTML 源码、响应头、状态码，可搜索、复制、导出。

## 功能特性

- 输入网址一键抓取网页 HTML 源码
- 显示 HTTP 状态码、响应头、内容大小、请求耗时
- 源码内搜索高亮，显示匹配数量
- 一键复制全部源码到剪贴板
- 导出为 .html 文件分享
- 历史记录自动保存（最多100条）
- 自定义 User-Agent（移动端/桌面端可切换）
- 自动识别网页编码（UTF-8 / GBK / GB2312 等）
- 支持 HTTP 和 HTTPS
- 适配 iPhone 和 iPad，支持横竖屏

## 系统要求

- iOS 15.0+
- Xcode 14.0+
- Swift 5.0+

## 编译安装步骤

### 方法一：Xcode 直接编译（推荐）

1. 将整个 `SourceGrabber` 文件夹拷贝到 Mac 上
2. 双击 `SourceGrabber.xcodeproj` 用 Xcode 打开
3. 在 Xcode 顶部选择你的 iPhone 设备（或模拟器）
4. 点击项目名称 → Signing & Capabilities → 选择你的 Apple ID 团队
5. 按 `Cmd + R` 编译运行
6. 首次安装到真机需要在手机 设置 → 通用 → VPN与设备管理 中信任开发者证书

### 方法二：导出 ipa

1. Xcode 中选择 Product → Archive
2. 归档完成后点 Distribute App
3. 选择 Development（自用）或 App Store Connect（上架）
4. 按向导完成签名，导出 ipa 文件
5. 用 Apple Configurator 或爱思助手安装到手机

## 项目结构

```
SourceGrabber/
├── SourceGrabber/
│   ├── SourceGrabberApp.swift    # 应用入口
│   ├── ContentView.swift          # 主界面
│   ├── SourceCodeViewModel.swift  # 源码抓取逻辑
│   ├── HistoryStore.swift         # 历史记录管理
│   ├── SettingsView.swift         # 设置页面
│   ├── HistoryView.swift          # 历史记录页面
│   ├── ResponseInfoView.swift     # 响应信息页面
│   ├── Info.plist                 # 应用配置
│   └── Assets.xcassets/           # 资源文件
└── SourceGrabber.xcodeproj/       # Xcode 项目文件
```

## 使用说明

1. 在顶部输入框输入网址（可省略 https://，自动补全）
2. 点击"抓取"按钮
3. 等待加载完成，下方显示网页源码
4. 工具栏按钮功能：
   - 🔍 搜索：在源码中搜索关键词，高亮显示匹配项
   - 📋 复制：复制全部源码到剪贴板
   - ⬆️ 分享：导出为 html 文件分享
   - ℹ️ 信息：查看状态码、响应头、耗时等详细信息
   - 🕐 历史：查看抓取历史记录
   - ⚙️ 设置：自定义 User-Agent

## 注意事项

- 本应用仅用于学习和合法的网页源码查看
- 部分网站可能有反爬机制，返回空内容或验证码
- 抓取大型网页可能需要较长时间，请耐心等待
- 应用已启用 NSAllowsArbitraryLoads，支持 HTTP 网站

## 版本信息

- 版本：1.0.0
- 构建：1
- Bundle ID：com.example.SourceGrabber（可自行修改）
