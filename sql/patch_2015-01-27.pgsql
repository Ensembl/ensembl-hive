
-- ---------------------------------------------------------------------------------------------------
-- Rename   all TIMESTAMP columns to have a 'when_' prefix for easier (and possibly automatic) identification.
-- Add      worker.when_seen TIMESTAMP
-- Fix      msg VIEW
-- ---------------------------------------------------------------------------------------------------

\set expected_version 63

\set ON_ERROR_STOP on

    -- warn that we detected the schema version mismatch:
SELECT ('The patch only applies to schema version '
    || CAST(:expected_version AS VARCHAR)
    || ', but the current schema version is '
    || meta_value
    || ', so skipping the rest.') as incompatible_msg
    FROM hive_meta WHERE meta_key='hive_sql_schema_version' AND meta_value!=CAST(:expected_version AS VARCHAR);

    -- cause division by zero only if current version differs from the expected one:
INSERT INTO hive_meta (meta_key, meta_value)
   SELECT 'this_should_never_be_inserted', 1 FROM hive_meta WHERE 1 != 1/CAST( (meta_key!='hive_sql_schema_version' OR meta_value=CAST(:expected_version AS VARCHAR)) AS INTEGER );

SELECT ('The patch seems to be compatible with schema version '
    || CAST(:expected_version AS VARCHAR)
    || ', applying the patch...') AS compatible_msg;


-- ----------------------------------<actual_patch> -------------------------------------------------

    -- First, rename all TIMESTAMPed columns to have a 'when_' prefix for automatic identification:
ALTER TABLE analysis_stats          RENAME COLUMN last_update   TO when_updated;
ALTER TABLE job                     RENAME COLUMN completed     TO when_completed;
ALTER TABLE worker                  RENAME COLUMN born          TO when_born;
ALTER TABLE worker                  RENAME COLUMN last_check_in TO when_checked_in;
ALTER TABLE worker                  RENAME COLUMN died          TO when_died;
ALTER TABLE log_message             RENAME COLUMN time          TO when_logged;
ALTER TABLE analysis_stats_monitor  RENAME COLUMN time          TO when_logged;
ALTER TABLE analysis_stats_monitor  RENAME COLUMN last_update   TO when_updated;

    -- Then add one more column to register when a Worker was last seen by the Meadow:
ALTER TABLE worker                  ADD COLUMN    when_seen     TIMESTAMP DEFAULT    NULL;

    -- replace the 'msg' view as the columns implicitly referenced there have been renamed:
DROP VIEW msg;
CREATE OR REPLACE VIEW msg AS
    SELECT a.analysis_id, a.logic_name, m.*
    FROM log_message m
    LEFT JOIN job j ON (j.job_id=m.job_id)
    LEFT JOIN analysis_base a ON (a.analysis_id=j.analysis_id);

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';

