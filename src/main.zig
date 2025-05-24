const FileLoadDecision = enum {
    AddFrame,
    AddSparrow,
    LoadDirectory,
    Ignore,
};

const RectangleI = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    pub fn init(x: i32, y: i32, width: i32, height: i32) RectangleI {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn fromRectangle(rect: rl.Rectangle) RectangleI {
        return .{
            .x = @intFromFloat(rect.x),
            .y = @intFromFloat(rect.y),
            .width = @intFromFloat(rect.width),
            .height = @intFromFloat(rect.height),
        };
    }
};

const Frame = struct {
    image: rl.Image,
    name: []const u8,
    rotated: bool,
    offsets: rl.Vector2,
    position: rl.Vector2,
    duplicate: bool,
};

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(1280, 720, "sparrow-packer");
    rl.setTargetFPS(240);

    var frames = std.ArrayList(Frame).init(std.heap.page_allocator);
    defer frames.deinit();

    var camera: rl.Camera2D = .{
        .offset = rl.Vector2.init(0.0, 0.0),
        .target = rl.Vector2.init(0.0, 0.0),
        .rotation = 0.0,
        .zoom = 0.5,
    };

    var spritesheet: ?rl.Texture2D = null;
    while (!rl.windowShouldClose()) {
        if (rl.isFileDropped()) {
            const dropped_files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(dropped_files);
            try loadFiles(dropped_files, &frames, false, std.heap.page_allocator);

            if (spritesheet != null) {
                spritesheet.?.unload();
            }

            const image = try packFrames(&frames, std.heap.page_allocator);
            defer image.unload();
            spritesheet = try image.toTexture();
            rl.setTextureWrap(spritesheet.?, .clamp);
        }

        const wheel = rl.getMouseWheelMove();
        camera.zoom += wheel / 10.0;
        camera.offset = rl.Vector2.init(
            0.5 * (1.0 - camera.zoom) * @as(f32, @floatFromInt(rl.getScreenWidth())),
            0.5 * (1.0 - camera.zoom) * @as(f32, @floatFromInt(rl.getScreenHeight())),
        );

        if (camera.zoom < 0.1) {
            camera.zoom = 0.1;
        }

        if (rl.isMouseButtonDown(.left)) {
            camera.target = camera.target.subtract(rl.getMouseDelta().divide(rl.Vector2.init(camera.zoom, camera.zoom)));
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.gray);

        camera.begin();

        if (spritesheet != null) {
            rl.drawTexture(spritesheet.?, 0, 0, .white);
        }

        camera.end();
    }

    defer rl.closeWindow();
}

fn framesByHeight(value: void, lhs: Frame, rhs: Frame) bool {
    _ = value;
    return lhs.image.height > rhs.image.height;
}

fn packFrames(frames: *std.ArrayList(Frame), allocator: std.mem.Allocator) !rl.Image {
    if (frames.items.len == 0) {
        return rl.Image.genColor(1, 1, .white);
    }

    _ = allocator;

    std.mem.sort(Frame, frames.items, {}, framesByHeight);

    var width: f32 = 0.0;
    var height: f32 = 0.0;
    var x: f32 = 0.0;
    var y: f32 = 0.0;
    var largest_height: f32 = 0.0;

    var index: usize = 0;
    while (index < frames.items.len) {
        var frame = frames.items[index];

        // SKIP DUPLICATES!!!
        if (frame.duplicate) {
            index += 1;
            continue;
        }

        const float_width: f32 = @floatFromInt(frame.image.width);
        const float_height: f32 = @floatFromInt(frame.image.height);

        if (width < float_width) {
            width += float_width;
        }

        if (height < float_height) {
            height += float_height;
        }

        if (x + float_width > width) {
            if (width < height) {
                width += float_width;
                x = 0.0;
                y = 0.0;
                largest_height = 0.0;
                index = 0;
                continue;
            } else {
                y += largest_height;
                x = 0.0;
                largest_height = 0.0;
            }
        }

        if (y + float_height > height) {
            if (height < width) {
                height += float_height;
                x = 0.0;
                y = 0.0;
                largest_height = 0.0;
                index = 0;
                continue;
            } else {
                width += float_width;
                x = 0.0;
                y = 0.0;
                largest_height = 0.0;
                index = 0;
                continue;
            }
        }

        frame.position.x = x;
        frame.position.y = y;

        x += float_width;
        if (float_height > largest_height) {
            largest_height = float_height;
        }

        frames.items[index] = frame;
        index += 1;
    }

    std.debug.print("Generating texture of {d}x{d}\n", .{ width, height });

    var image = rl.Image.genColor(@intFromFloat(width), @intFromFloat(height), .blank);
    for (frames.items) |frame| {
        // SKIP DUPLICATES!!!
        if (frame.duplicate) {
            continue;
        }

        image.drawImage(
            frame.image,
            rl.Rectangle.init(0.0, 0.0, @floatFromInt(frame.image.width), @floatFromInt(frame.image.height)),
            rl.Rectangle.init(frame.position.x, frame.position.y, @floatFromInt(frame.image.width), @floatFromInt(frame.image.height)),
            .white,
        );
    }

    return image;
}

fn loadFiles(list: rl.FilePathList, frames: *std.ArrayList(Frame), is_recursive: bool, allocator: std.mem.Allocator) !void {
    for (0..list.count) |i| {
        const file_path = std.mem.span(list.paths[i]);
        const decision = try loadFile(file_path, is_recursive, allocator);
        std.debug.print("Decision {} from \"{s}\"\n", .{ decision, file_path });
        switch (decision) {
            .AddFrame => {
                const image = rl.Image.init(file_path) catch {
                    std.log.err("File at path \"{s}\" could not be loaded (as an image)!", .{file_path});
                    continue;
                };

                const basename = std.fs.path.basename(file_path);
                try frames.append(.{
                    .image = image,
                    .name = try allocator.dupe(u8, basename),
                    .offsets = .{ .x = 0.0, .y = 0.0 },
                    .rotated = false,
                    .position = rl.Vector2.init(-1.0, -1.0),
                    .duplicate = false,
                });
            },
            .AddSparrow => {
                try parseSparrow(file_path, frames, allocator);
            },
            .LoadDirectory => {
                const directory_list = rl.loadDirectoryFiles(file_path);
                try loadFiles(directory_list, frames, true, allocator);
            },
            else => {},
        }
    }
}

fn loadFile(file_path: [:0]const u8, is_recursive: bool, allocator: std.mem.Allocator) std.mem.Allocator.Error!FileLoadDecision {
    if (!rl.isPathFile(file_path)) {
        return .LoadDirectory;
    }

    const extension = rl.getFileExtension(file_path);
    if (std.mem.eql(u8, extension, ".xml")) {
        return .AddSparrow;
    } else {
        const path = try replacePathExtension(file_path, ".xml", allocator);
        defer allocator.free(path);
        std.fs.accessAbsolute(path, .{}) catch return .AddFrame;
        return if (!is_recursive) .AddSparrow else .Ignore;
    }

    return .AddFrame;
}

fn parseSparrow(file_path: [:0]const u8, frames: *std.ArrayList(Frame), allocator: std.mem.Allocator) !void {
    const sparrow_path = try replacePathExtension(file_path, ".xml", allocator);
    defer allocator.free(sparrow_path);

    const file = try std.fs.openFileAbsolute(sparrow_path, .{});
    defer file.close();

    var document = xml.streamingDocument(allocator, file.reader());
    defer document.deinit();

    var reader = document.reader(allocator, .{});
    defer reader.deinit();

    var source_image: ?rl.Image = null;
    defer if (source_image != null) source_image.?.unload();

    var hash_map = std.AutoHashMap(RectangleI, rl.Image).init(allocator);
    defer hash_map.deinit();

    var node: xml.Reader.Node = .xml_declaration;
    while (node != .eof) {
        node = try reader.read();

        switch (node) {
            .element_start => {
                const element_name = reader.elementName();
                if (std.ascii.eqlIgnoreCase(element_name, "TextureAtlas")) {
                    if (source_image != null) {
                        break;
                    }

                    var free_path: bool = false;
                    var path: []const u8 = undefined;
                    const path_index = reader.attributeIndex("imagePath");
                    if (path_index == null) {
                        std.log.err("Missing imagePath in file! Will try fallback path.", .{});
                        path = try replacePathExtension(file_path, ".png", allocator);
                        free_path = true;
                    } else {
                        path = try reader.attributeValue(path_index.?);

                        const dir = std.fs.path.dirname(file_path);
                        if (dir != null) {
                            path = try std.fs.path.join(allocator, &.{ dir.?, path });
                            free_path = true;
                        }

                        std.fs.accessAbsolute(path, .{}) catch {
                            std.log.err("imagePath \"{s}\" cannot be found! Will try fallback path.", .{path});
                            allocator.free(path);
                            path = try replacePathExtension(file_path, ".png", allocator);
                            free_path = true;
                        };
                    }
                    defer if (free_path) allocator.free(path);

                    const sentinel_path = try allocator.dupeZ(u8, path);
                    defer allocator.free(sentinel_path);
                    std.mem.copyForwards(u8, sentinel_path, path);
                    source_image = rl.Image.init(sentinel_path[0.. :0]) catch {
                        std.log.err("Failed to load image at path \"{s}\"!", .{path});
                        break;
                    };
                }

                if (std.ascii.eqlIgnoreCase(element_name, "SubTexture")) {
                    if (source_image == null) {
                        std.log.err("Cannot parse SubTexture when no source spritesheet was found!", .{});
                        continue;
                    }

                    const name_index = reader.attributeIndex("name");
                    if (name_index == null) {
                        std.log.err("SubTexture is not in the correct format. Skipping.", .{});
                        continue;
                    }
                    const name = try reader.attributeValueAlloc(allocator, name_index.?);

                    const x_index = reader.attributeIndex("x").?;
                    const x = parseXMLNumber(try reader.attributeValue(x_index));

                    const y_index = reader.attributeIndex("y").?;
                    const y = parseXMLNumber(try reader.attributeValue(y_index));

                    const width_index = reader.attributeIndex("width").?;
                    const width = parseXMLNumber(try reader.attributeValue(width_index));

                    const height_index = reader.attributeIndex("height").?;
                    const height = parseXMLNumber(try reader.attributeValue(height_index));

                    var offsets: rl.Vector2 = .{ .x = 0.0, .y = 0.0 };
                    const frame_x_index = reader.attributeIndex("frameX");
                    if (frame_x_index != null) {
                        offsets.x = parseXMLNumber(try reader.attributeValue(frame_x_index.?));
                    }

                    const frame_y_index = reader.attributeIndex("frameY");
                    if (frame_y_index != null) {
                        offsets.y = parseXMLNumber(try reader.attributeValue(frame_y_index.?));
                    }

                    var rotated = false;
                    const rotated_index = reader.attributeIndex("rotated");
                    if (rotated_index != null) {
                        rotated = std.ascii.eqlIgnoreCase(try reader.attributeValue(rotated_index.?), "true");
                    }

                    const rect = rl.Rectangle.init(x, y, width, height);
                    const rect_i = RectangleI.fromRectangle(rect);
                    if (hash_map.contains(rect_i)) {
                        try frames.append(.{
                            .image = hash_map.get(rect_i).?,
                            .name = name,
                            .offsets = offsets,
                            .rotated = rotated,
                            .position = rl.Vector2.init(-1.0, -1.0),
                            .duplicate = true,
                        });
                    } else {
                        var frame_image = source_image.?.copyRec(rect);
                        if (rotated) {
                            rotated = false;
                            frame_image.rotateCCW();
                        }

                        try hash_map.put(rect_i, frame_image);
                        try frames.append(.{
                            .image = frame_image,
                            .name = name,
                            .offsets = offsets,
                            .rotated = rotated,
                            .position = rl.Vector2.init(-1.0, -1.0),
                            .duplicate = false,
                        });
                    }

                    std.debug.print("Successfully loaded frame \"{s}\"!\n", .{name});
                }
            },
            .xml_declaration => {
                std.debug.print("Loaded Sparrow with XML Version {s}", .{reader.xmlDeclarationVersion()});
                const encoding = reader.xmlDeclarationEncoding();
                if (encoding != null) {
                    std.debug.print(" and with encoding {s}", .{encoding.?});
                }
                std.debug.print("\n", .{});
            },
            else => {},
        }
    }
}

fn replacePathExtension(file_path: [:0]const u8, new_extension: [:0]const u8, allocator: std.mem.Allocator) ![]const u8 {
    const extension = rl.getFileExtension(file_path);
    if (std.mem.eql(u8, extension, new_extension)) {
        return try allocator.dupe(u8, file_path);
    }

    const dir = std.fs.path.dirname(file_path);
    const base = std.fs.path.stem(file_path);
    var path: []u8 = undefined;
    if (dir != null) {
        path = try std.fs.path.join(allocator, &.{ dir.?, base });
    } else {
        path = try allocator.dupe(u8, base);
    }

    path = try allocator.realloc(path, path.len + new_extension.len);
    @memcpy(path[path.len - new_extension.len .. path.len], new_extension);

    return path;
}

fn parseXMLNumber(input: []const u8) f32 {
    return std.fmt.parseFloat(f32, input) catch std.math.nan(f32);
}

const std = @import("std");
const rl = @import("raylib");
const xml = @import("xml");
