-- Prod scheduled task definitions for the dbt project object
-- Co-authored with CoCo
-- =============================================================================
-- These tasks are applied by the CD workflow (pr_merged.yml) on every merge.
-- CREATE OR ALTER is idempotent — safe to re-run even if nothing changed.
-- Tasks are owned by DBT_CI and execute on a user-managed warehouse.
-- =============================================================================

USE ROLE DBT_CI;
USE WAREHOUSE XSMALL_WH;

-- Daily full build at 5 AM UTC
CREATE OR ALTER TASK TASTY_BYTES_STAGE_DB.PUBLIC.daily_prod_build
  WAREHOUSE = XSMALL_WH
  SCHEDULE = 'USING CRON 0 5 * * * UTC'
AS
  EXECUTE DBT PROJECT tasty_bytes_dbt_object_gh_action
    ARGS = 'build --target prod --select path:models';

-- Hourly refresh for time-sensitive models (top of every hour)
CREATE OR ALTER TASK TASTY_BYTES_STAGE_DB.PUBLIC.hourly_prod_refresh
  WAREHOUSE = XSMALL_WH
  SCHEDULE = 'USING CRON 0 * * * * UTC'
AS
  EXECUTE DBT PROJECT tasty_bytes_dbt_object_gh_action
    ARGS = 'run --target prod --select tag:hourly';

-- Resume tasks (idempotent — already-resumed tasks are unaffected)
ALTER TASK TASTY_BYTES_STAGE_DB.PUBLIC.daily_prod_build RESUME;
ALTER TASK TASTY_BYTES_STAGE_DB.PUBLIC.hourly_prod_refresh RESUME;

-- =============================================================================
-- Monitoring: Create a view for easy task run history and failure tracking.
-- Developers with DBT_DEVELOPER + MONITOR can query this without needing DBT_CI.
-- =============================================================================

CREATE OR REPLACE VIEW TASTY_BYTES_STAGE_DB.PUBLIC.task_run_history AS
SELECT
    name AS task_name,
    state,
    query_start_time,
    completed_time,
    TIMESTAMPDIFF('second', query_start_time, completed_time) AS duration_seconds,
    error_code,
    error_message,
    scheduled_time,
    return_value
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -7, CURRENT_TIMESTAMP()),
    RESULT_LIMIT => 100
))
WHERE name IN ('DAILY_PROD_BUILD', 'HOURLY_PROD_REFRESH')
ORDER BY scheduled_time DESC;

-- Grant read access to developers
GRANT SELECT ON VIEW TASTY_BYTES_STAGE_DB.PUBLIC.task_run_history TO ROLE DBT_DEVELOPER;
