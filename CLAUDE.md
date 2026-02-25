# Venus dbt Project — Claude Context

## Project Context
- **Team**: xvslove_team
- **Dune MCP**: configured as HTTP MCP at `https://api.dune.com/mcp/v1`; requires Claude Code restart to load tools
- **API keys**: stored locally in `~/.claude.json` — do NOT commit to git
- **Branch**: `main`
- **Schedule**: daily at 03:00 UTC via GitHub Actions (`dbt_prod.yml`)

## Current Status
- 4 models DEPLOYED to production (`dune.xvslove_team.*`), incremental, verified working
- GitHub Actions schedule enabled, Dune native cron disabled (commented out in `dbt_project.yml`)
- Template models deleted from `models/templates/` and junk tables dropped from prod
- `dbt_ci.yml` deleted (was causing workflow file errors); `dbt_deploy.yml` kept but inactive
- `workflow_dispatch` supports `--select` and `--full-refresh` inputs for manual runs only
- Daily cron runs incrementally (no `--full-refresh`); `--full-refresh` is manual-only override
- Health check query created on Dune: query ID 6698398
- Tables are private by default; can toggle public in Dune UI or via `+meta.dune.is_public`

## Table Name Migration — COMPLETED
- 90 Dune queries updated across team account via API + MCP (no template repo needed)
- Old → new table name mapping:
  1. `dune.xvslove_team.result_methodology_daily_market_stats` → `dune.xvslove_team.daily_market_stats`
  2. `dune.xvslove_team.result_daily_user_stats` → `dune.xvslove_team.daily_user_stats`
  3. `dune.xvslove_team.result_all_user_transactions` → `dune.xvslove_team.all_user_transactions`
  4. `dune.xvslove_team.result_daily_market_info` → `dune.xvslove_team.daily_market_info`
- Verified: 0 old table names remain across all 428 team queries
- Note: queries with Dune `{{parameters}}` fail raw PATCH API with 400; use MCP `updateDuneQuery` tool instead

## Dune Queries → dbt Models
1. **5525501** → `daily_market_info.sql`
2. **5468916** → `daily_market_stats.sql` (refs daily_market_info)
3. **5595697** → `all_user_transactions.sql` (refs daily_market_info)
4. **5524758** → `daily_user_stats.sql` (refs daily_market_info + all_user_transactions)

## Data Freshness
- `daily_*` models show up to **yesterday** — they aggregate full days
- `all_user_transactions` shows **today's** data — it captures real-time events
- `__dbt_tmp` tables are temp staging tables from incremental runs; safe to drop if left behind
- GitHub Actions run tested: ~21 min total (~14.6 min for daily_market_info, the bottleneck)
- No data tests currently defined; `dbt test` shows "Nothing to do"

## Key Notes
- dbt is at `.venv/bin/dbt` (not on PATH)
- Project uses Trino adapter, `dune.xvslove_team` schema
- Incremental strategy: `delete+insert` with 2-day lookback, `--full-refresh` for first run
- External query deps kept as raw refs: query_5204403, query_5754116, query_5930024, query_5579782, query_5667382
- dev target → `xvslove_team__tmp_` schema; prod target → `xvslove_team` schema
- `gh` CLI installed via Homebrew, authenticated as Venus-ZD
- `all_user_transactions` uses `evt_block_date` as date column (not `day` or `block_date`)
- Personal Dune account API key has no paid plan — Query management endpoints require Analyst plan or higher; use team API key for bulk operations
