const std = @import("std");
const generator = @import("generator.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");

pub fn applyMulliganChoice(
    generated: *generator.GeneratedSnapshot,
    side: state.Side,
    choice: state.KeepState,
) !void {
    if (choice == .undecided) return error.InvalidChoice;
    if (generated.snapshot.decision_side != side) return error.NotCurrentDecision;

    const allocator = generated.arena.allocator();
    var player = switch (side) {
        .corp => &generated.snapshot.state.corp,
        .runner => &generated.snapshot.state.runner,
    };
    player.keep = choice;

    if (choice == .mulligan) {
        var rng_state = rng.fromOracleSeed(generated.snapshot.state.rng_seed orelse return error.MissingRngSeed);
        const combined = try combineCards(allocator, player.hand, player.deck);
        rng.shuffleInPlace(state.CardInstance, &rng_state, combined);
        player.hand = try cloneCards(allocator, combined[0..5]);
        player.deck = try cloneCards(allocator, combined[5..]);
        generated.snapshot.state.rng_seed = rng.oracleSeed(rng_state);
    }

    switch (side) {
        .corp => {
            player.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "waiting"),
                .choices = &.{},
            };

            generated.snapshot.state.runner.prompt_state = .{
                .prompt_type = try allocator.dupe(u8, "mulligan"),
                .choices = try dupMulliganChoices(allocator),
            };
            generated.snapshot.decision_side = .runner;
            generated.snapshot.legal_actions = try mulliganActionsForSide(allocator, .runner);
        },
        .runner => {
            generated.snapshot.state.corp.prompt_state = null;
            generated.snapshot.state.runner.prompt_state = null;
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try startTurnActions(allocator, .corp);
        },
    }
}

pub fn applyStartTurn(
    generated: *generator.GeneratedSnapshot,
    side: state.Side,
) !void {
    if (generated.snapshot.decision_side != side) return error.NotCurrentDecision;

    const allocator = generated.arena.allocator();
    if (!generated.snapshot.state.end_turn) return error.TurnAlreadyStarted;

    switch (side) {
        .corp => {
            var corp = &generated.snapshot.state.corp;
            if (corp.deck.len == 0) return error.EmptyDeck;

            const drawn = corp.deck[0];
            const next_hand = try allocator.alloc(state.CardInstance, corp.hand.len + 1);
            @memcpy(next_hand[0..corp.hand.len], corp.hand);
            next_hand[corp.hand.len] = drawn;

            const next_deck = try cloneCards(allocator, corp.deck[1..]);

            corp.hand = next_hand;
            corp.deck = next_deck;
            corp.click = corp.click_per_turn;

            generated.snapshot.state.active_player = .corp;
            generated.snapshot.state.turn += 1;
            generated.snapshot.state.end_turn = false;
            generated.snapshot.decision_side = .corp;
            generated.snapshot.legal_actions = try corpOpeningActions(allocator);
        },
        .runner => return error.UnsupportedSide,
    }
}

fn mulliganActionsForSide(
    allocator: std.mem.Allocator,
    side: state.Side,
) ![]const state.LegalAction {
    const actions = try allocator.alloc(state.LegalAction, 2);
    actions[0] = .{
        .kind = .prompt_choice,
        .side = side,
        .prompt_type = try allocator.dupe(u8, "mulligan"),
        .choice = stringChoice("Keep"),
    };
    actions[1] = .{
        .kind = .prompt_choice,
        .side = side,
        .prompt_type = try allocator.dupe(u8, "mulligan"),
        .choice = stringChoice("Mulligan"),
    };
    return actions;
}

fn startTurnActions(
    allocator: std.mem.Allocator,
    side: state.Side,
) ![]const state.LegalAction {
    const actions = try allocator.alloc(state.LegalAction, 1);
    actions[0] = .{
        .kind = .start_turn,
        .side = side,
    };
    return actions;
}

fn corpOpeningActions(allocator: std.mem.Allocator) ![]const state.LegalAction {
    const actions = try allocator.alloc(state.LegalAction, 4);
    actions[0] = .{
        .kind = .use_ability,
        .side = .corp,
        .ability_index = 0,
        .label = try allocator.dupe(u8, "Gain 1 [Credits]"),
    };
    actions[1] = .{
        .kind = .use_ability,
        .side = .corp,
        .ability_index = 1,
        .label = try allocator.dupe(u8, "Draw 1 card"),
    };
    actions[2] = .{
        .kind = .use_ability,
        .side = .corp,
        .ability_index = 4,
        .label = try allocator.dupe(u8, "Advance 1 installed card"),
    };
    actions[3] = .{
        .kind = .use_ability,
        .side = .corp,
        .ability_index = 6,
        .label = try allocator.dupe(u8, "Purge virus counters"),
    };
    return actions;
}

fn dupMulliganChoices(allocator: std.mem.Allocator) ![]const state.PromptChoice {
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

fn combineCards(
    allocator: std.mem.Allocator,
    hand: []const state.CardInstance,
    deck: []const state.CardInstance,
) ![]state.CardInstance {
    const combined = try allocator.alloc(state.CardInstance, hand.len + deck.len);
    @memcpy(combined[0..deck.len], deck);
    @memcpy(combined[deck.len..], hand);
    return combined;
}

fn cloneCards(
    allocator: std.mem.Allocator,
    cards: []const state.CardInstance,
) ![]const state.CardInstance {
    const copy = try allocator.alloc(state.CardInstance, cards.len);
    @memcpy(copy, cards);
    return copy;
}
