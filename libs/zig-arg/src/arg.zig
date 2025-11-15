const std = @import("std");

pub const ArgParser = struct {
    allocator: std.mem.Allocator,
    flags: std.StringHashMap(?[]const u8),
    positionals: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator) ArgParser {
        return ArgParser{
            .allocator = allocator,
            .flags = std.StringHashMap(?[]const u8).init(allocator),
            .positionals = std.ArrayListUnmanaged([]const u8){},
        };
    }

    pub fn deinit(self: *ArgParser) void {
        self.flags.deinit();
        self.positionals.deinit(self.allocator);
    }

    pub fn parse(self: *ArgParser, argv: []const []const u8) !void {
        var i: usize = 1;
        while (i < argv.len) : (i += 1) {
            const a = argv[i];
            if (a.len >= 2 and a[0] == '-') {
                if (a.len >= 3 and a[1] == '-') {
                    if (std.mem.indexOf(u8, a, "=")) |eq_idx| {
                        const name = a[2..eq_idx];
                        const value = a[eq_idx + 1 ..];
                        try self.flags.put(name, value);
                    } else {
                        const name = a[2..];
                        if (i + 1 < argv.len and argv[i + 1].len > 0 and argv[i + 1][0] != '-') {
                            try self.flags.put(name, argv[i + 1]);
                            i += 1;
                        } else {
                            try self.flags.put(name, null);
                        }
                    }
                } else {
                    if (a.len == 2) {
                        const name = a[1..2];
                        if (i + 1 < argv.len and argv[i + 1].len > 0 and argv[i + 1][0] != '-') {
                            try self.flags.put(name, argv[i + 1]);
                            i += 1;
                        } else {
                            try self.flags.put(name, null);
                        }
                    } else {
                        var j: usize = 1;
                        while (j < a.len) : (j += 1) {
                            const name = a[j .. j + 1];
                            try self.flags.put(name, null);
                        }
                    }
                }
            } else {
                try self.positionals.append(self.allocator, a);
            }
        }
    }

    pub fn hasFlag(self: *ArgParser, name: []const u8) bool {
        return self.flags.get(name) != null;
    }

    pub fn getFlag(self: *ArgParser, name: []const u8) ?[]const u8 {
        if (self.flags.get(name)) |v| return v;
        return null;
    }
};
