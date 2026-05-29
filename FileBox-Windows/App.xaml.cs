using System;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Interop;
using System.Windows.Threading;

namespace FileBox;

/// <summary>
/// Application entry point and coordinator.
/// Mirrors AppDelegate.swift 1-to-1, including all five setup methods.
///
/// macOS → Windows API mapping summary:
///   NSApplication.shared / NSApplicationDelegate  →  System.Windows.Application
///   NSApp.setActivationPolicy(.accessory)          →  ShutdownMode=OnExplicitShutdown + WS_EX_TOOLWINDOW
///   NSStatusItem (menu bar icon + menu)            →  System.Windows.Forms.NotifyIcon + ContextMenuStrip
///   NSEvent.addGlobalMonitorForEvents              →  GlobalMouseHook (WH_MOUSE_LL)
///   NSEvent.addGlobalMonitorForEvents(.keyDown)    →  GlobalHotKey (RegisterHotKey)
///   NSAppleScript (Finder selection)               →  Shell.Application COM (Explorer selection)
///   Combine sink on @Published                     →  ObservableCollection.CollectionChanged
/// </summary>
public partial class App : System.Windows.Application
{
    private FloatingWindow  _window  = null!;
    private ShelfViewModel  _shelf   = new();
    private NotifyIcon      _tray    = null!;
    private GlobalMouseHook _mouse   = new();
    private GlobalHotKey    _hotKey  = new();

    // Drag-show state — mirrors AppDelegate's isDragging / travelSinceDown / hideTimer
    private bool              _isDragging;
    private double            _travelSinceDown;
    private const double      ActivationTravel = 8.0;   // logical pixels
    private DispatcherTimer?  _hideTimer;

    // ── Startup / teardown ──────────────────────────────────────────────────

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        SetupWindow();
        SetupTrayIcon();
        SetupDragMonitors();
        SetupHotKey();
        ObserveShelf();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _shelf.Cleanup();
        _mouse.Dispose();
        _hotKey.Dispose();
        _tray.Dispose();
        base.OnExit(e);
    }

    // ── Panel setup ─────────────────────────────────────────────────────────
    // Mirrors setupPanel() in AppDelegate.swift.

    private void SetupWindow()
    {
        _window = new FloatingWindow(_shelf);

        // Position at top-right of the work area (excludes taskbar),
        // mirroring screen.visibleFrame on macOS.
        var area = SystemParameters.WorkArea;
        _window.Left = area.Right  - _window.Width  - 16;
        _window.Top  = area.Top    + 8;

        // Force HWND creation without showing the window.
        // Required so GlobalHotKey can attach its message hook immediately.
        new WindowInteropHelper(_window).EnsureHandle();
    }

    /// <summary>
    /// Resizes the panel while keeping its top edge pinned.
    /// Mirrors animateHeight(to:) in AppDelegate.swift.
    /// </summary>
    private void AnimateHeight(double newHeight)
        => _window.AnimateHeight(newHeight);

    /// <summary>Mirrors idealHeight(for:) in AppDelegate.swift.</summary>
    private static double IdealHeight(int count)
        => count == 0 ? 60 : Math.Min(40 + count * 36, 340);

    // ── Shelf observer ──────────────────────────────────────────────────────
    // Mirrors observeShelf() / the Combine .sink subscriber in AppDelegate.swift.

    private void ObserveShelf()
    {
        _shelf.Files.CollectionChanged += (_, _) =>
        {
            Dispatcher.Invoke(() =>
            {
                int count = _shelf.Files.Count;
                AnimateHeight(IdealHeight(count));

                if (count > 0)
                {
                    _hideTimer?.Stop();
                    if (!_window.IsVisible) _window.ShowAnimated();
                }
                else if (!_isDragging)
                {
                    _window.HideAnimated();
                }
            });
        };
    }

    // ── Drag detection ──────────────────────────────────────────────────────
    // Mirrors setupDragMonitors() in AppDelegate.swift.
    //
    // On macOS the drag pasteboard is checked for shelvable types before surfacing
    // the panel. On Windows there is no equivalent global OLE drag-data clipboard,
    // so the panel surfaces for any left-button drag that exceeds the travel threshold.
    // The drop handler in ShelfView filters non-shelvable payloads at drop time.

    private void SetupDragMonitors()
    {
        _mouse.MouseDown += () => _travelSinceDown = 0;

        _mouse.MouseDrag += (dx, dy) =>
        {
            if (_isDragging) return;
            _travelSinceDown += Math.Sqrt(dx * dx + dy * dy);
            if (_travelSinceDown >= ActivationTravel)
                HandleDragStart();
        };

        _mouse.MouseUp += HandleMouseUp;
        _mouse.Install();
    }

    private void HandleDragStart()
    {
        _isDragging = true;
        _hideTimer?.Stop();
        _window.ShowAnimated();
    }

    private void HandleMouseUp()
    {
        _isDragging      = false;
        _travelSinceDown = 0;

        // Give the user a moment, then hide if nothing was dropped.
        // Mirrors the 0.7 s Timer in AppDelegate.handleMouseUp().
        _hideTimer?.Stop();
        _hideTimer = new DispatcherTimer
            { Interval = TimeSpan.FromSeconds(0.7) };
        _hideTimer.Tick += (_, _) =>
        {
            _hideTimer.Stop();
            if (_shelf.Files.Count == 0) _window.HideAnimated();
        };
        _hideTimer.Start();
    }

    // ── Tray icon ───────────────────────────────────────────────────────────
    // Mirrors setupMenuBar() in AppDelegate.swift.
    //
    //   NSStatusBar.system.statusItem  →  NotifyIcon
    //   NSImage(systemSymbolName: "tray.2.fill")  →  programmatic GDI bitmap
    //   NSMenu / NSMenuItem             →  ContextMenuStrip / ToolStripMenuItem

    private void SetupTrayIcon()
    {
        _tray = new NotifyIcon
        {
            Icon    = BuildTrayIcon(),
            Text    = "FileBox",
            Visible = true
        };

        var menu = new ContextMenuStrip();
        menu.Items.Add("Grab Explorer Selection  (Alt+G)", null,
            (_, _) => GrabExplorerSelection());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Show Panel",  null, (_, _) => Dispatcher.Invoke(_window.ShowAnimated));
        menu.Items.Add("Clear All",   null, (_, _) => _shelf.Clear());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit FileBox", null, (_, _) => Dispatcher.Invoke(Shutdown));

        _tray.ContextMenuStrip = menu;
    }

    /// <summary>
    /// Draws a minimal inbox/tray icon at runtime.
    /// The macOS app uses SF Symbols "tray.2.fill" from the bundle;
    /// on Windows we generate an equivalent 16×16 icon with GDI+.
    /// Replace with a real .ico embedded resource for production.
    /// </summary>
    private static System.Drawing.Icon BuildTrayIcon()
    {
        using var bmp = new System.Drawing.Bitmap(
            16, 16, System.Drawing.Imaging.PixelFormat.Format32bppArgb);

        using (var g = System.Drawing.Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.Clear(System.Drawing.Color.Transparent);

            using var pen = new System.Drawing.Pen(System.Drawing.Color.White, 1.3f)
            {
                StartCap = System.Drawing.Drawing2D.LineCap.Round,
                EndCap   = System.Drawing.Drawing2D.LineCap.Round
            };

            // Tray box outline
            g.DrawLines(pen,
            [
                new System.Drawing.PointF(1, 9),
                new System.Drawing.PointF(1, 14),
                new System.Drawing.PointF(14, 14),
                new System.Drawing.PointF(14, 9)
            ]);
            // Angled sides (inbox shape)
            g.DrawLine(pen, 1,  9, 4,  5);
            g.DrawLine(pen, 14, 9, 11, 5);
            g.DrawLine(pen, 4,  5, 11, 5);
            // Shelf divider
            g.DrawLine(pen, 1, 9, 14, 9);
        }

        var hIcon = bmp.GetHicon();
        return System.Drawing.Icon.FromHandle(hIcon);
    }

    // ── Global hot key (Alt+G) ──────────────────────────────────────────────
    // Mirrors setupHotKey() — macOS ⌥G (keyCode 5, modifier .option) → Windows Alt+G.

    private void SetupHotKey()
    {
        var handle = new WindowInteropHelper(_window).Handle;
        _hotKey.HotKeyPressed += () =>
        {
            GrabExplorerSelection();
            Dispatcher.Invoke(_window.ShowAnimated);
        };
        _hotKey.Register(handle, GlobalHotKey.MOD_ALT, (uint)'G');
    }

    // ── Explorer integration ────────────────────────────────────────────────
    // Mirrors grabFinderFiles() in AppDelegate.swift.
    //
    //   AppleScript "tell application Finder / selection as alias list"
    //   → Shell.Application COM "Windows.Item(i).Document.SelectedItems()"
    //
    // Shell.Application is the late-bound Windows equivalent of Finder scripting.

    private void GrabExplorerSelection()
    {
        try
        {
            var shellType = Type.GetTypeFromProgID("Shell.Application")!;
            dynamic shell = Activator.CreateInstance(shellType)!;
            dynamic windows = shell.Windows();

            for (int i = 0; i < windows.Count; i++)
            {
                try
                {
                    dynamic win = windows.Item(i);
                    string? locationUrl = win?.LocationURL as string;
                    if (string.IsNullOrEmpty(locationUrl)) continue;  // not an Explorer window

                    dynamic? selected = win?.Document?.SelectedItems();
                    if (selected is null) continue;

                    foreach (dynamic item in selected)
                    {
                        string? path = item?.Path as string;
                        if (!string.IsNullOrEmpty(path))
                            _shelf.AddFile(new Uri(path));
                    }
                }
                catch { /* skip non-Explorer windows and COM errors */ }
            }
        }
        catch { /* Shell.Application unavailable */ }
    }
}
