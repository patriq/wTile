const std = @import("std");
const win32 = @import("win32").everything;

const common = @import("common.zig");
const Rect = @import("rect.zig").Rect;

pub const PreviewWindow = struct {
    window_class_registration: ?u16 = null,
    window: ?win32.HWND = null,

    const CLASS_NAME = win32.L("Grid Preview");
    const BACKGROUND_COLOR = common.RGB(83, 83, 83);

    fn wndProc(window: win32.HWND, message: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.winapi) win32.LRESULT {
        return win32.DefWindowProcW(window, message, wParam, lParam);
    }

    pub fn createWindow(self: *PreviewWindow, hInstance: win32.HINSTANCE) void {
        // Create the window class and register it once!
        if (self.window_class_registration == null) {
            const window_class = win32.WNDCLASSW{
                .style = win32.WNDCLASS_STYLES{},
                .lpfnWndProc = wndProc,
                .cbClsExtra = 0,
                .cbWndExtra = 0,
                .hInstance = hInstance,
                .hIcon = null,
                .hCursor = null,
                .hbrBackground = win32.CreateSolidBrush(BACKGROUND_COLOR),
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
        self.window = win32.CreateWindowExW(
            win32.WINDOW_EX_STYLE{ .LAYERED = 1, .TRANSPARENT = 1, .TOPMOST = 1, .NOACTIVATE = 1 },
            CLASS_NAME, // Class name
            null, // Window name
            win32.WINDOW_STYLE{ .POPUP = 1, .VISIBLE = 1, .SYSMENU = 1 },
            0,
            0,
            0,
            0,
            null, // Parent
            null, // Menu
            hInstance,
            null, // WM_CREATE lpParam
        ).?;

        // Set layed window attributes
        if (win32.SetLayeredWindowAttributes(self.window, 0, 107, win32.LWA_ALPHA) == win32.FALSE) {
            unreachable;
        }
    }

    pub fn setPos(self: *const PreviewWindow, rect: Rect, insert_after: ?win32.HWND) void {
        common.setWindowPos(self.window, rect, insert_after);
    }

    pub fn closeWindow(self: *PreviewWindow) void {
        common.closeWindow(self.window);
    }

    pub fn cleanup(self: *PreviewWindow) void {
        // Destroy the window
        if (self.window) |window| {
            _ = win32.DestroyWindow(window);
            self.window = null;
        }
        // Unregister the window class
        if (self.window_class_registration != null) {
            _ = win32.UnregisterClassW(CLASS_NAME, null);
            self.window_class_registration = null;
        }
    }
};
