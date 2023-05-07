// DPG - Get your dotfiles binaries right from your terminal
// Copyright (C) 2023  NTBBloodbath <bloodbathalchemist@protonmail.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

const std = @import("std");
const clap = @import("clap");

const config = @import("config.zig");

/// DPG version
const version = "0.1.0";

// I love XDG standards and so will you, MacOS.
pub const known_folders_config = .{
    .xdg_on_mac = true,
    .xdg_force_default = true,
};

pub fn main() !void {
    // stdout / stderr
    const stdout_file = std.io.getStdOut().writer();
    var bw_out = std.io.bufferedWriter(stdout_file);
    const stdout = bw_out.writer();

    const stderr_file = std.io.getStdErr().writer();
    var bw_err = std.io.bufferedWriter(stderr_file);
    const stderr = bw_err.writer();

    // Create an arena allocator to reduce time spent allocating
    // and freeing memory during runtime
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var allocator = arena.allocator();

    //    CLI logic
    // ---------------
    const params = comptime clap.parseParamsComptime(
        \\-h, --help           Display this help and exit.
        \\-v, --version        Display DPG version and exit.
        \\-r, --recipe <PATH>  Use a recipe from specified path.
        \\
    );

    const parsers = comptime .{
        .PATH = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var cli = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        try bw_err.flush();
        return err;
    };
    defer cli.deinit();

    // Flags
    if (cli.args.help != 0) {
        // I do not personally like clap default help message so I am making my own
        const help_message =
            \\Usage: dpg [flags] [options]
            \\
            \\Flags:
            \\    -h, --help
            \\            Display this help message and exit.
            \\
            \\    -v, --version
            \\            Display DPG version and exit.
            \\
            \\Options:
            \\    -r, --recipe <PATH>
            \\            Use a recipe from a specified path.
            \\            Default: $CONFIG_DIR/dpg/recipe.json
            \\
        ;
        try stdout.print("{s}", .{help_message});
        try bw_out.flush();
        return;
    }
    if (cli.args.version != 0) {
        try stdout.print("DPG v{s} by NTBBloodbath <bloodbathalchemist@protonmail.com>\n", .{version});
        try bw_out.flush();
        return;
    }

    // Options
    var recipe_file: ?[]const u8 = null;
    if (cli.args.recipe) |r|
        recipe_file = r;

    //    Main logic
    // ----------------
    //
    // Make initial configuration if needed (dpg directory and recipe file)
    try config.createConfig(allocator);

    // Load recipe file
    var recipe_data = try config.readConfig(allocator, recipe_file);
    defer recipe_data.deinit(allocator);

    for (recipe_data.packages) |pkg| {
        try stdout.print("Fetching '{s}' from {s} ...\n", .{ pkg.name, pkg.url });
    }

    // Flush stdout/stderr
    try bw_out.flush();
    try bw_err.flush();
}
