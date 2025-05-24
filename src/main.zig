pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true, .vsync_hint = true });
    rl.initWindow(1280, 720, "sparrow-packer");

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);
    }

    defer rl.closeWindow();
}

const std = @import("std");
const rl = @import("raylib");
