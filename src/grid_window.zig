const std = @import("std");
const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
};
const WINAPI = @import("std").os.windows.WINAPI;

const common = @import("common.zig");
const Rect = @import("rect.zig").Rect;
const Grid = @import("grid.zig").Grid;
const PreviewWindow = @import("preview_window.zig").PreviewWindow;

pub const GridWindow = struct {
    grid: *Grid,
    preview_window: *PreviewWindow,

    window: ?win32.HWND = null,
    window_class_registration: ?u16 = null,
    shift_pressed: bool = false,

    const CLASS_NAME = win32.L("Grid");
    const BACKGROUND_COLOR = common.RGB(44, 44, 44);
    const WINDOW_STYLE = win32.WS_OVERLAPPEDWINDOW;
    const WINDOW_EX_STYLE = win32.WINDOW_EX_STYLE{ .TOPMOST = 1, .TOOLWINDOW = 1 };

    fn wndProc(window: win32.HWND, message: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(WINAPI) win32.LRESULT {
        var repaint = false;
        // Repaint at the end if needed
        defer if (repaint) {
            _ = win32.InvalidateRect(window, null, win32.FALSE);
        };

        switch (message) {
            win32.WM_SETFOCUS => {
                std.debug.print("Got focus {}\n", .{wParam});
                return win32.FALSE;
            },
            win32.WM_KILLFOCUS => {
                std.debug.print("Lost focus {}\n", .{wParam});
                return win32.FALSE;
            },
            win32.WM_KEYDOWN => {
                const key: win32.VIRTUAL_KEY = @enumFromInt(wParam);
                const self: *GridWindow = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                switch (key) {
                    win32.VK_ESCAPE => {
                        // Send WM_CLOSE to the window
                        _ = win32.PostMessage(window, win32.WM_CLOSE, 0, 0);
                        return win32.FALSE;
                    },
                    win32.VK_SHIFT => {
                        self.shift_pressed = true;
                        return win32.FALSE;
                    },
                    win32.VK_UP, win32.VK_DOWN, win32.VK_LEFT, win32.VK_RIGHT => {
                        // Handle arrow keys
                        self.grid.handleKeys(key, self.shift_pressed);

                        // Repaint the window
                        repaint = true;

                        // Change preview window position
                        const preview_area = self.grid.currentPreviewArea();
                        self.preview_window.setPos(preview_area, self.window);
                        return win32.FALSE;
                    },
                    else => {
                        std.debug.print("{}", .{key});
                    },
                }
            },
            win32.WM_KEYUP => {
                const key: win32.VIRTUAL_KEY = @enumFromInt(wParam);
                const self: *GridWindow = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                switch (key) {
                    win32.VK_SHIFT => {
                        self.shift_pressed = false;
                        return win32.FALSE;
                    },
                    else => {},
                }
            },
            win32.WM_PAINT => {
                const self: *const GridWindow = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                self.render(window);
                return win32.FALSE;
            },
            win32.WM_CLOSE => {
                const self: *GridWindow = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                // Reset grid
                self.grid.resetSelection();
                // Close the preview window
                _ = win32.PostMessage(self.preview_window.window, win32.WM_CLOSE, 0, 0);
            },
            else => {},
        }
        return win32.DefWindowProcW(window, message, wParam, lParam);
    }

    pub fn createWindow(self: *GridWindow, hInstance: win32.HINSTANCE) void {
        // Create the window class and register it once
        if (self.window_class_registration == null) {
            const window_class = win32.WNDCLASSW{
                .style = win32.WNDCLASS_STYLES{},
                .lpfnWndProc = wndProc,
                .cbClsExtra = 0,
                .cbWndExtra = @sizeOf(*GridWindow), // Reserve the size to store a Self pointer in the window
            .hInstance = hInstance,
                .hIcon = null,
                .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
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

        // Find the client dimensions
        const client_dimensions = self.grid.dimensions();

        // Find the window rectangle based on the client dimensions
        var window_rect = win32.RECT{
            .left = 0,
            .top = 0,
            .right = client_dimensions[0],
            .bottom = client_dimensions[1],
        };
        _ = win32.AdjustWindowRectEx(&window_rect, WINDOW_STYLE, win32.FALSE, WINDOW_EX_STYLE);
        const window_dimensions = Rect.fromRECT(window_rect);

        // Find where to place the window (center of the current monitor)
        const work_area = common.getWorkArea();
        const x = @divTrunc(work_area.width, 2) - @divTrunc(window_dimensions.width, 2) + work_area.x + window_dimensions.x;
        const y = @divTrunc(work_area.height, 2) - @divTrunc(window_dimensions.height, 2) + work_area.y + window_dimensions.y;

        // Create the window
        const window = win32.CreateWindowExW(
            WINDOW_EX_STYLE,
            CLASS_NAME, // Class name
            null, // Window name
            WINDOW_STYLE,
            x,
            y,
            window_dimensions.width,
            window_dimensions.height,
            null, // Parent
            null, // Menu
            hInstance,
            null, // WM_CREATE lpParam
        ).?;

        // Store the Self pointer in the window at offset 0
        _ = win32.setWindowLongPtrW(window, 0, @intFromPtr(self));

        self.window = window;
    }

    pub fn showWindow(self: *const GridWindow) void {
        _ = win32.ShowWindow(self.window, win32.SW_SHOW);
    }

    fn forceSetForeground(self: *const GridWindow) bool {
        if (self.window) |window| {
            return common.forceSetForeground(window);
        }
        return false;
    }

    pub fn setForeground(self: *const GridWindow) bool {
        return win32.SetForegroundWindow(self.window) != win32.FALSE;
    }

    pub fn onForegroundChange(self: *GridWindow, previous: ?win32.HWND, current: ?win32.HWND) void {
        // Get its title and set it to the grid window
        if (current != self.window and current != self.preview_window.window) {
            var title = common.getWindowsText(current);
            _ = win32.SetWindowTextW(self.window, &title);
            std.debug.print("Changed window from {any} {any}\n", .{previous, current});
        }
    }

    fn destroyWindow(self: *GridWindow) void {
        if (self.window) |window| {
            _ = win32.DestroyWindow(window);
            self.window = null;
        }
    }

    fn deregisterWindowClass(self: *GridWindow) void {
        std.debug.print("Cleaning up grid window", .{});
        // Unregister the window class
        if (self.window_class_registration != null) {
            _ = win32.UnregisterClassW(CLASS_NAME, null);
            self.window_class_registration = null;
        }
    }

    pub fn cleanup(self: *GridWindow) void {
        self.destroyWindow();
        self.deregisterWindowClass();
    }

    fn render(self: *const GridWindow, window: win32.HWND) void {
        var paint: win32.PAINTSTRUCT = undefined;
        const hdc = win32.BeginPaint(window, &paint);
        defer _ = win32.EndPaint(window, &paint);

        const grid = self.grid;

        var row: i32 = 0;
        while (row < self.grid.rows) : (row += 1) {
            var col: i32 = 0;
            while (col < self.grid.cols) : (col += 1) {
                const color = if (grid.isSelected(row, col)) common.RGB(0, 77, 128) else common.RGB(255, 255, 255);
                const brush = win32.CreateSolidBrush(color);
                defer _ = win32.DeleteObject(brush);

                const tile_rect = self.grid.tileArea(row, col).toRECT();
                _ = win32.FillRect(hdc, &tile_rect, brush);
            }
        }
    }
};