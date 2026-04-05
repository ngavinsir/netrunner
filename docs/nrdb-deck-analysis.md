# NetrunnerDB Deck Analysis DB

Build the database:

```bash
python3 scripts/nrdb_deck_analysis_mirror.py --output netrunnerdb-deck-analysis.sqlite3
```

The mirror is aimed at deckbuilding analysis, not private-site reconstruction. It stores:

- Public v3 API resources such as `cards`, `printings`, `decklists`, `reviews`, and `rulings`
- Public decklist detail pages for deck popularity signals:
  - likes
  - favorites
  - comments
  - author reputation

Useful tables:

- `decklists`
- `decklist_cards`
- `cards`
- `printings`
- `card_sets`
- `card_cycles`

Useful views:

- `decklists_scored`
- `card_popularity`
- `pack_card_popularity`
- `popular_decklists_scored`
- `popular_card_popularity`
- `popular_pack_card_popularity`

Default popularity score:

```sql
1 + likes + (2 * favorites) + comments
```

This keeps every public decklist in the sample while still giving more weight to decklists that got attention.

Example queries:

Top runner cards overall:

```sql
SELECT
  title,
  decklists_using,
  weighted_copies_used
FROM card_popularity
WHERE side_id = 'runner'
  AND card_type_id <> 'identity'
ORDER BY weighted_copies_used DESC
LIMIT 50;
```

Top runner cards from the site’s popular decklists only:

```sql
SELECT
  title,
  decklists_using,
  weighted_copies_used
FROM popular_card_popularity
WHERE side_id = 'runner'
  AND card_type_id <> 'identity'
ORDER BY weighted_copies_used DESC
LIMIT 50;
```

Top corp cards in a specific pack:

```sql
SELECT
  rank_in_pack_for_side,
  title,
  weighted_copies_used,
  decklists_using
FROM pack_card_popularity
WHERE card_set_id = 'elevation'
  AND side_id = 'corp'
  AND card_type_id <> 'identity'
ORDER BY rank_in_pack_for_side
LIMIT 25;
```

Top corp cards in a specific pack, restricted to popular decklists:

```sql
SELECT
  rank_in_pack_for_side,
  title,
  weighted_copies_used,
  decklists_using
FROM popular_pack_card_popularity
WHERE card_set_id = 'elevation'
  AND side_id = 'corp'
  AND card_type_id <> 'identity'
ORDER BY rank_in_pack_for_side
LIMIT 25;
```

Most popular cards for a specific identity:

```sql
SELECT
  c.title,
  COUNT(*) AS deck_appearances,
  SUM(dc.quantity) AS copies_used,
  SUM(ds.popularity_score * dc.quantity) AS weighted_copies
FROM decklists_scored ds
JOIN decklist_cards dc
  ON dc.decklist_id = ds.decklist_id
JOIN cards c
  ON c.card_id = dc.card_id
WHERE ds.identity_card_id = 'hoshiko_shiro_untold_protagonist'
  AND c.card_type_id <> 'identity'
GROUP BY c.card_id, c.title
ORDER BY weighted_copies DESC
LIMIT 40;
```

Strongest packs by weighted usage:

```sql
SELECT
  card_set_id,
  pack_name,
  side_id,
  SUM(weighted_copies_used) AS pack_weight
FROM pack_card_popularity
WHERE card_type_id <> 'identity'
GROUP BY card_set_id, pack_name, side_id
ORDER BY pack_weight DESC;
```
