const win32 = struct {
    usingnamespace @import("win32").foundation;
};

pub const Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    const Self = @This();

    pub fn zero() Rect {
        return Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    }

    pub fn fromRECT(rect: win32.RECT) Rect {
        return Rect{
            .x = rect.left,
            .y = rect.top,
            .width = rect.right - rect.left,
            .height = rect.bottom - rect.top
        };
    }

    pub fn toRECT(self: *const Self) win32.RECT {
        return win32.RECT{
            .left = self.x,
            .top = self.y,
            .right = self.x + self.width,
            .bottom = self.y + self.height
        };
    }
};