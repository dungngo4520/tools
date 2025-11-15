# zig-arg

A lightweight command-line argument parser library for Zig. Supports flags, short options, long options, and positional arguments.

## Usage

```zig
const std = @import("std");
const arg = @import("zig-arg");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = arg.ArgParser.init(allocator);
    defer parser.deinit();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    try parser.parse(argv);

    if (parser.hasFlag("help")) {
        std.debug.print("Usage: program [options]\n", .{});
    }

    if (parser.getFlag("name")) |name| {
        std.debug.print("Name: {s}\n", .{name});
    }
}
```

## Features

- Long options: `--name`, `--name=value`
- Short options: `-n`, `-n value`
- Grouped short flags: `-abc`
- Positional arguments
- Simple and easy-to-use API
