const win32 = struct {
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
};

const common = @import("common.zig");
const Rect = @import("rect.zig").Rect;

// Grid
pub const Grid = struct {
    // Configuration
    rows: u16 = 8,
    cols: u16 = 6,
    margins: u16 = 3,

    // State
    selected_start_row: i32 = 0,
    selected_start_col: i32 = 0,
    selected_col_count: i32 = 0,
    selected_row_count: i32 = 0,

    const Self = @This();
    const TILE_WIDTH = 40;
    const TILE_HEIGHT = 34;

    pub fn dimensions(self: *const Self) struct { i32, i32 } {
        const width = TILE_WIDTH * self.cols + self.margins * (self.cols + 1);
        const height = TILE_HEIGHT * self.rows + self.margins * (self.rows + 1);
        return .{ @intCast(width), @intCast(height) };
    }

    pub fn tileArea(self: *const Self, row: i32, column: i32) Rect {
        const x = column * Grid.TILE_WIDTH + self.margins * (column + 1);
        const y = row * Grid.TILE_HEIGHT + self.margins * (row + 1);
        return Rect{ .x = x, .y = y, .width = Grid.TILE_WIDTH, .height = Grid.TILE_HEIGHT };
    }

    pub fn isSelected(self: *const Self, row: i32, col: i32) bool {
        return row >= self.selected_start_row and row < self.selected_start_row + self.selected_row_count and
            col >= self.selected_start_col and col < self.selected_start_col + self.selected_col_count;
    }

    pub fn isAnySelected(self: *const Self) bool {
        return self.selected_col_count > 0 and self.selected_row_count > 0;
    }

    pub fn currentPreviewArea(self: *const Self) Rect {
        const work_area = common.getWorkArea();
        const tile_width = @divTrunc(work_area.width, self.cols);
        const tile_height = @divTrunc(work_area.height, self.rows);
        const x = self.selected_start_col * tile_width + work_area.x;
        const y = self.selected_start_row * tile_height + work_area.y;
        return Rect{ .x = x, .y = y, .width = tile_width * self.selected_col_count, .height = tile_height * self.selected_row_count };
    }

    pub fn calculateActiveWindowArea(self: *const Self, active_window: win32.HWND) Rect {
        // Get the preview window position for use to set the active window position to
        var preview_area = self.currentPreviewArea();
        // Windows has some weird borders that need to be accounted for
        const borders = common.getTransparentBorders(active_window);
        preview_area.x -= borders[0];
        preview_area.width += borders[0] * 2;
        preview_area.height += borders[1];
        return preview_area;
    }

    pub fn resetSelection(self: *Self) void {
        self.selected_start_row = 0;
        self.selected_start_col = 0;
        self.selected_col_count = 0;
        self.selected_row_count = 0;
    }

    pub fn handleKeys(self: *Self, key: win32.VIRTUAL_KEY, shift: bool) void {
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