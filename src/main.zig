const std = @import("std");
const WINAPI = @import("std").os.windows.WINAPI;
const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").system.system_services;
    usingnamespace @import("win32").system.threading;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").graphics.gdi;
};

const common = @import("common.zig");
const Rect = @import("rect.zig").Rect;

// Set win32.unicode_mode to true to use Unicode functions
pub const UNICODE = true;

// Grid
const Grid = struct {
    // Configuration
    rows: u16 = 5,
    cols: u16 = 5,
    margins: u16 = 3,

    // State
    selected_start_row: i32 = 0,
    selected_start_col: i32 = 0,
    selected_col_count: i32 = 0,
    selected_row_count: i32 = 0,

    const Self = @This();
    const TILE_WIDTH = 40;
    const TILE_HEIGHT = 34;

    fn dimensions(self: *const Self) struct { i32, i32 } {
        const width = TILE_WIDTH * self.cols + self.margins * (self.cols + 1);
        const height = TILE_HEIGHT * self.rows + self.margins * (self.rows + 1);
        return .{ @intCast(width), @intCast(height) };
    }

    fn tileArea(self: *const Self, row: i32, column: i32) Rect {
        const x = column * Grid.TILE_WIDTH + self.margins * (column + 1);
        const y = row * Grid.TILE_HEIGHT + self.margins * (row + 1);
        return Rect{ .x = x, .y = y, .width = Grid.TILE_WIDTH, .height = Grid.TILE_HEIGHT };
    }

    fn isSelected(self: *const Self, row: i32, col: i32) bool {
        return row >= self.selected_start_row and row < self.selected_start_row + self.selected_row_count and
            col >= self.selected_start_col and col < self.selected_start_col + self.selected_col_count;
    }

    fn isAnySelected(self: *const Self) bool {
        return self.selected_col_count > 0 and self.selected_row_count > 0;
    }

    fn currentPreviewArea(self: *const Self) Rect {
        const work_area = common.getWorkArea();
        const tile_width = @divTrunc(work_area.width, self.cols);
        const tile_height = @divTrunc(work_area.height, self.rows);
        const x = self.selected_start_col * tile_width + work_area.x;
        const y = self.selected_start_row * tile_height + work_area.y;
        return Rect{ .x = x, .y = y, .width = tile_width * self.selected_col_count, .height = tile_height * self.selected_row_count };
    }

    fn handleKeys(self: *Self, key: win32.VIRTUAL_KEY, shift: bool) void {
        if (!self.isAnySelected()) {
            self.selected_start_row = 0;
            self.selected_start_col = 0;
            self.selected_col_count = 1;
            self.selected_row_count = 1;
            return;
        }

        if (shift) {
            switch (key) {
                win32.VK_LEFT => {
                    if (self.selected_col_count > 1) {
                        self.selected_col_count -= 1;
                    }
                },
                win32.VK_UP => {
                    if (self.selected_row_count > 1) {
                        self.selected_row_count -= 1;
                    }
                },
                win32.VK_RIGHT => {
                    if (self.selected_start_col + self.selected_col_count < self.cols) {
                        self.selected_col_count += 1;
                    }
                },
                win32.VK_DOWN => {
                    if (self.selected_start_row + self.selected_row_count < self.rows) {
                        self.selected_row_count += 1;
                    }
                },
                else => {},
            }
            return;
        }

        switch (key) {
            win32.VK_LEFT => {
                if (self.selected_start_col > 0) {
                    self.selected_start_col -= 1;
                } else if (self.selected_col_count > 1) {
                    self.selected_col_count -= 1;
                }
            },
            win32.VK_UP => {
                if (self.selected_start_row > 0) {
                    self.selected_start_row -= 1;
                } else if (self.selected_row_count > 1) {
                    self.selected_row_count -= 1;
                }
            },
            win32.VK_RIGHT => {
                if (self.selected_start_col + self.selected_col_count < self.cols) {
                    self.selected_start_col += 1;
                } else if (self.selected_col_count > 1) {
                    self.selected_col_count -= 1;
                    self.selected_start_col += 1;
                }
            },
            win32.VK_DOWN => {
                if (self.selected_start_row + self.selected_row_count < self.rows) {
                    self.selected_start_row += 1;
                } else if (self.selected_row_count > 1) {
                    self.selected_row_count -= 1;
                    self.selected_start_row += 1;
                }
            },
            else => {},
        }
    }
};

const GridWindow = struct {
    window: win32.HWND,
    hInstance: win32.HINSTANCE,
    grid: *Grid,
    preview_window: *const PreviewWindow,

    // State
    running: bool = true,
    shift_pressed: bool = false,

    const Self = @This();
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
                        // Send destroy
                        self.destroyWindow();
                        self.preview_window.destroyWindow();
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
                        self.preview_window.setPos(preview_area, self);
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
            win32.WM_DESTROY => {
                // Destroy the window
                // const self: *GridWindow = @ptrFromInt(win32.getWindowLongPtrW(window, 0));
                std.debug.print("Destroying all window\n", .{});
                return win32.FALSE;
            },
            else => {},
        }
        return win32.DefWindowProcW(window, message, wParam, lParam);
    }

    fn createWindow(hInstance: win32.HINSTANCE, grid: *Grid, preview_window: *const PreviewWindow) GridWindow {
        // Create the window class and register it
        const wc = win32.WNDCLASSW{
            .style = win32.WNDCLASS_STYLES{},
            .lpfnWndProc = wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = @sizeOf(*Self), // Reserve the size to store a Self pointer in the window
            .hInstance = hInstance,
            .hIcon = null,
            .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
            .hbrBackground = win32.CreateSolidBrush(BACKGROUND_COLOR),
            .lpszMenuName = null,
            .lpszClassName = CLASS_NAME,
        };
        if (win32.RegisterClassW(&wc) == win32.FALSE) {
            unreachable;
        }

        // Find the client dimensions
        const client_dimensions = grid.dimensions();

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
        return GridWindow{ .window = window, .hInstance = hInstance, .grid = grid, .preview_window = preview_window };
    }

    fn showWindow(self: *const Self) void {
        _ = win32.ShowWindow(self.window, win32.SW_SHOW);
    }

    fn forceSetForeground(self: *const Self) bool {
        return common.forceSetForeground(self.window);
    }

    fn setForeground(self: *const Self) bool {
        return win32.SetForegroundWindow(self.window) != win32.FALSE;
    }

    fn destroyWindow(self: *const Self) void {
        if (win32.IsWindow(self.window) != win32.FALSE) {
            _ = win32.DestroyWindow(self.window);
        }
        _ = win32.UnregisterClassW(CLASS_NAME, self.hInstance);
    }

    fn render(self: *const Self, window: win32.HWND) void {
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

const PreviewWindow = struct {
    window: win32.HWND,
    hInstance: win32.HINSTANCE,

    const Self = @This();
    const CLASS_NAME = win32.L("Grid Preview");
    const BACKGROUND_COLOR = common.RGB(0, 77, 128);

    fn wndProc(window: win32.HWND, message: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(WINAPI) win32.LRESULT {
        return win32.DefWindowProcW(window, message, wParam, lParam);
    }

    fn createWindow(hInstance: win32.HINSTANCE) Self {
        // Create the window class and register it
        const wc = win32.WNDCLASSW{
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
        if (win32.RegisterClassW(&wc) == win32.FALSE) {
            unreachable;
        }

        // Create the window
        const window = win32.CreateWindowExW(
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
        if (win32.SetLayeredWindowAttributes(window, 0, 107, win32.LWA_ALPHA) == win32.FALSE) {
            unreachable;
        }
        return PreviewWindow{ .window = window, .hInstance = hInstance };
    }

    fn setPos(self: *const Self, rect: Rect, grid_window: *const GridWindow) void {
        _ = win32.SetWindowPos(self.window, grid_window.window, rect.x, rect.y, rect.width, rect.height, win32.SWP_NOACTIVATE);
    }

    fn destroyWindow(self: *const Self) void {
        if (win32.IsWindow(self.window) != win32.FALSE) {
            _ = win32.DestroyWindow(self.window);
        }
        _ = win32.UnregisterClassW(CLASS_NAME, self.hInstance);
    }
};

pub export fn main(hInstance: win32.HINSTANCE, hPrevInstance: ?win32.HINSTANCE, pCmdLine: [*:0]u16, nCmdShow: u32) callconv(WINAPI) c_int {
    // Unused parameters
    _ = hPrevInstance;
    _ = pCmdLine;
    _ = nCmdShow;

    // Create the grid
    var grid = Grid{};

    // Register hotkey
    if (win32.RegisterHotKey(null, 1, win32.HOT_KEY_MODIFIERS{ .ALT = 1, .CONTROL = 1 }, @intFromEnum(win32.VK_RETURN)) == win32.FALSE) {
        std.debug.print("Couldnt register hotkey\n", .{});
        unreachable;
    }
    defer _ = win32.UnregisterHotKey(null, 1);

    // Allocate the preview window in the stack and defer its destruction on program exit
    var preview_window: PreviewWindow = undefined;
    defer preview_window.destroyWindow();

    // Allocate the grid window in the stack and defer its destruction on program exit
    var grid_window: GridWindow = undefined;
    defer grid_window.destroyWindow();

    // Standard message loop for all messages in this process
    var message: win32.MSG = undefined;
    while (win32.GetMessageW(&message, null, 0, 0) != win32.FALSE) {
        // Handle hotkey
        if (message.message == win32.WM_HOTKEY) {
            std.debug.print("Hotkey pressed\n", .{});

            // Create the preview window
            preview_window = PreviewWindow.createWindow(hInstance);

            // Create the window grid
            grid_window = GridWindow.createWindow(hInstance, &grid, &preview_window);
            // Store the Self pointer in the window at offset 0
            _ = win32.setWindowLongPtrW(grid_window.window, 0, @intFromPtr(&grid_window));

            // Get the current foreground window
            const foreground_window = win32.GetForegroundWindow();
            // Get its title and set it to the grid window
            var title: [256:0]u16 = undefined;
            _ = win32.GetWindowTextW(foreground_window, &title, @intCast(title.len));
            _ = win32.SetWindowTextW(grid_window.window, &title);

            // Show the window and set foreground
            grid_window.showWindow();
            if (!grid_window.setForeground()) {
                std.debug.print("Couldnt set foreground window\n", .{});
            }
            continue;
        }

        // Translate and dispatch the message
        _ = win32.TranslateMessage(&message);
        _ = win32.DispatchMessageW(&message);
    }
    return 0;
}