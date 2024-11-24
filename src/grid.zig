const win32 = struct {
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
};

const common = @import("common.zig");
const Rect = @import("rect.zig").Rect;

// Grid
pub const Grid = struct {
    // Configuration (make these configurable later)
    rows: u16 = 4,
    cols: u16 = 4,

    // State
    selected_start_row: i32 = 0,
    selected_start_col: i32 = 0,
    selected_col_count: i32 = 0,
    selected_row_count: i32 = 0,

    // Make these configurable later
    const TILE_WIDTH: i32 = 50;
    const TILE_HEIGHT: i32 = 50;
    const MARGIN_PIXELS: i32 = 4;

    pub fn dimensions(self: *const Grid) struct { i32, i32 } {
        const width = Grid.TILE_WIDTH * self.cols + Grid.MARGIN_PIXELS * (self.cols + 1);
        const height = Grid.TILE_HEIGHT * self.rows + Grid.MARGIN_PIXELS * (self.rows + 1);
        return .{ @intCast(width), @intCast(height) };
    }

    pub fn tileArea(_: *const Grid, row: i32, column: i32) Rect {
        const x = column * Grid.TILE_WIDTH + Grid.MARGIN_PIXELS * (column + 1);
        const y = row * Grid.TILE_HEIGHT + Grid.MARGIN_PIXELS * (row + 1);
        return Rect{ .x = x, .y = y, .width = Grid.TILE_WIDTH, .height = Grid.TILE_HEIGHT };
    }

    pub fn isSelected(self: *const Grid, row: i32, col: i32) bool {
        return row >= self.selected_start_row and row < self.selected_start_row + self.selected_row_count and
            col >= self.selected_start_col and col < self.selected_start_col + self.selected_col_count;
    }

    pub fn isAnySelected(self: *const Grid) bool {
        return self.selected_col_count > 0 and self.selected_row_count > 0;
    }

    pub fn isAllSelected(self: *const Grid) bool {
        return self.selected_col_count == self.cols and self.selected_row_count == self.rows
            and self.selected_start_row == 0 and self.selected_start_col == 0;
    }

    pub fn setSelectedUsingActiveWindow(self: *Grid, active_window: win32.HWND) void {
        const active_window_rect = common.getWindowsPos(active_window);
        const work_area = common.getWorkArea();
        const preview_tile_width = @divTrunc(work_area.width, self.cols);
        const preview_tile_height = @divTrunc(work_area.height, self.rows);

        // Find the first tile and the last tile that the active window overlaps with
        var start_col: i32 = -1;
        var start_row: i32 = -1;
        var end_col: i32 = -1;
        var end_row: i32 = -1;

        // Go through each tile and check if the active window is in it
        var row: i32 = 0;
        while (row < self.rows) : (row += 1) {
            var col: i32 = 0;
            while (col < self.cols) : (col += 1) {
                const x = col * preview_tile_width + work_area.x;
                const y = row * preview_tile_height + work_area.y;
                const preview_tile_area = Rect{ .x = x, .y = y, .width = preview_tile_width, .height = preview_tile_height };
                if (active_window_rect.overlaps(preview_tile_area)) {
                    if (start_col == -1) {
                        start_col = col;
                        start_row = row;
                    }
                    end_col = col;
                    end_row = row;
                }
            }
        }

        // Set the found tiles as the selected area
        if (start_col != -1) {
            self.selected_start_col = start_col;
            self.selected_start_row = start_row;
            self.selected_col_count = end_col - start_col + 1;
            self.selected_row_count = end_row - start_row + 1;
        }
    }

    pub fn setSelected(self: *Grid, row: i32, col: i32) void {
        self.selected_start_row = row;
        self.selected_start_col = col;
        self.selected_col_count = 1;
        self.selected_row_count = 1;
    }

    pub fn resetSelection(self: *Grid) void {
        self.selected_start_row = 0;
        self.selected_start_col = 0;
        self.selected_col_count = 0;
        self.selected_row_count = 0;
    }

    pub fn currentPreviewArea(self: *const Grid) Rect {
        const work_area = common.getWorkArea();
        const preview_tile_width = @divTrunc(work_area.width, self.cols);
        const preview_tile_height = @divTrunc(work_area.height, self.rows);
        const x = self.selected_start_col * preview_tile_width + work_area.x;
        const y = self.selected_start_row * preview_tile_height + work_area.y;
        return Rect{ .x = x, .y = y, .width = preview_tile_width * self.selected_col_count, .height = preview_tile_height * self.selected_row_count };
    }

    pub fn calculateActiveWindowArea(self: *const Grid, active_window: win32.HWND) Rect {
        // Get the preview window position for use to set the active window position to
        var preview_area = self.currentPreviewArea();
        // Windows has some weird borders that need to be accounted for
        const borders = common.getTransparentBorders(active_window);
        preview_area.x -= borders[0];
        preview_area.width += borders[0] * 2;
        preview_area.height += borders[1];
        return preview_area;
    }

    pub fn handleKeys(self: *Grid, key: win32.VIRTUAL_KEY, shift: bool) void {
        if (!self.isAnySelected()) {
            self.setSelected(0, 0);
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
