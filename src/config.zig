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
const known_folders = @import("known-folders");

pub const PackageDecl = struct {
    /// URL to get the binary from
    url: []const u8,
    /// Binary name to be looked for in the tarball
    name: []const u8,
    /// Get a specific version of the software, defaults to latest release
    tag: []const u8 = "latest",

    pub fn deinit(self: *const PackageDecl, allocator: std.mem.Allocator) void {
        defer allocator.free(self.url);
        defer allocator.free(self.tag);
        defer allocator.free(self.name);
    }
};

pub const Config = struct {
    install_path: []const u8,
    packages: []const PackageDecl,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        defer allocator.free(self.install_path);
        for (self.packages) |pkg| {
            defer pkg.deinit(allocator);
        }
    }
};

fn getConfigDirPath(allocator: std.mem.Allocator) ![]const u8 {
    const config_dir_path = try known_folders.getPath(allocator, known_folders.KnownFolder.local_configuration);
    const dpg_config_path = try allocator.alloc(u8, config_dir_path.?.len + "/dpg".len);
    std.mem.copy(u8, dpg_config_path, config_dir_path.?);
    std.mem.copy(u8, dpg_config_path[config_dir_path.?.len..], "/dpg");
    return dpg_config_path;
}

fn getConfigFilePath(allocator: std.mem.Allocator) ![]const u8 {
    const dpg_config_path = try getConfigDirPath(allocator);
    const dpg_recipe_path = try allocator.alloc(u8, dpg_config_path.len + "/recipe.json".len);
    std.mem.copy(u8, dpg_recipe_path, dpg_config_path);
    std.mem.copy(u8, dpg_recipe_path[dpg_config_path.len..], "/recipe.json");
    return dpg_recipe_path;
}

pub fn createConfig(allocator: std.mem.Allocator) !void {
    const dpg_config_path = try getConfigDirPath(allocator);
    defer allocator.free(dpg_config_path);

    // We want to create the directory if it does not exists and silently fail (aka do nothing) if exists
    if (std.fs.openDirAbsolute(dpg_config_path, .{})) |dir| {
        var dir_path = dir;
        dir_path.close();
    } else |err| switch (err) {
        error.FileNotFound => {
            try std.fs.makeDirAbsolute(dpg_config_path);
        },
        error.PathAlreadyExists => {},
        else => return err,
    }

    const dpg_recipe_path = try getConfigFilePath(allocator);
    defer allocator.free(dpg_recipe_path);

    if (std.fs.openFileAbsolute(dpg_recipe_path, .{})) |file| {
        file.close();
    } else |err| switch (err) {
        error.FileNotFound => {
            var config_file = try std.fs.createFileAbsolute(dpg_recipe_path, .{});
            const home_dir = try known_folders.getPath(allocator, known_folders.KnownFolder.home);

            // Default file contents
            //   {
            //      "install_path": "/home/JohnDoe/.local/bin",
            //      "packages": [
            //         {
            //            "url": "https://github.com/sharkdp/bat",
            //            "name": "bat",
            //            "tag": "latest"
            //         }
            //      ]
            //   }
            //
            // NOTE: perhaps there is a more efficient way to achieve this?
            try config_file.writeAll("{\n");
            try config_file.writeAll("  \"install_path\": \"");
            try config_file.writeAll(home_dir.?);
            try config_file.writeAll("/.local/bin");
            try config_file.writeAll("\",\n");
            try config_file.writeAll("  \"packages\": [\n");
            try config_file.writeAll("    {\n");
            try config_file.writeAll("      \"url\": \"https://github.com/sharkdp/bat\",\n");
            try config_file.writeAll("      \"tag\": \"latest\",\n");
            try config_file.writeAll("      \"name\": \"bat\"\n");
            try config_file.writeAll("    }\n");
            try config_file.writeAll("  ]\n");
            try config_file.writeAll("}\n");

            config_file.close();
        },
        else => return err,
    }
}

pub fn readConfig(allocator: std.mem.Allocator, path: ?[]const u8) !Config {
    var config: []const u8 = "";

    if (path != null) {
        config = try std.fs.cwd().readFileAlloc(allocator, path.?, 512);
    } else {
        const dpg_config_path = try getConfigDirPath(allocator);
        defer allocator.free(dpg_config_path);

        const config_dir = try std.fs.openDirAbsolute(dpg_config_path, .{});

        config = try config_dir.readFileAlloc(allocator, "recipe.json", 512);
    }

    var stream = std.json.TokenStream.init(config);
    return try std.json.parse(Config, &stream, .{
        .allocator = allocator,
    });
}
