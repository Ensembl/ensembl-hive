
-- ---------------------------------------------------------------------------------------------------
-- added time_analysis() function for timing individual analyses or groups
-- ---------------------------------------------------------------------------------------------------

\set expected_version 67

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

DROP FUNCTION IF EXISTS time_analysis(VARCHAR);
CREATE FUNCTION time_analysis(analyses_pattern VARCHAR DEFAULT '%')
RETURNS TABLE ( still_running BIGINT,
                measured_in_minutes DOUBLE PRECISION,
                measured_in_hours DOUBLE PRECISION,
                measured_in_days DOUBLE PRECISION)
AS $$
    SELECT  COUNT(*)-COUNT(when_finished),
            EXTRACT(EPOCH FROM (CASE WHEN COUNT(*)>COUNT(when_finished) THEN CURRENT_TIMESTAMP ELSE max(when_finished) END) - min(when_started))/60,
            EXTRACT(EPOCH FROM (CASE WHEN COUNT(*)>COUNT(when_finished) THEN CURRENT_TIMESTAMP ELSE max(when_finished) END) - min(when_started))/3600,
            EXTRACT(EPOCH FROM (CASE WHEN COUNT(*)>COUNT(when_finished) THEN CURRENT_TIMESTAMP ELSE max(when_finished) END) - min(when_started))/3600/24
    FROM role JOIN analysis_base USING (analysis_id)
    WHERE logic_name like $1;
$$ LANGUAGE SQL;


-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
