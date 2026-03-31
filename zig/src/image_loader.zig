const std = @import("std");

/// Testable async image loading state machine.
/// Decoupled from vaxis/rendering — uses u32 as opaque image handle.
pub const ImageLoader = struct {
    // Current displayed image
    current_code: c_int = 0,
    current_image: u32 = 0, // 0 = no image
    has_current: bool = false,

    // Image ready from background (set by worker, read by main thread)
    ready_code: c_int = 0,
    ready_image: u32 = 0,
    has_ready: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    // Download state
    is_busy: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    generation: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    thread: ?std.Thread = null,

    // Callbacks
    free_fn: ?*const fn (u32) void = null,
    /// Sync load (fast, main thread) — returns image id if cached, null to go async
    load_fn: ?*const fn (c_int) ?u32 = null,
    /// Async download+load (slow, background thread) — returns image id
    async_load_fn: ?*const fn (c_int) ?u32 = null,
    /// Called from background thread when async load finishes (to wake main loop)
    notify_fn: ?*const fn () void = null,

    // Stats for testing
    loads_started: u32 = 0,
    images_freed: u32 = 0,
    images_displayed: u32 = 0,

    const Self = @This();

    /// Called each frame with the card code to display.
    /// Returns the image handle to render, or 0 if not ready.
    pub fn update(self: *Self, code: c_int) u32 {
        if (code <= 0) return 0;

        // 1. If switched to a different card, drop current image
        if (code != self.current_code) {
            if (self.has_current) {
                self.free_image(self.current_image);
                self.has_current = false;
                self.current_image = 0;
            }
            self.current_code = code;
            // Invalidate in-flight download
            _ = self.generation.fetchAdd(1, .monotonic);
        }

        // 2. Check if background finished (acquire fence ensures ready_* visible)
        //    We check has_ready AFTER is_busy acquire to get proper ordering.
        const busy = self.is_busy.load(.acquire);
        if (self.has_ready.load(.acquire)) {
            self.has_ready.store(false, .release);
            if (self.ready_code == code) {
                // It's for the card we want
                if (self.has_current) self.free_image(self.current_image);
                self.current_image = self.ready_image;
                self.has_current = true;
                self.images_displayed += 1;
            } else {
                // Stale
                self.free_image(self.ready_image);
            }
            self.ready_image = 0;
        }

        // 3. If we have the right image, return it
        if (self.has_current and self.current_code == code) {
            return self.current_image;
        }

        // 4. If not busy, try to start a load (may complete synchronously)
        if (!busy) {
            self.start_load(code);
            // Sync load may have succeeded
            if (self.has_current and self.current_code == code) {
                return self.current_image;
            }
        }

        return 0;
    }

    fn start_load(self: *Self, code: c_int) void {
        // Join previous thread
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }

        self.loads_started += 1;
        const gen = self.generation.load(.acquire);

        // Try fast sync load first (e.g. already in memory)
        if (self.load_fn) |load_fn| {
            if (load_fn(code)) |img| {
                if (self.has_current) self.free_image(self.current_image);
                self.current_image = img;
                self.has_current = true;
                self.current_code = code;
                self.images_displayed += 1;
                return;
            }
        }

        // Fall back to async load (download + decode on background thread)
        if (self.async_load_fn) |_| {
            self.is_busy.store(true, .release);
            self.thread = std.Thread.spawn(.{}, worker, .{ self, code, gen }) catch {
                self.is_busy.store(false, .release);
                return;
            };
        }
    }

    fn worker(self: *Self, code: c_int, gen: u32) void {
        defer {
            self.is_busy.store(false, .release);
            // Always wake main thread so it can retry if this was stale
            if (self.notify_fn) |notify| notify();
        }

        if (self.generation.load(.acquire) != gen) return;

        const img = blk: {
            if (self.async_load_fn) |alf| {
                break :blk alf(code) orelse return;
            }
            return;
        };

        if (self.generation.load(.acquire) != gen) {
            self.free_image(img);
            return;
        }

        self.ready_code = code;
        self.ready_image = img;
        self.has_ready.store(true, .release);
    }

    fn free_image(self: *Self, img: u32) void {
        if (self.free_fn) |f| f(img);
        self.images_freed += 1;
    }

    pub fn deinit(self: *Self) void {
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
        if (self.has_current) {
            self.free_image(self.current_image);
            self.has_current = false;
        }
    }
};

// ============================================================
// Tests
// ============================================================

var test_next_image_id: u32 = 1;
var test_freed: [32]u32 = undefined;
var test_freed_count: usize = 0;
var test_downloaded: [32]c_int = undefined;
var test_downloaded_count: usize = 0;
var test_download_delay_ms: u64 = 0;

fn test_free(img: u32) void {
    if (test_freed_count < test_freed.len) {
        test_freed[test_freed_count] = img;
        test_freed_count += 1;
    }
}

fn test_load(_: c_int) ?u32 {
    const id = test_next_image_id;
    test_next_image_id += 1;
    return id;
}

fn test_async_load(code: c_int) ?u32 {
    if (test_download_delay_ms > 0) {
        std.Thread.sleep(test_download_delay_ms * std.time.ns_per_ms);
    }
    if (test_downloaded_count < test_downloaded.len) {
        test_downloaded[test_downloaded_count] = code;
        test_downloaded_count += 1;
    }
    const id = test_next_image_id;
    test_next_image_id += 1;
    return id;
}

fn reset_test_state() void {
    test_next_image_id = 1;
    test_freed_count = 0;
    test_downloaded_count = 0;
    test_download_delay_ms = 0;
}

fn new_loader() ImageLoader {
    return .{
        .free_fn = test_free,
        .load_fn = test_load,
        .async_load_fn = test_async_load,
    };
}

test "basic: request card, get image" {
    reset_test_state();
    var loader = new_loader();
    defer loader.deinit();

    const img = loader.update(30075);
    // Synchronous load_fn should return immediately
    try std.testing.expect(img > 0);
    try std.testing.expectEqual(@as(c_int, 30075), loader.current_code);
    try std.testing.expectEqual(@as(u32, 1), loader.images_displayed);
}

test "same card twice returns same image" {
    reset_test_state();
    var loader = new_loader();
    defer loader.deinit();

    const img1 = loader.update(30075);
    const img2 = loader.update(30075);
    try std.testing.expectEqual(img1, img2);
    try std.testing.expectEqual(@as(u32, 1), loader.images_displayed);
    try std.testing.expectEqual(@as(usize, 0), test_freed_count);
}

test "switch card frees old image" {
    reset_test_state();
    var loader = new_loader();
    defer loader.deinit();

    const img1 = loader.update(30075);
    try std.testing.expect(img1 > 0);

    const img2 = loader.update(30030);
    try std.testing.expect(img2 > 0);
    try std.testing.expect(img1 != img2);
    try std.testing.expectEqual(@as(usize, 1), test_freed_count);
    try std.testing.expectEqual(img1, test_freed[0]);
}

test "async: background load completes and image picked up" {
    reset_test_state();
    test_download_delay_ms = 10;
    var loader: ImageLoader = .{
        .free_fn = test_free,
        .load_fn = null,
        .async_load_fn = test_async_load,
    };
    defer loader.deinit();

    // First update: no sync load, starts async
    const img1 = loader.update(30075);
    try std.testing.expectEqual(@as(u32, 0), img1);
    try std.testing.expect(loader.is_busy.load(.acquire));

    // Wait for async to finish
    while (loader.is_busy.load(.acquire)) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    // Next update picks up the ready image
    const img2 = loader.update(30075);
    try std.testing.expect(img2 > 0);
}

test "async: no async_load_fn means no image" {
    reset_test_state();
    var loader: ImageLoader = .{
        .free_fn = test_free,
        .load_fn = null,
        .async_load_fn = null,
    };
    defer loader.deinit();

    const img = loader.update(30075);
    try std.testing.expectEqual(@as(u32, 0), img);
}

test "rapid switch: stale download discarded" {
    reset_test_state();
    test_download_delay_ms = 50;
    var loader = new_loader();
    defer loader.deinit();
    loader.load_fn = null; // force async path

    // Start download for card A
    _ = loader.update(30075);
    try std.testing.expect(loader.is_busy.load(.acquire));

    // Switch to card B while A is downloading
    _ = loader.update(30030);

    // Wait for A's download to finish
    while (loader.is_busy.load(.acquire)) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    // A's result should be stale — triggers new load for B
    _ = loader.update(30030);
    try std.testing.expect(loader.loads_started >= 2);

    // Wait for B's async load
    while (loader.is_busy.load(.acquire)) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    // Now pick up B's image
    const img = loader.update(30030);
    try std.testing.expect(img > 0);
    try std.testing.expectEqual(@as(c_int, 30030), loader.current_code);
}

test "rapid A->B->C: only C shown" {
    reset_test_state();
    test_download_delay_ms = 30;
    var loader = new_loader();
    defer loader.deinit();
    loader.load_fn = null;

    _ = loader.update(1); // start download A
    _ = loader.update(2); // switch to B (A still downloading)
    _ = loader.update(3); // switch to C

    // Wait for A to finish
    while (loader.is_busy.load(.acquire)) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    // Poll: should start download for C
    // async_load_fn already set from new_loader
    var img: u32 = 0;
    var attempts: u32 = 0;
    while (img == 0 and attempts < 200) : (attempts += 1) {
        img = loader.update(3);
        if (loader.is_busy.load(.acquire)) {
            while (loader.is_busy.load(.acquire)) {
                std.Thread.sleep(5 * std.time.ns_per_ms);
            }
        }
    }
    try std.testing.expect(img > 0);
    try std.testing.expectEqual(@as(c_int, 3), loader.current_code);
}

test "switch to same card during download: no extra download" {
    reset_test_state();
    test_download_delay_ms = 30;
    var loader = new_loader();
    defer loader.deinit();
    loader.load_fn = null;

    _ = loader.update(30075); // start download
    const started = loader.loads_started;

    // Same card, should not start another download
    _ = loader.update(30075);
    _ = loader.update(30075);
    try std.testing.expectEqual(started, loader.loads_started);

    // Wait for download
    while (loader.is_busy.load(.acquire)) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    // async_load_fn already set from new_loader
    const img = loader.update(30075);
    try std.testing.expect(img > 0);
}

test "code 0 returns 0" {
    reset_test_state();
    var loader = new_loader();
    defer loader.deinit();
    try std.testing.expectEqual(@as(u32, 0), loader.update(0));
    try std.testing.expectEqual(@as(u32, 0), loader.update(-1));
}

test "rapid switch back: image eventually shows" {
    reset_test_state();
    test_download_delay_ms = 20;
    var loader = new_loader();
    defer loader.deinit();
    loader.load_fn = null;

    // A -> B -> A rapidly
    _ = loader.update(30075);
    _ = loader.update(30030);
    _ = loader.update(30075);

    // Wait for any in-flight to finish
    while (loader.is_busy.load(.acquire)) {
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    // Keep polling until we get an image (retry logic)
    // async_load_fn already set from new_loader
    var img: u32 = 0;
    var attempts: u32 = 0;
    while (img == 0 and attempts < 100) : (attempts += 1) {
        img = loader.update(30075);
        if (img == 0 and loader.is_busy.load(.acquire)) {
            while (loader.is_busy.load(.acquire)) {
                std.Thread.sleep(5 * std.time.ns_per_ms);
            }
        }
    }

    try std.testing.expect(img > 0);
    try std.testing.expectEqual(@as(c_int, 30075), loader.current_code);
}
