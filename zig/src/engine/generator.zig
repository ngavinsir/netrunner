const std = @import("std");
const matchups = @import("matchups.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");

pub const GeneratedSnapshot = struct {
    arena: std.heap.ArenaAllocator,
    snapshot: state.SetupSnapshot,

    pub fn deinit(self: *GeneratedSnapshot) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

const corp_basic_action = matchups.CardSpec{
    .title = "Corp Basic Action Card",
    .side = .corp,
    .card_type = "Basic Action",
};

const runner_basic_action = matchups.CardSpec{
    .title = "Runner Basic Action Card",
    .side = .runner,
    .card_type = "Basic Action",
};

pub fn createInitialSnapshot(
    backing_allocator: std.mem.Allocator,
    matchup: matchups.MatchupSpec,
    seed: state.Seed,
) !GeneratedSnapshot {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();

    const allocator = arena.allocator();
    var rng_state = rng.init(seed);

    const corp_full_deck = try buildDeck(allocator, &rng_state, matchup.corp);
    const runner_full_deck = try buildDeck(allocator, &rng_state, matchup.runner);

    const corp_hand = try cloneCards(allocator, corp_full_deck[0..5]);
    const corp_deck = try cloneCards(allocator, corp_full_deck[5..]);
    const runner_hand = try cloneCards(allocator, runner_full_deck[0..5]);
    const runner_deck = try cloneCards(allocator, runner_full_deck[5..]);

    const mulligan_prompt = try dupPromptChoices(allocator);
    const legal_actions = try allocator.alloc(state.LegalAction, 2);
    legal_actions[0] = .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = try allocator.dupe(u8, "mulligan"),
        .choice = stringChoice("Keep"),
    };
    legal_actions[1] = .{
        .kind = .prompt_choice,
        .side = .corp,
        .prompt_type = try allocator.dupe(u8, "mulligan"),
        .choice = stringChoice("Mulligan"),
    };

    return .{
        .arena = arena,
        .snapshot = .{
            .state = .{
                .format = try allocator.dupe(u8, matchup.format),
                .seed = seed,
                .rng_seed = rng.oracleSeed(rng_state),
                .active_player = .runner,
                .turn = 0,
                .end_turn = true,
                .corp = .{
                    .identity = try makeCardInstance(allocator, matchup.corp.identity),
                    .basic_action_card = try makeCardInstance(allocator, corp_basic_action),
                    .click = 0,
                    .click_per_turn = 3,
                    .credit = 5,
                    .agenda_point = 0,
                    .agenda_point_req = matchup.agenda_point_req,
                    .hand_size = .{ .base = 5, .total = 5 },
                    .bad_publicity = .{ .base = 0, .additional = 0 },
                    .run_credit = 0,
                    .link = 0,
                    .tag = null,
                    .memory = null,
                    .brain_damage = 0,
                    .keep = .undecided,
                    .prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "mulligan"),
                        .choices = mulligan_prompt,
                    },
                    .deck = corp_deck,
                    .hand = corp_hand,
                    .discard = &.{},
                },
                .runner = .{
                    .identity = try makeCardInstance(allocator, matchup.runner.identity),
                    .basic_action_card = try makeCardInstance(allocator, runner_basic_action),
                    .click = 0,
                    .click_per_turn = 4,
                    .credit = 5,
                    .agenda_point = 0,
                    .agenda_point_req = matchup.agenda_point_req,
                    .hand_size = .{ .base = 5, .total = 5 },
                    .bad_publicity = null,
                    .run_credit = 0,
                    .link = 0,
                    .tag = .{ .base = 0, .total = 0, .is_tagged = false },
                    .memory = .{
                        .base = 4,
                        .available = 4,
                        .used = 0,
                    },
                    .brain_damage = 0,
                    .keep = .undecided,
                    .prompt_state = .{
                        .prompt_type = try allocator.dupe(u8, "waiting"),
                        .choices = &.{},
                    },
                    .deck = runner_deck,
                    .hand = runner_hand,
                    .discard = &.{},
                },
            },
            .decision_side = .corp,
            .legal_actions = legal_actions,
        },
    };
}

fn buildDeck(
    allocator: std.mem.Allocator,
    rng_state: *rng.RngState,
    side_spec: matchups.SideSpec,
) ![]state.CardInstance {
    const shuffled_lines = try allocator.dupe(matchups.DeckLine, side_spec.deck_lines);
    rng.shuffleInPlace(matchups.DeckLine, rng_state, shuffled_lines);

    const total_cards = countCards(shuffled_lines);
    const cards = try allocator.alloc(state.CardInstance, total_cards);

    var idx: usize = 0;
    for (shuffled_lines) |line| {
        var copy_idx: state.TinyCount = 0;
        while (copy_idx < line.qty) : (copy_idx += 1) {
            cards[idx] = try makeCardInstance(allocator, .{
                .title = line.title,
                .side = side_spec.identity.side,
            });
            idx += 1;
        }
    }

    rng.shuffleInPlace(state.CardInstance, rng_state, cards);
    return cards;
}

fn cloneCards(
    allocator: std.mem.Allocator,
    cards: []const state.CardInstance,
) ![]state.CardInstance {
    const copy = try allocator.alloc(state.CardInstance, cards.len);
    @memcpy(copy, cards);
    return copy;
}

fn countCards(lines: []const matchups.DeckLine) usize {
    var total: usize = 0;
    for (lines) |line| total += line.qty;
    return total;
}

fn dupPromptChoices(allocator: std.mem.Allocator) ![]const state.PromptChoice {
    const choices = try allocator.alloc(state.PromptChoice, 2);
    choices[0] = stringChoice("Keep");
    choices[1] = stringChoice("Mulligan");
    return choices;
}

fn stringChoice(text: []const u8) state.PromptChoice {
    return .{
        .kind = .string,
        .text = text,
    };
}

fn makeCardInstance(
    allocator: std.mem.Allocator,
    spec: matchups.CardSpec,
) !state.CardInstance {
    return .{
        .title = try allocator.dupe(u8, spec.title),
        .printed_title = try allocator.dupe(u8, spec.title),
        .code = spec.code,
        .side = spec.side,
        .card_type = if (spec.card_type) |kind| try allocator.dupe(u8, kind) else null,
    };
}
