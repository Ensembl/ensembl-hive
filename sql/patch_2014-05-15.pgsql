
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

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=61 WHERE meta_key='hive_sql_schema_version' AND meta_value='60';

