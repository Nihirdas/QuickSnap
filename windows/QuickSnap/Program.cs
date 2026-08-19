using System.Windows.Forms;

namespace QuickSnap;

internal static class Program
{
    // WinForms + clipboard require a single-threaded apartment.
    [STAThread]
    private static void Main()
    {
        // Applies the settings from the .csproj (high-DPI mode, visual styles).
        ApplicationConfiguration.Initialize();

        // No main window — the app lives entirely in the tray.
        Application.Run(new TrayApplicationContext());
    }
}
