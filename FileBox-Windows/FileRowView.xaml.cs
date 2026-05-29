using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace FileBox;

/// <summary>
/// A single row in the shelf list.
/// Mirrors FileRowView (struct) in ShelfView.swift.
/// </summary>
public partial class FileRowView : UserControl
{
    // ── Dependency property: FileItem ───────────────────────────────────────

    public static readonly DependencyProperty FileItemProperty =
        DependencyProperty.Register(nameof(FileItem), typeof(ShelfFile),
            typeof(FileRowView), new PropertyMetadata(null, OnFileItemChanged));

    public ShelfFile? FileItem
    {
        get => (ShelfFile?)GetValue(FileItemProperty);
        set => SetValue(FileItemProperty, value);
    }

    private static void OnFileItemChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is FileRowView row && e.NewValue is ShelfFile file)
        {
            row.IconImage.Source = file.Icon;
            row.NameText.Text    = file.Name;
        }
    }

    // ── Routed event: RemoveRequested ───────────────────────────────────────
    // Bubbles up to ShelfView, mirroring the onRemove closure in FileRowView.swift.

    public static readonly RoutedEvent RemoveRequestedEvent =
        EventManager.RegisterRoutedEvent(
            "RemoveRequested", RoutingStrategy.Bubble,
            typeof(RoutedEventHandler), typeof(FileRowView));

    public event RoutedEventHandler RemoveRequested
    {
        add    => AddHandler(RemoveRequestedEvent, value);
        remove => RemoveHandler(RemoveRequestedEvent, value);
    }

    /// <summary>Carries the file to remove, so ShelfView can call shelf.Remove(file).</summary>
    public sealed class RemoveEventArgs : RoutedEventArgs
    {
        public ShelfFile File { get; }
        public RemoveEventArgs(ShelfFile file)
            : base(RemoveRequestedEvent) => File = file;
    }

    // ── Drag-out state ──────────────────────────────────────────────────────

    private Point _dragStartPoint;
    private const double DragThreshold = 4.0;   // pixels before DoDragDrop fires

    // ── Constructor ─────────────────────────────────────────────────────────

    public FileRowView()
    {
        InitializeComponent();
    }

    // ── Hover effects ───────────────────────────────────────────────────────
    // Mirrors @State private var isHovered + .onHover { } in FileRowView.swift.
    // On hover: background fades to white/6%; remove button fades in.
    // Off hover: reverse.

    private static readonly SolidColorBrush HoverBg =
        new(Color.FromArgb(0x0F, 0xFF, 0xFF, 0xFF));   // white 6%

    private void OnMouseEnter(object sender, MouseEventArgs e)
    {
        RowBg.Background = HoverBg;
        FadeBtn(1.0, duration: 0.12);
    }

    private void OnMouseLeave(object sender, MouseEventArgs e)
    {
        RowBg.Background = Brushes.Transparent;
        FadeBtn(0.0, duration: 0.12);
    }

    private void FadeBtn(double to, double duration)
    {
        var anim = new DoubleAnimation(to, TimeSpan.FromSeconds(duration));
        RemoveBtn.BeginAnimation(OpacityProperty, anim);
    }

    // ── Remove button ───────────────────────────────────────────────────────

    private void RemoveBtn_Click(object sender, RoutedEventArgs e)
    {
        if (FileItem is not null)
            RaiseEvent(new RemoveEventArgs(FileItem));
        e.Handled = true;
    }

    /// <summary>Prevents the remove-button mouse-down from bubbling into drag detection.</summary>
    private void StopBubble(object sender, MouseButtonEventArgs e)
        => e.Handled = true;

    // ── Drag-out ────────────────────────────────────────────────────────────
    // Mirrors .onDrag { NSItemProvider(object: file.url as NSURL) } in FileRowView.swift.
    // Records start position on mouse-down; initiates DoDragDrop once the cursor
    // has moved past the threshold (avoids accidentally starting a drag on a click).

    private void OnPreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
            _dragStartPoint = e.GetPosition(null);
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || FileItem is null) return;

        var pos  = e.GetPosition(null);
        var diff = pos - _dragStartPoint;

        if (Math.Abs(diff.X) < DragThreshold &&
            Math.Abs(diff.Y) < DragThreshold) return;

        // Build a FileDrop DataObject — same payload a Windows Explorer drag carries.
        // Mirrors NSItemProvider(object: file.url as NSURL).
        string[] paths = FileItem.Uri.Scheme is "http" or "https"
            ? []                                    // URLs: nothing to FileDrop
            : [FileItem.Uri.LocalPath];

        if (paths.Length == 0) return;

        var data = new DataObject(DataFormats.FileDrop, paths);
        DragDrop.DoDragDrop(this, data,
            DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link);
    }
}
