using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;

namespace FileBox;

/// <summary>
/// Installs a WH_MOUSE_LL hook and fires events for global left-button activity.
/// Direct Windows equivalent of:
///   NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown / .leftMouseDragged / .leftMouseUp)
/// </summary>
internal sealed class GlobalMouseHook : IDisposable
{
    public event Action?                  MouseDown;
    public event Action<double, double>?  MouseDrag;   // (deltaX, deltaY) in screen pixels
    public event Action?                  MouseUp;

    private IntPtr _hookId = IntPtr.Zero;
    private readonly NativeMethods.LowLevelMouseProc _proc;  // keep delegate alive
    private NativeMethods.POINT _lastPos;

    internal GlobalMouseHook() => _proc = HookCallback;

    internal void Install()
    {
        using var module = Process.GetCurrentProcess().MainModule!;
        _hookId = NativeMethods.SetWindowsHookEx(
            NativeMethods.WH_MOUSE_LL, _proc,
            NativeMethods.GetModuleHandle(module.ModuleName), 0);
    }

    // ── Hook callback (runs on the hook's private thread) ──────────────────

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var s = Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam);

            switch ((int)wParam)
            {
                case NativeMethods.WM_LBUTTONDOWN:
                    _lastPos = s.pt;
                    Application.Current?.Dispatcher.BeginInvoke(
                        MouseDown ?? (Action)delegate { });
                    break;

                case NativeMethods.WM_MOUSEMOVE:
                    // Only treat as drag if the left button is actually held down.
                    // (bit 15 of GetKeyState(VK_LBUTTON) set = button is down)
                    if ((NativeMethods.GetKeyState(0x01) & 0x8000) != 0)
                    {
                        double dx = s.pt.x - _lastPos.x;
                        double dy = s.pt.y - _lastPos.y;
                        _lastPos = s.pt;
                        if (MouseDrag is { } h)
                            Application.Current?.Dispatcher.BeginInvoke(h, dx, dy);
                    }
                    break;

                case NativeMethods.WM_LBUTTONUP:
                    Application.Current?.Dispatcher.BeginInvoke(
                        MouseUp ?? (Action)delegate { });
                    break;
            }
        }

        return NativeMethods.CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    public void Dispose()
    {
        if (_hookId != IntPtr.Zero)
        {
            NativeMethods.UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
        }
    }
}
