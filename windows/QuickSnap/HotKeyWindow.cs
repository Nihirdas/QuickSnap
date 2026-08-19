using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace QuickSnap;

/// <summary>
/// A hidden window that registers a system-wide hotkey via Win32 and raises an
/// event when it fires. Uses <c>RegisterHotKey</c> directly — no dependencies,
/// and (unlike a low-level keyboard hook) no special permissions.
/// </summary>
internal sealed class HotKeyWindow : NativeWindow, IDisposable
{
    public event EventHandler? HotKeyPressed;

    private const int WM_HOTKEY = 0x0312;

    [Flags]
    public enum Mods : uint
    {
        Alt = 0x0001,
        Control = 0x0002,
        Shift = 0x0004,
        Win = 0x0008,
        NoRepeat = 0x4000
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private int _id;
    private bool _registered;

    public HotKeyWindow()
    {
        // Create a message-only-style window to receive WM_HOTKEY.
        CreateHandle(new CreateParams());
    }

    public bool Register(int id, Mods modifiers, Keys key)
    {
        _id = id;
        _registered = RegisterHotKey(Handle, id, (uint)(modifiers | Mods.NoRepeat), (uint)key);
        return _registered;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == _id)
        {
            HotKeyPressed?.Invoke(this, EventArgs.Empty);
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        if (_registered)
        {
            UnregisterHotKey(Handle, _id);
            _registered = false;
        }
        DestroyHandle();
    }
}
