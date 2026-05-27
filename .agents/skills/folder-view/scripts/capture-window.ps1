<#
.SYNOPSIS
    Capture any Windows GUI window to PNG using PrintWindow.
    Works regardless of z-order — window does not need to be in the foreground.

.DESCRIPTION
    Uses PrintWindow with PW_RENDERFULLCONTENT=2, which works for Win32, WPF,
    and hardware-accelerated windows (Electron, WebView2, etc.).

    Enumerates visible windows via EnumWindows, matches by title substring,
    then renders directly into a GDI bitmap.

.PARAMETER Target
    Substring to match against window titles. Case-insensitive.

.PARAMETER Out
    Output PNG path. Default: C:\Windows\Temp\capture.png

.EXAMPLE
    .\capture-window.ps1 -Target "Slett" -Out "C:\Temp\result.png"
#>
param(
    [string]$Target = "",
    [string]$Out    = "C:\Windows\Temp\capture.png"
)

Add-Type -AssemblyName System.Drawing

# P/Invoke declarations — EnumWindows, GetWindowText, PrintWindow, GDI helpers
# Bitmap save is done in PowerShell (System.Drawing already loaded above)
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class WinCapture {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lp);

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int  GetWindowTextLengthW(IntPtr hwnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
                              static extern int  GetWindowTextW(IntPtr hwnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] static extern IntPtr GetWindowDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int   ReleaseDC(IntPtr hwnd, IntPtr hdc);
    [DllImport("user32.dll")] static extern bool  PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint flags);
    [DllImport("gdi32.dll")]  static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")]  static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int cx, int cy);
    [DllImport("gdi32.dll")]  static extern IntPtr SelectObject(IntPtr hdc, IntPtr h);
    [DllImport("gdi32.dll")]  static extern bool  DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")]  static extern bool  DeleteObject(IntPtr h);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int L, T, R, B; }

    public static List<Tuple<IntPtr,string>> FindWindows(string contains) {
        var list = new List<Tuple<IntPtr,string>>();
        EnumWindows((hwnd, _) => {
            if (!IsWindowVisible(hwnd)) return true;
            int len = GetWindowTextLengthW(hwnd);
            if (len <= 0) return true;
            var sb = new StringBuilder(len + 2);
            GetWindowTextW(hwnd, sb, sb.Capacity);
            string title = sb.ToString();
            if (string.IsNullOrEmpty(contains) ||
                title.IndexOf(contains, StringComparison.OrdinalIgnoreCase) >= 0)
                list.Add(Tuple.Create(hwnd, title));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    // Returns HBITMAP of window contents. Caller must call FreeHBitmap() after use.
    public static IntPtr CaptureHBitmap(IntPtr hwnd) {
        RECT r;
        if (!GetWindowRect(hwnd, out r)) return IntPtr.Zero;
        int w = r.R - r.L, h = r.B - r.T;
        if (w <= 0 || h <= 0) return IntPtr.Zero;

        IntPtr winDC = GetWindowDC(hwnd);
        IntPtr memDC = CreateCompatibleDC(winDC);
        IntPtr hBmp  = CreateCompatibleBitmap(winDC, w, h);
        IntPtr prev  = SelectObject(memDC, hBmp);

        PrintWindow(hwnd, memDC, 2);   // 2 = PW_RENDERFULLCONTENT

        SelectObject(memDC, prev);
        DeleteDC(memDC);
        ReleaseDC(hwnd, winDC);
        return hBmp;
    }

    public static void FreeHBitmap(IntPtr hBmp) { DeleteObject(hBmp); }
}
'@

# ── Find window ───────────────────────────────────────────────────────────────
$windows = [WinCapture]::FindWindows($Target)

if ($windows.Count -eq 0) {
    if ($Target) {
        Write-Warning "No visible window matching '$Target'. Listing all:"
        [WinCapture]::FindWindows("") | ForEach-Object {
            Write-Host ("  hwnd={0,-10}  {1}" -f $_.Item1, $_.Item2)
        }
    } else {
        Write-Host "All visible windows:"
        [WinCapture]::FindWindows("") | ForEach-Object {
            Write-Host ("  hwnd={0,-10}  {1}" -f $_.Item1, $_.Item2)
        }
    }
    exit 0
}

foreach ($w in $windows) {
    Write-Host ("  hwnd={0,-10}  {1}" -f $w.Item1, $w.Item2)
}

$hwnd  = $windows[0].Item1
$title = $windows[0].Item2
Write-Host "Capturing: '$title' (hwnd=$hwnd)"

# ── Capture ───────────────────────────────────────────────────────────────────
$hBmp = [WinCapture]::CaptureHBitmap($hwnd)
if ($hBmp -eq [IntPtr]::Zero) {
    Write-Error "CaptureHBitmap returned null for hwnd=$hwnd"
    exit 1
}

# Save via System.Drawing (already loaded via Add-Type -AssemblyName above)
$bmp = [System.Drawing.Image]::FromHbitmap($hBmp)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
[WinCapture]::FreeHBitmap($hBmp)

Write-Host "Saved ($($bmp.Width)x$($bmp.Height)): $Out"
