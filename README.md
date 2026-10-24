<p align="center"><img src="Lumine/Assets.xcassets/AppIcon.appiconset/icon_128.png" width="96" alt="Lumine icon"></p>
<h1 align="center">Lumine</h1>
<p align="center">A quiet place to keep an eye on your system.</p>
<p align="center"><strong>English</strong> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ru.md">Русский</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a></p>

Lumine is a native desktop system monitor: a menu bar app on macOS and a system tray app on Windows. Check CPU activity, memory, storage, battery and network traffic from a compact purple dashboard, then click a card for details.

![Lumine on macOS: CPU details and system overview](docs/images/cpu.png)

*The macOS SwiftUI views, rendered with live local measurements. Windows uses a separate WPF interface; the image above does not depict the Windows version.*

<details>
<summary>System overview (macOS)</summary>
<p><img src="docs/images/overview.png" width="446" alt="System overview (macOS)"></p>
</details>

## Download

Download the portable packages from [GitHub Releases](https://github.com/liziwei01/Lumine/releases/latest): macOS universal (Apple Silicon and Intel), Windows x64, or Windows ARM64. Extract the archive before launching; Windows packages include the runtime. The macOS app is ad hoc signed, not notarized, and Windows packages are unsigned.

## What you can monitor

| Feature | macOS 13+ | Windows 10/11 |
| --- | --- | --- |
| CPU usage and uptime | Overall or per logical core, history | Overall usage, logical processor count, uptime |
| Memory | Usage, available memory, swap, process ranking | Usage and available physical memory |
| Storage | Volume capacity, manual file category scan | Available/total capacity for local volumes |
| Battery | Charge, health, cycles, temperature where available | Charge and AC power status where available |
| Network | Interface selection, rates, rolling traffic totals, manual speed test | Per-interface rates and adapter counter totals |
| External storage | Mounted local external volumes | Volumes Windows identifies as removable |
| Customization | Theme, widgets, sources, panel positions, sampling, login item | Language and sampling interval |
| UI languages | English, Simplified/Traditional Chinese, Russian, Japanese, Korean, Spanish | English, Simplified Chinese, Russian, Japanese, Korean |

Windows is an initial native implementation, with a smaller feature set. Hardware temperatures, SMART health, file categorization, process actions, speed tests and login startup are currently macOS-only. Windows reports unavailable readings rather than inventing sensor values. USB disks reported by Windows as fixed disks appear under Storage.

## Build and run

### macOS

Install Xcode 15 or newer, open `Lumine.xcodeproj`, and run the **Lumine** scheme. Or build from the repository root:

```sh
xcodebuild -project Lumine.xcodeproj -scheme Lumine -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
codesign --force --sign - --timestamp=none build/Build/Products/Release/Lumine.app
open build/Build/Products/Release/Lumine.app
```

Copy `Lumine.app` to `/Applications` for a stable installation. Look for the display icon in the menu bar; there is no Dock icon. Click it to show or hide the dashboard. The gear menu opens settings or quits the app. Enable launch at login in **Settings → General** after installation. Local ad hoc signing is for your own build; distribution to other Macs requires appropriate signing and notarization.

### Windows

On Windows, install the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0), then run:

```powershell
dotnet run --project windows/Lumine.Windows -c Release
```

To create a portable build that includes the runtime:

```powershell
dotnet publish windows/Lumine.Windows -c Release -r win-x64 --self-contained true -o dist/windows-x64
```

Run `dist/windows-x64/Lumine.exe`. Keep the entire output folder together. Use `win-arm64` for Windows on ARM. Closing the window hides it to the notification area; click the tray icon to reopen it, or choose **Quit** to stop monitoring. Settings persist under `%LOCALAPPDATA%\Lumine\settings.json`. No administrator privileges, drivers or background service are required.

The [build workflow](.github/workflows/build.yml) builds both platforms and produces Windows x64/ARM64 artifacts. Its x64 smoke test samples real Windows metrics and exports a WPF screenshot. This change was cross-compiled on macOS; Windows runtime validation must be confirmed by that Windows job or a Windows machine. See the [Windows implementation notes](docs/windows.md).

## Data and privacy

Monitoring uses local operating system interfaces. There is no account, analytics or telemetry in Lumine. CPU and network rates need two samples; the first reading may be unavailable. Windows network totals come from adapter counters, not a rolling history, and can reset when an adapter restarts. VPN and virtual adapters are listed separately to avoid double counting.

On macOS, file categorization runs only when you click **Rescan**; results may be incomplete without Full Disk Access. Traffic history and scan results remain in `~/Library/Application Support/Lumine/`, and settings in `~/Library/Preferences/app.lumine.monitor.plist`. A manual speed test contacts Cloudflare and transfers about 28 MB. Emptying Trash permanently deletes its contents after confirmation; requesting a process to quit can lose unsaved work. These actions never run automatically. Temperature availability depends on hardware and system access.

For all macOS settings, metric definitions, permissions and uninstall details, see the [macOS guide (Chinese)](docs/macos.zh-CN.md) and [architecture notes (Chinese)](docs/architecture.md).

## Development

```sh
# Platform-independent counter tests (.NET 10)
dotnet run --project windows/Lumine.Core.Tests -c Release
# Cross-compile Windows from macOS/Linux (does not run the app)
dotnet build windows/Lumine.Windows -c Release
```

Bug reports should include the OS version, app revision, affected metric and reproduction steps. Translation corrections are welcome: macOS strings live in `Lumine/*.lproj/Localizable.strings`; Windows strings are in `windows/Lumine.Windows/Localization.cs`. Keep all five README files in sync when changing platform support or setup instructions. Regenerate the macOS images with `./scripts/render_screenshots.sh` (requires Xcode); this renders the actual views with live measurements without capturing other desktop content.

Lumine is an independent project inspired by the menu bar monitor design of CleanMyMac. It is not affiliated with MacPaw and includes no CleanMyMac artwork or brand assets. Original requirements and review by liziwei; architecture, code and documentation developed with assistance from OpenAI Codex.

## License

[MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for macOS sensor protocol references.
