using Lumine.Core;

static void Equal(double? expected, double? actual)
{
    if (expected != actual) throw new Exception($"Expected {expected}, got {actual}");
}
Equal(null, Counters.Cpu(null, (10, 30, 20)));
Equal(75, Counters.Cpu((10, 30, 20), (20, 60, 30)));
Equal(0, Counters.Cpu((10, 30, 20), (20, 40, 20)));
Equal(100, Counters.Cpu((10, 30, 20), (10, 40, 20)));
Equal(null, Counters.Cpu((10, 30, 20), (10, 30, 20)));
Equal(null, Counters.Cpu((10, 30, 20), (5, 40, 30)));
Equal(null, Counters.Cpu((10, 30, 20), (100, 40, 30)));
Equal(500, Counters.Rate(1000, 2000, 2));
Equal(0, Counters.Rate(1000, 1000, 2));
Equal(null, Counters.Rate(2000, 1000, 2));
Equal(null, Counters.Rate(1000, 2000, 0));
if (Counters.Bytes(1024) != "1 KiB") throw new Exception("Byte formatting");
Console.WriteLine("12 counter checks passed.");
