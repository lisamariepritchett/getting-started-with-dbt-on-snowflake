# dbt on Snowflake — Architecture & Developer Guide

## Overview

This project uses **Snowflake-native dbt projects** with **GitHub Actions CI/CD**.
All dbt execution happens inside Snowflake (not locally). Code lives in a GitHub
repository and is deployed via `snow dbt deploy` / `snow dbt execute`.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              GITHUB REPOSITORY                                   │
│                              (main branch protected)                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   feature branch ──── PR opened ──── PR merged to main                          │
│        │                  │                  │                                   │
│        │                  ▼                  ▼                                   │
│        │         ┌────────────────┐  ┌────────────────────┐                     │
│        │         │ incoming_pr.yml│  │  pr_merged.yml      │                     │
│        │         │ (CI)           │  │  (CD)               │                     │
│        │         └───────┬────────┘  └─────────┬──────────┘                     │
│        │                 │                     │                                 │
└────────┼─────────────────┼─────────────────────┼─────────────────────────────────┘
         │                 │                     │
         │                 │ OIDC                │ OIDC
         │                 ▼                     ▼
┌────────┼─────────────────────────┐  ┌──────────────────────────────────┐
│        │     DEV ACCOUNT         │  │        PROD ACCOUNT               │
│        │                         │  │                                   │
│        ▼                         │  │                                   │
│  ┌───────────┐                   │  │                                   │
│  │ Workspace │ ← developers      │  │  (no workspace here)              │
│  │ (branch)  │   build/test      │  │                                   │
│  └─────┬─────┘   locally         │  │                                   │
│        │                         │  │                                   │
│        ▼                         │  │                                   │
│  ┌─────────────────────┐        │  │  ┌─────────────────────────┐      │
│  │ TASTY_BYTES_DBT_DB   │        │  │  │ TASTY_BYTES_STAGE_DB     │      │
│  │ ├── dev              │◄── CI  │  │  │ ├── pos_system           │◄── CD│
│  │ ├── dev_lisa         │        │  │  │ ├── crm                  │      │
│  │ └── dev_bob          │        │  │  │ └── <new folders auto>   │      │
│  └─────────────────────┘        │  │  └─────────────────────────┘      │
│                                  │  │                                   │
│  ┌─────────────────────────┐    │  │  ┌─────────────────────────┐      │
│  │ PROD_TASTY_BYTES_RAW_EL │    │  │  │ TASTY_BYTES_EDW_DB       │      │
│  │ (dev raw sources)       │    │  │  │ ├── marketing            │◄── CD│
│  │ └── raw (read-only)     │    │  │  │ ├── finance              │      │
│  └─────────────────────────┘    │  │  │ └── <new folders auto>   │      │
│                                  │  │  └─────────────────────────┘      │
│  Role: DBT_DEVELOPER             │  │                                   │
│  Role: DBT_CI (CI builds)        │  │  ┌─────────────────────────┐      │
│                                  │  │  │ TASTY_BYTES_RAW_EL_DB    │      │
│                                  │  │  │ (prod raw sources)       │      │
│                                  │  │  │ └── raw (read-only)      │      │
│                                  │  │  └─────────────────────────┘      │
│                                  │  │                                   │
│                                  │  │  Role: DBT_CI (CD + manual runs)  │
└──────────────────────────────────┘  └───────────────────────────────────┘

Manual prod run: GitHub Actions → "CD Prod Run" → workflow_dispatch → main branch only
```

## Databases

| Database | Purpose | Who writes | Account |
|----------|---------|------------|---------|
| `TASTY_BYTES_DBT_DB` | Dev schemas (dev, dev_lisa, etc.) | Developers | Dev |
| `PROD_TASTY_BYTES_RAW_EL_DB` | Raw source data for dev/test | Nobody (read-only, simulates prod share) | Dev |
| `TASTY_BYTES_RAW_EL_DB` | Raw source data for prod | EL tool (read-only to dbt) | Prod |
| `TASTY_BYTES_STAGE_DB` | Prod staging layer (views) | CI/CD only | Prod |
| `TASTY_BYTES_EDW_DB` | Prod marts layer (tables) | CI/CD only | Prod |

## Roles

| Role | Purpose | Granted to | Account |
|------|---------|------------|---------|
| `DBT_DEVELOPER` | Dev work — cannot write to prod | All developers (default role) | Dev |
| `DBT_CI` | All CI/CD: PR checks, prod deploys, manual runs | `github_actions_service_user` | Both |

**Key protection:** If your default role is `DBT_DEVELOPER`, you cannot accidentally
write to production databases (`TASTY_BYTES_STAGE_DB`, `TASTY_BYTES_EDW_DB`). The prod
profile in `profiles.yml` uses `role: DBT_CI`, which only the service user has.

**Note:** Users with `ACCOUNTADMIN` inherit all roles. In the multi-account setup,
the prod account won't have a dbt workspace at all — developers only have workspaces
in the dev account, and all prod builds flow exclusively through GitHub Actions.

## Developer Setup

### 1. Get your schema and profile target

Ask an admin to run:
```sql
CREATE SCHEMA IF NOT EXISTS TASTY_BYTES_DBT_DB.DEV_<YOUR_NAME>;
GRANT ALL ON SCHEMA TASTY_BYTES_DBT_DB.DEV_<YOUR_NAME> TO ROLE DBT_DEVELOPER;
GRANT ALL ON FUTURE TABLES IN SCHEMA TASTY_BYTES_DBT_DB.DEV_<YOUR_NAME> TO ROLE DBT_DEVELOPER;
GRANT ALL ON FUTURE VIEWS IN SCHEMA TASTY_BYTES_DBT_DB.DEV_<YOUR_NAME> TO ROLE DBT_DEVELOPER;
GRANT ROLE DBT_DEVELOPER TO USER <YOUR_USERNAME>;
ALTER USER <YOUR_USERNAME> SET DEFAULT_ROLE = DBT_DEVELOPER;
```

Then add your target to `profiles.yml`:
```yaml
dev_<your_name>:
  type: snowflake
  account: 'not needed'
  user: 'not needed'
  role: DBT_DEVELOPER
  database: tasty_bytes_dbt_db
  schema: dev_<your_name>
  warehouse: TASTY_BYTES_DBT_DB
  threads: 8
```

### 2. Daily workflow

1. Create a feature branch from `main`
2. Open the workspace, switch to your branch
3. Select your profile (e.g. `dev_lisa`) in the dbt UI
4. Develop and test — builds go to your isolated schema
5. Push and open a PR → CI runs automatically
6. After review, merge → CD deploys to prod

### 3. What happens on PR (CI)

- Detects what changed via `git diff` against `main`
- Model `.sql` changed → deploys + builds changed models + downstream
- Only `.yml` test files → deploys + runs scoped tests
- Macros/config changed → deploys only (validates compilation)
- Non-dbt changes → skips entirely
- Uses `--target dev` and role `DBT_CI`

### 4. What happens on merge (CD)

- Same change detection as CI
- Deploys prod project object with `--default-target prod`
- Builds/tests only what changed using `--target prod`
- Uses role `DBT_CI` (writes to stage_db / edw_db)

## Model Routing

Models route to different databases/schemas based on folder structure in production.
In dev, everything stays flat in your personal schema.

| Folder | Prod destination | Dev destination |
|--------|-----------------|-----------------|
| `models/staging/<folder>/` | `tasty_bytes_stage_db.<folder>` | `tasty_bytes_dbt_db.dev_<name>` |
| `models/marts/<folder>/` | `tasty_bytes_edw_db.<folder>` | `tasty_bytes_dbt_db.dev_<name>` |

**Examples:**
| Folder | Prod destination |
|--------|-----------------|
| `models/staging/pos_system/` | `tasty_bytes_stage_db.pos_system` |
| `models/staging/crm/` | `tasty_bytes_stage_db.crm` |
| `models/staging/new_system/` | `tasty_bytes_stage_db.new_system` (auto!) |
| `models/marts/finance/` | `tasty_bytes_edw_db.finance` |
| `models/marts/marketing/` | `tasty_bytes_edw_db.marketing` |

Routing is automatic — controlled entirely by macros:
- `macros/generate_schema_name.sql` — derives schema from the folder name
- `macros/generate_database_name.sql` — derives database from the layer (`staging` → stage_db, `marts` → edw_db)

**To add a new domain:** Just create a new folder (e.g. `models/staging/payments/`)
and add models in it. No `dbt_project.yml` changes needed. The schema is auto-created
on first prod build (the `DBT_CI` role has `CREATE SCHEMA` privileges).

## Source Database Routing

Sources read from different databases depending on target:
- **`prod` target** → `tasty_bytes_raw_el_db.raw`
- **All dev targets** → `prod_tasty_bytes_raw_el_db.raw`

This simulates separate prod/dev raw data environments.

**Implementation:** Controlled by inline Jinja, for example `models/staging/pos_system/__sources.yml`:
```yaml
database: "{% if target.name == 'prod' %}tasty_bytes_raw_el_db{% else %}prod_tasty_bytes_raw_el_db{% endif %}"
```

Note: Custom macros (`{{ my_macro() }}`) don't work in source YAML files — you must
use inline Jinja with `target.name` directly.

## Manual Prod Runs

For one-off prod rebuilds (backfills, fixes):

1. Go to GitHub → Actions → **"CD Prod Run"** (left sidebar)
2. Click **"Run workflow"** (top right)
3. Select **main** branch (enforced — other branches will fail)
4. Choose the dbt command (`run`, `build`, or `test`)
5. Enter the `--select` argument (e.g. `orders`, `tag:daily`, `+my_model`)
6. Optionally enter `--exclude`
7. Click **"Run workflow"**

This always runs against main branch code using the already-deployed project object.
Model names are lowercase (matching the filename without `.sql`).

**Selector examples:**
| What you want | Selector |
|---------------|----------|
| One model | `customer_loyalty_metrics` |
| Model + its upstream | `+orders` |
| Model + its downstream | `orders+` |
| A tag | `tag:daily` |
| All staging models | `path:models/staging` |
| All models (full rebuild) | `path:models` |
| Everything in one folder | `path:models/marts/finance` |

The `--select` field is required to prevent accidental full rebuilds.

## Do NOT

- **Never** add a dbt workspace to the prod Snowflake account — all prod changes go through GitHub Actions.
- Commit directly to `main` — always use feature branches + PRs. Enforce this with GitHub branch protection rules (require PR + status checks to pass before merging).
- Use `env_var()` in profiles.yml (doesn't work in Snowflake dbt)
- Use custom macros in source YAML files (use inline Jinja with `target.name` instead)
- Use UPPERCASE model names in `--select` (dbt selectors are case-sensitive, use lowercase)

## Repository Structure

```
tasty_bytes_dbt_demo/
├── dbt_project.yml          # Model routing config
├── profiles.yml             # All targets (dev, dev_lisa, prod)
├── packages.yml             # dbt_utils, dbt_semantic_view
├── macros/
│   ├── generate_schema_name.sql
│   └── generate_database_name.sql
├── models/
│   ├── staging/
│   │   ├── pos_system/      # 7 POS models + sources + tests
│   │   └── crm/             # 1 CRM model
│   └── marts/
│       ├── finance/         # orders.sql, sales_metrics_by_location.py
│       └── marketing/       # customer_loyalty_metrics.sql
├── setup/
│   ├── tasty_bytes_setup.sql          # Original demo data setup
│   ├── ci_cd_setup.sql               # OIDC + service user + network rules
│   └── rbac_and_routing_setup.sql    # Roles + multi-db routing
└── .github/workflows/
    ├── incoming_pr.yml      # CI workflow
    └── pr_merged.yml        # CD workflow
```
