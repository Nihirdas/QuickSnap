using System.Text.Json;

namespace QuickSnap;

/// <summary>
/// User settings, persisted as JSON in %AppData%\QuickSnap\settings.json.
/// </summary>
internal sealed class Settings
{
    public string SaveFolder { get; set; } = KnownFolders.Pictures;

    // The hotkey is fixed at Ctrl+Alt+S for v1 (rebinding UI is on the roadmap).
    public string HotKeyDisplay { get; set; } = "Ctrl+Alt+S";

    private static string ConfigPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "QuickSnap", "settings.json");

    public static Settings Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
            {
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(ConfigPath)) ?? new Settings();
            }
        }
        catch
        {
            // Corrupt/unreadable settings → fall back to defaults.
        }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!);
            File.WriteAllText(ConfigPath,
                JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch
        {
            // Best-effort; not fatal if we can't persist.
        }
    }
}

/// <summary>Common save-folder locations.</summary>
internal static class KnownFolders
{
    public static string Pictures => Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
    public static string Desktop => Environment.GetFolderPath(Environment.SpecialFolder.Desktop);

    // Windows has no SpecialFolder for Downloads; %UserProfile%\Downloads is the standard path.
    public static string Downloads => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
}
