
    -- Allow the monitor.analysis field to be arbitrarily long
    -- to accommodate multiple long analysis names concatenated together
ALTER TABLE monitor ALTER COLUMN analysis SET DATA TYPE TEXT;

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=51 WHERE meta_key='hive_sql_schema_version' AND meta_value='50';

