using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Forms = System.Windows.Forms;

namespace Lumine.Windows;

public partial class App : Application
{
    private Forms.NotifyIcon? tray;
    private Mutex? instance;
    private MainWindow? monitor;
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        instance = new Mutex(true, @"Local\Lumine.Windows", out var first);
        if (!first) { Shutdown(); return; }
        var preferences = Preferences.Load();
        L10n.Language = preferences.Language;
        monitor = new MainWindow(preferences);
        MainWindow = monitor;
        if (e.Args.Contains("--smoke-test"))
        {
            // Run real Win32 sampling and WPF rendering on Windows CI.
            try
            {
                var sampler = new Sampler();
                sampler.Read();
                await Task.Delay(1100);
                var sample = sampler.Read();
                if (sample.Cpu is null || sample.MemoryTotal is null or 0 || sample.Volumes.Length == 0)
                    throw new InvalidOperationException("Native sampling did not return CPU, memory and local storage.");
                monitor.Show();
                await monitor.RefreshAsync();
                await Task.Delay(1100);
                await monitor.RefreshAsync();
                monitor.UpdateLayout();
                var bitmap = new RenderTargetBitmap((int)monitor.ActualWidth, (int)monitor.ActualHeight, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(monitor);
                var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using (var file = File.Create("lumine-windows.png")) encoder.Save(file);
                File.WriteAllText("lumine-smoke.json", System.Text.Json.JsonSerializer.Serialize(sample));
                Quit();
            }
            catch (Exception ex) { File.WriteAllText("lumine-smoke-error.txt", ex.ToString()); Quit(1); }
            return;
        }
        using var executable = System.Diagnostics.Process.GetCurrentProcess();
        tray = new Forms.NotifyIcon
        {
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(executable.MainModule!.FileName!) ?? System.Drawing.SystemIcons.Application,
            Text = "Lumine", Visible = true
        };
        tray.MouseClick += (_, args) => { if (args.Button == Forms.MouseButtons.Left) Toggle(); };
        monitor.LanguageChanged += UpdateMenu;
        UpdateMenu();
        monitor.Show();
    }
    private void Toggle()
    {
        if (monitor!.IsVisible) monitor.Hide(); else { monitor.Show(); monitor.Activate(); }
    }
    private void UpdateMenu()
    {
        var old = tray!.ContextMenuStrip;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(L10n.T("open"), null, (_, _) => { monitor!.Show(); monitor.Activate(); });
        menu.Items.Add(L10n.T("quit"), null, (_, _) => Quit());
        tray.ContextMenuStrip = menu;
        old?.Dispose();
    }
    public void Quit(int code = 0) { monitor?.Stop(); Shutdown(code); }
    protected override void OnExit(ExitEventArgs e)
    {
        monitor?.Stop();
        if (tray is not null) { tray.Visible = false; tray.ContextMenuStrip?.Dispose(); tray.Icon?.Dispose(); tray.Dispose(); }
        instance?.Dispose();
        base.OnExit(e);
    }
}
