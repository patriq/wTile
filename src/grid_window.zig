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
    active_window: ?win32.HWND = null,

    const CLASS_NAME = win32.L("Grid");
    const BACKGROUND_COLOR = common.RGB(32, 33, 36);
    const SELECTED_COLOR = common.RGB(186, 188, 190);
    const UNSELECTED_COLOR = common.RGB(95, 99, 104);
    const WINDOW_STYLE = win32.WS_OVERLAPPEDWINDOW;
    const WINDOW_EX_STYLE = win32.WINDOW_EX_STYLE{ .TOPMOST = 1, .TOOLWINDOW = 1 };

    fn wndProc(window: win32.HWND, message: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(WINAPI) win32.LRESULT {
        var repaint = false;
        // Repaint at the end if needed
        defer if (repaint) {
            _ = win32.InvalidateRect(window, null, win32.FALSE);
        };

        switch (message) {
            win32.WM_KILLFOCUS => {
                // Close the window when it loses focus
                const self: *GridWindow = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                self.closeWindow();
                return win32.FALSE;
            },
            win32.WM_KEYDOWN => {
                const key: win32.VIRTUAL_KEY = @enumFromInt(wParam);
                const self: *GridWindow = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                switch (key) {
                    win32.VK_ESCAPE => {
                        self.closeWindow();
                        return win32.FALSE;
                    },
                    win32.VK_SHIFT => {
                        self.shift_pressed = true;
                        return win32.FALSE;
                    },
                    win32.VK_UP, win32.VK_DOWN, win32.VK_LEFT, win32.VK_RIGHT => {
                        // Try to set the current selection to the active window dimensions (nearest)
                        if (!self.grid.isAnySelected()) {
                            if (self.active_window) |active_window| {
                                self.grid.setSelectedUsingActiveWindow(active_window);
                            }
                        }

                        // Handle arrow keys
                        self.grid.handleKeys(key, self.shift_pressed);

                        // Repaint the window
                        repaint = true;

                        // Change preview window position
                        self.updatePreviewWindowPosition();
                        return win32.FALSE;
                    },
                    win32.VK_RETURN => {
                        self.applyActiveWindowResize();
                        self.closeWindow();
                    },
                    else => {},
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
                self.preview_window.closeWindow();
            },
            win32.WM_DESTROY => {
                const self: *GridWindow = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                self.window = null;
                return win32.FALSE;
            },
            else => {},
        }
        return win32.DefWindowProcW(window, message, wParam, lParam);
    }

    fn calculate_window_pos(self: *const GridWindow) Rect {
        const work_area = common.getWorkArea();

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
        const x = @divTrunc(work_area.width, 2) - @divTrunc(window_dimensions.width, 2) + work_area.x + window_dimensions.x;
        const y = @divTrunc(work_area.height, 2) - @divTrunc(window_dimensions.height, 2) + work_area.y + window_dimensions.y;
        return Rect{ .x = x, .y = y, .width = window_dimensions.width, .height = window_dimensions.height };
    }

    pub fn updatePreviewWindowPosition(self: *const GridWindow) void {
        const preview_area = self.grid.currentPreviewArea();
        self.preview_window.setPos(preview_area, self.window);
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

        // Calculate the window position
        const window_dimensions = self.calculate_window_pos();

        // Create the window
        const window = win32.CreateWindowExW(
            WINDOW_EX_STYLE,
            CLASS_NAME, // Class name
            null, // Window name
            WINDOW_STYLE,
            window_dimensions.x,
            window_dimensions.y,
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

    pub fn reposition(self: *const GridWindow) void {
        const window_dimensions = self.calculate_window_pos();
        common.setWindowPos(self.window, window_dimensions, null);
        self.updatePreviewWindowPosition();
    }

    pub fn showWindow(self: *const GridWindow) void {
        _ = win32.ShowWindow(self.window, win32.SW_SHOW);
    }

    pub fn setForeground(self: *const GridWindow) bool {
        return win32.SetForegroundWindow(self.window) != win32.FALSE;
    }

    fn isBlockedWindow(self: *const GridWindow, hwnd: ?win32.HWND) bool {
        // Dont resize null windows
        if (hwnd == null) {
            return true;
        }
        // Dont resize ourselves
        if (hwnd == self.window or hwnd == self.preview_window.window) {
            return true;
        }
        // Dont resize windows with no title
        if (win32.GetWindowTextLengthW(hwnd) == 0) {
            return true;
        }
        // Dont resize windows with blocked titles
        const blocked_titles = [_][:0]const u16{
            win32.L("Search"),
            win32.L("Start"),
        };
        var current_title: [256:0]u16 = undefined;
        const realLen = win32.GetWindowTextW(hwnd, &current_title, @intCast(current_title.len));
        const current_title_slice = current_title[0..@intCast(realLen)];
        for (blocked_titles) |title| {
            // I KNOWWW that comparing u16 slices is not the best way to compare unicode strings, but it works for now
            if (std.mem.eql(u16, title, current_title_slice)) {
                return true;
            }
        }
        return false;
    }

    pub fn onForegroundChange(self: *GridWindow, previous: ?win32.HWND, current: ?win32.HWND) void {
        // Always update the active window text when the foreground window changes
        // This ensures that the active window is always up to date (especially after the grid window is closed)
        defer if (true) {
            const active_window_text = common.getWindowsText(self.active_window);
            _ = win32.SetWindowTextW(self.window, &active_window_text);
        };

        // Go through the current and previous windows to find the most recent window that is not blocked from being
        // resized
        const found_candidate: win32.HWND = for ([_]?win32.HWND{current, previous}) |candidate| {
            // Skip if the window is the grid or preview window, or if it's not allowed
            if (self.isBlockedWindow(candidate)) {
                continue;
            }
            break candidate.?;
        } else return;

        // Set the active window to the found candidate
        self.active_window = found_candidate;
    }

    fn applyActiveWindowResize(self: *GridWindow) void {
        if (self.active_window) |active_window| {
            // Restore the window to fix resizing with maximized windows
            _ = win32.ShowWindow(active_window, win32.SW_RESTORE);
            // Get the active window area
            const active_window_area = self.grid.calculateActiveWindowArea(active_window);
            // Set the active window position without activating it (no loss of focus)
            common.setWindowPos(active_window, active_window_area, null);
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

    fn closeWindow(self: *GridWindow) void {
        common.closeWindow(self.window);
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
                const color = if (grid.isSelected(row, col)) SELECTED_COLOR else UNSELECTED_COLOR;
                const brush = win32.CreateSolidBrush(color);
                defer _ = win32.DeleteObject(brush);

                const tile_rect = self.grid.tileArea(row, col).toRECT();
                _ = win32.FillRect(hdc, &tile_rect, brush);
            }
        }
    }
};
