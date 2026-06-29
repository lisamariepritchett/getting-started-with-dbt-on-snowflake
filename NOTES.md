# dbt CI/CD Demo Project - Handoff Notes

## Purpose
This is a demo project testing whether Snowflake dbt projects + GitHub Actions CI/CD
will work for our mid-sized company's needs. The goal is to validate the workflow
before migrating our larger production dbt project.

## Repository
- GitHub: `lisamariepritchett/getting-started-with-dbt-on-snowflake`
- dbt project folder: `tasty_bytes_dbt_demo/`
- Snowflake account: `gi91075`

## What's Been Set Up

### Snowflake Objects
- Database: `tasty_bytes_dbt_db` with schemas: `dev`, `integrations`, `dev_lisa` (prod and raw schemas dropped)
- Service user: `github_actions_service_user` (OIDC auth with GitHub Actions)
- OIDC subject: `repo:lisamariepritchett/getting-started-with-dbt-on-snowflake:environment:prod`
- Network rule: `dbt_network_rule` (allows hub.getdbt.com, codeload.github.com)
- External access integration: `dbt_ext_access`
- Git secret + API integration for repo access
- Setup SQL is in `run_manual.sql`

### GitHub Actions Workflows
Both workflows use OIDC workload identity (no passwords stored).

**`incoming_pr.yml`** (CI - runs on PR to main):
- Detects what changed via git diff
- Model .sql changed → deploy + build changed models + downstream (`model+`)
- Only .yml test files changed → deploy + run tests scoped to changed folders
- Macros/config changed → deploy only (validates compilation)
- Non-dbt changes → skip entirely

**`pr_merged.yml`** (CD - runs on push to main):
- Same change detection logic as CI
- Deploys production project object: `tasty_bytes_dbt_object_gh_action`
- Builds/tests only what changed, targeting `--target prod`

### Developer Workflow
- Each developer gets their own profile/target (e.g. `dev_lisa`) and schema
- Developers select their profile in the Snowflake dbt project UI
- CI uses `--target dev`, CD uses `--target prod`
- `profiles.yml` is committed to repo with all targets

### Multi-Database/Schema Routing (NEW)
Production uses multiple databases and schemas based on folder structure.
Developer environments keep everything flat in a single schema.

**Folder → Prod routing:**
```
models/staging/pos_system/  → tasty_bytes_stage_db.pos_system
models/staging/crm/         → tasty_bytes_stage_db.crm
models/marts/marketing/     → tasty_bytes_edw_db.marketing
models/marts/finance/       → tasty_bytes_edw_db.finance
```

**Dev routing (dev_lisa, dev_bob, etc.):**
All models → `tasty_bytes_dbt_db.dev_lisa` regardless of folder.

**Controlled by:**
- `macros/generate_schema_name.sql` — derives schema from folder name automatically (no config needed)
- `macros/generate_database_name.sql` — derives database from layer (`staging` → stage_db, `marts` → edw_db)
- `dbt_project.yml` — only sets materialization per layer (view for staging, table for marts)

**Current model locations:**
- `models/staging/pos_system/` — 7 POS models (country, franchise, location, menu, order_detail, order_header, truck)
- `models/staging/crm/` — 1 CRM model (customer_loyalty)
- `models/marts/finance/orders.sql` + `sales_metrics_by_location.py` (Snowpark)
- `models/marts/marketing/customer_loyalty_metrics.sql`

**To test prod routing, need to create:**
```sql
CREATE DATABASE IF NOT EXISTS tasty_bytes_stage_db;
CREATE SCHEMA IF NOT EXISTS tasty_bytes_stage_db.pos_system;
CREATE SCHEMA IF NOT EXISTS tasty_bytes_stage_db.crm;
CREATE DATABASE IF NOT EXISTS tasty_bytes_edw_db;
CREATE SCHEMA IF NOT EXISTS tasty_bytes_edw_db.marketing;
CREATE SCHEMA IF NOT EXISTS tasty_bytes_edw_db.finance;
```

### Raw Source Database Routing
Sources point to different databases depending on target, simulating separate
prod and dev/test raw data environments (like a share from prod to dev).

- **`prod` target** → reads from `tasty_bytes_raw_el_db.raw`
- **All other targets** (dev, dev_lisa, etc.) → reads from `prod_tasty_bytes_raw_el_db.raw`

Controlled by inline Jinja in `models/staging/pos_system/__sources.yml`:
```yaml
database: "{% if target.name == 'prod' %}tasty_bytes_raw_el_db{% else %}prod_tasty_bytes_raw_el_db{% endif %}"
```

Note: Custom macros (`{{ my_macro() }}`) don't work in source YAML files — use inline
Jinja with `target.name` instead. Source name was renamed from `tb_101` to `tasty_bytes_raw`.

### Snowflake Databases
```
tasty_bytes_dbt_db          — dbt project database (dev, dev_lisa schemas only; prod/raw dropped)
tasty_bytes_raw_el_db       — prod raw source data (was clone of tasty_bytes_dbt_db.raw, now standalone)
prod_tasty_bytes_raw_el_db  — dev raw source data (was clone, now standalone; simulates share from prod)
tasty_bytes_stage_db        — prod staging layer (pos_system, crm schemas)
tasty_bytes_edw_db          — prod marts layer (marketing, finance schemas)
```

### profiles.yml Prod Target
Prod target now uses `database: tasty_bytes_stage_db` with `schema: unrouted` as a canary.
If a model has no explicit `+database`/`+schema` config, it falls into `tasty_bytes_stage_db.unrouted`
which either fails (schema doesn't exist) or is immediately visible as misconfigured.

## Key Decisions Made
1. No `env_var()` in profiles (doesn't work in Snowflake dbt projects)
2. Named targets per developer instead of dynamic schemas
3. Git diff-based model selection (not `state:modified` - unavailable in Snowflake dbt)
4. Deploy step validates compilation, so no separate compile step needed
5. Tests scoped by folder path (`--select path:models/staging`)
6. No full builds triggered on uncertainty - compile/deploy only
7. Dev environments are flat (single schema); prod routes to multiple databases/schemas
8. Macro-based routing: `generate_schema_name` + `generate_database_name`
9. Only `target.name == 'prod'` triggers multi-db routing (not `dev`) — caught a bug where
   `['dev', 'prod']` caused CI dev builds to route to prod databases
10. Custom macros don't work in source YAML — must use inline Jinja with `target.name`
11. Workflow env vars hardcoded per workflow (not `${{ vars.X }}`) — both share the same
    GitHub environment (`prod`) for OIDC, so can't use separate env variables for CI vs CD

## CLI Flags Discovered (via trial and error)
- `--install-local-deps` (not --install-packages)
- `--external-access-integration` (not --ext-access-integrations)
- `--source ./tasty_bytes_dbt_demo` (folder must match actual repo structure)

## Remaining Work / To Test
- [x] Verify dev_lisa flat routing works with new macros ✓
- [x] Verify dev (CI) flat routing + correct source database ✓
- [x] Drop `tasty_bytes_dbt_db.raw` (clones are standalone now) ✓
- [x] Drop `tasty_bytes_dbt_db.prod` (prod routes to stage_db/edw_db now) ✓
- [x] Update prod target: database → `tasty_bytes_stage_db`, schema → `unrouted` ✓
- [x] Move `sales_metrics_by_location.py` to `models/marts/finance/` ✓
- [x] Hardcode workflow env vars: CI → `TASTY_BYTES_DBT_DB.DEV`, CD → `TASTY_BYTES_STAGE_DB.PUBLIC` ✓
- [x] **RBAC roles** created: DBT_DEVELOPER + DBT_CI (simplified 2-role model) ✓
- [x] Updated profiles.yml to use new roles per target ✓
- [x] Granted DBT_EXT_ACCESS integration to DBT_DEVELOPER (needed for dbt deps) ✓
- [x] Created `setup/rbac_and_routing_setup.sql` with all grant statements ✓
- [x] Created `TEAM_GUIDE.md` for team reference ✓
- [x] **Manual prod job execution** via `workflow_dispatch` on CD workflow ✓
- [x] Auto-routing macros: schema derived from folder, database from layer ✓
- [x] Simplified dbt_project.yml (removed per-folder +schema/+database) ✓
- [ ] Test prod routing after merge (models should land in stage_db/edw_db)
- [ ] Test all workflow conditions (model change, test-only, macro, skip)
- [ ] Create test user with only DBT_DEVELOPER to verify prod is truly blocked
- [ ] Multi-account setup (dev/test account + prod account) when available
- [ ] Add proper dbt tests back to __schema.yml (currently minimal for testing)
- [ ] Consider blue/green deployment or clone-before-deploy for prod safety
- [ ] Branch protection rules on main (require CI to pass before merge)
- [ ] Evaluate for larger project: many models, multiple developers, test execution time
- [ ] Rename warehouse `TASTY_BYTES_DBT_DB` → `DBT_WH` (or similar)

## RBAC (Implemented)

### Roles (2-role model)

**`DBT_DEVELOPER`** — assigned to all human users as default role
- USAGE on warehouse
- READ on `prod_tasty_bytes_raw_el_db` (dev raw sources)
- ALL on `tasty_bytes_dbt_db` dev schemas (dev, dev_lisa, dev_bob, etc.)
- NO write access to `tasty_bytes_stage_db` or `tasty_bytes_edw_db`

**`DBT_CI`** — assigned to `github_actions_service_user`
- USAGE on warehouse
- READ on both raw source databases
- ALL on `tasty_bytes_dbt_db.dev` schema (CI PR checks)
- ALL on `tasty_bytes_stage_db` and `tasty_bytes_edw_db` (prod deploys)
- Can CREATE/ALTER/EXECUTE dbt project objects
- Handles CI, CD, and manual runs (all via GitHub Actions)

### Role Hierarchy
```
ACCOUNTADMIN
  └── SYSADMIN
        ├── DBT_CI
        └── DBT_DEVELOPER
```

### Manual Prod Runs (Implemented)

Developers trigger prod builds via GitHub Actions `workflow_dispatch`:
1. Go to GitHub → Actions → "CD Prod Run" → "Run workflow"
2. Select main branch (enforced), choose command, enter selector
3. Runs against the already-deployed project object with `--target prod`

Code always comes from main. Branch guard rejects non-main dispatch.

## Known Limitations
- `state:modified` not available in Snowflake dbt projects
- `env_var()` not available (dbt runs inside Snowflake, not locally)
- Git diff approach misses downstream impact of macro changes (falls back to deploy-only)
- Can't gitignore profiles.yml (needed for deploy to Snowflake)
- Toolbar Test button runs all tests, not file-scoped
- RBAC guardrails only block users who don't have ACCOUNTADMIN. Admins inherit all roles
  through the hierarchy. True isolation requires separate accounts.
- dbt selectors are case-sensitive (use lowercase model names)

## How to Resume
Tell CoCo: "Read the NOTES.md file for context on this project" at the start of a new chat.
