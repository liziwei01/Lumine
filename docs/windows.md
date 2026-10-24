# Lumine for Windows

The Windows implementation uses .NET 10, WPF for the dashboard and Windows Forms `NotifyIcon` for the system tray. It is independent of the existing Swift macOS target. It requires Windows 10/11 and does not install a service or driver. Build with the [.NET desktop SDK](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/msbuild-props-desktop).

## Sampling

| Metric | Source | Meaning |
| --- | --- | --- |
| CPU | `GetSystemTimes` | Difference of cumulative idle/kernel/user times. Kernel time includes idle; idle is subtracted once. On systems with more than 64 logical processors, Windows may limit these counters to the calling processor group. |
| Memory | `GlobalMemoryStatusEx` | Total and available physical memory; used percentage is `(total - available) / total`, not memory pressure. |
| Battery | `GetSystemPowerStatus` | Charge percent and AC connection. Missing/unknown batteries do not become 0%. |
| Uptime | `Environment.TickCount64` | OS uptime, independent of wall clock adjustments. |
| Volumes | `DriveInfo` | Ready fixed/removable volumes only. Network drives are excluded to avoid blocking on disconnected shares. Available space respects the calling user's quota. |
| Network | `NetworkInterface.GetIPStatistics` | Per-adapter received/sent bytes and differences over monotonic elapsed time. No sums across VPN/virtual/physical adapters. |

The overview shows the network adapter with the greatest measured activity. Details show every active non-loopback adapter. Counter rollback, adapter removal and the initial sample invalidate the rate. A zero delta is a valid zero rate. Hardware temperature, SMART, disk categories, swap details, process ranking/actions, speed tests, login startup and macOS theme/widget controls are not implemented on Windows.

Sampling runs on a worker task, with no overlapping reads. The interval defaults to 5 seconds and can be set to 2, 5, 10, 30 or 60 seconds. Closing the dashboard keeps sampling active; Quit stops its timer, removes the tray icon and exits the process. Another instance in the same Windows session exits immediately. CPU/network readings need two samples. Metrics are not persisted or sent anywhere; settings are saved to `%LOCALAPPDATA%\Lumine\settings.json` using a temporary file and replacement.

## Build and verification

From the repository root:

```powershell
dotnet run --project windows/Lumine.Core.Tests -c Release
dotnet publish windows/Lumine.Windows -c Release -r win-x64 --self-contained true -o dist/windows-x64
dotnet publish windows/Lumine.Windows -c Release -r win-arm64 --self-contained true -o dist/windows-arm64
```

Publish on Windows for distribution. [Microsoft documents cross-targeting on macOS/Linux](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/msbuild-props#enablewindowstargeting), but the executable may differ from a native Windows build (including its icon/console metadata). Portable builds include the runtime; retain all files in the publish folder. No signed installer is supplied.

The GitHub Actions Windows job runs counter calculation checks, publishes x64, launches `Lumine.exe --smoke-test`, checks real Win32 CPU/memory/storage availability and renders the WPF window to `lumine-windows.png`. It uploads the image, sample JSON and both architecture builds. ARM64 is compiled, not executed, in this job.

Manual Windows acceptance checks:

1. Start without elevation; verify CPU/memory/storage and a second network sample.
2. Click all six cards; check absent batteries and removable volumes.
3. Close and reopen using the tray, switch languages and sampling interval, restart and check persistence.
4. Disconnect/reconnect an adapter; ensure the first rate is unavailable, then resumes without a spike.
5. Open another instance, then Quit the original; ensure there are no remaining Lumine processes or tray icons.
6. Check display scaling, keyboard focus and multi-monitor behavior on the target hardware.

The v1.1.0 application code passed these x64 native sampling and WPF rendering checks in [Windows CI](https://github.com/liziwei01/Lumine/actions/runs/40080001959). The exported image is included in the README; this verifies basic startup/sampling/rendering, not all manual acceptance checks above.

## Remove

Choose Quit, delete the portable app folder, and optionally delete `%LOCALAPPDATA%\Lumine`. There are no registry startup entries or services to remove.
