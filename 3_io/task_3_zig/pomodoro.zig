//! Задача 3.3 (Zig): консольный Pomodoro-таймер с логированием сессий.
//!
//! В консоли идёт обратный отсчёт: строка перерисовывается на месте через '\r'.
//! По окончании работы - звуковой сигнал ('\a', BEL) и в файл stats.txt
//! дописывается дата и длительность сессии. В конце - сводка по всему файлу.
//!
//! Запуск:  pomodoro [работа] [перерыв] [циклов]
//!          длительность: 25m, 90s, 1h (без суффикса - минуты)
//!          по умолчанию: 25m 5m 1
//! Написано под Zig 0.13.0.

const std = @import("std");

const stats_file = "stats.txt";

/// "25m" -> 1500, "90s" -> 90, "1h" -> 3600, "10" -> 600
fn parseDuration(s: []const u8) !u32 {
    if (s.len == 0) return error.InvalidDuration;
    const mult: u32 = switch (s[s.len - 1]) {
        's' => 1,
        'm' => 60,
        'h' => 3600,
        else => 0,
    };
    const digits = if (mult == 0) s else s[0 .. s.len - 1];
    const n = try std.fmt.parseInt(u32, digits, 10);
    return n * (if (mult == 0) 60 else mult);
}

/// Обратный отсчёт с перерисовкой одной строки и полосой прогресса.
fn countdown(w: anytype, label: []const u8, total: u32) !void {
    const width: u32 = 30;
    var left: u32 = total;
    while (true) {
        const done = total - left;
        const filled = if (total == 0) width else done * width / total;
        // '\r' возвращает курсор в начало строки - так строка обновляется на месте
        try w.print("\r  {s}  {d:0>2}:{d:0>2}  [", .{ label, left / 60, left % 60 });
        var i: u32 = 0;
        while (i < width) : (i += 1) try w.writeByte(if (i < filled) '#' else '-');
        try w.writeAll("] ");
        if (left == 0) break;
        std.time.sleep(std.time.ns_per_s);
        left -= 1;
    }
    try w.writeAll("\n");
}

/// Дописать строку "YYYY-MM-DD HH:MM:SS UTC; работа; <секунды>" в конец stats.txt.
fn appendStats(label: []const u8, seconds: u32) !void {
    const ts = std.time.timestamp();
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(ts) };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();

    // truncate = false: файл не перезаписывается; если его нет - создаётся
    const file = try std.fs.cwd().createFile(stats_file, .{ .truncate = false });
    defer file.close();
    try file.seekFromEnd(0);
    try file.writer().print("{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC; {s}; {d}\n", .{
        yd.year,
        @intFromEnum(md.month),
        md.day_index + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
        label,
        seconds,
    });
}

/// Прочитать stats.txt и посчитать число рабочих сессий и суммарное время.
fn printSummary(alloc: std.mem.Allocator, w: anytype) !void {
    const data = std.fs.cwd().readFileAlloc(alloc, stats_file, 1 << 20) catch return;
    defer alloc.free(data);

    var sessions: u32 = 0;
    var total: u64 = 0;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "; работа; ") == null) continue;
        const sep = std.mem.lastIndexOf(u8, line, "; ") orelse continue;
        const num = std.mem.trim(u8, line[sep + 2 ..], " \r");
        const secs = std.fmt.parseInt(u64, num, 10) catch continue;
        sessions += 1;
        total += secs;
    }
    try w.print("Всего рабочих сессий в {s}: {d}, суммарно {d} ч {d} мин {d} с\n", .{
        stats_file, sessions, total / 3600, (total % 3600) / 60, total % 60,
    });
}

fn usage(w: anytype) !void {
    try w.writeAll(
        \\Использование: pomodoro [работа] [перерыв] [циклов]
        \\  длительность: 25m, 90s, 1h (без суффикса - минуты)
        \\  пример для демонстрации: pomodoro 10s 5s 2
        \\
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const out = std.io.getStdOut().writer();

    if (args.len > 1 and (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")))
        return usage(out);

    const work: u32 = if (args.len > 1) (parseDuration(args[1]) catch return usage(out)) else 25 * 60;
    const rest: u32 = if (args.len > 2) (parseDuration(args[2]) catch return usage(out)) else 5 * 60;
    const cycles: u32 = if (args.len > 3) (std.fmt.parseInt(u32, args[3], 10) catch return usage(out)) else 1;

    try out.print("Pomodoro: работа {d}:{d:0>2}, перерыв {d}:{d:0>2}, циклов: {d}\n\n", .{
        work / 60, work % 60, rest / 60, rest % 60, cycles,
    });

    var c: u32 = 1;
    while (c <= cycles) : (c += 1) {
        try out.print("Цикл {d}/{d}\n", .{ c, cycles });
        try countdown(out, "Работа ", work);
        try appendStats("работа", work);
        // '\x07' - символ BEL: терминал издаёт звуковой сигнал
        try out.writeAll("\x07  Время вышло! Сессия записана в stats.txt\n");

        if (c < cycles) {
            try countdown(out, "Перерыв", rest);
            try out.writeAll("\x07  Перерыв окончен\n\n");
        }
    }

    try out.writeAll("\n");
    try printSummary(alloc, out);
}
