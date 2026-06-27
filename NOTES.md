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
- Database: `tasty_bytes_dbt_db` with schemas: `dev`, `prod`, `integrations`, `dev_lisa`
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
models/staging/marketing/  → stage_db.marketing
models/staging/finance/    → stage_db.finance
models/marts/marketing/    → edw_db.marketing
models/marts/finance/      → edw_db.finance
```

**Dev routing (dev_lisa, dev_bob, etc.):**
All models → `tasty_bytes_dbt_db.dev_lisa` regardless of folder.

**Controlled by:**
- `macros/generate_schema_name.sql` — routes schema; uses custom schema in prod, target schema in dev
- `macros/generate_database_name.sql` — routes database; uses custom db in prod, default db in dev
- `dbt_project.yml` — folder-level `+schema` and `+database` configs

**Current model locations:**
- `models/marts/finance/orders.sql` (moved from marts root)
- `models/marts/marketing/customer_loyalty_metrics.sql` (moved from marts root)
- `models/staging/marketing/` and `models/staging/finance/` — empty, ready for models

**To test prod routing, need to create:**
```sql
CREATE DATABASE IF NOT EXISTS stage_db;
CREATE SCHEMA IF NOT EXISTS stage_db.marketing;
CREATE SCHEMA IF NOT EXISTS stage_db.finance;
CREATE DATABASE IF NOT EXISTS edw_db;
CREATE SCHEMA IF NOT EXISTS edw_db.marketing;
CREATE SCHEMA IF NOT EXISTS edw_db.finance;
```

## Key Decisions Made
1. No `env_var()` in profiles (doesn't work in Snowflake dbt projects)
2. Named targets per developer instead of dynamic schemas
3. Git diff-based model selection (not `state:modified` - unavailable in Snowflake dbt)
4. Deploy step validates compilation, so no separate compile step needed
5. Tests scoped by folder path (`--select path:models/staging`)
6. No full builds triggered on uncertainty - compile/deploy only
7. Dev environments are flat (single schema); prod routes to multiple databases/schemas
8. Macro-based routing: `generate_schema_name` + `generate_database_name`

## CLI Flags Discovered (via trial and error)
- `--install-local-deps` (not --install-packages)
- `--external-access-integration` (not --ext-access-integrations)
- `--source ./tasty_bytes_dbt_demo` (folder must match actual repo structure)

## Remaining Work / To Test
- [ ] Test all workflow conditions (model change, test-only, macro, skip)
- [ ] Test multi-db/schema routing in prod (create stage_db and edw_db first)
- [ ] Verify dev_lisa flat routing works with new macros
- [ ] Set up RBAC roles: DBT_DEVELOPER, DBT_PROD_OPERATOR, DBT_CI_CD, DBT_ADMIN
- [ ] Multi-account setup (dev/test account + prod account) when available
- [ ] Add proper dbt tests back to __schema.yml (currently minimal for testing)
- [ ] Consider blue/green deployment or clone-before-deploy for prod safety
- [ ] Branch protection rules on main (require CI to pass before merge)
- [ ] Test `--select` with `snow dbt execute` to confirm selectors pass through correctly
- [ ] Evaluate for larger project: many models, multiple developers, test execution time
- [ ] Add staging models to marketing/ and finance/ subfolders

## Known Limitations
- `state:modified` not available in Snowflake dbt projects
- `env_var()` not available (dbt runs inside Snowflake, not locally)
- Git diff approach misses downstream impact of macro changes (falls back to deploy-only)
- Can't gitignore profiles.yml (needed for deploy to Snowflake)
- Toolbar Test button runs all tests, not file-scoped

## How to Resume
Tell CoCo: "Read the NOTES.md file for context on this project" at the start of a new chat.
