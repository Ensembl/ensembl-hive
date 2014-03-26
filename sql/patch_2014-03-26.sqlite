
    -- remove the 'monitor' table (it has been replaced by generate_timeline.pl)
DROP TABLE monitor;

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=58 WHERE meta_key='hive_sql_schema_version' AND meta_value='57';

