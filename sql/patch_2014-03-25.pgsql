
-- ---------------------------------------------------------------------------------------------------
-- Create   pipeline_wide_parameters instead of meta (to avoid schema conflicts)
-- Copy     all the data from meta to pipeline_wide_parameters
-- ---------------------------------------------------------------------------------------------------

\set expected_version 56

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

    -- initially duplicate 'meta' table with 'pipeline_wide_parameters':
CREATE TABLE pipeline_wide_parameters (
    param_name              VARCHAR(255) NOT NULL PRIMARY KEY,
    param_value             TEXT

);
CREATE        INDEX ON pipeline_wide_parameters (param_value);

INSERT INTO pipeline_wide_parameters(param_name, param_value) SELECT meta_key, meta_value FROM meta;

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
