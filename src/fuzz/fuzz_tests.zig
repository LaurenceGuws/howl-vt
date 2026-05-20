const std = @import("std");
const protocol = @import("protocol.zig");
const scrollback = @import("scrollback.zig");

const Fuzzer = enum {
    smoke,
    protocol,
    scrollback,
};

const CLIArgs = struct {
    fuzzer: Fuzzer,
    seed: ?u64 = null,
    events_max: ?usize = null,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const argv = try init.minimal.args.toSlice(arena);

    const cli_args = try parseArgs(argv);

    switch (cli_args.fuzzer) {
        .smoke => try mainSmoke(gpa),
        .protocol => try mainProtocol(gpa, cli_args),
        .scrollback => try mainScrollback(gpa, cli_args),
    }
}

fn mainSmoke(gpa: std.mem.Allocator) !void {
    const seeds = [_]u64{
        0x1111111111111111,
        0x2222222222222222,
        0x3333333333333333,
    };

    for (seeds) |seed| {
        try scrollback.runCanonicalPreservation(gpa, seed, scrollback.defaultPreservationOptions(64));
    }
    try protocol.runSmoke(gpa);
}

fn mainProtocol(gpa: std.mem.Allocator, cli_args: CLIArgs) !void {
    const seed = cli_args.seed orelse 0x70726f746f636f6c;

    try protocol.runDeterminism(gpa, seed, protocol.defaultOptions(cli_args.events_max));
}

fn mainScrollback(gpa: std.mem.Allocator, cli_args: CLIArgs) !void {
    const seed = cli_args.seed orelse 0x7363726f6c6c6261;

    try scrollback.runCanonicalPreservation(gpa, seed, scrollback.defaultPreservationOptions(cli_args.events_max));
}

fn parseArgs(argv: []const [:0]const u8) !CLIArgs {
    var result = CLIArgs{ .fuzzer = .smoke };
    var positional: [2][]const u8 = undefined;
    var positional_len: usize = 0;

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.startsWith(u8, arg, "--events-max=")) {
            result.events_max = std.fmt.parseUnsigned(usize, arg["--events-max=".len..], 10) catch return error.InvalidEventsMax;
            continue;
        }
        if (std.mem.eql(u8, arg, "--events-max")) {
            i += 1;
            if (i >= argv.len) return error.MissingEventsMax;
            result.events_max = std.fmt.parseUnsigned(usize, argv[i], 10) catch return error.InvalidEventsMax;
            continue;
        }
        if (positional_len >= positional.len) return error.InvalidArguments;
        positional[positional_len] = arg;
        positional_len += 1;
    }

    if (positional_len == 0) return result;

    result.fuzzer = std.meta.stringToEnum(Fuzzer, positional[0]) orelse return error.UnknownFuzzer;
    if (positional_len >= 2) {
        result.seed = try scrollback.parseSeed(positional[1]);
    }
    return result;
}
