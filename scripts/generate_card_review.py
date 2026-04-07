#!/usr/bin/env python3
"""
Generate a markdown review document for all cards implemented in the Zig engine.

For each card in catalog.zig, emits:
  - Card title and metadata
  - Card image (from netrunnerdb CDN, same URL pattern as the TUI)
  - Full card definition block extracted from catalog.zig
"""

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPO_ROOT / "zig/src/engine/catalog.zig"
CARDS_JSON_PATH = REPO_ROOT / "zig/src/data/cards.json"
OUTPUT_PATH = REPO_ROOT / "docs/card-review.md"


def load_cards_json() -> dict[int, dict]:
    with open(CARDS_JSON_PATH) as f:
        cards = json.load(f)
    return {c["code"]: c for c in cards}


def extract_card_definitions(source: str) -> list[dict]:
    """
    Extract each card definition block from the all_cards array in catalog.zig.
    Returns list of dicts with keys: title, code, start_line, end_line, text
    """
    # Find the start of all_cards
    array_match = re.search(r'^pub const all_cards = \[_\]CardSpec\{', source, re.MULTILINE)
    if not array_match:
        print("ERROR: Could not find all_cards in catalog.zig", file=sys.stderr)
        sys.exit(1)

    array_start = array_match.end()
    lines = source.splitlines(keepends=True)

    # Map character offset -> line number (1-based)
    offset_to_line = []
    pos = 0
    for i, line in enumerate(lines, 1):
        offset_to_line.append((pos, i))
        pos += len(line)

    def char_to_line(offset: int) -> int:
        lo, hi = 0, len(offset_to_line) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if offset_to_line[mid][0] <= offset:
                lo = mid
            else:
                hi = mid - 1
        return offset_to_line[lo][1]

    cards = []
    i = array_start

    while i < len(source):
        # Skip whitespace
        while i < len(source) and source[i] in ' \t\n\r':
            i += 1

        if i >= len(source):
            break

        # End of all_cards array
        if source[i] == '}':
            break

        # Each entry starts with ".{"
        if source[i:i+2] != '.{':
            # Could be a comment or something else — skip the line
            end = source.find('\n', i)
            if end == -1:
                break
            i = end + 1
            continue

        # Find the matching closing brace for this entry using brace counting
        entry_start = i
        depth = 0
        j = i
        while j < len(source):
            ch = source[j]
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    # Entry ends here; skip trailing comma and whitespace
                    entry_end = j + 1
                    # Consume trailing comma
                    k = entry_end
                    while k < len(source) and source[k] in ' \t':
                        k += 1
                    if k < len(source) and source[k] == ',':
                        entry_end = k + 1
                    break
            elif ch == '"':
                # Skip string literal (handle escape sequences)
                j += 1
                while j < len(source):
                    if source[j] == '\\':
                        j += 2
                        continue
                    if source[j] == '"':
                        break
                    j += 1
            elif source[j:j+2] == '//':
                # Skip line comment
                end = source.find('\n', j)
                if end == -1:
                    j = len(source)
                    break
                j = end
            j += 1

        entry_text = source[entry_start:entry_end]

        # Extract title and code
        title_match = re.search(r'\.title\s*=\s*"([^"]+)"', entry_text)
        code_match = re.search(r'\.code\s*=\s*(\d+)', entry_text)

        if title_match and code_match:
            start_line = char_to_line(entry_start)
            end_line = char_to_line(entry_end - 1)
            cards.append({
                'title': title_match.group(1),
                'code': int(code_match.group(1)),
                'start_line': start_line,
                'end_line': end_line,
                'text': entry_text.rstrip(',\n'),
            })

        i = entry_end

    return cards


def side_label(side: str) -> str:
    return "Corp" if side == "corp" else "Runner"


def type_label(card_type: str) -> str:
    """Convert cards.json type field to a readable label without side prefix."""
    t = card_type.replace('_identity', ' Identity').replace('_', ' ').title()
    # Strip leading "Corp " or "Runner " prefix (already shown as side)
    for prefix in ('Corp ', 'Runner '):
        if t.startswith(prefix):
            t = t[len(prefix):]
    return t


def make_anchor(title: str) -> str:
    """Generate a GitHub-style anchor from a title, handling unicode."""
    # Normalize unicode characters to ASCII equivalents for anchor
    import unicodedata
    normalized = unicodedata.normalize('NFKD', title)
    ascii_title = normalized.encode('ascii', 'ignore').decode('ascii')
    return re.sub(r'[^a-z0-9]+', '-', ascii_title.lower()).strip('-')


def generate_markdown(cards_meta: dict[int, dict], card_defs: list[dict]) -> str:
    lines = [
        "# Zig Engine Card Implementation Review",
        "",
        f"Auto-generated from `zig/src/engine/catalog.zig`.",
        f"Total cards: **{len(card_defs)}**",
        "",
        "---",
        "",
    ]

    # Table of contents grouped by side
    corp_cards = [c for c in card_defs if cards_meta.get(c['code'], {}).get('side') == 'corp'
                  or c['title'].lower().find('corp') >= 0]
    runner_cards = [c for c in card_defs if cards_meta.get(c['code'], {}).get('side') == 'runner']

    # Simple TOC
    lines += ["## Contents", ""]
    for card in card_defs:
        meta = cards_meta.get(card['code'], {})
        title = meta.get('title', card['title'])
        anchor = make_anchor(title)
        side = side_label(meta.get('side', ''))
        card_type = type_label(meta.get('type', ''))
        lines.append(f"- [{title}](#{anchor}) — {side} {card_type} `{card['code']}`")
    lines += ["", "---", ""]

    # Card entries
    for card in card_defs:
        meta = cards_meta.get(card['code'], {})
        title = meta.get('title', card['title'])
        image_url = meta.get('image_url', f"https://card-images.netrunnerdb.com/v2/xlarge/{card['code']}.webp")
        side = side_label(meta.get('side', ''))
        card_type = type_label(meta.get('type', ''))
        faction = meta.get('faction', '').replace('_', ' ').title()
        anchor = make_anchor(title)

        lines += [
            f"## {title}",
            "",
            f"**Side:** {side} &nbsp; **Type:** {card_type} &nbsp; **Faction:** {faction} &nbsp; **Code:** `{card['code']}`  ",
            f"**catalog.zig lines:** {card['start_line']}–{card['end_line']}",
            "",
            f"![{title}]({image_url})",
            "",
            "```zig",
            card['text'],
            "```",
            "",
            "---",
            "",
        ]

    return "\n".join(lines)


def main():
    print(f"Reading {CATALOG_PATH} ...")
    source = CATALOG_PATH.read_text()

    print(f"Reading {CARDS_JSON_PATH} ...")
    cards_meta = load_cards_json()

    print("Extracting card definitions ...")
    card_defs = extract_card_definitions(source)
    print(f"Found {len(card_defs)} card definitions.")

    print("Generating markdown ...")
    md = generate_markdown(cards_meta, card_defs)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(md)
    print(f"Written to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
