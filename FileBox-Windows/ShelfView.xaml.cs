using System;
using System.Collections.Specialized;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace FileBox;

/// <summary>
/// Code-behind for ShelfView.xaml.
/// Mirrors the drop handling, drag-border toggle, header drag-move, and
/// collection-change reactions from ShelfView.swift.
/// </summary>
public partial class ShelfView : UserControl
{
    private ShelfViewModel? _shelf;

    // Border brush colours — mirrors isDragTargeted state in SwiftUI
    private static readonly SolidColorBrush BorderNormal  =
        new(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF));  // opacity 0.10
    private static readonly SolidColorBrush BorderTargeted =
        new(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF));  // opacity 0.40

    public ShelfView()
    {
        InitializeComponent();
        BorderNormal.Freeze();
        BorderTargeted.Freeze();
        DataContextChanged += OnDataContextChanged;

        // Subscribe to remove requests that bubble up from FileRowView items.
        AddHandler(FileRowView.RemoveRequestedEvent,
            new RoutedEventHandler(OnFileRemoveRequested));
    }

    // ── DataContext / shelf binding ─────────────────────────────────────────

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is ShelfViewModel old)
            old.Files.CollectionChanged -= OnFilesChanged;

        _shelf = e.NewValue as ShelfViewModel;

        if (_shelf is not null)
        {
            _shelf.Files.CollectionChanged += OnFilesChanged;
            FileList.ItemsSource = _shelf.Files;
            RefreshLayout();
        }
    }

    /// <summary>
    /// Mirrors the .sink { files in ... } subscriber in AppDelegate.observeShelf().
    /// Toggles empty-hint / file-list visibility and the Clear button.
    /// </summary>
    private void OnFilesChanged(object? sender, NotifyCollectionChangedEventArgs e)
        => Dispatcher.Invoke(RefreshLayout);

    private void RefreshLayout()
    {
        bool hasFiles = (_shelf?.Files.Count ?? 0) > 0;

        EmptyHint.Visibility  = hasFiles ? Visibility.Collapsed : Visibility.Visible;
        FileList.Visibility   = hasFiles ? Visibility.Visible   : Visibility.Collapsed;
        ClearBtn.Visibility   = hasFiles ? Visibility.Visible   : Visibility.Collapsed;
    }

    // ── Header drag-move ────────────────────────────────────────────────────

    /// <summary>
    /// Moves the floating window when the user drags the header strip.
    /// Mirrors WindowMoveHandle / mouseDownCanMoveWindow = true in ShelfView.swift.
    ///
    /// We walk the visual tree to skip the click if it originated from a Button,
    /// so the Clear button still fires its Click event normally.
    /// </summary>
    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        var el = e.OriginalSource as DependencyObject;
        while (el is not null)
        {
            if (el is Button) return;
            el = VisualTreeHelper.GetParent(el);
        }

        Window.GetWindow(this)?.DragMove();
    }

    /// <summary>Prevents mouse-down from bubbling out of the Clear button into DragMove.</summary>
    private void StopBubble(object sender, MouseButtonEventArgs e)
        => e.Handled = true;

    // ── Clear button ────────────────────────────────────────────────────────

    private void ClearBtn_Click(object sender, RoutedEventArgs e)
        => _shelf?.Clear();

    // ── Remove event from FileRowView ───────────────────────────────────────

    private void OnFileRemoveRequested(object sender, RoutedEventArgs e)
    {
        if (e is FileRowView.RemoveEventArgs args)
            _shelf?.Remove(args.File);
    }

    // ── Drag-and-drop target ────────────────────────────────────────────────

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = CanAccept(e) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void OnDragEnter(object sender, DragEventArgs e)
    {
        if (!CanAccept(e)) return;

        // Brighten border — mirrors isDragTargeted = true
        BgBorder.BorderBrush = BorderTargeted;
        AnimateBorder(0x66);

        EmptyHint.Text = "Release to add";

        e.Effects = DragDropEffects.Copy;
        e.Handled = true;
    }

    private void OnDragLeave(object sender, DragEventArgs e)
    {
        // Dim border — mirrors isDragTargeted = false
        AnimateBorder(0x1A);
        EmptyHint.Text = "Drop here  ·  Alt+G for Explorer selection";
    }

    /// <summary>
    /// Handles the actual drop.
    /// Mirrors handleDrop(_ providers: [NSItemProvider]) in ShelfView.swift.
    ///
    ///   UTType.fileURL  →  DataFormats.FileDrop
    ///   NSImage         →  DataFormats.Bitmap / DataFormats.Dib
    ///   UTType.url      →  DataFormats.Text (URI strings)
    /// </summary>
    private void OnDrop(object sender, DragEventArgs e)
    {
        AnimateBorder(0x1A);
        EmptyHint.Text = "Drop here  ·  Alt+G for Explorer selection";

        if (_shelf is null) return;

        // Files / folders
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            var paths = (string[])e.Data.GetData(DataFormats.FileDrop);
            foreach (var path in paths)
                _shelf.AddFile(new Uri(path));
        }
        // Bitmaps dragged from image editors / browsers
        else if (e.Data.GetDataPresent(DataFormats.Bitmap) ||
                 e.Data.GetDataPresent(DataFormats.Dib))
        {
            var format = e.Data.GetDataPresent(DataFormats.Bitmap)
                ? DataFormats.Bitmap : DataFormats.Dib;

            if (e.Data.GetData(format) is System.Windows.Media.Imaging.BitmapSource bmp)
                _shelf.AddImage(bmp);
        }
        // URLs dragged from browsers (text/uri-list or plain text URL)
        else if (e.Data.GetDataPresent(DataFormats.Text))
        {
            var text = (string)e.Data.GetData(DataFormats.Text);
            if (Uri.TryCreate(text?.Trim(), UriKind.Absolute, out var uri) &&
                uri.Scheme is "http" or "https")
            {
                _shelf.AddUrl(uri);
            }
        }

        e.Handled = true;
    }

    private static bool CanAccept(DragEventArgs e) =>
        e.Data.GetDataPresent(DataFormats.FileDrop) ||
        e.Data.GetDataPresent(DataFormats.Bitmap)   ||
        e.Data.GetDataPresent(DataFormats.Dib)      ||
        e.Data.GetDataPresent(DataFormats.Text);

    // ── Border colour animation ─────────────────────────────────────────────
    // Mirrors .animation(.spring(response:dampingFraction:), value: isDragTargeted).

    private void AnimateBorder(byte targetAlpha)
    {
        var anim = new ColorAnimation(
            Color.FromArgb(targetAlpha, 0xFF, 0xFF, 0xFF),
            TimeSpan.FromSeconds(0.18));
        BgBorder.BorderBrush = new SolidColorBrush(((SolidColorBrush)BgBorder.BorderBrush).Color);
        ((SolidColorBrush)BgBorder.BorderBrush).BeginAnimation(
            SolidColorBrush.ColorProperty, anim);
    }
}
