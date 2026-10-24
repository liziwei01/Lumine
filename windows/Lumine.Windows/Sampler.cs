using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using Lumine.Core;

namespace Lumine.Windows;

public record Volume(string Name, string Label, long Total, long Free, bool Removable);
public record Link(string Id, string Name, long Received, long Sent, double? Download, double? Upload);
public record Snapshot(double? Cpu, ulong? MemoryTotal, ulong? MemoryFree, int? Battery,
    bool? Charging, TimeSpan Uptime, Volume[] Volumes, Link[] Links);

public sealed class Sampler
{
    private (ulong Idle, ulong Kernel, ulong User)? previousCpu;
    private readonly Dictionary<string, (long Received, long Sent, double Time)> previousLinks = new();

    public Snapshot Read()
    {
        double? cpu = null;
        if (GetSystemTimes(out var idle, out var kernel, out var user))
        {
            var current = (idle.Value, kernel.Value, user.Value);
            cpu = Counters.Cpu(previousCpu, current);
            previousCpu = current;
        }
        else previousCpu = null;
        var memory = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        var hasMemory = GlobalMemoryStatusEx(ref memory);
        var hasBattery = GetSystemPowerStatus(out var battery) && battery.BatteryFlag != 255 &&
                         (battery.BatteryFlag & 128) == 0 && battery.BatteryLifePercent <= 100;
        var volumes = new List<Volume>();
        foreach (var drive in DriveInfo.GetDrives())
        {
            // Network drives can block while offline; only inspect local volumes.
            if (drive.DriveType != DriveType.Fixed && drive.DriveType != DriveType.Removable) continue;
            try
            {
                if (drive.IsReady) volumes.Add(new(drive.Name, drive.VolumeLabel, drive.TotalSize,
                    drive.AvailableFreeSpace, drive.DriveType == DriveType.Removable));
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        var links = new List<Link>();
        var now = Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency;
        try
        {
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                try
                {
                    var stats = nic.GetIPStatistics();
                    var known = previousLinks.TryGetValue(nic.Id, out var p);
                    links.Add(new(nic.Id, nic.Name, stats.BytesReceived, stats.BytesSent,
                        known ? Counters.Rate(p.Received, stats.BytesReceived, now - p.Time) : null,
                        known ? Counters.Rate(p.Sent, stats.BytesSent, now - p.Time) : null));
                    previousLinks[nic.Id] = (stats.BytesReceived, stats.BytesSent, now);
                }
                catch (NetworkInformationException) { previousLinks.Remove(nic.Id); }
            }
        }
        catch (NetworkInformationException) { }
        foreach (var id in previousLinks.Keys.Except(links.Select(l => l.Id)).ToArray()) previousLinks.Remove(id);
        return new(cpu, hasMemory ? memory.TotalPhysical : null, hasMemory ? memory.AvailablePhysical : null,
            hasBattery ? battery.BatteryLifePercent : null, hasBattery ? battery.ACLineStatus == 1 : null,
            TimeSpan.FromMilliseconds(Environment.TickCount64), volumes.ToArray(), links.ToArray());
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime { public uint Low, High; public readonly ulong Value => ((ulong)High << 32) | Low; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryStatus
    {
        public uint Length, Load;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile, TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct PowerStatus
    {
        public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag;
        public uint BatteryLifeTime, BatteryFullLifeTime;
    }
    [DllImport("kernel32.dll")][return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);
    [DllImport("kernel32.dll")][return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    [DllImport("kernel32.dll")][return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemPowerStatus(out PowerStatus status);
}
