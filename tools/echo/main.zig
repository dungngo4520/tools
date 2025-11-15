const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Skip the program name
    var i: usize = 1;
    var first = true;

    while (i < args.len) : (i += 1) {
        if (!first) {
            std.debug.print(" ", .{});
        }
        std.debug.print("{s}", .{args[i]});
        first = false;
    }

    // Print newline if there were any arguments
    if (!first) {
        std.debug.print("\n", .{});
    }
}
