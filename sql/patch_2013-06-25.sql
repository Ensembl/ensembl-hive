    -- create a new, hive-specific table for meta data and start using it for hive_sql_schema_version tracking:

CREATE TABLE hive_meta (
    meta_key                VARCHAR(80) NOT NULL PRIMARY KEY,
    meta_value              TEXT

);


    -- INSERT the 'hive_sql_schema_version' for the first time, then keep UPDATE'ing
INSERT INTO hive_meta (meta_key, meta_value) VALUES ('hive_sql_schema_version', '49');

    -- move 'hive_use_triggers' into hive_meta:
INSERT INTO hive_meta (meta_key, meta_value) SELECT 'hive_use_triggers', COALESCE(MIN(REPLACE(meta_value, '"', '')), 0) FROM meta WHERE meta_key='hive_use_triggers';

    -- move 'pipeline_name' into hive_meta and rename it into 'hive_pipeline_name':
INSERT INTO hive_meta (meta_key, meta_value) SELECT 'hive_pipeline_name', REPLACE(meta_value,'"','') FROM meta WHERE meta_key='pipeline_name' or meta_key='name';

