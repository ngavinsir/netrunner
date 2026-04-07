const std = @import("std");
const engine = @import("engine/game.zig");
const state = @import("engine/state.zig");

const Game = engine.Game;
const backing_allocator = std.heap.page_allocator;

const matchup_table = [_]engine.MatchupSpec{
    engine.system_gateway_beginner,
    engine.system_gateway_intermediate,
    engine.system_gateway_fullpack,
    engine.gnk_nbn_vs_loup,
    engine.system_gateway_hb,
};

pub const matchup_count: c_int = matchup_table.len;

fn get_game(handle: ?*anyopaque) ?*Game {
    const ptr = handle orelse return null;
    return @as(*Game, @ptrCast(@alignCast(ptr)));
}

fn write_str(buf: [*c]u8, buf_size: c_int, src: []const u8) c_int {
    if (buf_size <= 0) return 0;
    const size: usize = @intCast(buf_size);
    const copy_len = @min(src.len, size - 1);
    @memcpy(buf[0..copy_len], src[0..copy_len]);
    buf[copy_len] = 0;
    return @intCast(copy_len);
}

// ============================================================
// Game lifecycle
// ============================================================

pub export fn netrunner_create(matchup_id: c_int, seed: u64) callconv(.c) ?*anyopaque {
    if (matchup_id < 0 or @as(usize, @intCast(matchup_id)) >= matchup_table.len) return null;
    const game = backing_allocator.create(Game) catch return null;
    game.* = engine.createInitialSnapshot(backing_allocator, matchup_table[@intCast(matchup_id)], seed) catch {
        backing_allocator.destroy(game);
        return null;
    };
    return @ptrCast(game);
}

pub export fn netrunner_destroy(handle: ?*anyopaque) callconv(.c) void {
    const game = get_game(handle) orelse return;
    game.deinit();
    backing_allocator.destroy(game);
}

// ============================================================
// Core game state
// ============================================================

pub export fn netrunner_current_player(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return -1;
    return if (game.decision_side == .corp) 0 else 1;
}

pub export fn netrunner_is_terminal(handle: ?*anyopaque) callconv(.c) bool {
    const game = get_game(handle) orelse return true;
    return game.game_over;
}

pub export fn netrunner_winner(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return -1;
    const w = game.winner orelse return -1;
    return if (w == .corp) 0 else 1;
}

pub export fn netrunner_turn(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(game.turn);
}

pub export fn netrunner_active_player(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return -1;
    return if (game.active_player == .corp) 0 else 1;
}

// ============================================================
// Actions
// ============================================================

pub export fn netrunner_num_actions(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(game.legal_actions.len);
}

pub export fn netrunner_apply_action(handle: ?*anyopaque, index: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return -1;
    if (index < 0 or @as(usize, @intCast(index)) >= game.legal_actions.len) return -2;
    engine.applyAction(game, game.legal_actions[@intCast(index)]) catch return -3;
    return 0;
}

pub export fn netrunner_action_description(handle: ?*anyopaque, index: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (index < 0 or @as(usize, @intCast(index)) >= game.legal_actions.len) return 0;
    const action = game.legal_actions[@intCast(index)];
    var tmp: [256]u8 = undefined;
    const desc = format_action(game, action, &tmp);
    return write_str(buf, buf_size, desc);
}

fn findRunServerIce(game: *Game, run: state.RunState, ice_idx: u8) ?[]const u8 {
    for (game.corp_servers.items) |server| {
        if (run.server.matchesName(server.name)) {
            if (ice_idx < server.ices.items.len) return server.ices.items[ice_idx].title;
        }
    }
    return null;
}

fn resolve_choice_card_title(game: *Game, action: state.LegalAction) ?[]const u8 {
    // Advance/score choices encode "server|zone|index" in choice text
    const choice = action.choice orelse return null;
    const text = choice.text orelse return null;

    // Parse "servername|i|0" or "servername|c|0"
    var it = std.mem.splitScalar(u8, text, '|');
    const server_name = it.next() orelse return null;
    const zone = it.next() orelse return null;
    const idx_str = it.next() orelse return null;
    const idx = std.fmt.parseInt(usize, idx_str, 10) catch return null;

    for (game.corp_servers.items) |server| {
        if (!std.mem.eql(u8, server.name, server_name)) continue;
        if (std.mem.eql(u8, zone, "i")) {
            if (idx < server.ices.items.len) return server.ices.items[idx].title;
        } else if (std.mem.eql(u8, zone, "c")) {
            if (idx < server.content.items.len) return server.content.items[idx].title;
        }
    }
    return null;
}

fn format_action(game: *Game, action: state.LegalAction, buf: *[256]u8) []const u8 {
    return switch (action.kind) {
        .prompt_choice => blk: {
            if (action.label) |label| break :blk label;
            const pt = action.prompt_type;
            const prefix: []const u8 = if (pt == .discard)
                "Discard: "
            else if (pt == .install_destination)
                "Install in: "
            else if (pt == .access_choice)
                "Access: "
            else if (pt == .run_target)
                "Run: "
            else
                "";
            // For access prompts, include the source card name
            if (pt == .access_choice) {
                const source_title = if (game.runner_prompt_state) |ps| if (ps.source_card) |sc| sc.title else null else null;
                if (action.choice) |c| {
                    if (c.text) |t| {
                        if (source_title) |st| {
                            break :blk std.fmt.bufPrint(buf, "{s}{s} ({s})", .{ prefix, t, st }) catch t;
                        }
                        break :blk std.fmt.bufPrint(buf, "{s}{s}", .{ prefix, t }) catch t;
                    }
                }
            }
            if (action.choice) |c| {
                if (c.card) |card| {
                    if (card.title) |t| {
                        if (prefix.len > 0) break :blk std.fmt.bufPrint(buf, "{s}{s}", .{ prefix, t }) catch t;
                        break :blk t;
                    }
                }
                if (c.text) |t| {
                    if (prefix.len > 0) break :blk std.fmt.bufPrint(buf, "{s}{s}", .{ prefix, t }) catch t;
                    break :blk t;
                }
            }
            if (pt) |p| {
                break :blk std.fmt.bufPrint(buf, "({s})", .{p.toStr()}) catch "?";
            }
            break :blk "?";
        },
        .@"continue" => blk: {
            // Show what we're continuing (approach ice, access, etc.)
            if (action.prompt_type) |pt| {
                if (pt != .run) {
                    break :blk std.fmt.bufPrint(buf, "Continue ({s})", .{pt.toStr()}) catch "Continue";
                }
            }
            break :blk "Continue";
        },
        .start_turn => blk: {
            break :blk std.fmt.bufPrint(buf, "Start Turn ({s})", .{
                if (action.side == .corp) "Corp" else "Runner",
            }) catch "Start Turn";
        },
        .end_turn => "End Turn",
        .jack_out => "Jack Out",
        .run => std.fmt.bufPrint(buf, "Run {s}", .{action.server orelse "?"}) catch "Run",
        .install_from_hand => std.fmt.bufPrint(buf, "Install: {s}", .{action.card_title orelse "?"}) catch "Install",
        .play_from_hand => std.fmt.bufPrint(buf, "Play: {s}", .{action.card_title orelse "?"}) catch "Play",
        .use_ability => blk: {
            const ba = action.basic_action orelse break :blk "Use ability";
            break :blk switch (ba) {
                .gain_credit => "Gain 1 credit",
                .draw_card => "Draw 1 card",
                .install_from_grip => "Install from grip",
                .advance_installed => "Advance installed",
                .score_agenda => "Score agenda",
                .purge_viruses => "Purge virus counters",
                .run_any_server => "Run any server",
                .remove_tag => "Remove 1 tag",
            };
        },
        .use_installed_ability => std.fmt.bufPrint(buf, "Use: {s}", .{action.card_title orelse "?"}) catch "Use ability",
        .use_corp_ability => std.fmt.bufPrint(buf, "Corp: {s}", .{action.card_title orelse "?"}) catch "Corp ability",
        .use_runner_ability => std.fmt.bufPrint(buf, "Break: {s}", .{action.label orelse action.card_title orelse "?"}) catch "Break",
        .use_subroutine => std.fmt.bufPrint(buf, "Sub: {s}", .{action.label orelse "?"}) catch "Subroutine",
        .rez_ice => blk: {
            // Approached ICE — resolve from run state
            const title = action.card_title orelse if (game.run) |run| ice_title: {
                if (run.current_ice_index) |idx| {
                    const srv = findRunServerIce(game, run, idx);
                    if (srv) |t| break :ice_title t;
                }
                break :ice_title "ICE";
            } else "ICE";
            break :blk std.fmt.bufPrint(buf, "Rez ICE: {s}", .{title}) catch "Rez ICE";
        },
        .rez_non_ice => std.fmt.bufPrint(buf, "Rez: {s}", .{action.card_title orelse "?"}) catch "Rez",
        .advance => blk: {
            const title = action.card_title orelse resolve_choice_card_title(game, action) orelse "?";
            break :blk std.fmt.bufPrint(buf, "Advance: {s}", .{title}) catch "Advance";
        },
        .score => blk: {
            const title = action.card_title orelse resolve_choice_card_title(game, action) orelse "?";
            break :blk std.fmt.bufPrint(buf, "Score: {s}", .{title}) catch "Score";
        },
        .flashback => std.fmt.bufPrint(buf, "Flashback: {s}", .{action.card_title orelse "?"}) catch "Flashback",
        .use_identity_ability => std.fmt.bufPrint(buf, "ID: {s}", .{action.label orelse action.card_title orelse "?"}) catch "ID ability",
    };
}

// ============================================================
// Card code from action (for card preview lookup)
// ============================================================

/// Returns the most relevant card code for display, considering:
/// 1. The selected action's card
/// 2. The currently encountered ICE
/// 3. The card being accessed
/// 4. The prompt source card
pub export fn netrunner_context_card_code(handle: ?*anyopaque, action_index: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;

    // First try the selected action's card
    if (action_index >= 0 and @as(usize, @intCast(action_index)) < game.legal_actions.len) {
        const code = resolve_card_code(game, game.legal_actions[@intCast(action_index)]);
        if (code > 0) return code;
    }

    // During a run: show currently encountered/approached ICE
    if (game.run) |run| {
        if (run.current_ice_index) |ice_idx| {
            if (find_run_server_ice_code(game, run, ice_idx)) |code| return @intCast(code);
        }
        // Show accessed card
        if (run.access_card_index) |_| {
            // Access card is from the prompt source
            const ps = game.runner_prompt_state orelse game.corp_prompt_state;
            if (ps) |prompt| {
                if (prompt.source_card) |sc| {
                    if (sc.code) |code| return @intCast(code);
                }
            }
        }
    }

    // Show prompt source card
    const deciding = game.decision_side;
    const ps = if (deciding == .corp) game.corp_prompt_state else game.runner_prompt_state;
    if (ps) |prompt| {
        if (prompt.source_card) |sc| {
            if (sc.code) |code| return @intCast(code);
        }
    }

    return 0;
}

fn find_run_server_ice_code(game: *Game, run: state.RunState, ice_idx: u8) ?u32 {
    for (game.corp_servers.items) |server| {
        if (run.server.matchesName(server.name)) {
            if (ice_idx < server.ices.items.len) {
                return server.ices.items[ice_idx].code;
            }
        }
    }
    return null;
}

pub export fn netrunner_action_card_code(handle: ?*anyopaque, index: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (index < 0 or @as(usize, @intCast(index)) >= game.legal_actions.len) return 0;
    const action = game.legal_actions[@intCast(index)];
    return resolve_card_code(game, action);
}

fn resolve_card_code(game: *Game, action: state.LegalAction) c_int {
    // For hand actions, look up by card_index in the appropriate hand
    if (action.card_index) |ci| {
        switch (action.kind) {
            .install_from_hand, .play_from_hand => {
                if (action.side == .corp) {
                    if (ci < game.corp_hand.items.len) {
                        if (game.corp_hand.items[ci].code) |code| return @intCast(code);
                    }
                } else {
                    if (ci < game.runner_hand.items.len) {
                        if (game.runner_hand.items[ci].code) |code| return @intCast(code);
                    }
                }
            },
            .use_installed_ability => {
                // card_index is combined: resources[0..R], programs[R..R+P], hardware[R+P..]
                const res_len = game.runner_rig_resources.items.len;
                const prog_len = game.runner_rig_program.items.len;
                if (ci < res_len) {
                    if (game.runner_rig_resources.items[ci].code) |code| return @intCast(code);
                } else if (ci < res_len + prog_len) {
                    if (game.runner_rig_program.items[ci - res_len].code) |code| return @intCast(code);
                } else if (ci < res_len + prog_len + game.runner_rig_hardware.items.len) {
                    if (game.runner_rig_hardware.items[ci - res_len - prog_len].code) |code| return @intCast(code);
                }
            },
            .rez_non_ice => {
                // card_index is content index within a server
                if (action.server) |srv| {
                    for (game.corp_servers.items) |server| {
                        if (std.mem.eql(u8, server.name, srv)) {
                            if (ci < server.content.items.len) {
                                if (server.content.items[ci].code) |code| return @intCast(code);
                            }
                            break;
                        }
                    }
                }
            },
            else => {},
        }
    }

    // For prompt choices referencing a card
    if (action.choice) |choice| {
        if (choice.card) |card_ref| {
            if (card_ref.code) |code| return @intCast(code);
        }
    }

    // For advance/score/rez — resolve card from encoded "server|zone|index" choice
    if (action.kind == .advance or action.kind == .score or
        action.kind == .rez_non_ice or action.kind == .rez_ice)
    {
        if (resolve_choice_card_code(game, action)) |code| return @intCast(code);
    }

    // Fall back to title search across all zones
    const title = action.card_title orelse return 0;
    return find_code_by_title(game, title);
}

fn resolve_choice_card_code(game: *Game, action: state.LegalAction) ?u32 {
    const choice = action.choice orelse return null;
    const text = choice.text orelse return null;

    var it = std.mem.splitScalar(u8, text, '|');
    const server_name = it.next() orelse return null;
    const zone = it.next() orelse return null;
    const idx_str = it.next() orelse return null;
    const idx = std.fmt.parseInt(usize, idx_str, 10) catch return null;

    for (game.corp_servers.items) |server| {
        if (!std.mem.eql(u8, server.name, server_name)) continue;
        if (std.mem.eql(u8, zone, "i")) {
            if (idx < server.ices.items.len) return server.ices.items[idx].code;
        } else if (std.mem.eql(u8, zone, "c")) {
            if (idx < server.content.items.len) return server.content.items[idx].code;
        }
    }
    return null;
}

fn find_code_by_title(game: *Game, title: []const u8) c_int {
    // Search identities
    if (std.mem.eql(u8, game.corp_identity.title, title)) {
        if (game.corp_identity.code) |c| return @intCast(c);
    }
    if (std.mem.eql(u8, game.runner_identity.title, title)) {
        if (game.runner_identity.code) |c| return @intCast(c);
    }
    // Search hands
    for (game.corp_hand.items) |card| {
        if (std.mem.eql(u8, card.title, title)) {
            if (card.code) |c| return @intCast(c);
        }
    }
    for (game.runner_hand.items) |card| {
        if (std.mem.eql(u8, card.title, title)) {
            if (card.code) |c| return @intCast(c);
        }
    }
    // Search rig
    for (game.runner_rig_program.items) |card| {
        if (std.mem.eql(u8, card.title, title)) {
            if (card.code) |c| return @intCast(c);
        }
    }
    for (game.runner_rig_hardware.items) |card| {
        if (std.mem.eql(u8, card.title, title)) {
            if (card.code) |c| return @intCast(c);
        }
    }
    for (game.runner_rig_resources.items) |card| {
        if (std.mem.eql(u8, card.title, title)) {
            if (card.code) |c| return @intCast(c);
        }
    }
    // Search servers (ICE + content)
    for (game.corp_servers.items) |server| {
        for (server.ices.items) |card| {
            if (std.mem.eql(u8, card.title, title)) {
                if (card.code) |c| return @intCast(c);
            }
        }
        for (server.content.items) |card| {
            if (std.mem.eql(u8, card.title, title)) {
                if (card.code) |c| return @intCast(c);
            }
        }
    }
    // Search scored areas
    for (game.corp_scored.items) |card| {
        if (std.mem.eql(u8, card.title, title)) {
            if (card.code) |c| return @intCast(c);
        }
    }
    for (game.runner_scored.items) |card| {
        if (std.mem.eql(u8, card.title, title)) {
            if (card.code) |c| return @intCast(c);
        }
    }
    return 0;
}

// Card codes for hand/rig/server cards
pub export fn netrunner_hand_card_code(handle: ?*anyopaque, player: c_int, idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (player == 0) {
        if (idx < 0 or @as(usize, @intCast(idx)) >= game.corp_hand.items.len) return 0;
        return @intCast(game.corp_hand.items[@intCast(idx)].code orelse 0);
    } else {
        if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_hand.items.len) return 0;
        return @intCast(game.runner_hand.items[@intCast(idx)].code orelse 0);
    }
}

pub export fn netrunner_identity_code(handle: ?*anyopaque, player: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (player == 0) return @intCast(game.corp_identity.code orelse 0);
    return @intCast(game.runner_identity.code orelse 0);
}

pub export fn netrunner_server_ice_code(handle: ?*anyopaque, server_idx: c_int, ice_idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (server_idx < 0 or @as(usize, @intCast(server_idx)) >= game.corp_servers.items.len) return 0;
    const server = game.corp_servers.items[@intCast(server_idx)];
    if (ice_idx < 0 or @as(usize, @intCast(ice_idx)) >= server.ices.items.len) return 0;
    return @intCast(server.ices.items[@intCast(ice_idx)].code orelse 0);
}

pub export fn netrunner_server_content_code(handle: ?*anyopaque, server_idx: c_int, card_idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (server_idx < 0 or @as(usize, @intCast(server_idx)) >= game.corp_servers.items.len) return 0;
    const server = game.corp_servers.items[@intCast(server_idx)];
    if (card_idx < 0 or @as(usize, @intCast(card_idx)) >= server.content.items.len) return 0;
    return @intCast(server.content.items[@intCast(card_idx)].code orelse 0);
}

pub export fn netrunner_rig_program_code(handle: ?*anyopaque, idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_rig_program.items.len) return 0;
    return @intCast(game.runner_rig_program.items[@intCast(idx)].code orelse 0);
}

pub export fn netrunner_rig_hardware_code(handle: ?*anyopaque, idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_rig_hardware.items.len) return 0;
    return @intCast(game.runner_rig_hardware.items[@intCast(idx)].code orelse 0);
}

pub export fn netrunner_rig_resource_code(handle: ?*anyopaque, idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_rig_resources.items.len) return 0;
    return @intCast(game.runner_rig_resources.items[@intCast(idx)].code orelse 0);
}

// ============================================================
// Card counters
// ============================================================

pub export fn netrunner_server_content_adv(handle: ?*anyopaque, server_idx: c_int, card_idx: c_int) callconv(.c) c_int {
    const card = get_server_content(handle, server_idx, card_idx) orelse return 0;
    return card.advancement_counter;
}

pub export fn netrunner_server_content_adv_req(handle: ?*anyopaque, server_idx: c_int, card_idx: c_int) callconv(.c) c_int {
    const card = get_server_content(handle, server_idx, card_idx) orelse return 0;
    return @intCast(card.advancement_requirement orelse 0);
}

pub export fn netrunner_server_content_credits(handle: ?*anyopaque, server_idx: c_int, card_idx: c_int) callconv(.c) c_int {
    const card = get_server_content(handle, server_idx, card_idx) orelse return 0;
    return @intCast(card.credit_counter);
}

pub export fn netrunner_server_ice_adv(handle: ?*anyopaque, server_idx: c_int, ice_idx: c_int) callconv(.c) c_int {
    const card = get_server_ice(handle, server_idx, ice_idx) orelse return 0;
    return card.advancement_counter;
}

pub export fn netrunner_rig_program_virus(handle: ?*anyopaque, idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_rig_program.items.len) return 0;
    return @intCast(game.runner_rig_program.items[@intCast(idx)].virus_counter);
}

pub export fn netrunner_rig_resource_credits(handle: ?*anyopaque, idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_rig_resources.items.len) return 0;
    return @intCast(game.runner_rig_resources.items[@intCast(idx)].credit_counter);
}

fn get_server_content(handle: ?*anyopaque, server_idx: c_int, card_idx: c_int) ?state.CardInstance {
    const game = get_game(handle) orelse return null;
    if (server_idx < 0 or @as(usize, @intCast(server_idx)) >= game.corp_servers.items.len) return null;
    const server = game.corp_servers.items[@intCast(server_idx)];
    if (card_idx < 0 or @as(usize, @intCast(card_idx)) >= server.content.items.len) return null;
    return server.content.items[@intCast(card_idx)];
}

fn get_server_ice(handle: ?*anyopaque, server_idx: c_int, ice_idx: c_int) ?state.CardInstance {
    const game = get_game(handle) orelse return null;
    if (server_idx < 0 or @as(usize, @intCast(server_idx)) >= game.corp_servers.items.len) return null;
    const server = game.corp_servers.items[@intCast(server_idx)];
    if (ice_idx < 0 or @as(usize, @intCast(ice_idx)) >= server.ices.items.len) return null;
    return server.ices.items[@intCast(ice_idx)];
}

// ============================================================
// Card info lookup (from embedded JSON data)
// ============================================================

const card_json = @embedFile("data/cards.json");

pub const CardInfo = struct {
    code: u32,
    title: []const u8,
    card_type: []const u8,
    side: []const u8,
    faction: []const u8,
    cost: ?i32,
    strength: ?i32,
    mu: ?i32,
    trash_cost: ?i32,
    agenda_points: ?i32,
    adv_req: ?i32,
    text: []const u8,
    image_url: []const u8,
};

var card_db: ?[]const CardInfo = null;

fn get_card_db() []const CardInfo {
    if (card_db) |db| return db;

    const parsed = std.json.parseFromSlice([]const struct {
        code: i64,
        title: []const u8,
        type: []const u8,
        side: []const u8,
        faction: []const u8,
        cost: ?i64 = null,
        strength: ?i64 = null,
        mu: ?i64 = null,
        trash_cost: ?i64 = null,
        agenda_points: ?i64 = null,
        adv_req: ?i64 = null,
        text: ?[]const u8 = null,
        image_url: ?[]const u8 = null,
    }, backing_allocator, card_json, .{ .allocate = .alloc_always }) catch return &.{};

    const items = backing_allocator.alloc(CardInfo, parsed.value.len) catch return &.{};
    for (parsed.value, 0..) |entry, i| {
        items[i] = .{
            .code = @intCast(entry.code),
            .title = entry.title,
            .card_type = entry.type,
            .side = entry.side,
            .faction = entry.faction,
            .cost = if (entry.cost) |c| @intCast(c) else null,
            .strength = if (entry.strength) |s| @intCast(s) else null,
            .mu = if (entry.mu) |m| @intCast(m) else null,
            .trash_cost = if (entry.trash_cost) |t| @intCast(t) else null,
            .agenda_points = if (entry.agenda_points) |a| @intCast(a) else null,
            .adv_req = if (entry.adv_req) |a| @intCast(a) else null,
            .text = entry.text orelse "",
            .image_url = entry.image_url orelse "",
        };
    }
    card_db = items;
    return items;
}

pub fn lookup_card(code: u32) ?*const CardInfo {
    const db = get_card_db();
    for (db) |*card| {
        if (card.code == code) return card;
    }
    return null;
}

pub export fn netrunner_card_text(code: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    if (code <= 0) return 0;
    const card = lookup_card(@intCast(code)) orelse return 0;
    return write_str(buf, buf_size, card.text);
}

pub export fn netrunner_card_type(code: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    if (code <= 0) return 0;
    const card = lookup_card(@intCast(code)) orelse return 0;
    return write_str(buf, buf_size, card.card_type);
}

pub export fn netrunner_card_faction(code: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    if (code <= 0) return 0;
    const card = lookup_card(@intCast(code)) orelse return 0;
    return write_str(buf, buf_size, card.faction);
}

pub export fn netrunner_card_cost(code: c_int) callconv(.c) c_int {
    if (code <= 0) return -1;
    const card = lookup_card(@intCast(code)) orelse return -1;
    return card.cost orelse -1;
}

pub export fn netrunner_card_strength(code: c_int) callconv(.c) c_int {
    if (code <= 0) return -1;
    const card = lookup_card(@intCast(code)) orelse return -1;
    return card.strength orelse -1;
}

pub export fn netrunner_card_mu(code: c_int) callconv(.c) c_int {
    if (code <= 0) return -1;
    const card = lookup_card(@intCast(code)) orelse return -1;
    return card.mu orelse -1;
}

pub export fn netrunner_card_image_url(code: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    if (code <= 0) return 0;
    const card = lookup_card(@intCast(code)) orelse return 0;
    return write_str(buf, buf_size, card.image_url);
}

// ============================================================
// Player state
// ============================================================

pub export fn netrunner_player_credits(handle: ?*anyopaque, player: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(if (player == 0) game.corp_credit else game.runner_credit);
}

pub export fn netrunner_player_clicks(handle: ?*anyopaque, player: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(if (player == 0) game.corp_click else game.runner_click);
}

pub export fn netrunner_player_hand_size(handle: ?*anyopaque, player: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (player == 0) return @intCast(game.corp_hand.items.len);
    return @intCast(game.runner_hand.items.len);
}

pub export fn netrunner_player_deck_size(handle: ?*anyopaque, player: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (player == 0) return @intCast(game.corp_deck.items.len);
    return @intCast(game.runner_deck.items.len);
}

pub export fn netrunner_player_discard_size(handle: ?*anyopaque, player: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (player == 0) return @intCast(game.corp_discard.items.len);
    return @intCast(game.runner_discard.items.len);
}

pub export fn netrunner_player_score(handle: ?*anyopaque, player: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(if (player == 0) game.corp_agenda_point else game.runner_agenda_point);
}

pub export fn netrunner_player_score_req(handle: ?*anyopaque, player: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 7;
    return @intCast(if (player == 0) game.corp_agenda_point_req else game.runner_agenda_point_req);
}

pub export fn netrunner_identity_name(handle: ?*anyopaque, player: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const title = if (player == 0) game.corp_identity.title else game.runner_identity.title;
    return write_str(buf, buf_size, title);
}

// Runner-specific
pub export fn netrunner_runner_mu_used(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const mem = game.runner_memory orelse return 0;
    return @intCast(mem.used);
}

pub export fn netrunner_runner_mu_available(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const mem = game.runner_memory orelse return 0;
    return @intCast(mem.available);
}

pub export fn netrunner_runner_link(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(game.runner_link);
}

pub export fn netrunner_runner_tags(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const tag = game.runner_tag orelse return 0;
    return @intCast(tag.total);
}

pub export fn netrunner_runner_run_credits(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(game.runner_run_credit);
}

// Corp-specific
pub export fn netrunner_corp_bad_pub(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const bp = game.corp_bad_publicity orelse return 0;
    return @intCast(bp.base + bp.additional);
}

// ============================================================
// Board inspection — servers
// ============================================================

pub export fn netrunner_server_count(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(game.corp_servers.items.len);
}

pub export fn netrunner_server_name(handle: ?*anyopaque, idx: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.corp_servers.items.len) return 0;
    return write_str(buf, buf_size, game.corp_servers.items[@intCast(idx)].name);
}

pub export fn netrunner_server_ice_count(handle: ?*anyopaque, idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.corp_servers.items.len) return 0;
    return @intCast(game.corp_servers.items[@intCast(idx)].ices.items.len);
}

pub export fn netrunner_server_ice_name(handle: ?*anyopaque, server_idx: c_int, ice_idx: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (server_idx < 0 or @as(usize, @intCast(server_idx)) >= game.corp_servers.items.len) return 0;
    const server = game.corp_servers.items[@intCast(server_idx)];
    if (ice_idx < 0 or @as(usize, @intCast(ice_idx)) >= server.ices.items.len) return 0;
    return write_str(buf, buf_size, server.ices.items[@intCast(ice_idx)].title);
}

pub export fn netrunner_server_ice_rezzed(handle: ?*anyopaque, server_idx: c_int, ice_idx: c_int) callconv(.c) bool {
    const game = get_game(handle) orelse return false;
    if (server_idx < 0 or @as(usize, @intCast(server_idx)) >= game.corp_servers.items.len) return false;
    const server = game.corp_servers.items[@intCast(server_idx)];
    if (ice_idx < 0 or @as(usize, @intCast(ice_idx)) >= server.ices.items.len) return false;
    return server.ices.items[@intCast(ice_idx)].rezzed;
}

pub export fn netrunner_server_ice_strength(handle: ?*anyopaque, server_idx: c_int, ice_idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return -1;
    if (server_idx < 0 or ice_idx < 0) return -1;
    const strength = engine.effectiveIceStrengthForDisplay(
        game,
        @intCast(server_idx),
        @intCast(ice_idx),
    ) orelse return -1;
    return @intCast(strength);
}

pub export fn netrunner_server_content_count(handle: ?*anyopaque, idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.corp_servers.items.len) return 0;
    return @intCast(game.corp_servers.items[@intCast(idx)].content.items.len);
}

pub export fn netrunner_server_content_name(handle: ?*anyopaque, server_idx: c_int, card_idx: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (server_idx < 0 or @as(usize, @intCast(server_idx)) >= game.corp_servers.items.len) return 0;
    const server = game.corp_servers.items[@intCast(server_idx)];
    if (card_idx < 0 or @as(usize, @intCast(card_idx)) >= server.content.items.len) return 0;
    return write_str(buf, buf_size, server.content.items[@intCast(card_idx)].title);
}

pub export fn netrunner_server_content_rezzed(handle: ?*anyopaque, server_idx: c_int, card_idx: c_int) callconv(.c) bool {
    const game = get_game(handle) orelse return false;
    if (server_idx < 0 or @as(usize, @intCast(server_idx)) >= game.corp_servers.items.len) return false;
    const server = game.corp_servers.items[@intCast(server_idx)];
    if (card_idx < 0 or @as(usize, @intCast(card_idx)) >= server.content.items.len) return false;
    return server.content.items[@intCast(card_idx)].rezzed;
}

// ============================================================
// Board inspection — runner rig
// ============================================================

pub export fn netrunner_rig_program_count(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(game.runner_rig_program.items.len);
}

pub export fn netrunner_rig_hardware_count(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(game.runner_rig_hardware.items.len);
}

pub export fn netrunner_rig_resource_count(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(game.runner_rig_resources.items.len);
}

pub export fn netrunner_rig_program_name(handle: ?*anyopaque, idx: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_rig_program.items.len) return 0;
    return write_str(buf, buf_size, game.runner_rig_program.items[@intCast(idx)].title);
}

pub export fn netrunner_rig_program_strength(handle: ?*anyopaque, idx: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return -1;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_rig_program.items.len) return -1;
    const card = game.runner_rig_program.items[@intCast(idx)];
    if (card.strength == null and card.current_strength == null) return -1;
    return @intCast(engine.effectiveStrength(card));
}

pub export fn netrunner_rig_hardware_name(handle: ?*anyopaque, idx: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_rig_hardware.items.len) return 0;
    return write_str(buf, buf_size, game.runner_rig_hardware.items[@intCast(idx)].title);
}

pub export fn netrunner_rig_resource_name(handle: ?*anyopaque, idx: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_rig_resources.items.len) return 0;
    return write_str(buf, buf_size, game.runner_rig_resources.items[@intCast(idx)].title);
}

// ============================================================
// Hand contents (local play — both sides visible)
// ============================================================

pub export fn netrunner_hand_card_name(handle: ?*anyopaque, player: c_int, idx: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (player == 0) {
        if (idx < 0 or @as(usize, @intCast(idx)) >= game.corp_hand.items.len) return 0;
        return write_str(buf, buf_size, game.corp_hand.items[@intCast(idx)].title);
    } else {
        if (idx < 0 or @as(usize, @intCast(idx)) >= game.runner_hand.items.len) return 0;
        return write_str(buf, buf_size, game.runner_hand.items[@intCast(idx)].title);
    }
}

// ============================================================
// Run state
// ============================================================

pub export fn netrunner_is_run_active(handle: ?*anyopaque) callconv(.c) bool {
    const game = get_game(handle) orelse return false;
    return game.run != null;
}

pub export fn netrunner_run_server(handle: ?*anyopaque, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const run = game.run orelse return 0;
    switch (run.server) {
        .hq => return write_str(buf, buf_size, "hq"),
        .rnd => return write_str(buf, buf_size, "rnd"),
        .archives => return write_str(buf, buf_size, "archives"),
        .remote => |n| {
            var tmp: [16]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "remote{d}", .{n}) catch return 0;
            return write_str(buf, buf_size, s);
        },
    }
}

pub export fn netrunner_run_phase(handle: ?*anyopaque, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const run = game.run orelse return 0;
    return write_str(buf, buf_size, run.phase.toStr());
}

pub export fn netrunner_run_position(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return -1;
    const run = game.run orelse return -1;
    return @intCast(run.position);
}

// ============================================================
// Prompt state
// ============================================================

pub export fn netrunner_prompt_type(handle: ?*anyopaque, player: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const ps = if (player == 0) game.corp_prompt_state else game.runner_prompt_state;
    const prompt = ps orelse return 0;
    return write_str(buf, buf_size, prompt.prompt_type.toStr());
}

pub export fn netrunner_prompt_source(handle: ?*anyopaque, player: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const ps = if (player == 0) game.corp_prompt_state else game.runner_prompt_state;
    const prompt = ps orelse return 0;
    const card = prompt.source_card orelse return 0;
    return write_str(buf, buf_size, card.title);
}

// ============================================================
// Game log
// ============================================================

pub export fn netrunner_log_count(handle: ?*anyopaque) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    return @intCast(game.log_entries.len);
}

pub export fn netrunner_log_side(handle: ?*anyopaque, index: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return -1;
    if (index < 0 or @as(usize, @intCast(index)) >= game.log_entries.len) return -1;
    return if (game.log_entries.get(@intCast(index)).side == .corp) 0 else 1;
}

pub export fn netrunner_log_text(handle: ?*anyopaque, index: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (index < 0 or @as(usize, @intCast(index)) >= game.log_entries.len) return 0;
    return write_str(buf, buf_size, game.log_entries.get(@intCast(index)).text);
}

pub export fn netrunner_log_card_code(handle: ?*anyopaque, index: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    if (index < 0 or @as(usize, @intCast(index)) >= game.log_entries.len) return 0;
    return @intCast(game.log_entries.get(@intCast(index)).card_code);
}

// ============================================================
// Scored cards
// ============================================================

pub export fn netrunner_scored_count(handle: ?*anyopaque, player: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const scored = if (player == 0) game.corp_scored.items else game.runner_scored.items;
    return @intCast(scored.len);
}

pub export fn netrunner_scored_name(handle: ?*anyopaque, player: c_int, index: c_int, buf: [*c]u8, buf_size: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const scored = if (player == 0) game.corp_scored.items else game.runner_scored.items;
    if (index < 0 or @as(usize, @intCast(index)) >= scored.len) return 0;
    return write_str(buf, buf_size, scored[@intCast(index)].title);
}

pub export fn netrunner_scored_code(handle: ?*anyopaque, player: c_int, index: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const scored = if (player == 0) game.corp_scored.items else game.runner_scored.items;
    if (index < 0 or @as(usize, @intCast(index)) >= scored.len) return 0;
    return @intCast(scored[@intCast(index)].code orelse 0);
}

pub export fn netrunner_scored_points(handle: ?*anyopaque, player: c_int, index: c_int) callconv(.c) c_int {
    const game = get_game(handle) orelse return 0;
    const scored = if (player == 0) game.corp_scored.items else game.runner_scored.items;
    if (index < 0 or @as(usize, @intCast(index)) >= scored.len) return 0;
    return @intCast(scored[@intCast(index)].agenda_points orelse 0);
}
