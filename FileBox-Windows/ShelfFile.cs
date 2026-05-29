using System;
using System.IO;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace FileBox;

/// <summary>
/// Immutable value representing a single item on the shelf.
/// Mirrors the macOS <c>ShelfFile</c> struct from ShelfViewModel.swift.
///
/// macOS → Windows API mapping:
///   NSWorkspace.shared.icon(forFile:)  →  Icon.ExtractAssociatedIcon
///   NSImage(contentsOf:)               →  BitmapImage with UriSource
///   NSImage(systemSymbolName: "link")  →  hand-drawn link geometry
/// </summary>
public sealed class ShelfFile
{
    public Guid         Id     { get; } = Guid.NewGuid();
    public Uri          Uri    { get; }
    public string       Name   { get; }
    public ImageSource  Icon   { get; }
    public bool         IsTemp { get; }

    public ShelfFile(Uri uri, bool isTemp = false)
    {
        Uri    = uri;
        IsTemp = isTemp;

        if (uri.Scheme is "http" or "https")
        {
            Name = uri.Host.Length > 0 ? uri.Host : uri.AbsoluteUri;
            Icon = LinkIcon.Value;
        }
        else if (isTemp)
        {
            Name = Path.GetFileName(uri.LocalPath);
            Icon = LoadThumbnail(uri.LocalPath);
        }
        else
        {
            Name = Path.GetFileName(uri.LocalPath);
            Icon = ExtractShellIcon(uri.LocalPath);
        }
    }

    // ── Icon helpers ────────────────────────────────────────────────────────

    /// <summary>
    /// Extracts the shell icon for a file path.
    /// Equivalent to NSWorkspace.shared.icon(forFile: url.path).
    /// </summary>
    private static ImageSource ExtractShellIcon(string path)
    {
        try
        {
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (icon is not null)
            {
                var src = Imaging.CreateBitmapSourceFromHIcon(
                    icon.Handle, Int32Rect.Empty,
                    BitmapSizeOptions.FromEmptyOptions());
                src.Freeze();
                return src;
            }
        }
        catch { /* fall through */ }
        return LinkIcon.Value;
    }

    /// <summary>
    /// Loads a temporary image file as a thumbnail.
    /// Equivalent to NSImage(contentsOf: url) for isTemp images.
    /// </summary>
    private static ImageSource LoadThumbnail(string path)
    {
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.UriSource        = new Uri(path);
            bmp.DecodePixelWidth = 22;
            bmp.CacheOption      = BitmapCacheOption.OnLoad;
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch { return LinkIcon.Value; }
    }

    /// <summary>
    /// A hand-drawn chain-link icon frozen for reuse.
    /// Equivalent to SF Symbols "link" used on macOS for URL items.
    /// </summary>
    private static readonly Lazy<ImageSource> LinkIcon = new(() =>
    {
        var group = new DrawingGroup();
        using (var ctx = group.Open())
        {
            var pen = new Pen(new SolidColorBrush(Color.FromArgb(180, 200, 200, 200)), 1.4)
            {
                StartLineCap = PenLineCap.Round,
                EndLineCap   = PenLineCap.Round
            };
            pen.Freeze();
            // Left link ring
            ctx.DrawRoundedRectangle(null, pen, new Rect(0.5, 5, 7, 6), 2.5, 2.5);
            // Right link ring
            ctx.DrawRoundedRectangle(null, pen, new Rect(8.5, 5, 7, 6), 2.5, 2.5);
            // Connector bar
            ctx.DrawLine(pen, new Point(7, 8), new Point(9, 8));
        }
        group.Freeze();
        var img = new DrawingImage(group);
        img.Freeze();
        return img;
    });
}
