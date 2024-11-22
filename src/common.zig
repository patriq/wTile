const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").system.threading;
    usingnamespace @import("win32").system.process_status;
};

const Rect = @import("rect.zig").Rect;

pub fn getActiveMonitor() win32.HMONITOR {
    var point: win32.POINT = undefined;
    if (win32.GetCursorPos(&point) == win32.FALSE) {
        unreachable;
    }
    return win32.MonitorFromPoint(point, win32.MONITOR_DEFAULTTONEAREST).?;
}

pub fn getWorkArea() Rect {
    const active_monitor = getActiveMonitor();
    var monitor_info: win32.MONITORINFO = undefined;
    monitor_info.cbSize = @sizeOf(win32.MONITORINFO);
    if (win32.GetMonitorInfoW(active_monitor, &monitor_info) == win32.FALSE) {
        unreachable;
    }
    return Rect.fromRECT(monitor_info.rcWork);
}

pub fn RGB(r: u8, g: u8, b: u8) u32 {
    return @as(u32, r) | (@as(u32, g) << 8) | (@as(u32, b) << 16);
}

pub fn forceSetForeground(hwnd: win32.HWND) bool {
    // Bypass the foreground https://gist.github.com/Aetopia/1581b40f00cc0cadc93a0e8ccb65dc8c
    var inputs = [_]win32.INPUT{
        .{
            .type = win32.INPUT_TYPE.KEYBOARD,
            .Anonymous = .{
                .ki = .{
                    .wVk = win32.VK_MENU,
                    .dwFlags = win32.KEYBD_EVENT_FLAGS{},
                    .wScan = 0,
                    .dwExtraInfo = 0,
                    .time = 0,
                }
            }
        },
        .{
            .type = win32.INPUT_TYPE.KEYBOARD,
            .Anonymous = .{
                .ki = .{
                    .wVk = win32.VK_MENU,
                    .dwFlags = win32.KEYEVENTF_KEYUP,
                    .wScan = 0,
                    .dwExtraInfo = 0,
                    .time = 0,
                }
            }
        },
    };
    _ = win32.SendInput(inputs.len, &inputs, @sizeOf(win32.INPUT));
    return win32.SetForegroundWindow(hwnd) != win32.FALSE;
}

pub fn getWindowsText(hwnd: ?win32.HWND) [256:0]u16 {
    var title: [256:0]u16 = undefined;
    _ = win32.GetWindowTextW(hwnd, &title, @intCast(title.len));
    return title;
}

pub fn getWindowProcessText(hwnd: ?win32.HWND) [256:0]u16 {
    var process_id: u32 = 0;
    _ = win32.GetWindowThreadProcessId(hwnd, &process_id);
    const process = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, win32.FALSE, process_id);
    var buffer: [256:0]u16 = undefined;
    @memset(&buffer, 0);
    if (process == null) {
        return buffer;
    }
    defer _ = win32.CloseHandle(process);
    _ = win32.K32GetProcessImageFileNameW(process, &buffer, @intCast(buffer.len));
    return buffer;
}

pub fn getTransparentBorders(hwnd: ?win32.HWND) struct { i32, i32 } {
    var info: win32.WINDOWINFO = undefined;
    info.cbSize = @sizeOf(win32.WINDOWINFO);
    _ = win32.GetWindowInfo(hwnd, &info);
    const window_rect = Rect.fromRECT(info.rcWindow);
    const client_rect = Rect.fromRECT(info.rcClient);
    const x_border = window_rect.x - client_rect.x + window_rect.width - client_rect.width;
    const y_border = window_rect.y - client_rect.y + window_rect.height - client_rect.height;
    return .{ x_border , y_border };
}

pub fn closeWindow(hwnd: ?win32.HWND) void {
    _ = win32.PostMessageW(hwnd, win32.WM_CLOSE, 0, 0);
}

pub fn setWindowPos(hwnd: ?win32.HWND, rect: Rect, insert_after: ?win32.HWND) void {
    _ = win32.SetWindowPos(hwnd, insert_after, rect.x, rect.y, rect.width, rect.height, win32.SWP_NOACTIVATE);
}