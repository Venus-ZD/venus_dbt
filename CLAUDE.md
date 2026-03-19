# Venus dbt Project — Claude Context

## Project Context

- **Team**: xvslove_team
- **Branch**: `main`
- **Schedule**: daily at 03:00 UTC via GitHub Actions (`dbt_prod.yml`), typically starts ~05:00 UTC due to scheduler delay
- **Dune MCP**: HTTP MCP at `https://api.dune.com/mcp/v1`; requires Claude Code restart to load tools
- **API keys**: stored locally in `~/.claude.json` — do NOT commit to git

## Models

4 models deployed to `dune.xvslove_team.*`, all incremental `delete+insert`:

| Model | Refs | Date Column |
|-------|------|-------------|
| `daily_market_info` | — | `day` |
| `daily_market_stats` | daily_market_info | `day` |
| `all_user_transactions` | daily_market_info | `evt_block_date` |
| `daily_user_stats` | daily_market_info + all_user_transactions | `day` |

- External query deps (raw refs): query_5204403, query_5754116, query_5930024, query_5579782, query_5667382
- `daily_*` shows up to yesterday; `all_user_transactions` shows today's data

## Table Visibility

- Tables are private by default on Dune
- All 4 models have `post_hook` that runs `ALTER TABLE SET PROPERTIES extra_properties = map_from_entries(ARRAY[ROW('dune.public', 'true')])` — keeps tables public even after full refresh
- `+meta.dune.is_public` does NOT work (dbt-trino adapter doesn't support it)
- Visibility SQL requires transformation session — must run via dbt, not Dune query editor

## Backfill Procedure (New Asset in dataset_markets_all_chains)

2-day incremental lookback won't cover historical data. To backfill:

1. Change incremental filters in all 4 models to a hardcoded start date (e.g., `DATE '2026-03-02'`):
   - `daily_market_info.sql`: L138 prices filter + L171 main filter
   - `daily_market_stats.sql`: L194 main filter
   - `all_user_transactions.sql`: L261 prices filter + L265 main filter
   - `daily_user_stats.sql`: L41 timeseries GREATEST() start date
2. Run: `.venv/bin/dbt run --target prod`
3. Revert all files back to `date_add('day', -N, current_date)`

## Key Notes

- dbt: `.venv/bin/dbt` (not on PATH), Trino adapter
- dev target → `xvslove_team__tmp_`; prod target → `xvslove_team`
- `workflow_dispatch` supports `--select` and `--full-refresh` for manual runs
- `gh` CLI authenticated as Venus-ZD
- Personal Dune API key has no paid plan; use team API key for bulk operations
