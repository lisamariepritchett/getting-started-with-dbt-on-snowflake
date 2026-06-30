-- RBAC roles and multi-database routing setup for the dbt CI/CD project
-- Co-authored with CoCo

-- =============================================================================
-- OVERVIEW
-- This script sets up:
--   1. Multi-database routing (separate raw, staging, EDW databases)
--   2. RBAC roles (DBT_DEVELOPER, DBT_CI, DBT_DEPLOYER)
--   3. Role assignments for users and service accounts
--
-- Run as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- STEP 1: Create prod databases and schemas for multi-database routing
-- =============================================================================

-- Raw source databases (cloned from tasty_bytes_dbt_db.raw which has since been dropped)
-- In production, these would be populated by your EL tool (Fivetran, Airbyte, etc.)
CREATE DATABASE IF NOT EXISTS TASTY_BYTES_RAW_EL_DB;
CREATE SCHEMA IF NOT EXISTS TASTY_BYTES_RAW_EL_DB.RAW;

CREATE DATABASE IF NOT EXISTS PROD_TASTY_BYTES_RAW_EL_DB;
CREATE SCHEMA IF NOT EXISTS PROD_TASTY_BYTES_RAW_EL_DB.RAW;

-- Prod staging database (dbt views land here)
CREATE DATABASE IF NOT EXISTS TASTY_BYTES_STAGE_DB;
CREATE SCHEMA IF NOT EXISTS TASTY_BYTES_STAGE_DB.POS_SYSTEM;
CREATE SCHEMA IF NOT EXISTS TASTY_BYTES_STAGE_DB.CRM;

-- Prod EDW/marts database (dbt tables land here)
CREATE DATABASE IF NOT EXISTS TASTY_BYTES_EDW_DB;
CREATE SCHEMA IF NOT EXISTS TASTY_BYTES_EDW_DB.MARKETING;
CREATE SCHEMA IF NOT EXISTS TASTY_BYTES_EDW_DB.FINANCE;

-- =============================================================================
-- STEP 2: Create RBAC roles
-- =============================================================================

-- DBT_DEVELOPER: For human developers — dev schemas only, no prod write
CREATE ROLE IF NOT EXISTS DBT_DEVELOPER
  COMMENT = 'dbt developer role - dev schemas only, no prod write access';

-- DBT_CI: For GitHub Actions — all CI/CD operations (dev builds, prod deploys, manual runs)
CREATE ROLE IF NOT EXISTS DBT_CI
  COMMENT = 'dbt CI/CD role - used by GitHub Actions for PR checks, prod deploys, and manual runs';

-- =============================================================================
-- STEP 3: Role hierarchy (all roll up to SYSADMIN)
-- =============================================================================

GRANT ROLE DBT_DEVELOPER TO ROLE SYSADMIN;
GRANT ROLE DBT_CI TO ROLE SYSADMIN;

-- =============================================================================
-- STEP 4: Warehouse grants
-- =============================================================================

GRANT USAGE ON WAREHOUSE TASTY_BYTES_DBT_DB TO ROLE DBT_DEVELOPER;
GRANT USAGE ON WAREHOUSE TASTY_BYTES_DBT_DB TO ROLE DBT_CI;

-- =============================================================================
-- STEP 5: DBT_DEVELOPER grants
-- Dev database + all dev schemas, read-only on dev raw sources
-- =============================================================================

-- Dev database
GRANT USAGE ON DATABASE TASTY_BYTES_DBT_DB TO ROLE DBT_DEVELOPER;
GRANT USAGE ON ALL SCHEMAS IN DATABASE TASTY_BYTES_DBT_DB TO ROLE DBT_DEVELOPER;
GRANT CREATE SCHEMA ON DATABASE TASTY_BYTES_DBT_DB TO ROLE DBT_DEVELOPER;

-- Dev schemas (add more as new developers join)
GRANT ALL ON SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_DEVELOPER;
GRANT ALL ON ALL TABLES IN SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_DEVELOPER;
GRANT ALL ON ALL VIEWS IN SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_DEVELOPER;
GRANT ALL ON FUTURE TABLES IN SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_DEVELOPER;
GRANT ALL ON FUTURE VIEWS IN SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_DEVELOPER;

GRANT ALL ON SCHEMA TASTY_BYTES_DBT_DB.DEV_LISA TO ROLE DBT_DEVELOPER;
GRANT ALL ON ALL TABLES IN SCHEMA TASTY_BYTES_DBT_DB.DEV_LISA TO ROLE DBT_DEVELOPER;
GRANT ALL ON ALL VIEWS IN SCHEMA TASTY_BYTES_DBT_DB.DEV_LISA TO ROLE DBT_DEVELOPER;
GRANT ALL ON FUTURE TABLES IN SCHEMA TASTY_BYTES_DBT_DB.DEV_LISA TO ROLE DBT_DEVELOPER;
GRANT ALL ON FUTURE VIEWS IN SCHEMA TASTY_BYTES_DBT_DB.DEV_LISA TO ROLE DBT_DEVELOPER;

-- Read dev raw sources
GRANT USAGE ON DATABASE PROD_TASTY_BYTES_RAW_EL_DB TO ROLE DBT_DEVELOPER;
GRANT USAGE ON SCHEMA PROD_TASTY_BYTES_RAW_EL_DB.RAW TO ROLE DBT_DEVELOPER;
GRANT SELECT ON ALL TABLES IN SCHEMA PROD_TASTY_BYTES_RAW_EL_DB.RAW TO ROLE DBT_DEVELOPER;

-- =============================================================================
-- STEP 6: DBT_CI grants
-- Dev schema + prod databases + deploy dbt project objects
-- =============================================================================

-- Dev database (for CI PR checks)
GRANT USAGE ON DATABASE TASTY_BYTES_DBT_DB TO ROLE DBT_CI;
GRANT USAGE ON ALL SCHEMAS IN DATABASE TASTY_BYTES_DBT_DB TO ROLE DBT_CI;

GRANT ALL ON SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_CI;
GRANT ALL ON ALL TABLES IN SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_CI;
GRANT ALL ON ALL VIEWS IN SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_CI;
GRANT ALL ON FUTURE TABLES IN SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_CI;
GRANT ALL ON FUTURE VIEWS IN SCHEMA TASTY_BYTES_DBT_DB.DEV TO ROLE DBT_CI;

-- Read dev raw sources
GRANT USAGE ON DATABASE PROD_TASTY_BYTES_RAW_EL_DB TO ROLE DBT_CI;
GRANT USAGE ON SCHEMA PROD_TASTY_BYTES_RAW_EL_DB.RAW TO ROLE DBT_CI;
GRANT SELECT ON ALL TABLES IN SCHEMA PROD_TASTY_BYTES_RAW_EL_DB.RAW TO ROLE DBT_CI;

-- Prod staging database (for CD deploys and manual runs)
GRANT USAGE ON DATABASE TASTY_BYTES_STAGE_DB TO ROLE DBT_CI;
GRANT USAGE ON ALL SCHEMAS IN DATABASE TASTY_BYTES_STAGE_DB TO ROLE DBT_CI;
GRANT ALL ON ALL SCHEMAS IN DATABASE TASTY_BYTES_STAGE_DB TO ROLE DBT_CI;
GRANT ALL ON ALL TABLES IN DATABASE TASTY_BYTES_STAGE_DB TO ROLE DBT_CI;
GRANT ALL ON ALL VIEWS IN DATABASE TASTY_BYTES_STAGE_DB TO ROLE DBT_CI;
GRANT ALL ON FUTURE TABLES IN DATABASE TASTY_BYTES_STAGE_DB TO ROLE DBT_CI;
GRANT ALL ON FUTURE VIEWS IN DATABASE TASTY_BYTES_STAGE_DB TO ROLE DBT_CI;
GRANT CREATE SCHEMA ON DATABASE TASTY_BYTES_STAGE_DB TO ROLE DBT_CI;

-- Prod EDW database (for CD deploys and manual runs)
GRANT USAGE ON DATABASE TASTY_BYTES_EDW_DB TO ROLE DBT_CI;
GRANT USAGE ON ALL SCHEMAS IN DATABASE TASTY_BYTES_EDW_DB TO ROLE DBT_CI;
GRANT ALL ON ALL SCHEMAS IN DATABASE TASTY_BYTES_EDW_DB TO ROLE DBT_CI;
GRANT ALL ON ALL TABLES IN DATABASE TASTY_BYTES_EDW_DB TO ROLE DBT_CI;
GRANT ALL ON ALL VIEWS IN DATABASE TASTY_BYTES_EDW_DB TO ROLE DBT_CI;
GRANT ALL ON FUTURE TABLES IN DATABASE TASTY_BYTES_EDW_DB TO ROLE DBT_CI;
GRANT ALL ON FUTURE VIEWS IN DATABASE TASTY_BYTES_EDW_DB TO ROLE DBT_CI;
GRANT CREATE SCHEMA ON DATABASE TASTY_BYTES_EDW_DB TO ROLE DBT_CI;

-- Read prod raw sources
GRANT USAGE ON DATABASE TASTY_BYTES_RAW_EL_DB TO ROLE DBT_CI;
GRANT USAGE ON SCHEMA TASTY_BYTES_RAW_EL_DB.RAW TO ROLE DBT_CI;
GRANT SELECT ON ALL TABLES IN SCHEMA TASTY_BYTES_RAW_EL_DB.RAW TO ROLE DBT_CI;

-- Deploy/execute dbt project objects
GRANT USAGE ON SCHEMA TASTY_BYTES_DBT_DB.INTEGRATIONS TO ROLE DBT_CI;
GRANT CREATE DBT PROJECT ON SCHEMA TASTY_BYTES_DBT_DB.INTEGRATIONS TO ROLE DBT_CI;

-- =============================================================================
-- STEP 7: Assign roles to users
-- =============================================================================

-- Human developers get DBT_DEVELOPER only
GRANT ROLE DBT_DEVELOPER TO USER LISAPRITCHETT;
ALTER USER LISAPRITCHETT SET DEFAULT_ROLE = DBT_DEVELOPER;

-- GitHub Actions service user gets DBT_CI (handles both CI and CD)
GRANT ROLE DBT_CI TO USER GITHUB_ACTIONS_SERVICE_USER;
ALTER USER GITHUB_ACTIONS_SERVICE_USER SET DEFAULT_ROLE = DBT_CI;

-- =============================================================================
-- STEP 8: Grant external access integration usage (needed for dbt deps)
-- =============================================================================

GRANT USAGE ON INTEGRATION DBT_EXT_ACCESS TO ROLE DBT_CI;
GRANT USAGE ON INTEGRATION DBT_EXT_ACCESS TO ROLE DBT_DEVELOPER;

-- =============================================================================
-- ADDING NEW DEVELOPERS
-- When a new developer joins, run:
--
--   CREATE SCHEMA IF NOT EXISTS TASTY_BYTES_DBT_DB.DEV_<NAME>;
--   GRANT ALL ON SCHEMA TASTY_BYTES_DBT_DB.DEV_<NAME> TO ROLE DBT_DEVELOPER;
--   GRANT ALL ON FUTURE TABLES IN SCHEMA TASTY_BYTES_DBT_DB.DEV_<NAME> TO ROLE DBT_DEVELOPER;
--   GRANT ALL ON FUTURE VIEWS IN SCHEMA TASTY_BYTES_DBT_DB.DEV_<NAME> TO ROLE DBT_DEVELOPER;
--   GRANT ROLE DBT_DEVELOPER TO USER <USERNAME>;
--   ALTER USER <USERNAME> SET DEFAULT_ROLE = DBT_DEVELOPER;
--
-- Then add a new target in profiles.yml:
--   dev_<name>:
--     ...
--     schema: dev_<name>
-- =============================================================================
