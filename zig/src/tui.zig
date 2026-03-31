const std = @import("std");
const vaxis = @import("vaxis");
const api = @import("api.zig");
const ImageLoader = @import("image_loader.zig").ImageLoader;

const Cell = vaxis.Cell;
const Segment = Cell.Segment;
const Window = vaxis.Window;

// Restore terminal on panic so it doesn't stay wonky
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    vaxis.recover();
    std.debug.defaultPanic(msg, ret_addr);
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    mouse: vaxis.Mouse,
    image_ready,
};

// Colors — fg only, bg .default to respect terminal theme
const color = struct {
    const title = Cell.Color{ .rgb = .{ 0x61, 0xAF, 0xEF } };
    const corp = Cell.Color{ .rgb = .{ 0x56, 0xB6, 0xC2 } };
    const runner = Cell.Color{ .rgb = .{ 0xE0, 0x6C, 0x75 } };
    const credit = Cell.Color{ .rgb = .{ 0xE5, 0xC0, 0x7B } };
    const action_fg = Cell.Color{ .rgb = .{ 0x98, 0xC3, 0x79 } };
    const dim = Cell.Color{ .rgb = .{ 0x6B, 0x73, 0x7E } };
    const bright = Cell.Color{ .rgb = .{ 0xFF, 0xFF, 0xFF } };
    const run_active = Cell.Color{ .rgb = .{ 0xE5, 0xC0, 0x7B } };
    const selected_bg = Cell.Color{ .index = 237 };
    const faction_anarch = Cell.Color{ .rgb = .{ 0xFF, 0x44, 0x00 } };
    const faction_criminal = Cell.Color{ .rgb = .{ 0x44, 0x69, 0xBC } };
    const faction_shaper = Cell.Color{ .rgb = .{ 0x6A, 0xB5, 0x4A } };
    const faction_hb = Cell.Color{ .rgb = .{ 0x6F, 0x39, 0xA0 } };
    const faction_jinteki = Cell.Color{ .rgb = .{ 0xC8, 0x30, 0x30 } };
    const faction_nbn = Cell.Color{ .rgb = .{ 0xE8, 0x9E, 0x1C } };
    const faction_weyland = Cell.Color{ .rgb = .{ 0x3D, 0x7C, 0x47 } };
};

const sty = struct {
    const normal = Cell.Style{};
    const corp_label = Cell.Style{ .fg = color.corp, .bold = true };
    const runner_label = Cell.Style{ .fg = color.runner, .bold = true };
    const header = Cell.Style{ .fg = color.title, .bold = true };
    const credits = Cell.Style{ .fg = color.credit };
    const dim_text = Cell.Style{ .fg = color.dim };
    const action_num = Cell.Style{ .fg = color.action_fg, .bold = true };
    const action_text = Cell.Style{};
    const action_sel_num = Cell.Style{ .fg = color.action_fg, .bg = color.selected_bg, .bold = true };
    const action_sel_text = Cell.Style{ .fg = color.bright, .bg = color.selected_bg };
    const prompt_text = Cell.Style{ .fg = color.run_active, .bold = true };
};

// Game state
var game_handle: ?*anyopaque = null;
var selected_action: usize = 0;
var game_step: u32 = 0;
var status_msg: []const u8 = "";
var input_buf: [16]u8 = undefined;
var input_len: usize = 0;
var hover_card_code: c_int = 0; // card code from mouse hover on board

const ScreenMode = enum { menu, playing, game_over };
var current_screen: ScreenMode = .menu;
var menu_selection: usize = 0;

// Board element positions for mouse hover detection
const BoardCard = struct { row: u16, col_start: u16, col_end: u16, code: c_int };
var board_cards: [64]BoardCard = undefined;
var board_card_count: usize = 0;

// Game log — persistent across frames
const max_log_entries = 200;
var log_entries: [max_log_entries][]const u8 = undefined;
var log_count: usize = 0;
var log_alloc: std.heap.ArenaAllocator = undefined;

fn add_log(comptime f: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(log_alloc.allocator(), f, args) catch return;
    if (log_count < max_log_entries) {
        log_entries[log_count] = msg;
        log_count += 1;
    } else {
        // Shift entries (drop oldest)
        for (0..max_log_entries - 1) |i| {
            log_entries[i] = log_entries[i + 1];
        }
        log_entries[max_log_entries - 1] = msg;
    }
}

// Vaxis + image state
var vx_ptr: *vaxis.Vaxis = undefined;
var alloc_ptr: std.mem.Allocator = undefined;
var writer_ptr: *std.Io.Writer = undefined;
var img_loader: ImageLoader = .{};
var event_loop: *vaxis.Loop(Event) = undefined;

// Image cache directory
var cache_dir: []const u8 = "";

// Frame allocator
var frame_arena: std.heap.ArenaAllocator = undefined;

fn fmt(comptime f: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(frame_arena.allocator(), f, args) catch "?";
}

fn api_name(buf: []u8, len: c_int) []const u8 {
    if (len <= 0) return "";
    const src = buf[0..@intCast(len)];
    const dst = frame_arena.allocator().alloc(u8, src.len) catch return "?";
    @memcpy(dst, src);
    return dst;
}

fn side_label(player: c_int) []const u8 {
    return if (player == 0) "Corp" else "Runner";
}

fn side_sty(player: c_int) Cell.Style {
    return if (player == 0) sty.corp_label else sty.runner_label;
}

fn faction_color(faction: []const u8) Cell.Color {
    if (std.mem.eql(u8, faction, "anarch")) return color.faction_anarch;
    if (std.mem.eql(u8, faction, "criminal")) return color.faction_criminal;
    if (std.mem.eql(u8, faction, "shaper")) return color.faction_shaper;
    if (std.mem.eql(u8, faction, "haas_bioroid")) return color.faction_hb;
    if (std.mem.eql(u8, faction, "jinteki")) return color.faction_jinteki;
    if (std.mem.eql(u8, faction, "nbn")) return color.faction_nbn;
    if (std.mem.startsWith(u8, faction, "weyland")) return color.faction_weyland;
    return color.dim;
}

fn display_server(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "hq")) return "HQ";
    if (std.mem.eql(u8, name, "rnd")) return "R&D";
    if (std.mem.eql(u8, name, "archives")) return "Archives";
    if (std.mem.startsWith(u8, name, "remote")) {
        return fmt("Server {s}", .{name["remote".len..]});
    }
    return name;
}

fn pretty_type(t: []const u8) []const u8 {
    if (std.mem.eql(u8, t, "runner_identity") or std.mem.eql(u8, t, "corp_identity")) return "Identity";
    if (std.mem.eql(u8, t, "ice")) return "ICE";
    if (std.mem.eql(u8, t, "event")) return "Event";
    if (std.mem.eql(u8, t, "operation")) return "Operation";
    if (std.mem.eql(u8, t, "program")) return "Program";
    if (std.mem.eql(u8, t, "hardware")) return "Hardware";
    if (std.mem.eql(u8, t, "resource")) return "Resource";
    if (std.mem.eql(u8, t, "agenda")) return "Agenda";
    if (std.mem.eql(u8, t, "asset")) return "Asset";
    if (std.mem.eql(u8, t, "upgrade")) return "Upgrade";
    return t;
}

// ============================================================
// Rendering — Menu
// ============================================================

fn render_menu(win: Window) void {
    var row: u16 = 2;
    _ = win.print(&.{.{ .text = "  NETRUNNER", .style = sty.header }}, .{ .row_offset = row });
    row += 2;
    _ = win.print(&.{.{ .text = "  Select matchup:", .style = sty.normal }}, .{ .row_offset = row });
    row += 2;

    const matchups = [_][]const u8{
        "System Gateway - Beginner",
        "System Gateway - Intermediate",
        "System Gateway - Full Pack",
        "GNK: NBN Bounce Rate vs Loup",
    };

    for (matchups, 0..) |name, i| {
        const is_sel = i == menu_selection;
        _ = win.print(&.{
            .{ .text = fmt("  [{d}] ", .{i + 1}), .style = if (is_sel) sty.action_sel_num else sty.action_num },
            .{ .text = name, .style = if (is_sel) sty.action_sel_text else sty.action_text },
        }, .{ .row_offset = row });
        row +|= 1;
    }

    row += 2;
    _ = win.print(&.{.{ .text = "  UP/DOWN to select, ENTER to start, q to quit", .style = sty.dim_text }}, .{ .row_offset = row });
}

// ============================================================
// Rendering — Game (split layout)
// ============================================================

fn render_game(win: Window) void {
    const h = game_handle orelse return;

    // Layout:
    // ┌─────────────────────────────────┬──────────┐
    // │ Board (stats/servers/rig/hands) │  Log     │
    // ├────────────────┬────────────────┤          │
    // │ Actions        │ Card Image     │          │
    // └────────────────┴────────────────┴──────────┘

    const log_w: u16 = if (win.width > 100) 45 else if (win.width > 70) 38 else 0;
    const left_w = win.width -| log_w;

    // Board section at the top of the left area
    const board_win = win.child(.{ .width = left_w, .height = win.height });
    board_card_count = 0; // reset hover targets for this frame
    const actions_start = render_board_section(board_win, h);

    // Below board: actions (left) + card image (right)
    const bottom_h = win.height -| actions_start;
    if (bottom_h > 2) {
        const img_w: u16 = if (left_w > 80 and vx_ptr.caps.kitty_graphics) left_w / 3 else 0;
        const actions_w = left_w -| img_w;

        const actions_win = win.child(.{
            .y_off = @intCast(actions_start),
            .width = actions_w,
            .height = bottom_h,
        });
        render_actions(actions_win, h, 0);

        if (img_w > 0) {
            const img_panel = win.child(.{
                .x_off = @intCast(actions_w),
                .y_off = @intCast(actions_start),
                .width = img_w,
                .height = bottom_h,
            });
            render_image_panel(img_panel, h);
        }
    }

    // Right panel: log only (full height)
    if (log_w > 0) {
        const log_win = win.child(.{
            .x_off = @intCast(left_w),
            .width = log_w,
            .height = win.height,
        });
        render_log(log_win);
    }
}

fn render_board_section(win: Window, h: ?*anyopaque) u16 {
    var row: u16 = 0;

    row = render_header(win, h, row);
    row +|= 1;
    if (row >= win.height) return row;
    row = render_player_section(win, h, 0, row);
    row +|= 1;
    if (row >= win.height) return row;
    render_hline(win, row);
    row +|= 1;
    if (row >= win.height) return row;
    row = render_player_section(win, h, 1, row);
    row +|= 1;
    if (row >= win.height) return row;

    if (api.netrunner_is_run_active(h))
        row = render_run_state(win, h, row);

    row = render_prompt(win, h, row);
    if (row >= win.height) return row;
    row = render_hand(win, h, 0, row);
    row = render_hand(win, h, 1, row);
    return row;
}

fn render_image_panel(win: Window, h: ?*anyopaque) void {
    render_vsep(win);
    const content = win.child(.{ .x_off = 1, .width = win.width -| 1, .height = win.height });

    if (!vx_ptr.caps.kitty_graphics) return;

    render_hline_w(content, 0);

    // Priority: mouse hover > action card > context card (ICE encounter, access, prompt)
    const code = if (hover_card_code > 0)
        hover_card_code
    else
        api.netrunner_context_card_code(h, @intCast(selected_action));
    if (code <= 0) return;

    _ = try_render_card_image(content, code, 2);
}

fn render_vsep(win: Window) void {
    var r: u16 = 0;
    while (r < win.height) : (r +|= 1) {
        win.writeCell(0, r, .{
            .char = .{ .grapheme = "|", .width = 1 },
            .style = sty.dim_text,
        });
    }
}

fn render_log(win: Window) void {
    // Vertical separator
    var r: u16 = 0;
    while (r < win.height) : (r +|= 1) {
        win.writeCell(0, r, .{
            .char = .{ .grapheme = "|", .width = 1 },
            .style = sty.dim_text,
        });
    }

    const content = win.child(.{ .x_off = 2, .width = win.width -| 2, .height = win.height });

    _ = content.print(&.{.{ .text = "Log", .style = sty.header }}, .{ .row_offset = 0 });
    if (content.height < 3) return;

    const available = content.height -| 1;
    const start_idx = if (log_count > available) log_count - available else 0;
    var row: u16 = 1;
    for (log_entries[start_idx..log_count]) |entry| {
        if (row >= content.height) break;
        _ = content.print(&.{.{ .text = entry, .style = sty.dim_text }}, .{
            .row_offset = row,
            .wrap = .none,
        });
        row +|= 1;
    }
}

fn try_render_card_image(win: Window, code: c_int, start_row: u16) u16 {
    if (win.height < start_row +| 4) return 0;

    const img_id = img_loader.update(code);

    if (img_id == 0) {
        _ = win.print(&.{.{ .text = "Loading...", .style = sty.dim_text }}, .{ .row_offset = start_row });
        return 1;
    }

    const max_h = win.height -| start_row;
    if (max_h < 4) return 0;

    // Card is 750x1050 (w:h = 5:7). Reduce cols so image fits vertically.
    // Kitty scales by cols and preserves aspect ratio.
    // With cell aspect ~1:2, cols C gives height ≈ C * 7/5 / 2 = C * 0.7 rows.
    // We want height <= max_h, so cols <= max_h / 0.7 ≈ max_h * 10 / 7.
    const max_cols_for_height = max_h *| 10 / 7;
    const cols = @min(win.width, max_cols_for_height);

    const img: vaxis.Image = .{ .id = img_id, .width = 750, .height = 1050 };
    const img_win = win.child(.{
        .y_off = @intCast(start_row),
        .width = cols,
        .height = max_h,
    });

    img.draw(img_win, .{
        .size = .{ .cols = cols },
    }) catch return 0;
    return max_h;
}

fn notify_image_ready() void {
    event_loop.postEvent(.image_ready);
}

fn vaxis_free_image(img_id: u32) void {
    vx_ptr.freeImage(writer_ptr, img_id);
}

/// Called on background thread — downloads if needed, then loads PNG into vaxis.
fn vaxis_async_load(code: c_int) ?u32 {
    const dest_path = std.fmt.allocPrint(alloc_ptr, "{s}/{d}.png", .{ cache_dir, code }) catch return null;
    defer alloc_ptr.free(dest_path);

    // Download if not cached
    std.fs.cwd().access(dest_path, .{}) catch {
        var url_buf: [256]u8 = undefined;
        const url_len = api.netrunner_card_image_url(code, &url_buf, url_buf.len);
        if (url_len <= 0) return null;

        const tmp_path = std.fmt.allocPrint(alloc_ptr, "{s}.webp", .{dest_path}) catch return null;
        defer alloc_ptr.free(tmp_path);
        var dl = std.process.Child.init(
            &.{ "curl", "-sL", "-o", tmp_path, url_buf[0..@intCast(url_len)] },
            alloc_ptr,
        );
        dl.stdin_behavior = .Close;
        dl.stdout_behavior = .Close;
        dl.stderr_behavior = .Close;
        const dl_term = dl.spawnAndWait() catch return null;
        if (dl_term.Exited != 0) return null;

        var conv = std.process.Child.init(
            &.{ "sips", "-s", "format", "png", tmp_path, "--out", dest_path },
            alloc_ptr,
        );
        conv.stdin_behavior = .Close;
        conv.stdout_behavior = .Close;
        conv.stderr_behavior = .Close;
        _ = conv.spawnAndWait() catch {};
        std.fs.cwd().deleteFile(tmp_path) catch {};
    };

    // Transmit file path to terminal — terminal reads PNG directly (no decode/re-encode)
    const img = vx_ptr.transmitLocalImagePath(alloc_ptr, writer_ptr, dest_path, 0, 0, .file, .png) catch return null;
    return img.id;
}

// ============================================================
// Rendering — Board components
// ============================================================

fn render_header(win: Window, h: ?*anyopaque, start_row: u16) u16 {
    var row = start_row;
    const turn = api.netrunner_turn(h);
    const active = api.netrunner_active_player(h);
    const deciding = api.netrunner_current_player(h);

    _ = win.print(&.{
        .{ .text = " NETRUNNER", .style = sty.header },
        .{ .text = " | ", .style = sty.dim_text },
        .{ .text = fmt("Turn {d}", .{turn}), .style = sty.normal },
        .{ .text = " | ", .style = sty.dim_text },
        .{ .text = side_label(active), .style = side_sty(active) },
        .{ .text = "'s turn | ", .style = sty.dim_text },
        .{ .text = side_label(deciding), .style = side_sty(deciding) },
        .{ .text = " to decide", .style = sty.dim_text },
    }, .{ .row_offset = row });
    row +|= 1;
    render_hline(win, row);
    return row +| 1;
}

fn render_player_section(win: Window, h: ?*anyopaque, player: c_int, start_row: u16) u16 {
    var row = start_row;
    var id_buf: [256]u8 = undefined;
    const id_len = api.netrunner_identity_name(h, player, &id_buf, id_buf.len);

    _ = win.print(&.{
        .{ .text = if (player == 0) " CORP: " else " RUNNER: ", .style = side_sty(player) },
        .{ .text = api_name(&id_buf, id_len), .style = sty.normal },
    }, .{ .row_offset = row });
    row +|= 1;

    const cr = api.netrunner_player_credits(h, player);
    const cl = api.netrunner_player_clicks(h, player);
    const hd = api.netrunner_player_hand_size(h, player);
    const dk = api.netrunner_player_deck_size(h, player);
    const dc = api.netrunner_player_discard_size(h, player);
    const sc = api.netrunner_player_score(h, player);
    const sr = api.netrunner_player_score_req(h, player);

    if (player == 1) {
        const mu = api.netrunner_runner_mu_used(h);
        const ma = api.netrunner_runner_mu_available(h);
        const lk = api.netrunner_runner_link(h);
        const tg = api.netrunner_runner_tags(h);
        const rc = api.netrunner_runner_run_credits(h);
        const stat = if (rc > 0)
            fmt(" ${d}(+{d}) Cl:{d} H:{d} D:{d} Dc:{d} MU:{d}/{d} Lk:{d} T:{d} Sc:{d}/{d}", .{ cr, rc, cl, hd, dk, dc, mu, ma, lk, tg, sc, sr })
        else
            fmt(" ${d} Cl:{d} H:{d} D:{d} Dc:{d} MU:{d}/{d} Lk:{d} T:{d} Sc:{d}/{d}", .{ cr, cl, hd, dk, dc, mu, ma, lk, tg, sc, sr });
        _ = win.print(&.{.{ .text = stat, .style = sty.credits }}, .{ .row_offset = row });
    } else {
        const bp = api.netrunner_corp_bad_pub(h);
        const stat = if (bp > 0)
            fmt(" ${d} Cl:{d} H:{d} D:{d} Dc:{d} BP:{d} Sc:{d}/{d}", .{ cr, cl, hd, dk, dc, bp, sc, sr })
        else
            fmt(" ${d} Cl:{d} H:{d} D:{d} Dc:{d} Sc:{d}/{d}", .{ cr, cl, hd, dk, dc, sc, sr });
        _ = win.print(&.{.{ .text = stat, .style = sty.credits }}, .{ .row_offset = row });
    }
    row +|= 1;

    if (player == 0) return render_servers(win, h, row) else return render_rig(win, h, row);
}

fn render_servers(win: Window, h: ?*anyopaque, start_row: u16) u16 {
    var row = start_row;
    const count = api.netrunner_server_count(h);
    if (count == 0) return row;

    var i: c_int = 0;
    while (i < count) : (i += 1) {
        var name_buf: [64]u8 = undefined;
        const name_len = api.netrunner_server_name(h, i, &name_buf, name_buf.len);
        const server_label = display_server(api_name(&name_buf, name_len));
        var col_pos: u16 = @intCast(server_label.len +| 1); // track column for hover regions
        var line: []const u8 = fmt(" {s: <10}", .{server_label});
        col_pos = @intCast(@min(line.len, 65535));

        const ice_count = api.netrunner_server_ice_count(h, i);
        var j: c_int = 0;
        while (j < ice_count) : (j += 1) {
            var ice_buf: [128]u8 = undefined;
            const ice_len = api.netrunner_server_ice_name(h, i, j, &ice_buf, ice_buf.len);
            const rezzed = api.netrunner_server_ice_rezzed(h, i, j);
            const ice_name = api_name(&ice_buf, ice_len);
            const old_len = line.len;
            line = fmt("{s} [{s}{s}]", .{ line, ice_name, if (rezzed) "" else "?" });

            // Register hover region for this ICE
            const ice_code = api.netrunner_server_ice_code(h, i, j);
            if (ice_code > 0 and board_card_count < board_cards.len) {
                board_cards[board_card_count] = .{
                    .row = row,
                    .col_start = @intCast(old_len),
                    .col_end = @intCast(line.len),
                    .code = ice_code,
                };
                board_card_count += 1;
            }
        }

        const content_count = api.netrunner_server_content_count(h, i);
        j = 0;
        while (j < content_count) : (j += 1) {
            var card_buf: [128]u8 = undefined;
            const card_len = api.netrunner_server_content_name(h, i, j, &card_buf, card_buf.len);
            const rezzed = api.netrunner_server_content_rezzed(h, i, j);
            const old_len = line.len;
            line = fmt("{s} {s}{s}", .{ line, api_name(&card_buf, card_len), if (rezzed) "" else "?" });

            const card_code = api.netrunner_server_content_code(h, i, j);
            if (card_code > 0 and board_card_count < board_cards.len) {
                board_cards[board_card_count] = .{
                    .row = row,
                    .col_start = @intCast(old_len),
                    .col_end = @intCast(line.len),
                    .code = card_code,
                };
                board_card_count += 1;
            }
        }

        _ = win.print(&.{.{ .text = line, .style = sty.normal }}, .{ .row_offset = row });
        row +|= 1;
    }
    return row;
}

fn render_rig(win: Window, h: ?*anyopaque, start_row: u16) u16 {
    var row = start_row;
    const hw = api.netrunner_rig_hardware_count(h);
    const prog = api.netrunner_rig_program_count(h);
    const res = api.netrunner_rig_resource_count(h);

    if (hw == 0 and prog == 0 and res == 0) {
        _ = win.print(&.{.{ .text = " Rig: (empty)", .style = sty.dim_text }}, .{ .row_offset = row });
        return row +| 1;
    }

    if (prog > 0) row = render_rig_zone(win, h, "Prg", prog, api.netrunner_rig_program_name, api.netrunner_rig_program_code, row);
    if (hw > 0) row = render_rig_zone(win, h, "Hw", hw, api.netrunner_rig_hardware_name, api.netrunner_rig_hardware_code, row);
    if (res > 0) row = render_rig_zone(win, h, "Res", res, api.netrunner_rig_resource_name, api.netrunner_rig_resource_code, row);
    return row;
}

fn render_rig_zone(
    win: Window,
    h: ?*anyopaque,
    label: []const u8,
    count: c_int,
    name_fn: *const fn (?*anyopaque, c_int, [*c]u8, c_int) callconv(.c) c_int,
    code_fn: *const fn (?*anyopaque, c_int) callconv(.c) c_int,
    start_row: u16,
) u16 {
    var line: []const u8 = fmt(" {s}:", .{label});
    var i: c_int = 0;
    while (i < count) : (i += 1) {
        var buf: [128]u8 = undefined;
        const len = name_fn(h, i, &buf, buf.len);
        const name = api_name(&buf, len);
        const sep = if (i > 0) ", " else " ";
        const old_len = line.len;
        line = fmt("{s}{s}{s}", .{ line, sep, name });

        const card_code = code_fn(h, i);
        if (card_code > 0 and board_card_count < board_cards.len) {
            board_cards[board_card_count] = .{
                .row = start_row,
                .col_start = @intCast(old_len),
                .col_end = @intCast(line.len),
                .code = card_code,
            };
            board_card_count += 1;
        }
    }
    _ = win.print(&.{.{ .text = line, .style = sty.normal }}, .{ .row_offset = start_row });
    return start_row +| 1;
}

fn render_run_state(win: Window, h: ?*anyopaque, start_row: u16) u16 {
    var srv_buf: [64]u8 = undefined;
    var ph_buf: [64]u8 = undefined;
    const srv_len = api.netrunner_run_server(h, &srv_buf, srv_buf.len);
    const ph_len = api.netrunner_run_phase(h, &ph_buf, ph_buf.len);
    const pos = api.netrunner_run_position(h);

    _ = win.print(&.{.{
        .text = fmt(" >> RUN {s} | {s} | Pos:{d}", .{ api_name(&srv_buf, srv_len), api_name(&ph_buf, ph_len), pos }),
        .style = sty.prompt_text,
    }}, .{ .row_offset = start_row });
    return start_row +| 1;
}

fn render_prompt(win: Window, h: ?*anyopaque, start_row: u16) u16 {
    const deciding = api.netrunner_current_player(h);
    var type_buf: [128]u8 = undefined;
    var source_buf: [128]u8 = undefined;
    const type_len = api.netrunner_prompt_type(h, deciding, &type_buf, type_buf.len);
    const source_len = api.netrunner_prompt_source(h, deciding, &source_buf, source_buf.len);

    if (type_len <= 0) return start_row;

    const text = if (source_len > 0)
        fmt(" Prompt: {s} (from {s})", .{ api_name(&type_buf, type_len), api_name(&source_buf, source_len) })
    else
        fmt(" Prompt: {s}", .{api_name(&type_buf, type_len)});

    _ = win.print(&.{.{ .text = text, .style = sty.prompt_text }}, .{ .row_offset = start_row });
    return start_row +| 1;
}

fn render_hand(win: Window, h: ?*anyopaque, player: c_int, start_row: u16) u16 {
    const hand_size = api.netrunner_player_hand_size(h, player);
    var line: []const u8 = if (player == 0) " Corp Hand: " else " Runner Hand: ";

    if (hand_size == 0) {
        line = fmt("{s}(empty)", .{line});
    } else {
        var i: c_int = 0;
        while (i < hand_size) : (i += 1) {
            var buf: [128]u8 = undefined;
            const len = api.netrunner_hand_card_name(h, player, i, &buf, buf.len);
            const sep: []const u8 = if (i > 0) ", " else "";
            const old_len = line.len;
            line = fmt("{s}{s}{s}", .{ line, sep, api_name(&buf, len) });

            // Register hover region for hand card
            const card_code = api.netrunner_hand_card_code(h, player, i);
            if (card_code > 0 and board_card_count < board_cards.len) {
                board_cards[board_card_count] = .{
                    .row = start_row,
                    .col_start = @intCast(old_len + sep.len),
                    .col_end = @intCast(line.len),
                    .code = card_code,
                };
                board_card_count += 1;
            }
        }
    }
    _ = win.print(&.{.{ .text = line, .style = sty.dim_text }}, .{ .row_offset = start_row });
    return start_row +| 1;
}

fn render_actions(win: Window, h: ?*anyopaque, start_row: u16) void {
    if (start_row >= win.height) return;
    var row = start_row;
    const count = api.netrunner_num_actions(h);
    const deciding = api.netrunner_current_player(h);

    render_hline(win, row);
    row +|= 1;
    if (row >= win.height) return;

    var pt_buf: [64]u8 = undefined;
    const pt_len = api.netrunner_prompt_type(h, deciding, &pt_buf, pt_buf.len);
    const prompt_type = if (pt_len > 0) pt_buf[0..@intCast(pt_len)] else "";
    const header = if (std.mem.eql(u8, prompt_type, "discard"))
        fmt(" Discard to hand size ({s}):", .{side_label(deciding)})
    else if (std.mem.eql(u8, prompt_type, "install-destination"))
        fmt(" Choose install location ({s}):", .{side_label(deciding)})
    else if (std.mem.eql(u8, prompt_type, "access-choice"))
        fmt(" Access card ({s}):", .{side_label(deciding)})
    else if (std.mem.eql(u8, prompt_type, "run-target"))
        fmt(" Choose run target ({s}):", .{side_label(deciding)})
    else if (std.mem.eql(u8, prompt_type, "run"))
        fmt(" Run in progress ({s}):", .{side_label(deciding)})
    else
        fmt(" Actions ({s}):", .{side_label(deciding)});
    _ = win.print(&.{.{
        .text = header,
        .style = side_sty(deciding),
    }}, .{ .row_offset = row });
    row +|= 1;

    var i: c_int = 0;
    while (i < count) : (i += 1) {
        if (row >= win.height -| 2) break; // leave room for status bar

        var buf: [256]u8 = undefined;
        const len = api.netrunner_action_description(h, i, &buf, buf.len);

        const idx: usize = @intCast(i);
        const is_sel = idx == selected_action;
        const ns = if (is_sel) sty.action_sel_num else sty.action_num;
        const ts = if (is_sel) sty.action_sel_text else sty.action_text;

        _ = win.print(&.{
            .{ .text = fmt(" [{d}] ", .{i + 1}), .style = ns },
            .{ .text = api_name(&buf, len), .style = ts },
        }, .{ .row_offset = row });
        row +|= 1;
    }

    // Status bar at bottom
    if (win.height > 2) {
        const status_row = win.height - 1;
        if (input_len > 0) {
            _ = win.print(&.{.{ .text = fmt(" > {s}", .{input_buf[0..input_len]}), .style = sty.normal }}, .{ .row_offset = status_row });
        } else if (status_msg.len > 0) {
            _ = win.print(&.{.{ .text = fmt(" {s}", .{status_msg}), .style = sty.prompt_text }}, .{ .row_offset = status_row });
        } else {
            _ = win.print(&.{.{ .text = " #/j/k + ENTER, q quit | ? = unrezzed", .style = sty.dim_text }}, .{ .row_offset = status_row });
        }
    }
}

fn render_game_over(win: Window) void {
    const h = game_handle orelse return;
    var row: u16 = 3;

    _ = win.print(&.{.{ .text = " GAME OVER", .style = sty.header }}, .{ .row_offset = row });
    row += 2;

    const winner = api.netrunner_winner(h);
    if (winner >= 0) {
        var name_buf: [256]u8 = undefined;
        const name_len = api.netrunner_identity_name(h, winner, &name_buf, name_buf.len);
        _ = win.print(&.{
            .{ .text = " Winner: ", .style = sty.normal },
            .{ .text = side_label(winner), .style = side_sty(winner) },
            .{ .text = " - ", .style = sty.normal },
            .{ .text = api_name(&name_buf, name_len), .style = sty.normal },
        }, .{ .row_offset = row });
    } else {
        _ = win.print(&.{.{ .text = " Draw.", .style = sty.normal }}, .{ .row_offset = row });
    }
    row += 2;

    _ = win.print(&.{.{
        .text = fmt(" Corp: {d}/{d}  |  Runner: {d}/{d}", .{
            api.netrunner_player_score(h, 0), api.netrunner_player_score_req(h, 0),
            api.netrunner_player_score(h, 1), api.netrunner_player_score_req(h, 1),
        }),
        .style = sty.credits,
    }}, .{ .row_offset = row });
    row +|= 1;

    _ = win.print(&.{.{ .text = fmt(" Steps: {d}", .{game_step}), .style = sty.dim_text }}, .{ .row_offset = row });
    row += 2;
    _ = win.print(&.{.{ .text = " Press q to quit", .style = sty.dim_text }}, .{ .row_offset = row });
}

fn render_hline(win: Window, row: u16) void {
    render_hline_w(win, row);
}

fn render_hline_w(win: Window, row: u16) void {
    var col: u16 = 0;
    while (col < win.width) : (col += 1) {
        win.writeCell(col, row, .{
            .char = .{ .grapheme = "-", .width = 1 },
            .style = sty.dim_text,
        });
    }
}

// ============================================================
// Input handling
// ============================================================

fn handle_event(event: Event, allocator: std.mem.Allocator, vx: *vaxis.Vaxis, writer: *std.Io.Writer) bool {
    switch (event) {
        .key_press => |key| {
            hover_card_code = 0;
            const quit = switch (current_screen) {
                .menu => handle_menu_key(key),
                .playing => handle_game_key(key),
                .game_over => key.matches('q', .{}) or key.matches('c', .{ .ctrl = true }),
            };
            return quit;
        },
        .mouse => |mouse| {
            handle_mouse(mouse);
            return false;
        },
        .winsize => |ws| {
            vx.resize(allocator, writer, ws) catch {};
            return false;
        },
        .image_ready => return false, // just re-render
    }
}

fn handle_mouse(mouse: vaxis.Mouse) void {
    if (current_screen != .playing) return;

    // Check if mouse is hovering over a registered board card
    hover_card_code = 0;
    const row: u16 = @intCast(mouse.row);
    const col: u16 = @intCast(mouse.col);
    for (board_cards[0..board_card_count]) |bc| {
        if (row == bc.row and col >= bc.col_start and col < bc.col_end) {
            hover_card_code = bc.code;
            break;
        }
    }
}

fn handle_menu_key(key: vaxis.Key) bool {
    if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) return true;
    if (key.codepoint == vaxis.Key.up or key.matches('k', .{})) {
        if (menu_selection > 0) menu_selection -= 1;
    } else if (key.codepoint == vaxis.Key.down or key.matches('j', .{})) {
        if (menu_selection < api.matchup_count - 1) menu_selection += 1;
    } else if (key.codepoint == vaxis.Key.enter) {
        start_game();
    } else if (key.codepoint >= '1' and key.codepoint <= '0' + @as(u21, @intCast(api.matchup_count))) {
        menu_selection = key.codepoint - '1';
        start_game();
    }
    return false;
}

fn start_game() void {
    const seed: u64 = @bitCast(std.time.milliTimestamp());
    const matchup: c_int = @intCast(menu_selection);
    game_handle = api.netrunner_create(matchup, seed);
    if (game_handle != null) {
        current_screen = .playing;
        selected_action = 0;
        game_step = 0;
        status_msg = "";
        input_len = 0;
        auto_advance();
    }
}

fn log_and_apply(h: ?*anyopaque, idx: c_int) bool {
    var buf: [256]u8 = undefined;
    const len = api.netrunner_action_description(h, idx, &buf, buf.len);
    const desc = if (len > 0) buf[0..@intCast(len)] else "?";
    const deciding = api.netrunner_current_player(h);

    if (api.netrunner_apply_action(h, idx) == 0) {
        add_log("{s}: {s}", .{ side_label(deciding), desc });
        game_step += 1;
        return true;
    }
    return false;
}

fn auto_advance() void {
    const h = game_handle orelse return;
    while (!api.netrunner_is_terminal(h)) {
        const num: usize = @intCast(api.netrunner_num_actions(h));
        if (num != 1) break;
        _ = log_and_apply(h, 0);
    }
    if (api.netrunner_is_terminal(h)) current_screen = .game_over;
    selected_action = 0;
}

fn handle_game_key(key: vaxis.Key) bool {
    if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) return true;
    const h = game_handle orelse return false;
    const num_actions: usize = @intCast(api.netrunner_num_actions(h));
    if (num_actions == 0) return false;

    if (key.codepoint == vaxis.Key.up or key.matches('k', .{})) {
        if (selected_action > 0) selected_action -= 1;
        status_msg = "";
    } else if (key.codepoint == vaxis.Key.down or key.matches('j', .{})) {
        if (selected_action < num_actions - 1) selected_action += 1;
        status_msg = "";
    } else if (key.codepoint == vaxis.Key.enter) {
        if (input_len > 0) {
            try_apply_numbered_input(h, num_actions);
        } else {
            apply_selected_action(h);
        }
    } else if (key.codepoint >= '0' and key.codepoint <= '9') {
        if (input_len < input_buf.len - 1) {
            input_buf[input_len] = @intCast(key.codepoint);
            input_len += 1;
        }
    } else if (key.codepoint == vaxis.Key.backspace or key.codepoint == 127) {
        if (input_len > 0) input_len -= 1;
    }
    return false;
}

fn try_apply_numbered_input(h: ?*anyopaque, num_actions: usize) void {
    const choice = std.fmt.parseInt(usize, input_buf[0..input_len], 10) catch {
        input_len = 0;
        status_msg = "Invalid number";
        return;
    };
    input_len = 0;
    if (choice >= 1 and choice <= num_actions) {
        if (log_and_apply(h, @intCast(choice - 1))) {
            auto_advance();
            status_msg = "";
        } else {
            status_msg = "Action failed";
        }
    } else {
        status_msg = "Invalid choice";
    }
}

fn apply_selected_action(h: ?*anyopaque) void {
    if (log_and_apply(h, @intCast(selected_action))) {
        input_len = 0;
        auto_advance();
        status_msg = "";
    } else {
        status_msg = "Action failed";
    }
}

// ============================================================
// Main
// ============================================================

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    alloc_ptr = allocator;

    frame_arena = std.heap.ArenaAllocator.init(allocator);
    defer frame_arena.deinit();

    log_alloc = std.heap.ArenaAllocator.init(allocator);
    defer log_alloc.deinit();

    // Setup image cache directory
    const home = std.posix.getenv("HOME") orelse "/tmp";
    cache_dir = std.fmt.allocPrint(allocator, "{s}/.cache/netrunner-tui/images", .{home}) catch "/tmp/netrunner-tui";
    std.fs.cwd().makePath(cache_dir) catch {};

    var tty_buf: [4096]u8 = undefined;
    var tty: vaxis.Tty = try .init(&tty_buf);
    defer tty.deinit();

    var vx: vaxis.Vaxis = try .init(allocator, .{});
    defer vx.deinit(allocator, tty.writer());
    vx_ptr = &vx;

    const writer = tty.writer();
    writer_ptr = writer;

    var loop: vaxis.Loop(Event) = .{ .vaxis = &vx, .tty = &tty };
    try loop.init();
    try loop.start();
    defer loop.stop();
    event_loop = &loop;

    try vx.enterAltScreen(writer);
    try vx.setMouseMode(writer, true);
    try vx.queryTerminal(writer, 1 * std.time.ns_per_s);

    // Initialize image loader — all loads go through async_load_fn
    // (vaxis loadImage decodes PNG which is too slow for the main thread)
    img_loader = .{
        .free_fn = vaxis_free_image,
        .load_fn = null,
        .async_load_fn = vaxis_async_load,
        .notify_fn = notify_image_ready,
    };

    while (true) {
        // Always block — background thread posts image_ready event when done
        const event = loop.nextEvent();
        if (handle_event(event, allocator, &vx, writer)) break;

        _ = frame_arena.reset(.retain_capacity);

        const win = vx.window();
        win.clear();

        switch (current_screen) {
            .menu => render_menu(win),
            .playing => render_game(win),
            .game_over => render_game_over(win),
        }

        try vx.render(writer);
        try writer.flush();
    }

    img_loader.deinit();
    if (game_handle) |h| {
        api.netrunner_destroy(h);
        game_handle = null;
    }
}
