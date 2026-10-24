<p align="center"><img src="Lumine/Assets.xcassets/AppIcon.appiconset/icon_128.png" width="96" alt="Lumine 图标"></p>
<h1 align="center">Lumine</h1>
<p align="center">随时了解系统状态，安静陪伴日常工作。</p>
<p align="center"><a href="README.md">English</a> · <strong>简体中文</strong> · <a href="README.ru.md">Русский</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a></p>

Lumine 是原生桌面系统监控工具：macOS 版驻留菜单栏，Windows 版驻留系统托盘。在紫色仪表盘中查看 CPU、内存、磁盘、电池与网络状态，点击卡片展开详情。

![macOS 版 Lumine：CPU 详情与系统总览](docs/images/cpu.png)

*图片由 macOS 版真实 SwiftUI 界面与本机实时采样生成。Windows 使用独立的 WPF 界面，上图不代表 Windows 版。*

<details>
<summary>系统总览（macOS）</summary>
<p><img src="docs/images/overview.png" width="446" alt="系统总览（macOS）"></p>
</details>

## 下载

从 [GitHub Releases](https://github.com/liziwei01/Lumine/releases/latest) 下载：macOS 通用版（Apple Silicon 与 Intel）、Windows x64 或 Windows ARM64。解压后运行；Windows 包含运行时。macOS App 使用临时签名，未经公证；Windows 包未签名。

## 功能与平台

| 功能 | macOS 13+ | Windows 10/11 |
| --- | --- | --- |
| CPU | 总体／单核心使用率、历史、运行时间 | 总体使用率、逻辑处理器数、运行时间 |
| 内存 | 占用、可用量、交换空间、进程排行 | 物理内存占用与可用量 |
| 磁盘 | 卷容量、手动文件类别扫描 | 本地卷的可用／总容量 |
| 电池 | 电量、健康度、循环数、可用时显示温度 | 电量与电源连接状态 |
| 网络 | 可选接口、速率、滚动累计流量、手动测速 | 各接口速率与接口累计计数 |
| 外置存储 | 已挂载的本地外置卷 | Windows 标记为可移动的卷 |
| 设置 | 配色、组件、来源、位置、采样、登录启动 | 语言与采样间隔 |
| 界面语言 | 中简／繁、英、俄、日、韩、西 | 中简、英、俄、日、韩 |

Windows 版是首个原生实现，功能少于 macOS 版。硬件温度、SMART、文件分类、进程操作、测速和登录启动暂仅限 macOS。Windows 读取不到的数据会显示为不可用；系统识别为固定磁盘的 USB 硬盘列在磁盘详情中。

## 构建与运行

### macOS

安装 Xcode 15 或更新版本，打开 `Lumine.xcodeproj` 并运行 **Lumine** scheme，或在仓库根目录执行：

```sh
xcodebuild -project Lumine.xcodeproj -scheme Lumine -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
codesign --force --sign - --timestamp=none build/Build/Products/Release/Lumine.app
open build/Build/Products/Release/Lumine.app
```

将 App 复制到 `/Applications` 后，从菜单栏的显示器图标打开面板；没有 Dock 图标。齿轮菜单可打开设置或退出。固定安装位置后，可在“设置 → 通用”启用登录启动。临时签名用于本地构建，分发到其他 Mac 仍需适当签名与公证。

### Windows

在 Windows 安装 [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)，在仓库根目录执行：

```powershell
dotnet run --project windows/Lumine.Windows -c Release
# 生成包含运行时的便携版
dotnet publish windows/Lumine.Windows -c Release -r win-x64 --self-contained true -o dist/windows-x64
```

运行 `dist/windows-x64/Lumine.exe`，保留输出目录中的全部文件。ARM 设备将 `win-x64` 改为 `win-arm64`。关闭窗口会收起到系统托盘，点击托盘图标重新打开，选择“退出”才停止监控。设置保存在 `%LOCALAPPDATA%\Lumine\settings.json`。不需要管理员权限、驱动或后台服务。

[构建工作流](.github/workflows/build.yml)会构建两个平台，并生成 Windows x64／ARM64 产物；x64 冒烟检查会采集真实 Windows 指标并导出 WPF 截图。本次已在 macOS 交叉编译，Windows 运行验收仍需以 Windows CI 或真机结果为准。详见 [Windows 实现说明（英文）](docs/windows.md)。

## 数据与隐私

日常监控通过本机系统接口完成，Lumine 没有账号、分析或遥测功能。CPU 和网络速率需要两次采样，首轮可能显示不可用。Windows 网络总量来自接口计数器，并非滚动历史，接口重启可能重置；VPN 与虚拟网卡分别显示，避免重复累加。

macOS 文件分类只在点击“重新扫描”后运行，缺少完全磁盘访问权限时结果可能不完整。缓存与流量历史保存在 `~/Library/Application Support/Lumine/`，设置保存在 `~/Library/Preferences/app.lumine.monitor.plist`。手动测速连接 Cloudflare，约传输 28 MB；清空废纸篓在确认后永久删除内容；请求进程退出可能丢失未保存工作。这些操作均不自动执行，温度是否可用取决于硬件和系统访问条件。

更多设置、指标口径、权限和卸载说明见 [macOS 完整指南](docs/macos.zh-CN.md)与[架构说明](docs/architecture.md)。

## 参与开发

```sh
# 跨平台计数器测试，需要 .NET 10
dotnet run --project windows/Lumine.Core.Tests -c Release
# 可在 macOS/Linux 交叉编译，但不能运行 Windows App
dotnet build windows/Lumine.Windows -c Release
```

报告问题请附系统版本、代码版本、相关指标与复现步骤。欢迎校对翻译：macOS 文案位于 `Lumine/*.lproj/Localizable.strings`，Windows 文案位于 `windows/Lumine.Windows/Localization.cs`。平台支持和安装说明变更时，请同步五种语言 README。

Lumine 的设计参考 CleanMyMac 菜单栏监控页面，是独立项目，与 MacPaw 无关，不包含其品牌素材。需求与审阅由 liziwei 完成，架构、代码和文档使用 OpenAI Codex 协助开发。

## 许可

[MIT](LICENSE)。macOS 传感器协议参考来源见[第三方声明](THIRD_PARTY_NOTICES.md)。
