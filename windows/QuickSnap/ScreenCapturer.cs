using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;

namespace QuickSnap;

/// <summary>
/// Captures the primary screen and turns it into the two outputs we want:
/// a PNG file on disk and an image on the clipboard.
/// </summary>
internal static class ScreenCapturer
{
    public static Bitmap CapturePrimaryScreen()
    {
        Rectangle bounds = Screen.PrimaryScreen?.Bounds ?? SystemInformation.VirtualScreen;
        var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            // CaptureBlt also grabs layered/transparent windows.
            graphics.CopyFromScreen(
                bounds.X, bounds.Y, 0, 0, bounds.Size,
                CopyPixelOperation.SourceCopy | CopyPixelOperation.CaptureBlt);
        }
        return bitmap;
    }

    public static string SavePng(Bitmap bitmap, string folder)
    {
        Directory.CreateDirectory(folder);
        string fileName = $"Screenshot {DateTime.Now:yyyy-MM-dd 'at' HH.mm.ss}.png";
        string path = Path.Combine(folder, fileName);
        bitmap.Save(path, ImageFormat.Png);
        return path;
    }

    public static void CopyToClipboard(Bitmap bitmap)
    {
        // Clipboard keeps a reference, so hand it an independent copy.
        Clipboard.SetImage((Image)bitmap.Clone());
    }
}
