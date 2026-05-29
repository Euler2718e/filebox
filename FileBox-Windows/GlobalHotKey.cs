using System;
using System.Windows;
using System.Windows.Interop;

namespace FileBox;

/// <summary>
/// Registers a system-wide hot key via RegisterHotKey and fires
/// <see cref="HotKeyPressed"/> when it is triggered.
///
/// Windows equivalent of:
///   NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
///       guard event.modifierFlags == .option, event.keyCode == 5 else { return }
///       ...
///   }
///
/// macOS ⌥G  →  Windows Alt+G
/// </summary>
internal sealed class GlobalHotKey : IDisposable
{
    public const uint MOD_ALT   = 0x0001;
    public const uint MOD_CTRL  = 0x0002;
    public const uint MOD_SHIFT = 0x0004;
    public const uint MOD_WIN   = 0x0008;

    public event Action? HotKeyPressed;

    private const int  HotkeyId = 9001;
    private IntPtr     _hWnd    = IntPtr.Zero;
    private HwndSource? _source;

    /// <summary>
    /// Call after the window HWND has been created
    /// (i.e. after WindowInteropHelper.EnsureHandle or SourceInitialized).
    /// </summary>
    internal void Register(IntPtr hWnd, uint modifiers, uint vk)
    {
        _hWnd   = hWnd;
        _source = HwndSource.FromHwnd(hWnd);
        _source?.AddHook(WndProc);
        NativeMethods.RegisterHotKey(hWnd, HotkeyId, modifiers, vk);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam,
                           ref bool handled)
    {
        const int WM_HOTKEY = 0x0312;
        if (msg == WM_HOTKEY && (int)wParam == HotkeyId)
        {
            HotKeyPressed?.Invoke();
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        if (_hWnd != IntPtr.Zero)
        {
            NativeMethods.UnregisterHotKey(_hWnd, HotkeyId);
            _source?.RemoveHook(WndProc);
            _hWnd = IntPtr.Zero;
        }
    }
}
