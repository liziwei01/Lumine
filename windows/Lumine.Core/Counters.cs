namespace Lumine.Core;

public static class Counters
{
    // Windows includes idle time in kernel time. The first sample has no rate.
    public static double? Cpu((ulong Idle, ulong Kernel, ulong User)? previous,
                              (ulong Idle, ulong Kernel, ulong User) current)
    {
        if (previous is not { } p || current.Idle < p.Idle || current.Kernel < p.Kernel || current.User < p.User)
            return null;
        var total = (double)(current.Kernel - p.Kernel) + (current.User - p.User);
        var idle = current.Idle - p.Idle;
        return total > 0 && idle <= total ? Math.Clamp(100 * (total - idle) / total, 0, 100) : null;
    }

    public static double? Rate(long previous, long current, double seconds) =>
        seconds > 0 && current >= previous ? (current - previous) / seconds : null;

    public static string Bytes(double bytes)
    {
        string[] units = ["B", "KiB", "MiB", "GiB", "TiB"];
        var unit = 0;
        while (bytes >= 1024 && unit < units.Length - 1) { bytes /= 1024; unit++; }
        return $"{bytes:0.#} {units[unit]}";
    }
}
