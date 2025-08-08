const win32 = @import("win32").everything;

pub const Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    pub fn fromRECT(rect: win32.RECT) Rect {
        return Rect{
            .x = rect.left,
            .y = rect.top,
            .width = rect.right - rect.left,
            .height = rect.bottom - rect.top
        };
    }

    pub fn toRECT(self: *const Rect) win32.RECT {
        return win32.RECT{
            .left = self.x,
            .top = self.y,
            .right = self.x + self.width,
            .bottom = self.y + self.height
        };
    }

    pub fn overlaps(self: *const Rect, other: Rect) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }
};