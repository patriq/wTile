const win32 = struct {
    usingnamespace @import("win32").foundation;
};

pub const Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    const Self = @This();

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

    pub fn overlaps(rect1: Rect, rect2: Rect) bool {
        return rect1.x < rect2.x + rect2.width and
            rect1.x + rect1.width > rect2.x and
            rect1.y < rect2.y + rect2.height and
            rect1.y + rect1.height > rect2.y;
    }
};