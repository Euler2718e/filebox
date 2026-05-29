using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Animation;

namespace FileBox;

/// <summary>
/// Always-on-top borderless floating window.
/// Mirrors FloatingPanel.swift (NSPanel subclass).
///
/// Key macOS → Windows mappings:
///   panel.orderFrontRegardless()           → Visibility = Visible (Topmost=True handles level)
///   panel.orderOut(nil)                    → Visibility = Hidden
///   NSAnimationContext (alphaValue)        → DoubleAnimation on OpacityProperty
///   NSAnimationContext (frame.size.height) → DoubleAnimation on HeightProperty
///   .nonactivatingPanel                    → WS_EX_NOACTIVATE set in OnSourceInitialized
///   canBecomeKey = true                    → default for WPF windows
///   canBecomeMain = false                  → ShowInTaskbar=False + WS_EX_TOOLWINDOW
/// </summary>
public partial class FloatingWindow : Window
{
    public FloatingWindow(ShelfViewModel shelf)
    {
        InitializeComponent();
        ShelfViewControl.DataContext = shelf;
    }

    // ── Window initialisation ───────────────────────────────────────────────

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        // Apply WS_EX_NOACTIVATE so the panel never steals keyboard focus,
        // mirroring NSPanel's .nonactivatingPanel style mask.
        // WS_EX_TOOLWINDOW hides it from Alt+Tab, mirroring NSApp.setActivationPolicy(.accessory).
        var handle  = new WindowInteropHelper(this).Handle;
        int exStyle = NativeMethods.GetWindowLong(handle, NativeMethods.GWL_EXSTYLE);
        NativeMethods.SetWindowLong(handle, NativeMethods.GWL_EXSTYLE,
            exStyle | NativeMethods.WS_EX_NOACTIVATE | NativeMethods.WS_EX_TOOLWINDOW);
    }

    // ── Animated show / hide ────────────────────────────────────────────────

    /// <summary>
    /// Fades the window in from transparent.
    /// Mirrors FloatingPanel.showAnimated() (ctx.duration = 0.12).
    /// </summary>
    public void ShowAnimated()
    {
        if (Visibility == Visibility.Visible && Opacity >= 1) return;

        Opacity    = 0;
        Visibility = Visibility.Visible;

        var anim = new DoubleAnimation(1, TimeSpan.FromSeconds(0.12));
        BeginAnimation(OpacityProperty, anim);
    }

    /// <summary>
    /// Fades the window out then hides it.
    /// Mirrors FloatingPanel.hideAnimated() (ctx.duration = 0.15).
    /// </summary>
    public void HideAnimated()
    {
        if (Visibility == Visibility.Hidden) return;

        var anim = new DoubleAnimation(0, TimeSpan.FromSeconds(0.15));
        anim.Completed += (_, _) =>
        {
            Visibility = Visibility.Hidden;
            Opacity    = 1;   // reset so ShowAnimated works cleanly next time
        };
        BeginAnimation(OpacityProperty, anim);
    }

    /// <summary>
    /// Animates the window height while keeping the top edge pinned.
    /// Mirrors AppDelegate.animateHeight(to:) (ctx.duration = 0.26, easeInEaseOut).
    ///
    /// On macOS: frame.origin.y = frame.maxY - newHeight keeps maxY (the top in Y-up coords) fixed.
    /// On Windows: Top is the top edge; changing only Height achieves the same effect.
    /// </summary>
    public void AnimateHeight(double newHeight)
    {
        var anim = new DoubleAnimation(newHeight,
            new Duration(TimeSpan.FromSeconds(0.26)))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut }
        };
        BeginAnimation(HeightProperty, anim);
    }
}
