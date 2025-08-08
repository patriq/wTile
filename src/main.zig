const std = @import("std");
const win32 = @import("win32").everything;

const common = @import("common.zig");
const Rect = @import("rect.zig").Rect;
const Grid = @import("grid.zig").Grid;
const PreviewWindow = @import("preview_window.zig").PreviewWindow;
const GridWindow = @import("grid_window.zig").GridWindow;
const Tray = @import("tray.zig").Tray;
const foreground_hook = @import("foreground_hook.zig");

// Set win32.unicode_mode to true to use Unicode functions
pub const UNICODE = true;

fn handle_hotkey(hInstance: win32.HINSTANCE, grid_window: *GridWindow, preview_window: *PreviewWindow) void {
    // If the grid window is already visible, repostion it
    if (grid_window.window != null) {
        grid_window.reposition();
        return;
    }

    // Set the preview window and grid window
    preview_window.createWindow(hInstance);
    grid_window.createWindow(hInstance);

    // Show the window and set foreground
    grid_window.showWindow();
    if (!grid_window.setForeground()) {
        std.debug.print("Couldnt set foreground window\n", .{});
    }
}

pub export fn main(hInstance: win32.HINSTANCE, hPrevInstance: ?win32.HINSTANCE, pCmdLine: [*:0]u16, nCmdShow: u32) callconv(.winapi) c_int {
    // Unused parameters
    _ = hPrevInstance;
    _ = pCmdLine;
    _ = nCmdShow;

    // Register hotkey
    if (win32.RegisterHotKey(null, 1, win32.HOT_KEY_MODIFIERS{ .ALT = 1, .CONTROL = 1 }, @intFromEnum(win32.VK_RETURN)) == win32.FALSE) {
        std.debug.print("Couldnt register hotkey\n", .{});
        unreachable;
    }
    defer _ = win32.UnregisterHotKey(null, 1);

    // Spawn tray icon
    var tray = Tray{};
    tray.create(hInstance);
    defer tray.cleanup();

    // Create the grid
    var grid = Grid{};

    // Allocate the preview window in the stack and defer its cleanup on program exit
    var preview_window = PreviewWindow{};
    defer preview_window.cleanup();

    // Allocate the grid window in the stack and defer its cleanup on program exit
    var grid_window = GridWindow{.grid = &grid, .preview_window = &preview_window};
    defer grid_window.cleanup();

    // Register a hook to keep track of the foreground window
    const ForegroundGridWindowHook = foreground_hook.ForegroundHook(*GridWindow);
    var foreground_grid_window_hook = ForegroundGridWindowHook.hook(&grid_window, GridWindow.onForegroundChange);
    defer foreground_grid_window_hook.unhook();

    // Standard message loop for all messages in this process
    var message: win32.MSG = undefined;
    while (win32.GetMessageW(&message, null, 0, 0) != win32.FALSE) {
        // Handle hotkey
        if (message.message == win32.WM_HOTKEY) {
            handle_hotkey(hInstance, &grid_window, &preview_window);
            continue;
        }

        // Translate and dispatch the message
        _ = win32.TranslateMessage(&message);
        _ = win32.DispatchMessageW(&message);
    }
    return 0;
}
