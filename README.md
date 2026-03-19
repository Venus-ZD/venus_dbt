# Venus dbt Project

dbt project for Venus Protocol data models on Dune (Trino adapter).

## Setup

```bash
uv sync                    # Install Python dependencies
uv run dbt deps            # Install dbt packages
uv run dbt debug           # Test connection
```

**Required environment variables:**

| Variable         | Description          | Where to Get                                           |
| ---------------- | -------------------- | ------------------------------------------------------ |
| `DUNE_API_KEY`   | Dune API key         | [dune.com/settings/api](https://dune.com/settings/api) |
| `DUNE_TEAM_NAME` | Team name for schema | Your Dune team name                                    |

## Targets

Both targets connect to the same Dune API (`trino.api.dune.com`); the target controls schema naming:

| Target | Schema             | Use Case    |
| ------ | ------------------ | ----------- |
| `dev`  | `{team}__tmp_`     | Development |
| `prod` | `{team}`           | Production  |

Set `DEV_SCHEMA_SUFFIX=your_name` for personal dev schema: `{team}__tmp_{your_name}`.

## Common Commands

```bash
uv run dbt run                                    # Run all models (dev)
uv run dbt run --target prod                      # Run all models (prod)
uv run dbt run --select model_name                # Run specific model
uv run dbt run --select model_name --full-refresh # Full refresh
uv run dbt test                                   # Run tests
```

## Models

4 incremental models in `models/venus/`, all `delete+insert` strategy:

| Model | Description | Depends On |
|-------|-------------|------------|
| `daily_market_info` | Base market data | — |
| `daily_market_stats` | Market statistics | daily_market_info |
| `all_user_transactions` | User transaction log | daily_market_info |
| `daily_user_stats` | User statistics | daily_market_info, all_user_transactions |

Tables are written to `dune.xvslove_team.*` and auto-set to public via post-hook.

## GitHub Actions

**`dbt_prod.yml`** — daily incremental run at 03:00 UTC, with manual `workflow_dispatch` supporting `--select` and `--full-refresh`.

## Querying on Dune

Models must be queried with the `dune` catalog prefix:

```sql
select * from dune.xvslove_team.daily_market_stats
```

## Project Structure

```
models/venus/        # dbt models
macros/              # Custom macros (schema overrides, table visibility)
scripts/             # Utility scripts (drop_tables.py)
profiles.yml         # Trino connection profiles
dbt_project.yml      # Project configuration
```

## Links

- [dbt-trino Setup](https://docs.getdbt.com/docs/core/connect-data-platform/trino-setup)
- [dbt Documentation](https://docs.getdbt.com/)
