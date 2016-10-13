
-- ---------------------------------------------------------------------------------------------------

\set expected_version 83

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

ALTER TABLE analysis_base ADD COLUMN is_excluded SMALLINT NOT NULL DEFAULT 0;

CREATE TYPE msg_class AS ENUM ('INFO', 'PIPELINE_CAUTION', 'PIPELINE_ERROR', 'WORKER_CAUTION', 'WORKER_ERROR');
ALTER TABLE log_message ADD COLUMN message_class msg_class NOT NULL DEFAULT 'INFO';

UPDATE log_message
SET message_class = 'PIPELINE_ERROR'
WHERE is_error = 1;

ALTER TABLE log_message DROP COLUMN is_error;

ALTER TABLE analysis_stats_monitor ADD COLUMN is_excluded SMALLINT NOT NULL DEFAULT 0;

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
