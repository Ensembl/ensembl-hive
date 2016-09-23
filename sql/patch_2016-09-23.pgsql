
-- ---------------------------------------------------------------------------------------------------

\set expected_version 82

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

ALTER TABLE beekeeper ADD COLUMN is_blocked SMALLINT NOT NULL DEFAULT 0;

DROP VIEW IF EXISTS beekeeper_activity;
CREATE OR REPLACE VIEW beekeeper_activity AS
    SELECT b.beekeeper_id, b.meadow_host, b.sleep_minutes, b.loop_limit, b.is_blocked,
           b.cause_of_death, COUNT(*) AS loops_executed,
           MAX(lm.when_logged) AS last_heartbeat,
           now() - max(lm.when_logged) AS time_since_last_heartbeat,
           JUSTIFY_INTERVAL( (sleep_minutes * 60|| 'seconds')::interval) -
               (now() - max(lm.when_logged)) < INTERVAL '0'  AS is_overdue
    FROM beekeeper b
    LEFT JOIN log_message lm
    ON b.beekeeper_id = lm.beekeeper_id
    GROUP BY b.beekeeper_id;

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
