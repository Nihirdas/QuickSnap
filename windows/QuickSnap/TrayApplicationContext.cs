using System.Drawing;
using System.Windows.Forms;

namespace QuickSnap;

/// <summary>
/// Runs QuickSnap as a tray-only utility: a <see cref="NotifyIcon"/> plus a
/// hidden window for the global hotkey. No main window, no taskbar entry.
/// One keystroke captures the whole screen, saves a PNG to the chosen folder,
/// and copies it to the clipboard — silently.
/// </summary>
internal sealed class TrayApplicationContext : ApplicationContext
{
    private const int HotKeyId = 1;

    private readonly NotifyIcon _tray;
    private readonly HotKeyWindow _hotKeyWindow;
    private readonly Settings _settings;

    public TrayApplicationContext()
    {
        _settings = Settings.Load();

        _tray = new NotifyIcon
        {
            Icon = SystemIcons.Application, // TODO: ship a custom .ico
            Text = "QuickSnap",
            Visible = true
        };
        _tray.DoubleClick += (_, _) => Capture();
        RebuildMenu();

        _hotKeyWindow = new HotKeyWindow();
        _hotKeyWindow.HotKeyPressed += (_, _) => Capture();
        RegisterHotKey();
    }

    // MARK: - Menu

    private void RebuildMenu()
    {
        var menu = new ContextMenuStrip();

        menu.Items.Add("Capture now", null, (_, _) => Capture());
        menu.Items.Add(new ToolStripSeparator());

        var saveTo = new ToolStripMenuItem("Save to");
        AddFolderChoice(saveTo, "Pictures", KnownFolders.Pictures);
        AddFolderChoice(saveTo, "Desktop", KnownFolders.Desktop);
        AddFolderChoice(saveTo, "Downloads", KnownFolders.Downloads);
        saveTo.DropDownItems.Add("Choose folder…", null, (_, _) => ChooseFolder());
        menu.Items.Add(saveTo);

        menu.Items.Add(new ToolStripMenuItem($"→ {_settings.SaveFolder}") { Enabled = false });

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem($"Shortcut: {_settings.HotKeyDisplay}") { Enabled = false });

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit QuickSnap", null, (_, _) => Quit());

        _tray.ContextMenuStrip = menu;
    }

    private void AddFolderChoice(ToolStripMenuItem parent, string label, string folder)
    {
        var item = new ToolStripMenuItem(label, null, (_, _) => SetFolder(folder))
        {
            Checked = string.Equals(
                Path.TrimEndingDirectorySeparator(folder),
                Path.TrimEndingDirectorySeparator(_settings.SaveFolder),
                StringComparison.OrdinalIgnoreCase)
        };
        parent.DropDownItems.Add(item);
    }

    // MARK: - Actions

    private void SetFolder(string folder)
    {
        _settings.SaveFolder = folder;
        _settings.Save();
        RebuildMenu();
    }

    private void ChooseFolder()
    {
        using var dialog = new FolderBrowserDialog { SelectedPath = _settings.SaveFolder };
        if (dialog.ShowDialog() == DialogResult.OK)
        {
            SetFolder(dialog.SelectedPath);
        }
    }

    private void RegisterHotKey()
    {
        // Ctrl+Alt+S — Win+Shift+S is taken by the Snipping Tool.
        bool ok = _hotKeyWindow.Register(
            HotKeyId, HotKeyWindow.Mods.Control | HotKeyWindow.Mods.Alt, Keys.S);

        if (!ok)
        {
            _tray.ShowBalloonTip(3000, "QuickSnap",
                "Couldn't register Ctrl+Alt+S (another app may be using it).",
                ToolTipIcon.Warning);
        }
    }

    private void Capture()
    {
        try
        {
            using Bitmap bitmap = ScreenCapturer.CapturePrimaryScreen();
            string path = ScreenCapturer.SavePng(bitmap, _settings.SaveFolder);
            ScreenCapturer.CopyToClipboard(bitmap);
            _tray.ShowBalloonTip(1500, "QuickSnap",
                $"Saved & copied — {Path.GetFileName(path)}", ToolTipIcon.Info);
        }
        catch (Exception ex)
        {
            _tray.ShowBalloonTip(3000, "QuickSnap — capture failed", ex.Message, ToolTipIcon.Error);
        }
    }

    private void Quit()
    {
        _tray.Visible = false;
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _hotKeyWindow.Dispose();
            _tray.Visible = false;
            _tray.Dispose();
        }
        base.Dispose(disposing);
    }
}
