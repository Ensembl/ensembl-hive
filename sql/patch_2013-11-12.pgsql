
    -- Rename resource_description.parameters to stop confusion with job/analysis/pipeline parameters:
ALTER TABLE resource_description RENAME COLUMN parameters TO submission_cmd_args;

    -- Add resource-specific worker_cmd_args :
ALTER TABLE resource_description ADD COLUMN worker_cmd_args VARCHAR(255) NOT NULL DEFAULT '';

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=54 WHERE meta_key='hive_sql_schema_version' AND meta_value='53';

