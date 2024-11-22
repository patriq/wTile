const std = @import("std");
const win32 = struct {
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.windows_and_messaging;
};

pub fn ForegroundHook(comptime T: type) type {
    return struct {
        const win = std.os.windows;
        const DWORD = win.DWORD;
        const LONG = win.LONG;
        const HWINEVENTHOOK = win.HANDLE;
        const WINEVENTPROC = *const fn (HWINEVENTHOOK, DWORD, ?win32.HWND, LONG, LONG, DWORD, DWORD) callconv(win.WINAPI) void;
        extern "user32" fn SetWinEventHook(eventMin: DWORD, eventMax: DWORD, hmodWinEventProc: ?win.HMODULE, pfnWinEventProc: WINEVENTPROC, idProcess: DWORD, idThread: DWORD, dwFlags: DWORD) callconv(win.WINAPI) ?HWINEVENTHOOK;
        extern "user32" fn UnhookWinEvent(hWinEventHook: ?HWINEVENTHOOK) callconv(win.WINAPI) win.BOOL;

        // Static variables to store the value and function for the hook to call
        var any_value: ?T = null;
        var any_function: ?*const fn (T, ?win32.HWND, ?win32.HWND) void = null;
        var previous_hwnd: ?win32.HWND = null;

        fn hookFn(h: HWINEVENTHOOK, event: DWORD, hwnd: ?win32.HWND, idObject: LONG, idChild: LONG, idEventThread: DWORD, dwmsEventTime: DWORD) callconv(win.WINAPI) void {
            _ = h;
            _ = event;
            _ = idObject;
            _ = idChild;
            _ = idEventThread;
            _ = dwmsEventTime;

            const current_hwnd = hwnd;
            if (current_hwnd == previous_hwnd) {
                return;
            }
            // Call the function with the value as the first argument and the new window as the second
            if (any_function) |func| {
                if (any_value) |value| {
                    func(value, previous_hwnd, current_hwnd);
                }
            }
            previous_hwnd = current_hwnd;
        }

        foreground_hook: ?win.HANDLE = null,

        pub fn hook(val: ?T, func: *const fn (T, ?win32.HWND, ?win32.HWND) void) @This() {
            // Set the value and function to call
            any_value = val;
            any_function = func;
            // Manually get the previous foreground window
            previous_hwnd = win32.GetForegroundWindow();

            // Register the hook
            const foreground_hook = SetWinEventHook(
                win32.EVENT_SYSTEM_FOREGROUND,
                win32.EVENT_SYSTEM_FOREGROUND,
                null,
                hookFn,
                0,
                0,
                win32.WINEVENT_OUTOFCONTEXT,
            );
            if (foreground_hook == null) {
                std.debug.print("Couldnt register hook\n", .{});
                unreachable;
            }
            // Save the hook for later unhooking
            return @This(){ .foreground_hook = foreground_hook };
        }

        pub fn unhook(self: *@This()) void {
            // Unhook the event
            if (self.foreground_hook != null) {
                _ = UnhookWinEvent(self.foreground_hook);
                self.foreground_hook = null;
            }

            // Clear the value and function
            any_value = null;
            any_function = null;
        }
    };
}
