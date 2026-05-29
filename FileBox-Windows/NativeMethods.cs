using System;
using System.Runtime.InteropServices;

namespace FileBox;

/// <summary>
/// Win32 P/Invoke declarations used across the app.
/// Mirrors the role of AppKit/Carbon imports on macOS.
/// </summary>
internal static class NativeMethods
{
    // ── Window extended styles ──────────────────────────────────────────────
    internal const int GWL_EXSTYLE      = -20;
    internal const int WS_EX_NOACTIVATE = 0x0800_0000;  // never steals focus
    internal const int WS_EX_TOOLWINDOW = 0x0000_0080;  // hidden from Alt+Tab

    [DllImport("user32.dll")]
    internal static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    internal static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    // ── Low-level mouse hook (WH_MOUSE_LL) ─────────────────────────────────
    // Used to detect global drag activity, mirroring NSEvent.addGlobalMonitorForEvents.

    internal const int WH_MOUSE_LL   = 14;
    internal const int WM_LBUTTONDOWN = 0x0201;
    internal const int WM_LBUTTONUP   = 0x0202;
    internal const int WM_MOUSEMOVE   = 0x0200;

    internal delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    internal static extern IntPtr SetWindowsHookEx(
        int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    internal static extern IntPtr CallNextHookEx(
        IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    internal static extern IntPtr GetModuleHandle(string? lpModuleName);

    /// <summary>Bit 15 set → key is down.</summary>
    [DllImport("user32.dll")]
    internal static extern short GetKeyState(int nVirtKey);

    [StructLayout(LayoutKind.Sequential)]
    internal struct POINT { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MSLLHOOKSTRUCT
    {
        public POINT  pt;
        public uint   mouseData;
        public uint   flags;
        public uint   time;
        public IntPtr dwExtraInfo;
    }

    // ── Global hot key ──────────────────────────────────────────────────────
    // Mirrors NSEvent.addGlobalMonitorForEvents(matching: .keyDown).

    [DllImport("user32.dll")]
    internal static extern bool RegisterHotKey(
        IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    internal static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
