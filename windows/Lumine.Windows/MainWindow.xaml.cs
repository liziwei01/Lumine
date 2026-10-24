using System;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Lumine.Core;

namespace Lumine.Windows;

public partial class MainWindow : Window
{
    private readonly Sampler sampler = new();
    private readonly Preferences preferences;
    private readonly DispatcherTimer timer = new();
    private Snapshot? snapshot;
    private bool reading;
    private bool stopped;
    private string selected = "cpu";
    public event Action? LanguageChanged;
    public MainWindow(Preferences preferences)
    {
        this.preferences = preferences;
        InitializeComponent();
        timer.Interval = TimeSpan.FromSeconds(preferences.Interval);
        timer.Tick += async (_, _) => await RefreshAsync();
        timer.Start();
        Loaded += async (_, _) => await RefreshAsync();
        Render();
    }
    public void Stop() { stopped = true; timer.Stop(); }
    public async Task RefreshAsync()
    {
        if (reading || stopped) return;
        reading = true;
        try { snapshot = await Task.Run(sampler.Read); Render(); }
        catch (Exception e) when (e is System.IO.IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or System.Net.NetworkInformation.NetworkInformationException)
        { snapshot = null; Render(); Status.Text = L10n.T("error"); }
        finally { reading = false; }
    }
    private static string Percent(double? value) => value is { } n ? $"{n:0.#}%" : L10n.T("unavailable");
    private static string Rate(double? value) => value is { } n ? Counters.Bytes(n) + "/s" : "—";
    private string Free(Volume v) => $"{v.Name} {v.Label}\n{Counters.Bytes(v.Free)} {L10n.T("free")} / {Counters.Bytes(v.Total)}";
    private void Render()
    {
        Subtitle.Text = L10n.T("subtitle");
        SettingsButton.Content = L10n.T("settings"); HideButton.Content = L10n.T("hide"); QuitButton.Content = L10n.T("quit");
        Status.Text = L10n.T("local");
        Cards.Children.Clear();
        var s = snapshot;
        var systemDrive = s?.Volumes.FirstOrDefault(v => string.Equals(v.Name, System.IO.Path.GetPathRoot(Environment.SystemDirectory), StringComparison.OrdinalIgnoreCase));
        var memoryUsed = s?.MemoryTotal is > 0 && s.MemoryFree.HasValue ? (double?)(100.0 * (s.MemoryTotal.Value - s.MemoryFree.Value) / s.MemoryTotal.Value) : null;
        // Keep adapters separate: adding virtual and physical counters can double-count traffic.
        var primary = s?.Links.OrderByDescending(l => (l.Download ?? 0) + (l.Upload ?? 0)).FirstOrDefault();
        (string Key, string Value)[] values = [
            ("disk", systemDrive is null ? L10n.T("unavailable") : Counters.Bytes(systemDrive.Free) + " " + L10n.T("free")),
            ("memory", Percent(memoryUsed)), ("battery", Percent(s?.Battery)), ("cpu", Percent(s?.Cpu)),
            ("network", primary is null ? L10n.T("none") : $"↓ {Rate(primary.Download)}\n↑ {Rate(primary.Upload)}"),
            ("devices", s is null ? L10n.T("unavailable") : s.Volumes.Count(v => v.Removable).ToString()) ];
        foreach (var item in values)
        {
            var content = new StackPanel();
            content.Children.Add(new TextBlock { Text = L10n.T(item.Key), Foreground = new SolidColorBrush(Color.FromRgb(201, 196, 220)) });
            content.Children.Add(new TextBlock { Text = item.Value, FontSize = 19, Margin = new Thickness(0, 10, 0, 2) });
            var button = new Button { Content = content, MinHeight = 100, HorizontalContentAlignment = HorizontalAlignment.Stretch,
                BorderBrush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(selected == item.Key ? "#7895FF" : "#745D9E")) };
            button.Click += (_, _) => { selected = item.Key; Render(); };
            Cards.Children.Add(button);
        }
        DetailTitle.Text = L10n.T(selected);
        var unknown = L10n.T("unavailable");
        DetailText.Text = s is null ? unknown : selected switch
        {
            "cpu" => $"{Percent(s.Cpu)} · {Environment.ProcessorCount} CPU\n{L10n.T("uptime")}: {s.Uptime:d\\.hh\\:mm\\:ss}\n\n{L10n.T("limits")}",
            "memory" => s.MemoryTotal is { } total && s.MemoryFree is { } free ? $"{Counters.Bytes(free)} {L10n.T("free")} / {Counters.Bytes(total)}\n{Percent(memoryUsed)}" : unknown,
            "disk" => string.Join("\n\n", s.Volumes.Select(Free)),
            "battery" => s.Battery is { } b ? $"{b}% · {L10n.T(s.Charging == true ? "charging" : "discharging")}" : L10n.T("none"),
            "network" => string.Join("\n\n", s.Links.Select(l => $"{l.Name}\n↓ {Rate(l.Download)} · ↑ {Rate(l.Upload)}\n↓ {Counters.Bytes(l.Received)} · ↑ {Counters.Bytes(l.Sent)}")) + "\n\n" + L10n.T("counters"),
            "devices" => s.Volumes.Any(v => v.Removable) ? string.Join("\n\n", s.Volumes.Where(v => v.Removable).Select(Free)) : L10n.T("none"),
            _ => unknown
        };
    }
    private void SettingsClick(object sender, RoutedEventArgs e)
    {
        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(new TextBlock { Text = L10n.T("language"), Foreground = Brushes.Black });
        var language = new ComboBox { ItemsSource = L10n.Names, SelectedIndex = Array.IndexOf(L10n.Codes, preferences.Language), Margin = new Thickness(0, 8, 0, 16) };
        panel.Children.Add(language);
        panel.Children.Add(new TextBlock { Text = L10n.T("interval"), Foreground = Brushes.Black });
        var interval = new ComboBox { ItemsSource = new[] { 2, 5, 10, 30, 60 }, SelectedItem = preferences.Interval, Margin = new Thickness(0, 8, 0, 16) };
        if (interval.SelectedIndex < 0) interval.SelectedItem = 5;
        panel.Children.Add(interval);
        var save = new Button { Content = L10n.T("save") };
        panel.Children.Add(save);
        var dialog = new Window { Title = L10n.T("settings"), Width = 360, SizeToContent = SizeToContent.Height, Owner = this, WindowStartupLocation = WindowStartupLocation.CenterOwner, Content = panel, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false };
        save.Click += (_, _) =>
        {
            var updated = new Preferences { Language = L10n.Codes[Math.Max(0, language.SelectedIndex)], Interval = (int)interval.SelectedItem };
            try { updated.Save(); }
            catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException)
            { MessageBox.Show(dialog, L10n.T("saveError"), "Lumine"); return; }
            preferences.Language = updated.Language; preferences.Interval = updated.Interval;
            L10n.Language = preferences.Language; timer.Interval = TimeSpan.FromSeconds(preferences.Interval);
            Render(); LanguageChanged?.Invoke(); dialog.Close();
        };
        dialog.ShowDialog();
    }
    protected override void OnClosing(CancelEventArgs e) { e.Cancel = true; Hide(); base.OnClosing(e); }
    private void HideClick(object sender, RoutedEventArgs e) => Hide();
    private void QuitClick(object sender, RoutedEventArgs e) => ((App)Application.Current).Quit();
}
