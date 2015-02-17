
-- ---------------------------------------------------------------------------------------------------
-- Change   the `worker`.last_check_in to auto-initialize by NULL (bugfix to 6d6edeb)
-- Remove   constraints to deleting `worker`.analysis_id
-- Drop     `worker`.analysis_id
-- ---------------------------------------------------------------------------------------------------

\set expected_version 60

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

    -- bugfix [to 6d6edeb] : make sure the default timestamp is always present:
ALTER TABLE worker ALTER COLUMN last_check_in DROP NOT NULL;
ALTER TABLE worker ALTER COLUMN last_check_in SET DEFAULT NULL;

    -- adding a previously missing index to match mysql schema:
CREATE INDEX ON worker (meadow_type, meadow_name, process_id);


    -- First remove the foreign key from worker.analysis_id:
ALTER TABLE worker DROP CONSTRAINT worker_analysis_id_fkey;

    -- And an index from the same column:
DROP INDEX worker_analysis_id_status_idx;

    -- Now we can drop the column itself:
ALTER TABLE worker DROP COLUMN analysis_id;

-- ----------------------------------</actual_patch> -------------------------------------------------


    -- increase the schema version by one:
UPDATE hive_meta SET meta_value= (CAST(meta_value AS INTEGER) + 1) WHERE meta_key='hive_sql_schema_version';
