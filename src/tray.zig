const std = @import("std");
const win32 = @import("win32").everything;

const common = @import("common.zig");

const NOTIFYICONDATAW = extern struct {
    cbSize: std.os.windows.DWORD = @sizeOf(NOTIFYICONDATAW),
    hWnd: win32.HWND,
    uID: std.os.windows.UINT,
    uFlags: std.os.windows.UINT,
    uCallbackMessage: std.os.windows.UINT,
    hIcon: win32.HICON,
    szTip: [128:0]u16,
    dwState: std.os.windows.DWORD,
    dwStateMask: std.os.windows.DWORD,
    szInfo: [256]u16,
    DUMMYUNIONNAME: extern union {
        uTimeout: std.os.windows.UINT,
        uVersion: std.os.windows.UINT,
    },
    szInfoTitle: [64]u16,
    dwInfoFlags: std.os.windows.DWORD,
    guidItem: std.os.windows.GUID,
    hBalloonIcon: std.os.windows.HICON,
};
extern "shell32" fn Shell_NotifyIconW(dwMessage: std.os.windows.DWORD, lpData: [*c]NOTIFYICONDATAW) callconv(.winapi) std.os.windows.BOOL;

const NIF_ICON = 0x00000002;
const NIF_MESSAGE = 0x00000001;
const NIF_TIP = 0x00000004;
const NIM_ADD = 0x00000000;
const NIM_DELETE = 0x00000002;

pub const Tray = struct {
    window_class_registration: ?u16 = null,
    window: ?win32.HWND = null,

    const CLASS_NAME = win32.L("wTile tray");
    const TRACK_POPUP_MENU_FLAGS = win32.TRACK_POPUP_MENU_FLAGS {
        .RIGHTBUTTON = 1,
        .RETURNCMD = 1,
        .NONOTIFY = 1,
    };
    // Tray icon
    const ICON_BYTES = @embedFile("res/icon.png");
    // Custom message to handle tray icon events
    const WM_TRAY_CALLBACK_MESSAGE = win32.WM_USER + 1;
    // Menu item IDs
    const ID_EXIT = 1;

    fn wndProc(window: win32.HWND, message: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
        switch (message) {
            win32.WM_CLOSE => {
                const self: *Tray = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                self.removeIcon();
                win32.PostQuitMessage(0);
                return win32.FALSE;
            },
            win32.WM_COMMAND => {
                const wmId = wParam & 0xFFFF;
                switch (wmId) {
                    ID_EXIT => {
                        common.closeWindow(window);
                    },
                    else => {},
                }
            },
            WM_TRAY_CALLBACK_MESSAGE => {
                if (lParam == win32.WM_RBUTTONUP) {
                    const self: *Tray = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                    self.createAndTrackPopupMenu();
                }
                return win32.FALSE;
            },
            else => {},
        }
        return win32.DefWindowProcW(window, message, wParam, lParam);
    }

    pub fn create(self: *Tray, hInstance: win32.HINSTANCE) void {
        // Create the window class and register it once!
        if (self.window_class_registration == null) {
            const window_class = win32.WNDCLASSW{
                .style = win32.WNDCLASS_STYLES{},
                .lpfnWndProc = wndProc,
                .cbClsExtra = 0,
                .cbWndExtra = @sizeOf(*Tray), // Reserve the size to store a Self pointer in the window
                .hInstance = hInstance,
                .hIcon = null,
                .hCursor = null,
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = CLASS_NAME,
            };

            const atom = win32.RegisterClassW(&window_class);
            if (atom == win32.FALSE) {
                unreachable;
            }
            self.window_class_registration = atom;
        }

        // Create the window
        const window = win32.CreateWindowExW(
            win32.WS_EX_NOACTIVATE,
            CLASS_NAME, // Class name
            null, // Window name
            win32.WINDOW_STYLE{},
            0,
            0,
            0,
            0,
            null, // Parent
            null, // Menu
            hInstance,
            null, // WM_CREATE lpParam
        ).?;

        // Store the Self pointer in the window at offset 0
        _ = win32.setWindowLongPtrW(window, 0, @intFromPtr(self));

        self.window = window;

        // Create the tray icon
        self.addIcon();
    }

    pub fn cleanup(self: *Tray) void {
        if (self.window != null) {
            _ = win32.DestroyWindow(self.window);
        }
        if (self.window_class_registration != null) {
            _ = win32.UnregisterClassW(CLASS_NAME, null);
        }
    }

    fn createAndTrackPopupMenu(self: *Tray) void {
        const menu = win32.CreatePopupMenu();
        defer _ = win32.DestroyMenu(menu);

        // Build the menu
        _ = win32.InsertMenuW(menu, 0, win32.MENU_ITEM_FLAGS{}, ID_EXIT, win32.L("Exit"));

        // Send the menu to the window
        _ = win32.SendMessageW(self.window, win32.WM_INITMENUPOPUP, @intFromPtr(menu), 0);

        // Spawn the menu at the cursor position
        var cursor_point: win32.POINT = undefined;
        _ = win32.GetCursorPos(&cursor_point);
        // https://www.codeproject.com/KB/shell/systemtray.aspx
        _ = win32.SetForegroundWindow(self.window);
        const cmd = win32.TrackPopupMenu(menu, TRACK_POPUP_MENU_FLAGS, cursor_point.x, cursor_point.y, 0, self.window, null);
        _ = win32.SendMessageW(self.window, win32.WM_COMMAND, @as(usize, @intCast(cmd)), 0);
    }

    fn addIcon(self: *Tray) void {
        // Load the tray icon
        const icon_handle = win32.CreateIconFromResourceEx(@ptrCast(@constCast(ICON_BYTES)), ICON_BYTES.len, win32.TRUE, 0x30000, 32, 32, win32.LR_DEFAULTCOLOR).?;
        defer _ = win32.DestroyIcon(icon_handle);

        // Add the tray icon
        var nid: NOTIFYICONDATAW = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = self.window.?;
        nid.uID = 0;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.hIcon = icon_handle;
        nid.uCallbackMessage = WM_TRAY_CALLBACK_MESSAGE;
        nid.szTip = comptime createTooltipArray(win32.L("wTile"));
        if (Shell_NotifyIconW(NIM_ADD, &nid) == win32.FALSE) {
            unreachable;
        }
    }

    fn removeIcon(self: *Tray) void {
        var nid: NOTIFYICONDATAW = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = self.window.?;
        nid.uID = 0;
        if (Shell_NotifyIconW(NIM_DELETE, &nid) == win32.FALSE) {
            unreachable;
        }
    }

    fn createTooltipArray(comptime tip: [:0]const u16) [128:0]u16 {
        var szTip: [128:0]u16 = undefined;
        @memset(&szTip, 0);
        comptime if (tip.len > szTip.len - 1) {
            @compileError("Tooltip is too long");
        };
        std.mem.copyForwards(u16, &szTip, tip);
        return szTip;
    }
};