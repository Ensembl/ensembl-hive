
    -- Add 'RELOCATED' to the possible values of cause_of_death:
ALTER TYPE worker_cod ADD VALUE 'RELOCATED' AFTER 'CONTAMINATED';

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=55 WHERE meta_key='hive_sql_schema_version' AND meta_value='54';

