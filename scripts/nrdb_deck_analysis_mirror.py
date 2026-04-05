#!/usr/bin/env python3
"""Mirror public NetrunnerDB data into a local SQLite database for deck analysis.

This script targets the public dataset that is useful for deckbuilding analysis:

- v3 public API resources: cards, printings, decklists, reviews, rulings, and
  reference metadata.
- Public "popular decklists" listing pages to capture likes, favorites,
  comments, and author reputation for the subset of decklists that receive
  visible social traction on NetrunnerDB.

It does not reconstruct private production data. It only stores public data
that is exposed by NetrunnerDB.
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import html
import json
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


SCRIPT_VERSION = "2026-03-29.2"
USER_AGENT = (
    "Mozilla/5.0 (compatible; nrdb-deck-analysis-mirror/1.0; "
    "+https://github.com/Null-Signal-Games/netrunnerdb)"
)
API_BASE = "https://api.netrunnerdb.com/api/v3/public"
SITE_BASE = "https://netrunnerdb.com"

DEFAULT_V3_ENDPOINTS = (
    "card_cycles",
    "card_set_types",
    "card_sets",
    "card_subtypes",
    "card_types",
    "cards",
    "decklists",
    "factions",
    "illustrators",
    "printings",
    "reviews",
    "rulings",
    "sides",
)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default="netrunnerdb-deck-analysis.sqlite3",
        help="Path to the SQLite database to create or update.",
    )
    parser.add_argument(
        "--page-size",
        type=int,
        default=100,
        help="Page size for v3 API pagination.",
    )
    parser.add_argument(
        "--sleep-seconds",
        type=float,
        default=0.05,
        help="Delay between HTTP requests.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=60.0,
        help="HTTP timeout.",
    )
    parser.add_argument(
        "--only-endpoints",
        nargs="*",
        default=None,
        help="Optional subset of v3 endpoints to mirror.",
    )
    parser.add_argument(
        "--skip-recent-html",
        action="store_true",
        help="Skip scraping decklist HTML pages for popularity metrics.",
    )
    parser.add_argument(
        "--max-pages-per-endpoint",
        type=int,
        default=None,
        help="Limit pages fetched per v3 endpoint. Useful for testing.",
    )
    parser.add_argument(
        "--max-recent-pages",
        type=int,
        default=None,
        help="Limit popular decklist listing pages scraped. Useful for testing.",
    )
    return parser.parse_args()


class HttpClient:
    def __init__(self, timeout_seconds: float, sleep_seconds: float) -> None:
        self.timeout_seconds = timeout_seconds
        self.sleep_seconds = sleep_seconds

    def _request(self, url: str) -> bytes:
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "*/*",
                "Accept-Encoding": "gzip, deflate",
            },
        )
        with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
            body = response.read()
            if response.headers.get("Content-Encoding", "").lower() == "gzip":
                return gzip.decompress(body)
            return body

    def get_text(self, url: str) -> str:
        try:
            body = self._request(url)
        except urllib.error.HTTPError as exc:
            raise RuntimeError(f"GET {url} failed with HTTP {exc.code}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"GET {url} failed: {exc.reason}") from exc
        finally:
            time.sleep(self.sleep_seconds)
        return body.decode("utf-8")

    def get_json(self, url: str) -> dict[str, Any]:
        return json.loads(self.get_text(url))


class DecklistListingParser(HTMLParser):
    """Parse paginated decklist listing pages for popularity signals."""

    deck_href_re = re.compile(r"^/en/decklist/([0-9a-f-]+)/([^/]+)$")
    profile_href_re = re.compile(r"^/en/profile/(\d+)/([^/]+)$")

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.entries: list[dict[str, Any]] = []
        self._entry_stack: list[int] = []
        self._div_depth = 0
        self._active_entry: dict[str, Any] | None = None
        self._active_deck_href: str | None = None
        self._active_profile_href: str | None = None
        self._capture_title = False
        self._capture_username = False
        self._capture_reputation = False
        self._metric_queue: list[str] = []
        self._pending_metric: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr_map = dict(attrs)

        if tag == "div":
            self._div_depth += 1
            style = attr_map.get("style") or ""
            if "border-top: 1px solid" in style:
                self._active_entry = {
                    "decklist_id": None,
                    "slug": None,
                    "name": None,
                    "likes": None,
                    "favorites": None,
                    "comments": None,
                    "profile_id": None,
                    "user_name": None,
                    "reputation": None,
                    "published_at": None,
                }
                self._entry_stack.append(self._div_depth)

        if not self._active_entry:
            return

        if tag == "a":
            href = attr_map.get("href") or ""
            deck_match = self.deck_href_re.match(href)
            if deck_match and self._active_entry["decklist_id"] is None:
                self._active_entry["decklist_id"] = deck_match.group(1)
                self._active_entry["slug"] = deck_match.group(2)
                self._active_deck_href = href
                self._capture_title = True
                return

            profile_match = self.profile_href_re.match(href)
            if profile_match and self._active_entry["profile_id"] is None:
                self._active_entry["profile_id"] = profile_match.group(1)
                self._active_profile_href = href
                self._capture_username = True
                return

        if tag == "span":
            classes = set((attr_map.get("class") or "").split())
            if "social-icon-like" in classes and self._active_entry["likes"] is None:
                self._metric_queue.append("likes")
            elif "social-icon-favorite" in classes and self._active_entry["favorites"] is None:
                self._metric_queue.append("favorites")
            elif "social-icon-comment" in classes and self._active_entry["comments"] is None:
                self._metric_queue.append("comments")

        if tag == "small" and "reputation" in (attr_map.get("class") or ""):
            self._capture_reputation = True

        if tag == "time":
            datetime_value = attr_map.get("datetime")
            if datetime_value and self._active_entry["published_at"] is None:
                self._active_entry["published_at"] = datetime_value

    def handle_endtag(self, tag: str) -> None:
        if self._active_entry:
            if tag == "a":
                self._capture_title = False
                self._capture_username = False
                self._active_deck_href = None
                self._active_profile_href = None
            elif tag == "small":
                self._capture_reputation = False

        if tag == "div":
            if self._active_entry and self._entry_stack and self._entry_stack[-1] == self._div_depth:
                if self._active_entry["decklist_id"]:
                    self.entries.append(self._active_entry)
                self._active_entry = None
                self._entry_stack.pop()
                self._metric_queue.clear()
                self._pending_metric = None
                self._capture_title = False
                self._capture_username = False
                self._capture_reputation = False
            self._div_depth -= 1

    def handle_data(self, data: str) -> None:
        if not self._active_entry:
            return

        text = data.strip()
        if not text:
            return

        if self._capture_title and self._active_entry["name"] is None:
            self._active_entry["name"] = html.unescape(text)
            return

        if self._capture_username and self._active_entry["user_name"] is None:
            self._active_entry["user_name"] = html.unescape(text)
            return

        if self._capture_reputation and self._active_entry["reputation"] is None:
            if text.isdigit():
                self._active_entry["reputation"] = int(text)
            return

        if self._pending_metric is None and self._metric_queue:
            self._pending_metric = self._metric_queue.pop(0)

        if self._pending_metric is not None and text.isdigit():
            self._active_entry[self._pending_metric] = int(text)
            self._pending_metric = None


def scrape_popular_decklist_pages(
    conn: sqlite3.Connection,
    client: HttpClient,
    max_pages: int | None,
) -> int:
    matched = 0
    page_number = 1
    consecutive_empty_pages = 0

    while True:
        if max_pages is not None and page_number > max_pages:
            break

        url = f"{SITE_BASE}/en/decklists" if page_number == 1 else f"{SITE_BASE}/en/decklists/popular/{page_number}"
        page_html = client.get_text(url)
        fetched_at = utc_now()

        parser = DecklistListingParser()
        parser.feed(page_html)

        if not parser.entries:
            consecutive_empty_pages += 1
            print(
                f"[popular-html] page {page_number} matched 0 decklists",
                file=sys.stderr,
            )
            if consecutive_empty_pages >= 3:
                break
            page_number += 1
            continue

        consecutive_empty_pages = 0
        for entry in parser.entries:
            conn.execute(
                """
                UPDATE decklists
                   SET popularity_likes = ?,
                       popularity_favorites = ?,
                       popularity_comments = ?,
                       popularity_profile_id = ?,
                       popularity_user_name = ?,
                       popularity_reputation = ?,
                       popularity_page = ?,
                       popularity_seen_at = ?
                 WHERE decklist_id = ?
                """,
                (
                    entry.get("likes"),
                    entry.get("favorites"),
                    entry.get("comments"),
                    entry.get("profile_id"),
                    entry.get("user_name"),
                    entry.get("reputation"),
                    page_number,
                    fetched_at,
                    entry["decklist_id"],
                ),
            )
            matched += 1

        conn.commit()
        print(
            f"[popular-html] page {page_number} matched {len(parser.entries)} decklists",
            file=sys.stderr,
        )
        page_number += 1

    return matched


def connect_db(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS raw_api_objects (
            endpoint TEXT NOT NULL,
            object_id TEXT NOT NULL,
            object_type TEXT NOT NULL,
            attributes_json TEXT NOT NULL,
            relationships_json TEXT,
            links_json TEXT,
            raw_json TEXT NOT NULL,
            fetched_at TEXT NOT NULL,
            PRIMARY KEY (endpoint, object_id)
        );

        CREATE TABLE IF NOT EXISTS raw_recent_pages (
            page_number INTEGER PRIMARY KEY,
            url TEXT NOT NULL,
            html TEXT NOT NULL,
            fetched_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS cards (
            card_id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            stripped_title TEXT,
            side_id TEXT,
            faction_id TEXT,
            card_type_id TEXT,
            latest_printing_id TEXT,
            date_release TEXT,
            influence_cost INTEGER,
            influence_limit INTEGER,
            deck_limit INTEGER,
            minimum_deck_size INTEGER,
            agenda_points INTEGER,
            advancement_requirement INTEGER,
            cost INTEGER,
            memory_cost INTEGER,
            strength INTEGER,
            trash_cost INTEGER,
            is_unique INTEGER,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS printings (
            printing_id TEXT PRIMARY KEY,
            card_id TEXT NOT NULL,
            card_cycle_id TEXT,
            card_cycle_name TEXT,
            card_set_id TEXT,
            card_set_name TEXT,
            position INTEGER,
            position_in_set INTEGER,
            quantity INTEGER,
            date_release TEXT,
            released_by TEXT,
            is_latest_printing INTEGER,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS card_cycles (
            card_cycle_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            date_release TEXT,
            legacy_code TEXT,
            position INTEGER,
            released_by TEXT,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS card_sets (
            card_set_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            date_release TEXT,
            size INTEGER,
            card_cycle_id TEXT,
            card_set_type_id TEXT,
            legacy_code TEXT,
            position INTEGER,
            released_by TEXT,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS factions (
            faction_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            side_id TEXT,
            is_mini INTEGER,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sides (
            side_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS card_types (
            card_type_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            side_id TEXT,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS card_set_types (
            card_set_type_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS card_subtypes (
            card_subtype_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            side_id TEXT,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS illustrators (
            illustrator_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS decklists (
            decklist_id TEXT PRIMARY KEY,
            user_id TEXT,
            identity_card_id TEXT,
            name TEXT NOT NULL,
            notes TEXT,
            side_id TEXT,
            faction_id TEXT,
            created_at TEXT,
            updated_at TEXT,
            num_cards INTEGER,
            influence_spent INTEGER,
            follows_basic_deckbuilding_rules INTEGER,
            popularity_likes INTEGER,
            popularity_favorites INTEGER,
            popularity_comments INTEGER,
            popularity_profile_id TEXT,
            popularity_user_name TEXT,
            popularity_reputation INTEGER,
            popularity_page INTEGER,
            popularity_seen_at TEXT,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS decklist_cards (
            decklist_id TEXT NOT NULL,
            card_id TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            PRIMARY KEY (decklist_id, card_id)
        );

        CREATE TABLE IF NOT EXISTS reviews (
            review_id TEXT PRIMARY KEY,
            card_id TEXT,
            card_title TEXT,
            username TEXT,
            body TEXT,
            votes INTEGER,
            created_at TEXT,
            updated_at TEXT,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS review_comments (
            review_id TEXT NOT NULL,
            comment_id TEXT NOT NULL,
            username TEXT,
            body TEXT,
            created_at TEXT,
            updated_at TEXT,
            raw_json TEXT NOT NULL,
            PRIMARY KEY (review_id, comment_id)
        );

        CREATE TABLE IF NOT EXISTS rulings (
            ruling_id TEXT PRIMARY KEY,
            card_id TEXT,
            question TEXT,
            answer TEXT,
            text_ruling TEXT,
            nsg_rules_team_verified INTEGER,
            updated_at TEXT,
            raw_json TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_raw_api_objects_endpoint
            ON raw_api_objects (endpoint);
        CREATE INDEX IF NOT EXISTS idx_printings_card_id
            ON printings (card_id);
        CREATE INDEX IF NOT EXISTS idx_card_sets_cycle
            ON card_sets (card_cycle_id);
        CREATE INDEX IF NOT EXISTS idx_cards_side
            ON cards (side_id);
        CREATE INDEX IF NOT EXISTS idx_cards_type
            ON cards (card_type_id);
        CREATE INDEX IF NOT EXISTS idx_decklists_identity
            ON decklists (identity_card_id);
        CREATE INDEX IF NOT EXISTS idx_decklists_side
            ON decklists (side_id);
        CREATE INDEX IF NOT EXISTS idx_decklists_faction
            ON decklists (faction_id);
        CREATE INDEX IF NOT EXISTS idx_decklist_cards_card
            ON decklist_cards (card_id);
        CREATE INDEX IF NOT EXISTS idx_decklist_cards_deck
            ON decklist_cards (decklist_id);
        CREATE INDEX IF NOT EXISTS idx_reviews_card
            ON reviews (card_id);
        CREATE INDEX IF NOT EXISTS idx_rulings_card
            ON rulings (card_id);

        DROP VIEW IF EXISTS decklists_scored;
        CREATE VIEW decklists_scored AS
        SELECT
            d.*,
            1
                + COALESCE(d.popularity_likes, 0)
                + (2 * COALESCE(d.popularity_favorites, 0))
                + COALESCE(d.popularity_comments, 0) AS popularity_score
        FROM decklists AS d;

        DROP VIEW IF EXISTS card_popularity;
        CREATE VIEW card_popularity AS
        SELECT
            dc.card_id,
            c.title,
            c.side_id,
            c.faction_id,
            c.card_type_id,
            COUNT(DISTINCT dc.decklist_id) AS decklists_using,
            SUM(dc.quantity) AS total_copies_used,
            SUM(ds.popularity_score) AS weighted_decklists_using,
            SUM(ds.popularity_score * dc.quantity) AS weighted_copies_used
        FROM decklist_cards AS dc
        JOIN cards AS c
          ON c.card_id = dc.card_id
        JOIN decklists_scored AS ds
          ON ds.decklist_id = dc.decklist_id
        GROUP BY dc.card_id, c.title, c.side_id, c.faction_id, c.card_type_id;

        DROP VIEW IF EXISTS popular_decklists_scored;
        CREATE VIEW popular_decklists_scored AS
        SELECT
            d.*,
            COALESCE(d.popularity_likes, 0)
                + (2 * COALESCE(d.popularity_favorites, 0))
                + COALESCE(d.popularity_comments, 0) AS popularity_score
        FROM decklists AS d
        WHERE d.popularity_seen_at IS NOT NULL;

        DROP VIEW IF EXISTS popular_card_popularity;
        CREATE VIEW popular_card_popularity AS
        SELECT
            dc.card_id,
            c.title,
            c.side_id,
            c.faction_id,
            c.card_type_id,
            COUNT(DISTINCT dc.decklist_id) AS decklists_using,
            SUM(dc.quantity) AS total_copies_used,
            SUM(pds.popularity_score) AS weighted_decklists_using,
            SUM(pds.popularity_score * dc.quantity) AS weighted_copies_used
        FROM decklist_cards AS dc
        JOIN cards AS c
          ON c.card_id = dc.card_id
        JOIN popular_decklists_scored AS pds
          ON pds.decklist_id = dc.decklist_id
        GROUP BY dc.card_id, c.title, c.side_id, c.faction_id, c.card_type_id;

        DROP VIEW IF EXISTS pack_card_popularity;
        CREATE VIEW pack_card_popularity AS
        SELECT
            p.card_set_id,
            cs.name AS pack_name,
            cs.card_cycle_id,
            cc.name AS cycle_name,
            c.side_id,
            c.faction_id,
            c.card_type_id,
            p.card_id,
            c.title,
            COUNT(DISTINCT dc.decklist_id) AS decklists_using,
            SUM(dc.quantity) AS total_copies_used,
            SUM(ds.popularity_score) AS weighted_decklists_using,
            SUM(ds.popularity_score * dc.quantity) AS weighted_copies_used,
            RANK() OVER (
                PARTITION BY p.card_set_id, c.side_id
                ORDER BY
                    SUM(ds.popularity_score * dc.quantity) DESC,
                    COUNT(DISTINCT dc.decklist_id) DESC,
                    SUM(dc.quantity) DESC,
                    c.title ASC
            ) AS rank_in_pack_for_side
        FROM decklist_cards AS dc
        JOIN decklists_scored AS ds
          ON ds.decklist_id = dc.decklist_id
        JOIN cards AS c
          ON c.card_id = dc.card_id
        JOIN printings AS p
          ON p.card_id = dc.card_id
        LEFT JOIN card_sets AS cs
          ON cs.card_set_id = p.card_set_id
        LEFT JOIN card_cycles AS cc
          ON cc.card_cycle_id = p.card_cycle_id
        GROUP BY
            p.card_set_id,
            cs.name,
            cs.card_cycle_id,
            cc.name,
            c.side_id,
            c.faction_id,
            c.card_type_id,
            p.card_id,
            c.title;

        DROP VIEW IF EXISTS popular_pack_card_popularity;
        CREATE VIEW popular_pack_card_popularity AS
        SELECT
            p.card_set_id,
            cs.name AS pack_name,
            cs.card_cycle_id,
            cc.name AS cycle_name,
            c.side_id,
            c.faction_id,
            c.card_type_id,
            p.card_id,
            c.title,
            COUNT(DISTINCT dc.decklist_id) AS decklists_using,
            SUM(dc.quantity) AS total_copies_used,
            SUM(pds.popularity_score) AS weighted_decklists_using,
            SUM(pds.popularity_score * dc.quantity) AS weighted_copies_used,
            RANK() OVER (
                PARTITION BY p.card_set_id, c.side_id
                ORDER BY
                    SUM(pds.popularity_score * dc.quantity) DESC,
                    COUNT(DISTINCT dc.decklist_id) DESC,
                    SUM(dc.quantity) DESC,
                    c.title ASC
            ) AS rank_in_pack_for_side
        FROM decklist_cards AS dc
        JOIN popular_decklists_scored AS pds
          ON pds.decklist_id = dc.decklist_id
        JOIN cards AS c
          ON c.card_id = dc.card_id
        JOIN printings AS p
          ON p.card_id = dc.card_id
        LEFT JOIN card_sets AS cs
          ON cs.card_set_id = p.card_set_id
        LEFT JOIN card_cycles AS cc
          ON cc.card_cycle_id = p.card_cycle_id
        GROUP BY
            p.card_set_id,
            cs.name,
            cs.card_cycle_id,
            cc.name,
            c.side_id,
            c.faction_id,
            c.card_type_id,
            p.card_id,
            c.title;
        """
    )
    conn.commit()


def maybe_int(value: Any) -> int | None:
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def bool_to_int(value: Any) -> int | None:
    if value is None:
        return None
    return 1 if value else 0


def upsert_metadata(conn: sqlite3.Connection, key: str, value: Any) -> None:
    conn.execute(
        """
        INSERT INTO metadata (key, value)
        VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
        (key, json.dumps(value) if not isinstance(value, str) else value),
    )


def endpoint_url(endpoint: str, page_number: int, page_size: int) -> str:
    params = urllib.parse.urlencode(
        {
            "page[number]": page_number,
            "page[size]": page_size,
        }
    )
    return f"{API_BASE}/{endpoint}?{params}"


def store_raw_objects(
    conn: sqlite3.Connection,
    endpoint: str,
    payload: dict[str, Any],
    fetched_at: str,
) -> None:
    for obj in payload.get("data", []):
        conn.execute(
            """
            INSERT INTO raw_api_objects (
                endpoint, object_id, object_type, attributes_json,
                relationships_json, links_json, raw_json, fetched_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(endpoint, object_id) DO UPDATE SET
                object_type = excluded.object_type,
                attributes_json = excluded.attributes_json,
                relationships_json = excluded.relationships_json,
                links_json = excluded.links_json,
                raw_json = excluded.raw_json,
                fetched_at = excluded.fetched_at
            """,
            (
                endpoint,
                obj["id"],
                obj.get("type", endpoint),
                json.dumps(obj.get("attributes", {}), ensure_ascii=False, sort_keys=True),
                json.dumps(obj.get("relationships", {}), ensure_ascii=False, sort_keys=True),
                json.dumps(obj.get("links", {}), ensure_ascii=False, sort_keys=True),
                json.dumps(obj, ensure_ascii=False, sort_keys=True),
                fetched_at,
            ),
        )


def project_v3_data(conn: sqlite3.Connection, endpoint: str, payload: dict[str, Any]) -> None:
    for obj in payload.get("data", []):
        attributes = obj.get("attributes", {})
        raw_json = json.dumps(obj, ensure_ascii=False, sort_keys=True)

        if endpoint == "cards":
            conn.execute(
                """
                INSERT INTO cards (
                    card_id, title, stripped_title, side_id, faction_id,
                    card_type_id, latest_printing_id, date_release,
                    influence_cost, influence_limit, deck_limit,
                    minimum_deck_size, agenda_points, advancement_requirement,
                    cost, memory_cost, strength, trash_cost, is_unique, raw_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(card_id) DO UPDATE SET
                    title = excluded.title,
                    stripped_title = excluded.stripped_title,
                    side_id = excluded.side_id,
                    faction_id = excluded.faction_id,
                    card_type_id = excluded.card_type_id,
                    latest_printing_id = excluded.latest_printing_id,
                    date_release = excluded.date_release,
                    influence_cost = excluded.influence_cost,
                    influence_limit = excluded.influence_limit,
                    deck_limit = excluded.deck_limit,
                    minimum_deck_size = excluded.minimum_deck_size,
                    agenda_points = excluded.agenda_points,
                    advancement_requirement = excluded.advancement_requirement,
                    cost = excluded.cost,
                    memory_cost = excluded.memory_cost,
                    strength = excluded.strength,
                    trash_cost = excluded.trash_cost,
                    is_unique = excluded.is_unique,
                    raw_json = excluded.raw_json
                """,
                (
                    obj["id"],
                    attributes.get("title"),
                    attributes.get("stripped_title"),
                    attributes.get("side_id"),
                    attributes.get("faction_id"),
                    attributes.get("card_type_id"),
                    attributes.get("latest_printing_id"),
                    attributes.get("date_release"),
                    maybe_int(attributes.get("influence_cost")),
                    maybe_int(attributes.get("influence_limit")),
                    maybe_int(attributes.get("deck_limit")),
                    maybe_int(attributes.get("minimum_deck_size")),
                    maybe_int(attributes.get("agenda_points")),
                    maybe_int(attributes.get("advancement_requirement")),
                    maybe_int(attributes.get("cost")),
                    maybe_int(attributes.get("memory_cost")),
                    maybe_int(attributes.get("strength")),
                    maybe_int(attributes.get("trash_cost")),
                    bool_to_int(attributes.get("is_unique")),
                    raw_json,
                ),
            )

        elif endpoint == "printings":
            conn.execute(
                """
                INSERT INTO printings (
                    printing_id, card_id, card_cycle_id, card_cycle_name,
                    card_set_id, card_set_name, position, position_in_set,
                    quantity, date_release, released_by, is_latest_printing,
                    raw_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(printing_id) DO UPDATE SET
                    card_id = excluded.card_id,
                    card_cycle_id = excluded.card_cycle_id,
                    card_cycle_name = excluded.card_cycle_name,
                    card_set_id = excluded.card_set_id,
                    card_set_name = excluded.card_set_name,
                    position = excluded.position,
                    position_in_set = excluded.position_in_set,
                    quantity = excluded.quantity,
                    date_release = excluded.date_release,
                    released_by = excluded.released_by,
                    is_latest_printing = excluded.is_latest_printing,
                    raw_json = excluded.raw_json
                """,
                (
                    obj["id"],
                    attributes.get("card_id"),
                    attributes.get("card_cycle_id"),
                    attributes.get("card_cycle_name"),
                    attributes.get("card_set_id"),
                    attributes.get("card_set_name"),
                    maybe_int(attributes.get("position")),
                    maybe_int(attributes.get("position_in_set")),
                    maybe_int(attributes.get("quantity")),
                    attributes.get("date_release"),
                    attributes.get("released_by"),
                    bool_to_int(attributes.get("is_latest_printing")),
                    raw_json,
                ),
            )

        elif endpoint == "card_cycles":
            conn.execute(
                """
                INSERT INTO card_cycles (
                    card_cycle_id, name, date_release, legacy_code,
                    position, released_by, raw_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(card_cycle_id) DO UPDATE SET
                    name = excluded.name,
                    date_release = excluded.date_release,
                    legacy_code = excluded.legacy_code,
                    position = excluded.position,
                    released_by = excluded.released_by,
                    raw_json = excluded.raw_json
                """,
                (
                    obj["id"],
                    attributes.get("name"),
                    attributes.get("date_release"),
                    attributes.get("legacy_code"),
                    maybe_int(attributes.get("position")),
                    attributes.get("released_by"),
                    raw_json,
                ),
            )

        elif endpoint == "card_sets":
            conn.execute(
                """
                INSERT INTO card_sets (
                    card_set_id, name, date_release, size, card_cycle_id,
                    card_set_type_id, legacy_code, position, released_by, raw_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(card_set_id) DO UPDATE SET
                    name = excluded.name,
                    date_release = excluded.date_release,
                    size = excluded.size,
                    card_cycle_id = excluded.card_cycle_id,
                    card_set_type_id = excluded.card_set_type_id,
                    legacy_code = excluded.legacy_code,
                    position = excluded.position,
                    released_by = excluded.released_by,
                    raw_json = excluded.raw_json
                """,
                (
                    obj["id"],
                    attributes.get("name"),
                    attributes.get("date_release"),
                    maybe_int(attributes.get("size")),
                    attributes.get("card_cycle_id"),
                    attributes.get("card_set_type_id"),
                    attributes.get("legacy_code"),
                    maybe_int(attributes.get("position")),
                    attributes.get("released_by"),
                    raw_json,
                ),
            )

        elif endpoint == "factions":
            conn.execute(
                """
                INSERT INTO factions (faction_id, name, side_id, is_mini, raw_json)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(faction_id) DO UPDATE SET
                    name = excluded.name,
                    side_id = excluded.side_id,
                    is_mini = excluded.is_mini,
                    raw_json = excluded.raw_json
                """,
                (
                    obj["id"],
                    attributes.get("name"),
                    attributes.get("side_id"),
                    bool_to_int(attributes.get("is_mini")),
                    raw_json,
                ),
            )

        elif endpoint == "sides":
            conn.execute(
                """
                INSERT INTO sides (side_id, name, raw_json)
                VALUES (?, ?, ?)
                ON CONFLICT(side_id) DO UPDATE SET
                    name = excluded.name,
                    raw_json = excluded.raw_json
                """,
                (obj["id"], attributes.get("name"), raw_json),
            )

        elif endpoint == "card_types":
            conn.execute(
                """
                INSERT INTO card_types (card_type_id, name, side_id, raw_json)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(card_type_id) DO UPDATE SET
                    name = excluded.name,
                    side_id = excluded.side_id,
                    raw_json = excluded.raw_json
                """,
                (obj["id"], attributes.get("name"), attributes.get("side_id"), raw_json),
            )

        elif endpoint == "card_set_types":
            conn.execute(
                """
                INSERT INTO card_set_types (card_set_type_id, name, raw_json)
                VALUES (?, ?, ?)
                ON CONFLICT(card_set_type_id) DO UPDATE SET
                    name = excluded.name,
                    raw_json = excluded.raw_json
                """,
                (obj["id"], attributes.get("name"), raw_json),
            )

        elif endpoint == "card_subtypes":
            conn.execute(
                """
                INSERT INTO card_subtypes (card_subtype_id, name, side_id, raw_json)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(card_subtype_id) DO UPDATE SET
                    name = excluded.name,
                    side_id = excluded.side_id,
                    raw_json = excluded.raw_json
                """,
                (obj["id"], attributes.get("name"), attributes.get("side_id"), raw_json),
            )

        elif endpoint == "illustrators":
            conn.execute(
                """
                INSERT INTO illustrators (illustrator_id, display_name, raw_json)
                VALUES (?, ?, ?)
                ON CONFLICT(illustrator_id) DO UPDATE SET
                    display_name = excluded.display_name,
                    raw_json = excluded.raw_json
                """,
                (obj["id"], attributes.get("display_name") or attributes.get("name"), raw_json),
            )

        elif endpoint == "decklists":
            conn.execute(
                """
                INSERT INTO decklists (
                    decklist_id, user_id, identity_card_id, name, notes, side_id,
                    faction_id, created_at, updated_at, num_cards, influence_spent,
                    follows_basic_deckbuilding_rules, raw_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(decklist_id) DO UPDATE SET
                    user_id = excluded.user_id,
                    identity_card_id = excluded.identity_card_id,
                    name = excluded.name,
                    notes = excluded.notes,
                    side_id = excluded.side_id,
                    faction_id = excluded.faction_id,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    num_cards = excluded.num_cards,
                    influence_spent = excluded.influence_spent,
                    follows_basic_deckbuilding_rules = excluded.follows_basic_deckbuilding_rules,
                    raw_json = excluded.raw_json
                """,
                (
                    obj["id"],
                    attributes.get("user_id"),
                    attributes.get("identity_card_id"),
                    attributes.get("name"),
                    attributes.get("notes"),
                    attributes.get("side_id"),
                    attributes.get("faction_id"),
                    attributes.get("created_at"),
                    attributes.get("updated_at"),
                    maybe_int(attributes.get("num_cards")),
                    maybe_int(attributes.get("influence_spent")),
                    bool_to_int(attributes.get("follows_basic_deckbuilding_rules")),
                    raw_json,
                ),
            )

            conn.execute("DELETE FROM decklist_cards WHERE decklist_id = ?", (obj["id"],))
            for card_id, quantity in (attributes.get("card_slots") or {}).items():
                conn.execute(
                    """
                    INSERT INTO decklist_cards (decklist_id, card_id, quantity)
                    VALUES (?, ?, ?)
                    """,
                    (obj["id"], card_id, maybe_int(quantity) or 0),
                )

        elif endpoint == "reviews":
            conn.execute(
                """
                INSERT INTO reviews (
                    review_id, card_id, card_title, username, body, votes,
                    created_at, updated_at, raw_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(review_id) DO UPDATE SET
                    card_id = excluded.card_id,
                    card_title = excluded.card_title,
                    username = excluded.username,
                    body = excluded.body,
                    votes = excluded.votes,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    raw_json = excluded.raw_json
                """,
                (
                    obj["id"],
                    attributes.get("card_id"),
                    attributes.get("card"),
                    attributes.get("username"),
                    attributes.get("body"),
                    maybe_int(attributes.get("votes")),
                    attributes.get("created_at"),
                    attributes.get("updated_at"),
                    raw_json,
                ),
            )

            conn.execute("DELETE FROM review_comments WHERE review_id = ?", (obj["id"],))
            for comment in attributes.get("comments") or []:
                comment_id = str(comment.get("id"))
                conn.execute(
                    """
                    INSERT INTO review_comments (
                        review_id, comment_id, username, body, created_at,
                        updated_at, raw_json
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        obj["id"],
                        comment_id,
                        comment.get("user"),
                        comment.get("body"),
                        comment.get("created_at"),
                        comment.get("updated_at"),
                        json.dumps(comment, ensure_ascii=False, sort_keys=True),
                    ),
                )

        elif endpoint == "rulings":
            conn.execute(
                """
                INSERT INTO rulings (
                    ruling_id, card_id, question, answer, text_ruling,
                    nsg_rules_team_verified, updated_at, raw_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(ruling_id) DO UPDATE SET
                    card_id = excluded.card_id,
                    question = excluded.question,
                    answer = excluded.answer,
                    text_ruling = excluded.text_ruling,
                    nsg_rules_team_verified = excluded.nsg_rules_team_verified,
                    updated_at = excluded.updated_at,
                    raw_json = excluded.raw_json
                """,
                (
                    obj["id"],
                    attributes.get("card_id"),
                    attributes.get("question"),
                    attributes.get("answer"),
                    attributes.get("text_ruling"),
                    bool_to_int(attributes.get("nsg_rules_team_verified")),
                    attributes.get("updated_at"),
                    raw_json,
                ),
            )


def paginate_endpoint(
    conn: sqlite3.Connection,
    client: HttpClient,
    endpoint: str,
    page_size: int,
    max_pages: int | None,
) -> int:
    page_number = 1
    total_objects = 0

    while True:
        if max_pages is not None and page_number > max_pages:
            break

        url = endpoint_url(endpoint, page_number, page_size)
        payload = client.get_json(url)
        fetched_at = utc_now()

        store_raw_objects(conn, endpoint, payload, fetched_at)
        project_v3_data(conn, endpoint, payload)
        conn.commit()

        objects = payload.get("data", [])
        total_objects += len(objects)
        print(
            f"[v3:{endpoint}] page {page_number} fetched {len(objects)} objects",
            file=sys.stderr,
        )

        links = payload.get("links", {})
        if not links.get("next"):
            break
        page_number += 1

    return total_objects


def summarize(conn: sqlite3.Connection) -> dict[str, int]:
    tables = (
        "cards",
        "printings",
        "card_cycles",
        "card_sets",
        "factions",
        "sides",
        "card_types",
        "card_set_types",
        "card_subtypes",
        "illustrators",
        "decklists",
        "decklist_cards",
        "reviews",
        "review_comments",
        "rulings",
    )
    summary: dict[str, int] = {}
    for table in tables:
        row = conn.execute(f"SELECT COUNT(*) AS n FROM {table}").fetchone()
        summary[table] = int(row["n"])
    return summary


def main() -> int:
    args = parse_args()
    output_path = Path(args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    endpoints = tuple(args.only_endpoints) if args.only_endpoints else DEFAULT_V3_ENDPOINTS

    client = HttpClient(
        timeout_seconds=args.timeout_seconds,
        sleep_seconds=args.sleep_seconds,
    )
    conn = connect_db(output_path)
    create_schema(conn)

    upsert_metadata(conn, "script_version", SCRIPT_VERSION)
    upsert_metadata(conn, "generated_at", utc_now())
    upsert_metadata(conn, "v3_endpoints", list(endpoints))
    conn.commit()

    print(f"Writing SQLite mirror to {output_path}", file=sys.stderr)

    fetched_counts: dict[str, int] = {}
    for endpoint in endpoints:
        fetched_counts[endpoint] = paginate_endpoint(
            conn=conn,
            client=client,
            endpoint=endpoint,
            page_size=args.page_size,
            max_pages=args.max_pages_per_endpoint,
        )

    if not args.skip_recent_html:
        matched = scrape_popular_decklist_pages(
            conn=conn,
            client=client,
            max_pages=args.max_recent_pages,
        )
        upsert_metadata(conn, "popular_html_matches", matched)
        conn.commit()

    summary = summarize(conn)
    upsert_metadata(conn, "table_counts", summary)
    upsert_metadata(conn, "generated_at", utc_now())
    conn.commit()

    print(json.dumps({"fetched": fetched_counts, "tables": summary}, indent=2), file=sys.stderr)
    print(str(output_path))
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
