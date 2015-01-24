
    -- First, rename 'host' to 'meadow_host' for consistency:
ALTER TABLE worker RENAME COLUMN host TO meadow_host;

    -- Then allow each Worker to register the username that is running the process on the meadow_host:
ALTER TABLE worker ADD COLUMN meadow_user VARCHAR(255) DEFAULT NULL;

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=63 WHERE meta_key='hive_sql_schema_version' AND meta_value='62';

