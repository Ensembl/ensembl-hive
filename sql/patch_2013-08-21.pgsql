
    -- Documentation claims there is no performance gain from using fixed-width CHAR() types, changing them to TEXT:
ALTER TABLE job ALTER COLUMN input_id SET DATA TYPE TEXT;

    -- Add two new fields to job table to support parameter/accu stacks:
ALTER TABLE job ADD COLUMN param_id_stack          TEXT    NOT NULL DEFAULT '';
ALTER TABLE job ADD COLUMN accu_id_stack           TEXT    NOT NULL DEFAULT '';

    -- Extend the unique constraint to include both new fields:
ALTER TABLE job DROP CONSTRAINT job_input_id_analysis_id_key;
ALTER TABLE job ADD UNIQUE (input_id, param_id_stack, accu_id_stack, analysis_id);

    -- UPDATE hive_sql_schema_version
UPDATE hive_meta SET meta_value=52 WHERE meta_key='hive_sql_schema_version' AND meta_value='51';

