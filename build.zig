const std = @import("std");

const log = std.log.scoped(.zigtoybox);

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .os_tag = .linux,
            .abi = .musl,
        },
    });
    var optimize = b.standardOptimizeOption(.{});
    if (optimize == .Debug or optimize == .ReleaseSafe) {
        log.warn("Toybox does not build in {{.Debug, .ReleaseSafe}}. Defaulting to .ReleaseSmall", .{});
        optimize = .ReleaseSmall;
    }

    const strip = b.option(bool, "strip", "Omit debug information") orelse true;
    const allno = b.option(bool, "allno", "Default all configs to =n") orelse false;
    const allyes = b.option(bool, "allyes", "Default all configs to =y") orelse false;
    if (allno and allyes) @panic("Cannot set both allno and allyes");

    const configs = try readToyboxConfig(b.allocator);
    for (configs.items) |*c| c.makeOption(b, allyes, allno);

    const exe = b.addExecutable(.{
        .name = "toybox",
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(&[_][]const u8{"toybox/main.c"}, &cflags);
    exe.addCSourceFiles(&lib_files, &cflags);
    exe.addCSourceFiles(&toy_files, &cflags);
    exe.addCSourceFiles(&notandroid_files, &cflags);
    exe.addCSourceFiles(&pending_files, &cflags);
    exe.addIncludePath(.{ .path = "toybox" });
    exe.addIncludePath(addGeneratedConfig(b, &configs).getOutput());
    exe.linkLibC();
    exe.strip = strip;

    b.installArtifact(exe);

    const runstep = b.step("run", "Run toybox");
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    runstep.dependOn(b.getInstallStep());
    runstep.dependOn(&run.step);
}

// These are the default cflags from toybox
const cflags = [_][]const u8{
    "-Wall",
    "-Wundef",
    "-Werror=implicit-function-declaration",
    "-Wno-char-subscripts",
    "-Wno-pointer-sign",
    "-funsigned-char",
    "-ffunction-sections",
    "-fdata-sections",
    "-fno-asynchronous-unwind-tables",
    "-fno-strict-aliasing",
};

const GeneratedConfigStep = struct {
    step: std.Build.Step,
    configs: *const ToyboxConfigList,
    output_file: std.Build.GeneratedFile,

    fn create(b: *std.Build, configs: *const ToyboxConfigList) *@This() {
        var self = b.allocator.create(@This()) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "genconfig",
                .owner = b,
                .makeFn = make,
            }),
            .configs = configs,
            .output_file = .{ .step = &self.step },
        };
        return self;
    }

    fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
        const b = step.owner;
        const self = @fieldParentPtr(@This(), "step", step);
        const alloc = b.allocator;

        var man = b.cache.obtain();
        defer man.deinit();

        var output = std.ArrayList(u8).init(alloc);
        defer output.deinit();
        const writer = output.writer();

        try writeConfigHeader(self.configs.items, writer);

        man.hash.addBytes(output.items);

        if (try step.cacheHit(&man)) {
            const digest = man.final();
            self.output_file.path = try b.cache_root.join(alloc, &.{ "o", &digest });
            return;
        }

        const digest = man.final();

        const output_dir = try std.fs.path.join(alloc, &.{ "o", &digest, "generated" });
        const include_dir = std.fs.path.dirname(output_dir).?;
        b.cache_root.handle.makePath(output_dir) catch |err| {
            return step.fail("unable to make path '{}{s}': {s}", .{
                b.cache_root, include_dir, @errorName(err),
            });
        };

        const fpath = try std.fs.path.join(alloc, &.{ output_dir, "config.h" });
        b.cache_root.handle.writeFile(fpath, output.items) catch |err| {
            return step.fail("unable to write file '{}{s}': {s}", .{
                b.cache_root, output_dir, @errorName(err),
            });
        };

        self.output_file.path = try b.cache_root.join(alloc, &.{include_dir});
        try man.writeManifest();
    }

    fn getOutput(self: *@This()) std.Build.LazyPath {
        return .{ .generated = &self.output_file };
    }
};

fn writeConfigHeader(configs: []const ToyboxConfig, writer: anytype) !void {
    try (ToyboxConfig{ .name = "TOYBOX", .value = .{ .yn = true } }).writeHeader(writer);
    for (configs) |c| try c.writeHeader(writer);
}

const ToyboxConfigList = std.ArrayList(ToyboxConfig);

fn addGeneratedConfig(b: *std.Build, configs: *const ToyboxConfigList) *GeneratedConfigStep {
    return GeneratedConfigStep.create(b, configs);
}

const lib_files = [_][]const u8{
    "toybox/lib/args.c",
    "toybox/lib/deflate.c",
    "toybox/lib/env.c",
    "toybox/lib/password.c",
    "toybox/lib/portability.c",
    "toybox/lib/utf8.c",
    "toybox/lib/commas.c",
    "toybox/lib/dirtree.c",
    "toybox/lib/lib.c",
    "toybox/lib/llist.c",
    "toybox/lib/net.c",
    "toybox/lib/tty.c",
    "toybox/lib/xwrap.c",
};

const toy_files = [_][]const u8{
    "toybox/toys/lsb/pidof.c",
    "toybox/toys/lsb/gzip.c",
    "toybox/toys/lsb/md5sum.c",
    "toybox/toys/lsb/seq.c",
    "toybox/toys/lsb/killall.c",
    "toybox/toys/lsb/sync.c",
    "toybox/toys/lsb/passwd.c",
    "toybox/toys/lsb/mknod.c",
    "toybox/toys/lsb/su.c",
    "toybox/toys/lsb/umount.c",
    "toybox/toys/lsb/hostname.c",
    "toybox/toys/lsb/mktemp.c",
    "toybox/toys/lsb/mount.c",
    "toybox/toys/lsb/dmesg.c",
    "toybox/toys/net/rfkill.c",
    "toybox/toys/net/ifconfig.c",
    "toybox/toys/net/ftpget.c",
    "toybox/toys/net/netcat.c",
    "toybox/toys/net/wget.c",
    "toybox/toys/net/netstat.c",
    "toybox/toys/net/httpd.c",
    "toybox/toys/net/host.c",
    "toybox/toys/net/tunctl.c",
    "toybox/toys/net/sntp.c",
    "toybox/toys/net/microcom.c",
    "toybox/toys/net/ping.c",
    "toybox/toys/example/demo_number.c",
    "toybox/toys/example/hello.c",
    "toybox/toys/example/demo_utf8towc.c",
    "toybox/toys/example/logpath.c",
    "toybox/toys/example/skeleton.c",
    "toybox/toys/example/demo_many_options.c",
    "toybox/toys/example/demo_scankey.c",
    "toybox/toys/example/hostid.c",
    "toybox/toys/other/truncate.c",
    "toybox/toys/other/uuidgen.c",
    "toybox/toys/other/openvt.c",
    "toybox/toys/other/shuf.c",
    "toybox/toys/other/readelf.c",
    "toybox/toys/other/rev.c",
    "toybox/toys/other/help.c",
    "toybox/toys/other/eject.c",
    "toybox/toys/other/vmstat.c",
    "toybox/toys/other/mountpoint.c",
    "toybox/toys/other/clear.c",
    "toybox/toys/other/reset.c",
    "toybox/toys/other/rtcwake.c",
    "toybox/toys/other/rmmod.c",
    "toybox/toys/other/count.c",
    "toybox/toys/other/lsattr.c",
    "toybox/toys/other/losetup.c",
    "toybox/toys/other/swapoff.c",
    "toybox/toys/other/stat.c",
    "toybox/toys/other/blockdev.c",
    "toybox/toys/other/pwgen.c",
    "toybox/toys/other/mix.c",
    "toybox/toys/other/pmap.c",
    "toybox/toys/other/sysctl.c",
    "toybox/toys/other/chroot.c",
    "toybox/toys/other/timeout.c",
    "toybox/toys/other/fsfreeze.c",
    "toybox/toys/other/w.c",
    "toybox/toys/other/switch_root.c",
    "toybox/toys/other/devmem.c",
    "toybox/toys/other/sha3sum.c",
    "toybox/toys/other/insmod.c",
    "toybox/toys/other/taskset.c",
    "toybox/toys/other/oneit.c",
    "toybox/toys/other/tac.c",
    "toybox/toys/other/ionice.c",
    "toybox/toys/other/nbd_server.c",
    "toybox/toys/other/printenv.c",
    "toybox/toys/other/fallocate.c",
    "toybox/toys/other/nsenter.c",
    "toybox/toys/other/swapon.c",
    "toybox/toys/other/base64.c",
    "toybox/toys/other/mcookie.c",
    "toybox/toys/other/flock.c",
    "toybox/toys/other/usleep.c",
    "toybox/toys/other/pwdx.c",
    "toybox/toys/other/blkdiscard.c",
    "toybox/toys/other/factor.c",
    "toybox/toys/other/hwclock.c",
    "toybox/toys/other/setfattr.c",
    "toybox/toys/other/fmt.c",
    "toybox/toys/other/ascii.c",
    "toybox/toys/other/yes.c",
    "toybox/toys/other/nbd_client.c",
    "toybox/toys/other/modinfo.c",
    "toybox/toys/other/lsmod.c",
    "toybox/toys/other/blkid.c",
    "toybox/toys/other/makedevs.c",
    "toybox/toys/other/acpi.c",
    "toybox/toys/other/setsid.c",
    "toybox/toys/other/bzcat.c",
    "toybox/toys/other/watch.c",
    "toybox/toys/other/uclampset.c",
    "toybox/toys/other/which.c",
    "toybox/toys/other/i2ctools.c",
    "toybox/toys/other/freeramdisk.c",
    "toybox/toys/other/xxd.c",
    "toybox/toys/other/chrt.c",
    "toybox/toys/other/inotifyd.c",
    "toybox/toys/other/readahead.c",
    "toybox/toys/other/vconfig.c",
    "toybox/toys/other/login.c",
    "toybox/toys/other/readlink.c",
    "toybox/toys/other/partprobe.c",
    "toybox/toys/other/reboot.c",
    "toybox/toys/other/uptime.c",
    "toybox/toys/other/gpiod.c",
    "toybox/toys/other/mkswap.c",
    "toybox/toys/other/pivot_root.c",
    "toybox/toys/other/free.c",
    "toybox/toys/other/lsusb.c",
    "toybox/toys/other/fsync.c",
    "toybox/toys/other/shred.c",
    "toybox/toys/other/dos2unix.c",
    "toybox/toys/other/hexedit.c",
    "toybox/toys/other/watchdog.c",
    "toybox/toys/posix/echo.c",
    "toybox/toys/posix/sed.c",
    "toybox/toys/posix/ulimit.c",
    "toybox/toys/posix/uname.c",
    "toybox/toys/posix/env.c",
    "toybox/toys/posix/who.c",
    "toybox/toys/posix/chgrp.c",
    "toybox/toys/posix/tar.c",
    "toybox/toys/posix/od.c",
    "toybox/toys/posix/logger.c",
    "toybox/toys/posix/link.c",
    "toybox/toys/posix/patch.c",
    "toybox/toys/posix/false.c",
    "toybox/toys/posix/dd.c",
    "toybox/toys/posix/head.c",
    "toybox/toys/posix/nl.c",
    "toybox/toys/posix/paste.c",
    "toybox/toys/posix/ls.c",
    "toybox/toys/posix/touch.c",
    "toybox/toys/posix/mkdir.c",
    "toybox/toys/posix/strings.c",
    "toybox/toys/posix/file.c",
    "toybox/toys/posix/comm.c",
    "toybox/toys/posix/pwd.c",
    "toybox/toys/posix/mkfifo.c",
    "toybox/toys/posix/sort.c",
    "toybox/toys/posix/ps.c",
    "toybox/toys/posix/cut.c",
    "toybox/toys/posix/cksum.c",
    "toybox/toys/posix/tee.c",
    "toybox/toys/posix/cpio.c",
    "toybox/toys/posix/nohup.c",
    "toybox/toys/posix/cp.c",
    "toybox/toys/posix/cat.c",
    "toybox/toys/posix/rm.c",
    "toybox/toys/posix/rmdir.c",
    "toybox/toys/posix/uudecode.c",
    "toybox/toys/posix/uuencode.c",
    "toybox/toys/posix/tty.c",
    "toybox/toys/posix/split.c",
    "toybox/toys/posix/uniq.c",
    "toybox/toys/posix/nice.c",
    "toybox/toys/posix/unlink.c",
    "toybox/toys/posix/basename.c",
    "toybox/toys/posix/dirname.c",
    "toybox/toys/posix/true.c",
    "toybox/toys/posix/grep.c",
    "toybox/toys/posix/du.c",
    "toybox/toys/posix/time.c",
    "toybox/toys/posix/date.c",
    "toybox/toys/posix/ln.c",
    "toybox/toys/posix/sleep.c",
    "toybox/toys/posix/tail.c",
    "toybox/toys/posix/expand.c",
    "toybox/toys/posix/getconf.c",
    "toybox/toys/posix/xargs.c",
    "toybox/toys/posix/iconv.c",
    "toybox/toys/posix/find.c",
    "toybox/toys/posix/kill.c",
    "toybox/toys/posix/wc.c",
    "toybox/toys/posix/cmp.c",
    "toybox/toys/posix/renice.c",
    "toybox/toys/posix/id.c",
    "toybox/toys/posix/printf.c",
    "toybox/toys/posix/cal.c",
    "toybox/toys/posix/chmod.c",
    "toybox/toys/posix/test.c",
    "toybox/toys/posix/df.c",
};

const android_files = [_][]const u8{
    "toybox/toys/android/log.c",
    "toybox/toys/android/sendevent.c",
};

const notandroid_files = [_][]const u8{
    "toybox/toys/other/mkpasswd.c",
};

const selinux_files = [_][]const u8{
    "toybox/toys/other/chcon.c",
    "toybox/toys/android/getenforce.c",
    "toybox/toys/android/load_policy.c",
    "toybox/toys/android/restorecon.c",
    "toybox/toys/android/runcon.c",
    "toybox/toys/android/setenforce.c",
};

const pending_files = [_][]const u8{
    "toybox/toys/pending/brctl.c",
    "toybox/toys/pending/arp.c",
    "toybox/toys/pending/tr.c",
    "toybox/toys/pending/syslogd.c",
    "toybox/toys/pending/xzcat.c",
    "toybox/toys/pending/bc.c",
    "toybox/toys/pending/fsck.c",
    "toybox/toys/pending/init.c",
    "toybox/toys/pending/arping.c",
    "toybox/toys/pending/lsof.c",
    "toybox/toys/pending/mdev.c",
    "toybox/toys/pending/ipcrm.c",
    "toybox/toys/pending/traceroute.c",
    "toybox/toys/pending/dhcp6.c",
    "toybox/toys/pending/diff.c",
    "toybox/toys/pending/more.c",
    "toybox/toys/pending/tftp.c",
    "toybox/toys/pending/getopt.c",
    "toybox/toys/pending/getty.c",
    "toybox/toys/pending/ip.c",
    "toybox/toys/pending/last.c",
    "toybox/toys/pending/dhcpd.c",
    "toybox/toys/pending/bootchartd.c",
    "toybox/toys/pending/ipcs.c",
    "toybox/toys/pending/dhcp.c",
    "toybox/toys/pending/getfattr.c",
    "toybox/toys/pending/vi.c",
    "toybox/toys/pending/mke2fs.c",
    "toybox/toys/pending/tftpd.c",
    "toybox/toys/pending/crontab.c",
    "toybox/toys/pending/fold.c",
    "toybox/toys/pending/man.c",
    "toybox/toys/pending/dumpleases.c",
    "toybox/toys/pending/tcpsvd.c",
    "toybox/toys/pending/hexdump.c",
    "toybox/toys/pending/telnetd.c",
    "toybox/toys/pending/modprobe.c",
    "toybox/toys/pending/crond.c",
    "toybox/toys/pending/fdisk.c",
    "toybox/toys/pending/strace.c",
    "toybox/toys/pending/stty.c",
    "toybox/toys/pending/expr.c",
    "toybox/toys/pending/route.c",
    "toybox/toys/pending/sulogin.c",
    "toybox/toys/pending/klogd.c",
    "toybox/toys/pending/sh.c",
    "toybox/toys/pending/telnet.c",
    // Note: These don't currently build
    //
    // error: too few arguments to function call, expected 4, have 3
    // toybox/lib/pending.h:6:5: note: 'update_password' declared here
    //"toybox/toys/pending/groupadd.c",
    //"toybox/toys/pending/groupdel.c",
    //"toybox/toys/pending/useradd.c",
    //"toybox/toys/pending/userdel.c",
    //"toybox/toys/pending/chsh.c",
    //
    // fatal error: 'openssl/sha.h' file not found
    //"toybox/toys/pending/git.c",
};

fn readToyboxConfig(allocator: std.mem.Allocator) !ToyboxConfigList {
    var lines = std.mem.splitSequence(u8, @embedFile("toybox/.config"), "\n");
    var configs = ToyboxConfigList.init(allocator);
    while (lines.next()) |line| {
        if (ToyboxConfig.parse(line)) |c| try configs.append(c);
    }
    return configs;
}

const ToyboxConfig = struct {
    name: []const u8,
    value: union(enum) {
        yn: bool,
        str: []const u8,
    },

    fn parse(line: []const u8) ?@This() {
        const self: @This() = blk: {
            const nsprefix = "# CONFIG_";
            const nssuffix = " is not set";
            if (std.mem.startsWith(u8, line, nsprefix) and std.mem.endsWith(u8, line, nssuffix)) {
                // # CONFIG_X is not set
                const name = line[nsprefix.len .. line.len - nssuffix.len];
                break :blk .{ .name = name, .value = .{ .yn = false } };
            } else if (std.mem.endsWith(u8, line, "=n")) {
                // CONFIG_X=n
                const name = line["CONFIG_".len .. line.len - 2];
                break :blk .{ .name = name, .value = .{ .yn = false } };
            } else if (std.mem.endsWith(u8, line, "=y")) {
                // CONFIG_X=y
                const name = line["CONFIG_".len .. line.len - 2];
                break :blk .{ .name = name, .value = .{ .yn = true } };
            } else if (std.mem.startsWith(u8, line, "CONFIG_")) {
                // CONFIG_X=STR
                const eq = std.mem.indexOf(u8, line, "=").?;
                const name = line["CONFIG_".len..eq];
                const val = line[eq + 1 ..];
                break :blk .{ .name = name, .value = .{ .str = val } };
            } else {
                return null;
            }
        };
        // TOYBOX will always be defined so skip
        if (std.mem.eql(u8, self.name, "TOYBOX")) return null;
        return self;
    }

    fn writeHeader(self: @This(), out: anytype) !void {
        switch (self.value) {
            .yn => |yn| {
                if (yn) {
                    try out.print("#define CFG_{s} 1\n", .{self.name});
                    try out.print("#define USE_{s}(...) __VA_ARGS__\n", .{self.name});
                } else {
                    try out.print("#define CFG_{s} 0\n", .{self.name});
                    try out.print("#define USE_{s}(...)\n", .{self.name});
                }
            },
            .str => |val| {
                try out.print("#define CFG_{s} {s}\n", .{ self.name, val });
            },
        }
    }

    fn makeOption(self: *@This(), b: *std.Build, allyes: bool, allno: bool) void {
        const c = self;
        switch (c.value) {
            .yn => {
                const opt = b.option(bool, c.name, b.fmt("CONFIG_{s}", .{c.name}));
                if (opt) |v| {
                    // User-specified
                    c.value = .{ .yn = v };
                } else if (allyes) {
                    // All yes
                    c.value = .{ .yn = true };
                } else if (allno) {
                    // All no
                    c.value = .{ .yn = false };
                }
            },
            .str => {
                const val = b.option([]const u8, c.name, b.fmt("CONFIG_{s}", .{c.name}));
                if (val) |v| {
                    // User-specified
                    c.value = .{ .str = v };
                }
            },
        }
    }
};
