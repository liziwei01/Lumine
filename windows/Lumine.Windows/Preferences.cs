using System;
using System.IO;
using System.Text.Json;

namespace Lumine.Windows;

public sealed class Preferences
{
    public string Language { get; set; } = L10n.SystemLanguage;
    public int Interval { get; set; } = 5;
    public static string FilePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lumine", "settings.json");
    public static Preferences Load()
    {
        try
        {
            var value = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(FilePath)) ?? new();
            if (Array.IndexOf(L10n.Codes, value.Language) < 0) value.Language = "en";
            value.Interval = Math.Clamp(value.Interval, 2, 60);
            return value;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return new(); }
    }
    public void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temporary = FilePath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(this));
        File.Move(temporary, FilePath, true);
    }
}
