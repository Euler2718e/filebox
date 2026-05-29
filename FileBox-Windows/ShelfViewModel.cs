using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media.Imaging;

namespace FileBox;

/// <summary>
/// Manages the list of shelved items.
/// Mirrors the macOS <c>ShelfViewModel</c> class from ShelfViewModel.swift.
///
/// macOS @Published var files: [ShelfFile]  →  ObservableCollection&lt;ShelfFile&gt;
///   (WPF's ItemsControl binds to ObservableCollection and reacts to CollectionChanged,
///    the same way SwiftUI reacts to @Published.)
/// </summary>
public sealed class ShelfViewModel
{
    public ObservableCollection<ShelfFile> Files { get; } = [];

    private readonly List<string> _tempPaths = [];

    // ── Mutators ────────────────────────────────────────────────────────────

    /// <summary>Mirrors addFile(_ url: URL).</summary>
    public void AddFile(Uri uri)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            if (Files.Any(f => f.Uri == uri)) return;
            Files.Add(new ShelfFile(uri));
        });
    }

    /// <summary>
    /// Saves the bitmap to a temp PNG then shelves it.
    /// Mirrors addImage(_ image: NSImage).
    ///
    ///   NSBitmapImageRep + .png representation  →  PngBitmapEncoder
    ///   FileManager.default.temporaryDirectory  →  Path.GetTempPath()
    /// </summary>
    public void AddImage(BitmapSource image)
    {
        var path = Path.Combine(Path.GetTempPath(), $"FileBox_{Guid.NewGuid()}.png");
        try
        {
            using var stream = File.OpenWrite(path);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(image));
            encoder.Save(stream);
        }
        catch { return; }

        _tempPaths.Add(path);
        var uri = new Uri(path);
        Application.Current.Dispatcher.Invoke(() =>
            Files.Add(new ShelfFile(uri, isTemp: true)));
    }

    /// <summary>Mirrors addURL(_ url: URL).</summary>
    public void AddUrl(Uri uri)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            if (Files.Any(f => f.Uri == uri)) return;
            Files.Add(new ShelfFile(uri));
        });
    }

    /// <summary>Mirrors remove(_ file: ShelfFile).</summary>
    public void Remove(ShelfFile file)
    {
        Application.Current.Dispatcher.Invoke(() => Files.Remove(file));
    }

    /// <summary>Mirrors clear().</summary>
    public void Clear()
    {
        Application.Current.Dispatcher.Invoke(() => Files.Clear());
    }

    /// <summary>
    /// Deletes temporary image files written during this session.
    /// Mirrors cleanup() / applicationWillTerminate.
    /// </summary>
    public void Cleanup()
    {
        foreach (var p in _tempPaths)
            try { File.Delete(p); } catch { }
    }
}
